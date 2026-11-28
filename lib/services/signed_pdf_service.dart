import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/declaration.dart';

class SigningPdfStatus {
  final bool prepared;
  final bool ownerVerified;
  final bool superiorVerified;

  const SigningPdfStatus({
    required this.prepared,
    required this.ownerVerified,
    required this.superiorVerified,
  });

  factory SigningPdfStatus.fromMap(Map<String, dynamic> data) {
    return SigningPdfStatus(
      prepared: data['prepared'] == true,
      ownerVerified: data['ownerVerified'] == true,
      superiorVerified: data['superiorVerified'] == true,
    );
  }
}

class SignedPdfService {
  final FirebaseFunctions functions =
      FirebaseFunctions.instanceFor(region: 'us-east1');

  Future<Map<String, dynamic>> _call(
    String name,
    Declaration declaration, [
    Map<String, dynamic> extra = const {},
  ]) async {
    try {
      final result = await functions
          .httpsCallable(
        name,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 150),
        ),
      )
          .call(<String, dynamic>{
        'declarationId': declaration.id,
        'version': declaration.version,
        ...extra,
      });

      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw StateError(
        error.message ?? 'No se pudo completar la operación de firma.',
      );
    }
  }

  Future<SigningPdfStatus> status(
    Declaration declaration,
  ) async {
    return SigningPdfStatus.fromMap(
      await _call('getSigningPdfStatus', declaration),
    );
  }

  Future<String?> download(
    Declaration declaration, {
    required bool prepare,
  }) async {
    if (prepare) {
      await _call('prepareSigningPdf', declaration);
    }

    final result = await _call(
      'downloadSigningPdf',
      declaration,
    );

    final Uint8List bytes = base64Decode(result['pdfBase64'] as String);

    if (sha256.convert(bytes).toString() != result['sha256']) {
      throw StateError(
        'El PDF descargado no coincide con su registro.',
      );
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar PDF para firma digital',
      fileName: 'declaracion_${declaration.id}_v${declaration.version}.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: bytes,
    );

    if (kIsWeb) {
      return 'Descarga solicitada. Revisá las descargas del navegador.';
    }

    return path == null ? null : 'PDF guardado correctamente.';
  }

  Future<String?> upload(Declaration declaration) async {
    final selection = await FilePicker.platform.pickFiles(
      dialogTitle: 'Seleccionar el PDF firmado digitalmente',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
      withData: true,
    );

    if (selection == null) return null;

    final file = selection.files.single;
    final bytes = file.bytes;

    if (bytes == null || bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw StateError(
        'Seleccioná un PDF de hasta 5 MiB.',
      );
    }

    if (bytes.length < 5 ||
        ascii.decode(
              bytes.sublist(0, 5),
              allowInvalid: true,
            ) !=
            '%PDF-') {
      throw StateError(
        'El archivo seleccionado no es un PDF.',
      );
    }

    await _call(
      'uploadSignedPdf',
      declaration,
      {'pdfBase64': base64Encode(bytes)},
    );

    return 'PDF recibido y firmas digitales verificadas.';
  }

  Future<String?> send(Declaration declaration) async {
    await _call(
      'sendDigitallySignedDeclaration',
      declaration,
    );

    return 'Declaración enviada al superior.';
  }

  Future<String?> accept(Declaration declaration) async {
    await _call(
      'acceptDeclarationAndSendHr',
      declaration,
    );

    return 'Declaración aceptada y enviada a Recursos Humanos.';
  }
}
