import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:printing/printing.dart';

import 'personal_data_validator.dart';

import '../models/declaration.dart';
import 'validation_service.dart';
import 'declaration_pdf_layout.dart';

import 'package:cloud_functions/cloud_functions.dart';

class DeclarationService {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  User get user => FirebaseAuth.instance.currentUser!;

  CollectionReference<Map<String, dynamic>> get declarations {
    return db.collection('declarations');
  }

  // ==========================================================
  // CONSULTAR DECLARACIONES
  // ==========================================================

  Stream<List<Declaration>> watchMine() {
    return declarations.where('ownerId', isEqualTo: user.uid).snapshots().map((
      snapshot,
    ) {
      final list = snapshot.docs.map(Declaration.fromDoc).toList();

      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return list;
    });
  }

  Stream<List<Declaration>> watchAll() {
    return declarations.snapshots().map((snapshot) {
      final list = snapshot.docs.map(Declaration.fromDoc).toList();

      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return list;
    });
  }

  Stream<List<Declaration>> watchAssigned() {
    return declarations
        .where('superiorId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map(Declaration.fromDoc).toList();

      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return list;
    });
  }

  // ==========================================================
  // GUARDAR DECLARACIONES
  // ==========================================================

  Future<void> save(Declaration declaration) async {
    if (declaration.status != 'BORRADOR') {
      throw StateError('Solo se pueden guardar borradores.');
    }
    PersonalDataValidator.ensureValid(declaration);
    final callable = FirebaseFunctions.instanceFor(region: 'us-east1')
        .httpsCallable('saveDeclarationValidated');
    try {
      final result = await callable.call(<String, dynamic>{
        'id': declaration.id,
        'version': declaration.version,
        'periodId': declaration.periodId,
        'superiorId': declaration.superiorId,
        'ownerName': declaration.ownerName,
        'identification': declaration.identification,
        'phone': declaration.phone,
        'email': declaration.email,
        'unit': declaration.unit,
        'observations': declaration.observations,
        'appointments':
            declaration.appointments.map((job) => job.toMap()).toList(),
        'externalJobs':
            declaration.externalJobs.map((job) => job.toMap()).toList(),
      });
      final response = Map<String, dynamic>.from(result.data as Map);
      if (response['saved'] == false) {
        throw StateError('No hay cambios para guardar.');
      }
    } on FirebaseFunctionsException catch (error) {
      throw StateError(error.message ?? 'No se pudo guardar la declaración.');
    }
  }

  // ==========================================================
  // REGISTRAR EVENTOS EN EL HISTORIAL
  // ==========================================================

  Future<void> event(
    DocumentReference<Map<String, dynamic>> reference,
    String type,
    int version,
    String previous,
    String next, [
    String note = '',
  ]) {
    return reference.collection('events').add({
      'event': type,
      'userId': user.uid,
      'dateTime': FieldValue.serverTimestamp(),
      'version': version,
      'previousStatus': previous,
      'newStatus': next,
      'observation': note,
    });
  }

  // ==========================================================
  // CAMBIAR EL ESTADO DE UNA DECLARACION
  // ==========================================================

  Future<void> transition(
    Declaration declaration,
    String action, {
    String note = '',
    bool confirmed = false,
  }) async {
    final reference = declarations.doc(declaration.id);

    final allowed = {
      'validate': ['BORRADOR'],
      'submit': ['VALIDADA'],
      'signOwner': ['PENDIENTE_FIRMA_DECLARANTE'],
      'route': ['FIRMADA_POR_DECLARANTE'],
      'signSuperior': ['PENDIENTE_FIRMA_SUPERIOR'],
      'return': ['PENDIENTE_FIRMA_SUPERIOR'],
      'sendHr': ['FIRMADA_POR_SUPERIOR'],
      'receive': ['ENVIADA_A_RRHH'],
      'finish': ['RECIBIDA_RRHH'],
      'newVersion': ['DEVUELTA'],
      'annul': ['BORRADOR', 'VALIDADA'],
    };

    final next = {
      'validate': 'VALIDADA',
      'submit': 'PENDIENTE_FIRMA_DECLARANTE',
      'signOwner': 'FIRMADA_POR_DECLARANTE',
      'route': 'PENDIENTE_FIRMA_SUPERIOR',
      'signSuperior': 'FIRMADA_POR_SUPERIOR',
      'return': 'DEVUELTA',
      'sendHr': 'ENVIADA_A_RRHH',
      'receive': 'RECIBIDA_RRHH',
      'finish': 'FINALIZADA',
      'newVersion': 'BORRADOR',
      'annul': 'ANULADA',
    };

    // Verificar que el cambio de estado sea permitido.

    if (!(allowed[action]?.contains(declaration.status) ?? false)) {
      throw StateError('Transición inválida.');
    }

    // Una devolución debe tener una observación.

    if (action == 'return' && note.trim().isEmpty) {
      throw StateError('La devolución requiere observación.');
    }

    if (action == 'validate') {
      PersonalDataValidator.ensureValid(declaration);
    }

    // Validar los horarios antes de continuar.

    if (action == 'validate' &&
        !ValidationService.validate(
          declaration.appointments,
          declaration.externalJobs,
        ).valid) {
      throw StateError('Existen errores de validación.');
    }

    // Estas acciones se verifican en el servidor sobre los datos guardados.
    if (action == 'validate' || action == 'newVersion') {
      final functionName = action == 'validate'
          ? 'validateDeclarationSchedule'
          : 'newDeclarationVersion';
      try {
        await FirebaseFunctions.instanceFor(region: 'us-east1')
            .httpsCallable(functionName)
            .call(<String, dynamic>{
          'id': declaration.id,
          'version': declaration.version,
        });
      } on FirebaseFunctionsException catch (error) {
        throw StateError(
          error.message ?? 'No se pudo actualizar la declaración.',
        );
      }
      return;
    }

    // Confirmar la declaración bajo juramento.

    if (action == 'signOwner' && !confirmed) {
      throw StateError('Debe confirmar la declaración bajo juramento.');
    }

    // Verificar la identidad del declarante.

    if (action == 'signOwner' && declaration.ownerId != user.uid) {
      throw StateError('No autorizado.');
    }

    // Verificar la identidad del superior.

    if (action == 'signSuperior' && declaration.superiorId != user.uid) {
      throw StateError('No autorizado.');
    }

    final newVersion = declaration.version;

    // Ejecutar los cambios en una transacción.

    await db.runTransaction((transaction) async {
      final fresh = await transaction.get(reference);

      if (fresh.data()?['status'] != declaration.status ||
          fresh.data()?['version'] != declaration.version) {
        throw StateError('La declaración cambió. Actualice la página.');
      }

      transaction.update(reference, {
        'status': next[action],
        'version': newVersion,
        'updatedAt': FieldValue.serverTimestamp(),
        if (action == 'return') 'returnNote': note,
      });

      final eventReference = reference.collection('events').doc();
      transaction.set(eventReference, {
        'event': action,
        'userId': user.uid,
        'dateTime': FieldValue.serverTimestamp(),
        'version': newVersion,
        'previousStatus': declaration.status,
        'newStatus': next[action]!,
        'observation': note,
      });

      // Registrar firmas electrónicas internas.

      if (action == 'signOwner' || action == 'signSuperior') {
        final canonical = jsonEncode({
          ...fresh.data()!,
          'version': declaration.version,
          'updatedAt': null,
        });

        final signature = reference
            .collection('versions')
            .doc('${declaration.version}')
            .collection('signatures')
            .doc(action == 'signOwner' ? 'owner' : 'superior');

        transaction.set(signature, {
          'userId': user.uid,
          'name': user.displayName ?? user.email ?? '',
          'dateTime': FieldValue.serverTimestamp(),
          'version': declaration.version,
          'signatureId': signature.id,
          'hash': sha256.convert(utf8.encode(canonical)).toString(),
          'type': action == 'signOwner' ? 'DECLARANTE' : 'SUPERIOR',
        });
      }
    });
  }

  // ==========================================================
  // CONSULTAR HISTORIAL
  // ==========================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> timeline(String id) {
    return declarations
        .doc(id)
        .collection('events')
        .orderBy('dateTime')
        .snapshots();
  }

  // Devuelve true si el PDF ya existía y se conservó el original.
  Future<bool> archivePdf(Declaration declaration) async {
    if (declaration.status != 'FINALIZADA') {
      throw StateError(
        'La declaración debe estar finalizada para archivar el PDF.',
      );
    }

    final bytes = await _buildPdf(declaration);

    if (bytes.isEmpty || bytes.length >= 10 * 1024 * 1024) {
      throw StateError('El PDF debe pesar menos de 10 MiB.');
    }

    final callable =
        FirebaseFunctions.instanceFor(region: 'us-east1').httpsCallable(
      'archiveDeclarationPdf',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    );

    final result = await callable.call({
      'declarationId': declaration.id,
      'version': declaration.version,
      'pdfBase64': base64Encode(bytes),
    });

    final data = Map<String, dynamic>.from(result.data as Map);

    return data['alreadyExists'] == true;
  }

  // Abre exactamente el archivo guardado en Storage.
  Future<void> openArchivedPdf(Declaration declaration) async {
    final callable =
        FirebaseFunctions.instanceFor(region: 'us-east1').httpsCallable(
      'downloadDeclarationPdf',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    );

    final result = await callable.call({
      'declarationId': declaration.id,
      'version': declaration.version,
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    final encoded = data['pdfBase64'];
    final expectedHash = data['sha256'];

    if (encoded is! String || expectedHash is! String) {
      throw StateError('La respuesta del PDF es inválida.');
    }

    final bytes = base64Decode(encoded);

    if (bytes.isEmpty || bytes.length >= 10 * 1024 * 1024) {
      throw StateError('El tamaño del PDF es inválido.');
    }

    if (sha256.convert(bytes).toString() != expectedHash) {
      throw StateError(
        'El PDF descargado no coincide con su huella registrada.',
      );
    }

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Declaracion_${declaration.id}_v${declaration.version}.pdf',
    );
  }
  // ==========================================================
  // GENERAR PDF DE LA DECLARACION
  // ==========================================================

  Future<Uint8List> _buildPdf(Declaration declaration) async {
    final version = await declarations
        .doc(declaration.id)
        .collection('versions')
        .doc('${declaration.version}')
        .get();

    final signatures = await declarations
        .doc(declaration.id)
        .collection('versions')
        .doc('${declaration.version}')
        .collection('signatures')
        .get();

    if (!version.exists) {
      throw StateError(
        'No se encontró la versión guardada de esta declaración.',
      );
    }

    final saved = Declaration.fromDoc(version);

    if (saved.version != declaration.version ||
        saved.ownerId != declaration.ownerId ||
        saved.superiorId != declaration.superiorId) {
      throw StateError('La versión guardada no coincide con la declaración.');
    }

    // Conservar el identificador y el estado del trámite.
    // Tomar el contenido desde la versión guardada.
    declaration = Declaration(
      id: declaration.id,
      ownerId: saved.ownerId,
      ownerName: saved.ownerName,
      identification: saved.identification,
      phone: saved.phone,
      email: saved.email,
      unit: saved.unit,
      periodId: saved.periodId,
      superiorId: saved.superiorId,
      status: declaration.status,
      observations: saved.observations,
      version: saved.version,
      appointments: saved.appointments,
      externalJobs: saved.externalJobs,
      updatedAt: saved.updatedAt,
    );

    // Un PDF definitivo necesita las dos firmas de esa versión.
    if (declaration.status == 'FINALIZADA') {
      final signaturesById = {
        for (final doc in signatures.docs) doc.id: doc.data(),
      };

      final ownerSignature = signaturesById['owner'];
      final superiorSignature = signaturesById['superior'];

      if (ownerSignature?['userId'] != declaration.ownerId ||
          superiorSignature?['userId'] != declaration.superiorId ||
          ownerSignature?['version'] != declaration.version ||
          superiorSignature?['version'] != declaration.version) {
        throw StateError(
          'Faltan firmas válidas para generar el PDF definitivo.',
        );
      }
    }

    final logoData = await rootBundle.load('assets/images/logo_ucr.png');
    return buildDeclarationPdfTables(
      declaration: declaration.toMap(),
      signatures: signatures.docs.map((signature) {
        final data = signature.data();
        return <String, dynamic>{
          ...data,
          'type': signature.id,
          'id': data['signatureId'] ?? signature.id,
        };
      }).toList(),
      logoBytes: logoData.buffer.asUint8List(
        logoData.offsetInBytes,
        logoData.lengthInBytes,
      ),
    );
  }

  Future<void> generatePdf(Declaration declaration) async {
    final bytes = await _buildPdf(declaration);

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Declaracion_${declaration.id}_v${declaration.version}.pdf',
    );
  }
}
