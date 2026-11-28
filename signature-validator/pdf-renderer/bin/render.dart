import 'dart:convert';
import 'dart:io';

import '../lib/declaration_pdf_layout.dart';

Future<void> main() async {
  try {
    final payload = jsonDecode(
      await stdin.transform(utf8.decoder).join(),
    ) as Map;

    final declaration = Map<String, dynamic>.from(
      payload['declaration'] as Map,
    );

    final bytes = await buildDeclarationPdfTables(
      declaration: declaration,
      signatures: <Map<String, dynamic>>[],
      logoBytes: await File(
        Platform.environment['PDF_LOGO_PATH'] ??
            '/app/assets/logo_ucr.png',
      ).readAsBytes(),
    );

    stdout.add(bytes);
    await stdout.flush();
  } catch (error) {
    stderr.writeln(
      'No se pudo generar la plantilla de declaración: $error',
    );

    exitCode = 1;
  }
}
