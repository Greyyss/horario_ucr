import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../models/declaration.dart';
import 'validation_service.dart';

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
    return declarations
        .where('ownerId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
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

    final bool isNew = declaration.id.isEmpty;

    final reference =
        isNew ? declarations.doc() : declarations.doc(declaration.id);

    if (!isNew) {
      final snapshot = await reference.get();

      if (!snapshot.exists ||
          snapshot.data()?['ownerId'] != user.uid ||
          snapshot.data()?['status'] != 'BORRADOR') {
        throw StateError('No autorizado para editar esta declaración.');
      }
    }

    
final data = declaration.toMap();

data['ownerId'] = user.uid;

final versionReference =
    reference.collection('versions').doc('${declaration.version}');

// Generar el identificador del evento antes de guardar.
final eventReference = reference.collection('events').doc();

// Asociar cada modificación con su evento de auditoría.
if (!isNew) {
  data['lastEditEventId'] = eventReference.id;
}


    final batch = db.batch();

    batch.set(reference, data);

    batch.set(versionReference, {
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.set(eventReference, {
      'event': isNew ? 'CREADA' : 'MODIFICADA',
      'userId': user.uid,
      'dateTime': FieldValue.serverTimestamp(),
      'version': declaration.version,
      'previousStatus': declaration.status,
      'newStatus': declaration.status,
      'observation': '',
    });

    await batch.commit();
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

    // Validar los horarios antes de continuar.

    if (action == 'validate' &&
        !ValidationService.validate(
          declaration.appointments,
          declaration.externalJobs,
        ).valid) {
      throw StateError('Existen errores de validación.');
    }

    // Confirmar la declaración bajo juramento.

    if (action == 'signOwner' && !confirmed) {
      throw StateError(
        'Debe confirmar la declaración bajo juramento.',
      );
    }

    // Verificar la identidad del declarante.

    if (action == 'signOwner' && declaration.ownerId != user.uid) {
      throw StateError('No autorizado.');
    }

    // Verificar la identidad del superior.

    if (action == 'signSuperior' && declaration.superiorId != user.uid) {
      throw StateError('No autorizado.');
    }

    final newVersion =
        action == 'newVersion' ? declaration.version + 1 : declaration.version;

    // Ejecutar los cambios en una transacción.

    await db.runTransaction((transaction) async {
      final fresh = await transaction.get(reference);

      if (fresh.data()?['status'] != declaration.status ||
          fresh.data()?['version'] != declaration.version) {
        throw StateError(
          'La declaración cambió. Actualice la página.',
        );
      }

      if (action == 'newVersion' && fresh.data()?['ownerId'] != user.uid) {
        throw StateError('No autorizado.');
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

      // Crear una nueva versión cuando se devuelve.

      if (action == 'newVersion') {
        transaction.set(
          reference.collection('versions').doc('$newVersion'),
          {
            ...fresh.data()!,
            'status': 'BORRADOR',
            'version': newVersion,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      }

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
            .doc(
              action == 'signOwner' ? 'owner' : 'superior',
            );

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

  Stream<QuerySnapshot<Map<String, dynamic>>> timeline(
    String id,
  ) {
    return declarations
        .doc(id)
        .collection('events')
        .orderBy('dateTime')
        .snapshots();
  }

  // ==========================================================
  // GENERAR PDF DE LA DECLARACION
  // ==========================================================

  
Future<void> generatePdf(Declaration declaration) async {
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

  final pdf = pw.Document();

  final jobs = [
    ...declaration.appointments,
    ...declaration.externalJobs,
  ];

  final logoData = await rootBundle.load(
  'assets/images/logo_ucr.png',
);

final logoUcr = pw.MemoryImage(
  logoData.buffer.asUint8List(),
);

  
pdf.addPage(
  pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),


header: (context) {
 return pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.only(bottom: 14),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(
          color: PdfColor.fromHex('#163A63'),
          width: 2,
        ),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Image(
          logoUcr,
          width: 250,
          height: 75,
          fit: pw.BoxFit.contain,
        ),

        pw.SizedBox(height: 8),

        pw.Text(
          'Sistema DeclaraHorario',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#163A63'),
          ),
        ),

        pw.Text(
          'Período ${declaration.periodId}',
          style: const pw.TextStyle(
            fontSize: 9,
          ),
        ),
      ],
    ),
  );
},


  
footer: (context) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(top: 10),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(
          color: PdfColors.grey300,
          width: 0.7,
        ),
      ),
    ),
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          'Registro electrónico interno académico. '
          'No equivale a firma digital certificada.',
          style: const pw.TextStyle(
            fontSize: 8,
            color: PdfColors.grey700,
          ),
          textAlign: pw.TextAlign.center,
        ),

        pw.SizedBox(height: 6),

        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Universidad de Costa Rica | DeclaraHorario',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
            pw.Text(
              'Versión ${declaration.version} | '
              'Página ${context.pageNumber} de '
              '${context.pagesCount}',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
      ],
    ),
  );
},
  

    build: (context) => [
      pw.SizedBox(height: 24),

        pw.Text(
          'Declaración Jurada de Horario y Jornada de Trabajo',
        ),

        pw.SizedBox(height: 14),

       
pw.Text(
  'DATOS DEL DECLARANTE',
  style: pw.TextStyle(
    fontSize: 12,
    fontWeight: pw.FontWeight.bold,
  ),
),

pw.SizedBox(height: 12),

pw.Text('Nombre completo: ${declaration.ownerName}'),
pw.SizedBox(height: 7),

pw.Text('Identificación: ${declaration.identification}'),
pw.SizedBox(height: 7),

pw.Text('Teléfono: ${declaration.phone}'),
pw.SizedBox(height: 7),

pw.Text('Correo electrónico: ${declaration.email}'),
pw.SizedBox(height: 7),

pw.Text('Unidad: ${declaration.unit}'),
pw.SizedBox(height: 7),

pw.Text('Período académico: ${declaration.periodId}'),
pw.SizedBox(height: 7),

pw.Text('Versión: ${declaration.version}'),
pw.SizedBox(height: 7),

pw.Text('Estado: ${declaration.status}'),

pw.SizedBox(height: 18),


        pw.SizedBox(height: 12),

        // Nombramientos y trabajos externos.
        ...jobs.asMap().entries.expand((entry) {
          final job = entry.value;

          final type = entry.key < declaration.appointments.length
              ? 'Nombramiento'
              : 'Otra institución';

          return [
            pw.Text(
              '$type: ${job.workplace}',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
              ),
            ),

            pw.Text(
              'Cargo: ${job.position}  |  '
              'Jornada: ${job.expectedHours} h',
            ),

            pw.Text(
              'Vigencia: ${job.startDate} a ${job.endDate}',
            ),

            ...job.blocks.map((block) {
              return pw.Text(
                'Día ${block.day}: '
                '${block.start} - ${block.end}',
              );
            }),

            pw.SizedBox(height: 9),
          ];
        }),

        pw.Text(
          'Observaciones: ${declaration.observations}',
        ),

        pw.SizedBox(height: 14),

        pw.Text(
          'Declaro bajo juramento que los datos '
          'consignados son veraces.',
        ),

        pw.SizedBox(height: 10),

        // Firmas electrónicas internas.
        ...signatures.docs.map((signature) {
          final data = signature.data();

          return pw.Text(
            'Firma interna ${data['type']}: '
            '${data['name']} | '
            'ID: ${data['signatureId']} | '
            'Huella: ${data['hash']}',
          );
        }),

        pw.SizedBox(height: 12),


        if (!version.exists)
          pw.Text(
            'Advertencia: no se encontró la '
            'instantánea de versión.',
          ),
      ],
    ),
  );

  // Generar el PDF sin utilizar Firebase Storage.
  final bytes = await pdf.save();

  // Abrir la opción de impresión o guardado como PDF.
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'Declaracion_${declaration.id}_v${declaration.version}',
  );
}
}
