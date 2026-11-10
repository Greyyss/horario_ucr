import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Presenta los datos de la versión guardada.
/// Los permisos y la comprobación de firmas siguen en el servicio.
Future<Uint8List> buildDeclarationPdfTables({
  required Map<String, dynamic> declaration,
  required List<Map<String, dynamic>> signatures,
  required Uint8List logoBytes,
}) async {
  final pdf = pw.Document();
  final logo = pw.MemoryImage(logoBytes);

  final blue = PdfColor.fromHex('#163A63');
  final lightBlue = PdfColor.fromHex('#EDF3FA');
  final line = PdfColor.fromHex('#CAD4E0');

  const days = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
  ];

  const workloadHours = <String, double>{
    '1/8': 5,
    '1/4': 10,
    '3/8': 15,
    '1/2': 20,
    '5/8': 25,
    '3/4': 30,
    '7/8': 35,
    '1 TC': 40,
  };

  String text(dynamic value) {
    return value?.toString() ?? '';
  }

  List<Map<String, dynamic>> maps(dynamic value) {
    return (value as List? ?? []).map((item) {
      return Map<String, dynamic>.from(item as Map);
    }).toList();
  }

  String hours(dynamic value) {
    if (value is! num) return '';

    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  DateTime? instant(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  String signatureDate(
    dynamic value, {
    bool withTime = false,
  }) {
    final original = instant(value);

    if (original == null) {
      return 'Pendiente de firma';
    }

    final costaRica = original.toUtc().subtract(
          const Duration(hours: 6),
        );

    String two(int number) {
      return number.toString().padLeft(2, '0');
    }

    final date = '${two(costaRica.day)}/'
        '${two(costaRica.month)}/'
        '${costaRica.year.toString().padLeft(4, '0')}';

    if (!withTime) return date;

    return '$date '
        '${two(costaRica.hour)}:'
        '${two(costaRica.minute)}:'
        '${two(costaRica.second)} '
        '(Costa Rica, UTC-6)';
  }

  String validity(dynamic value) {
    final source = text(value);
    final parts = source.split('-');

    if (parts.length == 3 && parts[0].length == 4) {
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    }

    return source;
  }

  String wrappedHash(dynamic value) {
    final hash = text(value);

    return [
      for (var i = 0; i < hash.length; i += 32)
        hash.substring(
          i,
          i + 32 < hash.length ? i + 32 : hash.length,
        ),
    ].join('\n');
  }

  int? minute(dynamic value) {
    final parts = text(value).split(':');

    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final min = int.tryParse(parts[1]);

    if (hour == null ||
        min == null ||
        hour < 0 ||
        hour > 23 ||
        min < 0 ||
        min > 59) {
      return null;
    }

    return hour * 60 + min;
  }

  double totalHours(List<Map<String, dynamic>> jobs) {
    var total = 0.0;

    for (final job in jobs) {
      for (final block in maps(job['blocks'])) {
        final start = minute(block['start']);
        final end = minute(block['end']);

        if (start != null && end != null && end > start) {
          total += (end - start) / 60;
        }
      }
    }

    return total;
  }

  pw.Widget cell(
    String value, {
    bool bold = false,
    bool header = false,
    double size = 7.5,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 4,
      ),
      color: header ? lightBlue : null,
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: size,
          color: header ? blue : PdfColors.black,
          fontWeight:
              bold || header ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget heading(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(
        top: 9,
        bottom: 5,
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: blue,
        ),
      ),
    );
  }

  pw.Widget details(List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(
        color: line,
        width: 0.5,
      ),
      columnWidths: {
        0: const pw.FixedColumnWidth(140),
        1: const pw.FlexColumnWidth(),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows.map((row) {
        return pw.TableRow(
          children: [
            cell(row[0], header: true),
            cell(row[1]),
          ],
        );
      }).toList(),
    );
  }

  // Cada día tiene De / A.
  // El curso y la actividad se muestran debajo de esas horas.
  pw.Widget dayCell(
    String from,
    String to, {
    String? dayHeading,
    String activity = '',
  }) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        if (dayHeading != null)
          pw.Container(
            width: double.infinity,
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              color: lightBlue,
              border: pw.Border(
                bottom: pw.BorderSide(
                  color: line,
                  width: 0.5,
                ),
              ),
            ),
            child: pw.Text(
              dayHeading,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: blue,
              ),
            ),
          ),
        pw.Row(
          children: [
            pw.Expanded(
              child: cell(
                from,
                header: dayHeading != null,
                size: 7,
              ),
            ),
            pw.Expanded(
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    left: pw.BorderSide(
                      color: line,
                      width: 0.5,
                    ),
                  ),
                ),
                child: cell(
                  to,
                  header: dayHeading != null,
                  size: 7,
                ),
              ),
            ),
          ],
        ),
        if (activity.isNotEmpty)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(
              4,
              0,
              4,
              5,
            ),
            child: pw.Text(
              activity,
              style: pw.TextStyle(
                fontSize: 6.5,
                color: blue,
              ),
            ),
          ),
      ],
    );
  }

  pw.Widget scheduleTable(
    List<Map<String, dynamic>> jobs, {
    required bool internal,
  }) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(
          color: lightBlue,
        ),
        children: [
          cell('Lugar de trabajo', header: true),
          cell('Cargo o categoría', header: true),
          cell('Jornada de trabajo', header: true),
          cell('Vigencia\nDesde', header: true),
          cell('Vigencia\nHasta', header: true),
          for (final day in days)
            dayCell(
              'De',
              'A',
              dayHeading: day,
            ),
        ],
      ),
    ];

    if (jobs.isEmpty) {
      rows.add(
        pw.TableRow(
          children: [
            cell('Sin registros'),
            for (var i = 1; i < 5; i++) cell(''),
            for (var i = 0; i < 6; i++) dayCell('', ''),
          ],
        ),
      );
    }

    for (var jobIndex = 0; jobIndex < jobs.length; jobIndex++) {
      final job = jobs[jobIndex];

      final byDay = List.generate(
        6,
        (_) => <Map<String, dynamic>>[],
      );

      for (final block in maps(job['blocks'])) {
        final day = block['day'];

        if (day is int && day >= 1 && day <= 6) {
          byDay[day - 1].add(block);
        }
      }

      for (final blocks in byDay) {
        blocks.sort((a, b) {
          return (minute(a['start']) ?? 0).compareTo(
            minute(b['start']) ?? 0,
          );
        });
      }

      final rowCount = byDay.fold<int>(
        1,
        (largest, blocks) => largest > blocks.length ? largest : blocks.length,
      );

      final fraction = text(job['workloadFraction']);

      final load = internal && workloadHours.containsKey(fraction)
          ? '$fraction\n(${hours(job['expectedHours'])} h)'
          : '${hours(job['expectedHours'])} horas';

      // Cada bloque adicional del mismo día ocupa otra fila.
      // Se mantiene la relación entre horario, curso y actividad.
      for (var slot = 0; slot < rowCount; slot++) {
        rows.add(
          pw.TableRow(
            children: [
              cell(
                slot == 0
                    ? text(job['workplace'])
                    : 'Registro ${jobIndex + 1} (cont.)',
              ),
              cell(
                slot == 0
                    ? text(job['position'])
                    : '${text(job['position'])} (cont.)',
              ),
              cell(slot == 0 ? load : ''),
              cell(
                slot == 0 ? validity(job['startDate']) : '',
                size: 6.5,
              ),
              cell(
                slot == 0 ? validity(job['endDate']) : '',
                size: 6.5,
              ),
              for (final blocks in byDay)
                dayCell(
                  slot < blocks.length ? text(blocks[slot]['start']) : '',
                  slot < blocks.length ? text(blocks[slot]['end']) : '',
                ),
            ],
          ),
        );
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(
        color: line,
        width: 0.5,
      ),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(1.65),
        2: const pw.FlexColumnWidth(0.9),
        3: const pw.FlexColumnWidth(0.9),
        4: const pw.FlexColumnWidth(0.9),
        for (var i = 5; i < 11; i++) i: const pw.FlexColumnWidth(1.25),
      },
      children: rows,
    );
  }

  Map<String, dynamic>? ownerSignature;
  Map<String, dynamic>? superiorSignature;

  for (final signature in signatures) {
    if (signature['type'] == 'owner') {
      ownerSignature = signature;
    }

    if (signature['type'] == 'superior') {
      superiorSignature = signature;
    }
  }

  pw.Widget signatureBox(
    String label,
    Map<String, dynamic>? signature,
  ) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            signature == null ? 'Pendiente de firma' : text(signature['name']),
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            signature == null
                ? ''
                : signatureDate(
                    signature['dateTime'],
                    withTime: true,
                  ),
            style: const pw.TextStyle(fontSize: 7),
          ),
          pw.SizedBox(height: 5),
          pw.Divider(
            thickness: 0.5,
            color: line,
          ),
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: blue,
            ),
          ),
        ],
      ),
    );
  }

  final internal = maps(declaration['appointments']);
  final external = maps(declaration['externalJobs']);

  final observations = text(declaration['observations']).trim();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter.landscape,
      margin: const pw.EdgeInsets.fromLTRB(
        24,
        18,
        24,
        24,
      ),
      maxPages: 100,
      header: (context) {
        return pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 6),
          margin: const pw.EdgeInsets.only(bottom: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(
                color: blue,
                width: 1,
              ),
            ),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(
                logo,
                width: 110,
                height: 40,
                fit: pw.BoxFit.contain,
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'UNIVERSIDAD DE COSTA RICA',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: blue,
                      ),
                    ),
                    pw.Text(
                      'Oficina de Recursos Humanos',
                      style: const pw.TextStyle(
                        fontSize: 9,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'DECLARACIÓN JURADA DE HORARIO '
                      'Y JORNADA DE TRABAJO',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      footer: (context) {
        return pw.Column(
          children: [
            pw.Divider(
              thickness: 0.5,
              color: line,
            ),
            pw.Text(
              'Registro electrónico interno académico. '
              'No equivale a firma digital certificada.',
              style: const pw.TextStyle(
                fontSize: 6,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'DeclaraHorario | '
                  'Período ${text(declaration['periodId'])} | '
                  'Versión ${text(declaration['version'])}',
                  style: const pw.TextStyle(
                    fontSize: 6,
                  ),
                ),
                pw.Text(
                  'Página ${context.pageNumber} '
                  'de ${context.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 6,
                  ),
                ),
              ],
            ),
          ],
        );
      },
      build: (context) => [
        pw.Table(
          border: pw.TableBorder.all(
            color: line,
            width: 0.5,
          ),
          children: [
            pw.TableRow(
              children: [
                cell(
                  'Nombre del funcionario(a): '
                  '${text(declaration['ownerName'])}',
                ),
                cell(
                  'Cédula: '
                  '${text(declaration['identification'])}',
                ),
                cell(
                  'Teléfono: '
                  '${text(declaration['phone'])}',
                ),
              ],
            ),
            pw.TableRow(
              children: [
                cell(
                  'Unidad académica o administrativa: '
                  '${text(declaration['unit'])}',
                ),
                cell(
                  'Correo: '
                  '${text(declaration['email'])}',
                ),
                cell(
                  'Fecha de declaración: '
                  '${signatureDate(ownerSignature?['dateTime'])}',
                ),
              ],
            ),
          ],
        ),
        heading(
          'A continuación declaro los horarios '
          'y jornadas convenidos con:',
        ),
        heading(
          'UNIVERSIDAD DE COSTA RICA '
          '(sea como docente y/o administrativo)',
        ),
        scheduleTable(
          internal,
          internal: true,
        ),
        heading(
          'OTRAS INSTITUCIONES PÚBLICAS, '
          'PRIVADAS Y FUNDACIONES',
        ),
        scheduleTable(
          external,
          internal: false,
        ),
        pw.SizedBox(height: 7),
        pw.Text(
          'Horas institucionales: '
          '${totalHours(internal).toStringAsFixed(2)} | '
          'Horas externas: '
          '${totalHours(external).toStringAsFixed(2)}',
          style: const pw.TextStyle(
            fontSize: 7,
          ),
        ),
        heading('OBSERVACIONES'),

        // Presenta las observaciones guardadas.
        // No las vuelve a generar al abrir el PDF.
        // Cada párrafo puede continuar en otra página.
        pw.Table(
          border: pw.TableBorder(
            top: pw.BorderSide(
              color: line,
              width: 0.5,
            ),
            bottom: pw.BorderSide(
              color: line,
              width: 0.5,
            ),
            left: pw.BorderSide(
              color: line,
              width: 0.5,
            ),
            right: pw.BorderSide(
              color: line,
              width: 0.5,
            ),
          ),
          children: [
            for (final paragraph
                in (observations.isEmpty ? 'Sin observaciones.' : observations)
                    .split(RegExp(r'\r?\n')))
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    child: pw.Text(
                      paragraph.isEmpty ? ' ' : paragraph,
                      style: const pw.TextStyle(
                        fontSize: 8,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),

        pw.SizedBox(height: 8),
        pw.Text(
          'Declaro bajo juramento que los datos proporcionados '
          'en este documento son ciertos y que conozco las '
          'sanciones establecidas por la legislación institucional '
          'y nacional vigentes, que se refieren a la declaración '
          'falsa u omisa de las jornadas y horarios laborales '
          'aquí consignados.',
          style: const pw.TextStyle(
            fontSize: 8,
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            signatureBox(
              'Firma del Funcionario(a) Declarante',
              ownerSignature,
            ),
            pw.SizedBox(width: 28),
            signatureBox(
              'Superior Jerárquico Unidad',
              superiorSignature,
            ),
          ],
        ),
        if (signatures.isNotEmpty) ...[
          pw.NewPage(),
          heading(
            'ANEXO: REGISTRO DE FIRMAS '
            'ELECTRÓNICAS INTERNAS',
          ),
          pw.Text(
            'Detalle de las firmas correspondientes '
            'a esta versión de la declaración.',
            style: const pw.TextStyle(
              fontSize: 8,
            ),
          ),
          for (final signature in signatures) ...[
            pw.SizedBox(height: 12),
            details([
              [
                'Firmante en calidad de',
                signature['type'] == 'owner'
                    ? 'Declarante'
                    : signature['type'] == 'superior'
                        ? 'Superior'
                        : text(signature['type']),
              ],
              [
                'Nombre',
                text(signature['name']),
              ],
              [
                'Fecha y hora de firma',
                signatureDate(
                  signature['dateTime'],
                  withTime: true,
                ),
              ],
              [
                'Huella SHA-256',
                wrappedHash(signature['hash']),
              ],
            ]),
          ],
        ],
      ],
    ),
  );

  return pdf.save();
}
