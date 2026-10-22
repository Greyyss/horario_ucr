import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Solo presenta datos: permisos, firmas y lectura de versiones siguen en el servicio.
Future<Uint8List> buildDeclarationPdfTables({
  required Map<String, dynamic> declaration,
  required List<Map<String, dynamic>> signatures,
  required Uint8List logoBytes,
}) async {
  final pdf = pw.Document();
  final blue = PdfColor.fromHex('#163A63');
  final lightBlue = PdfColor.fromHex('#EDF3FA');
  final line = PdfColor.fromHex('#CAD4E0');
  final logo = pw.MemoryImage(logoBytes);
  String text(dynamic value) => value == null || value.toString().trim().isEmpty
      ? 'No indicado'
      : value.toString();
  String hours(dynamic value) =>
      value is num ? value.toStringAsFixed(2) : '0.00';
  List<Map<String, dynamic>> maps(dynamic value) => (value as List? ?? [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();

  pw.Widget heading(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 15, bottom: 7),
    child: pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: blue,
      ),
    ),
  );
  pw.Widget cell(String value, {bool label = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    color: label ? lightBlue : null,
    child: pw.Text(
      value,
      style: pw.TextStyle(
        fontSize: 9,
        color: label ? blue : PdfColors.black,
        fontWeight: label ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
  pw.Widget details(List<List<String>> rows) => pw.Table(
    border: pw.TableBorder.all(color: line, width: 0.5),
    columnWidths: {
      0: const pw.FixedColumnWidth(130),
      1: const pw.FlexColumnWidth(),
    },
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: rows
        .map(
          (row) =>
              pw.TableRow(children: [cell(row[0], label: true), cell(row[1])]),
        )
        .toList(),
  );
  const days = [
    '',
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
  ];
  double blockHours(Map<String, dynamic> block) {
    int? minute(dynamic value) {
      final parts = value.toString().split(':');
      if (parts.length != 2) return null;
      final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59)
        return null;
      return h * 60 + m;
    }

    final start = minute(block['start']), end = minute(block['end']);
    return start == null || end == null || end <= start
        ? 0
        : (end - start) / 60;
  }

  List<pw.Widget> appointments(String title, List<Map<String, dynamic>> jobs) {
    final widgets = <pw.Widget>[
      pw.NewPage(freeSpace: jobs.isEmpty ? 65 : 180),
      heading(title),
    ];
    if (jobs.isEmpty) {
      widgets.add(
        details([
          ['Registro', 'Sin registros.'],
        ]),
      );
      return widgets;
    }
    for (var index = 0; index < jobs.length; index++) {
      if (index > 0) widgets.add(pw.NewPage(freeSpace: 160));
      final job = jobs[index];
      final blocks = maps(job['blocks']);
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 5, bottom: 5),
          child: pw.Text(
            'Registro ${index + 1}',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: blue,
            ),
          ),
        ),
      );
      widgets.add(
        details([
          ['Institución / lugar de trabajo', text(job['workplace'])],
          ['Cargo o categoría', text(job['position'])],
          ['Vigencia', '${text(job['startDate'])} / ${text(job['endDate'])}'],
          ['Jornada semanal esperada', '${hours(job['expectedHours'])} horas'],
        ]),
      );
      widgets.add(pw.SizedBox(height: 6));
      widgets.add(
        pw.TableHelper.fromTextArray(
          headers: ['Día', 'Hora inicial', 'Hora final', 'Horas'],
          data: blocks.map((block) {
            final day = block['day'];
            return [
              day is int && day >= 1 && day <= 6 ? days[day] : text(day),
              text(block['start']),
              text(block['end']),
              blockHours(block).toStringAsFixed(2),
            ];
          }).toList(),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: pw.BoxDecoration(color: blue),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          cellAlignment: pw.Alignment.center,
          cellAlignments: {0: pw.Alignment.centerLeft},
          columnWidths: {
            0: const pw.FlexColumnWidth(1.3),
            1: const pw.FlexColumnWidth(),
            2: const pw.FlexColumnWidth(),
            3: const pw.FlexColumnWidth(0.8),
          },
          border: pw.TableBorder.all(color: line, width: 0.5),
          oddRowDecoration: pw.BoxDecoration(color: lightBlue),
        ),
      );
      widgets.add(pw.SizedBox(height: 9));
    }
    return widgets;
  }

  final internal = maps(declaration['appointments']);
  final external = maps(declaration['externalJobs']);
  double total(List<Map<String, dynamic>> jobs) => jobs.fold<double>(
    0,
    (sum, job) =>
        sum + maps(job['blocks']).fold<double>(0, (s, b) => s + blockHours(b)),
  );
  String wrappedHash(dynamic value) {
    final hash = text(value);
    return [
      for (var i = 0; i < hash.length; i += 32)
        hash.substring(i, i + 32 < hash.length ? i + 32 : hash.length),
    ].join('\n');
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(38, 30, 38, 34),
      maxPages: 100,
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 9),
        margin: const pw.EdgeInsets.only(bottom: 9),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: blue, width: 1.5)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Image(logo, width: 175, height: 49, fit: pw.BoxFit.contain),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'DECLARACIÓN JURADA',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: blue,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Horario y jornada de trabajo',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Período ${text(declaration['periodId'])} | Versión ${text(declaration['version'])}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 7),
        decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: line, width: 0.5)),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              'Registro electrónico interno académico. No equivale a firma digital certificada.',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Universidad de Costa Rica | DeclaraHorario',
                  style: const pw.TextStyle(fontSize: 7),
                ),
                pw.Text(
                  'Página ${context.pageNumber} de ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7),
                ),
              ],
            ),
          ],
        ),
      ),
      build: (context) => [
        heading('1. DATOS DEL DECLARANTE'),
        details([
          ['Nombre completo', text(declaration['ownerName'])],
          ['Identificación', text(declaration['identification'])],
          ['Correo electrónico', text(declaration['email'])],
          ['Teléfono', text(declaration['phone'])],
          ['Unidad académica / administrativa', text(declaration['unit'])],
          [
            'Estado del trámite',
            text(declaration['status']).replaceAll('_', ' '),
          ],
        ]),
        ...appointments('2. NOMBRAMIENTOS INSTITUCIONALES', internal),
        ...appointments('3. TRABAJOS EN OTRAS INSTITUCIONES', external),
        heading('4. RESUMEN DE HORAS'),
        details([
          [
            'Horas institucionales',
            '${total(internal).toStringAsFixed(2)} horas',
          ],
          ['Horas externas', '${total(external).toStringAsFixed(2)} horas'],
        ]),
        heading('5. OBSERVACIONES'),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: line, width: 0.5),
          ),
          child: pw.Text(
            (declaration['observations'] ?? '').toString().trim().isEmpty
                ? 'Sin observaciones.'
                : declaration['observations'].toString(),
            style: const pw.TextStyle(fontSize: 9, lineSpacing: 3),
          ),
        ),
        heading('6. DECLARACIÓN Y FIRMAS'),
        pw.Paragraph(
          text: 'Declaro bajo juramento que los datos consignados son veraces.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        if (signatures.isEmpty)
          details([
            [
              'Firmas electrónicas internas',
              'Sin firmas registradas para esta versión.',
            ],
          ]),
        for (final signature in signatures) ...[
          details([
            [
              'Tipo de firma',
              signature['type'] == 'owner'
                  ? 'Declarante'
                  : signature['type'] == 'superior'
                  ? 'Superior'
                  : text(signature['type']),
            ],
            ['Nombre', text(signature['name'])],
            ['Identificador', text(signature['id'])],
            ['Huella SHA-256', wrappedHash(signature['hash'])],
          ]),
          pw.SizedBox(height: 8),
        ],
      ],
    ),
  );
  return pdf.save();
}
