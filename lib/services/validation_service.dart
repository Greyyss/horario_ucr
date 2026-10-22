import '../models/declaration.dart';

class ValidationResult {
  final List<String> errors;
  final double institutionalHours;
  final double externalHours;
  final double expectedHours;

  bool get valid => errors.isEmpty;

  const ValidationResult(
    this.errors,
    this.institutionalHours,
    this.externalHours,
    this.expectedHours,
  );
}

class ValidationService {
  // Evita que Dart convierta fechas inexistentes en otras fechas.
  static DateTime? parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  static int minutes(String time) {
    final parts = time.split(':');

    if (parts.length != 2) {
      throw const FormatException('Hora inválida');
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      throw const FormatException('Hora inválida');
    }

    return hour * 60 + minute;
  }

  static String formatMinutes(int value) {
    final hour = (value ~/ 60).toString().padLeft(2, '0');
    final minute = (value % 60).toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  static ValidationResult validate(
    List<Appointment> jobs,
    List<Appointment> external,
  ) {
    final errors = <String>[];

    final byDay = <int, List<({int start, int end, String source})>>{};

    double internal = 0;
    double outside = 0;
    double expected = 0;

    if (jobs.isEmpty) {
      errors.add('Debe registrar al menos un nombramiento institucional.');
    }

    final allJobs = [
      ...jobs.map((job) => (job: job, external: false)),
      ...external.map((job) => (job: job, external: true)),
    ];

    for (final entry in allJobs) {
      final job = entry.job;

      if (job.workplace.trim().isEmpty ||
          job.position.trim().isEmpty ||
          job.startDate.isEmpty ||
          job.endDate.isEmpty) {
        errors.add('Complete los datos del nombramiento: ${job.workplace}.');
      }

      final startDate = parseDate(job.startDate);
      final endDate = parseDate(job.endDate);

      final noEndDate = job.endDate.trim().toLowerCase() == 'no aplica';

      if (startDate == null ||
          (!noEndDate && (endDate == null || endDate.isBefore(startDate)))) {
        errors.add('Vigencia inválida en ${job.workplace}.');
      }

      final validExpectedHours =
          job.expectedHours.isFinite && job.expectedHours > 0;
      if (!validExpectedHours) {
        errors.add(
          'La jornada debe ser un número finito mayor que cero '
          'en ${job.workplace}.',
        );
      }

      if (!entry.external && validExpectedHours) {
        expected += job.expectedHours;
      }

      if (job.blocks.isEmpty) {
        errors.add('Agregue al menos un horario a ${job.workplace}.');
      }

      for (final block in job.blocks) {
        try {
          final start = minutes(block.start);
          final end = minutes(block.end);

          if (block.day < 1 || block.day > 6) {
            errors.add('Solo se admiten horarios de lunes a sábado.');
            continue;
          }

          if (end <= start) {
            errors.add(
              'La hora final debe ser posterior a la inicial '
              '(${job.workplace}).',
            );
            continue;
          }

          if (start < 780 && end > 720) {
            errors.add(
              'Horario excluido de 12:00 a 13:00 '
              'en ${job.workplace}.',
            );
          }

          byDay.putIfAbsent(block.day, () => []).add((
            start: start,
            end: end,
            source: job.workplace,
          ));

          final hours = (end - start) / 60;

          if (entry.external) {
            outside += hours;
          } else {
            internal += hours;
          }
        } catch (_) {
          errors.add('Formato de hora inválido en ${job.workplace}.');
        }
      }
    }

    for (final entry in byDay.entries) {
      final blocks = entry.value;

      blocks.sort((a, b) => a.start.compareTo(b.start));

      // Calcular minutos únicos, sin duplicar traslapes.
      int totalMinutes = 0;
      int? currentStart;
      int? currentEnd;

      for (final block in blocks) {
        if (currentStart == null || currentEnd == null) {
          currentStart = block.start;
          currentEnd = block.end;
        } else if (block.start <= currentEnd) {
          if (block.end > currentEnd) {
            currentEnd = block.end;
          }
        } else {
          totalMinutes += currentEnd - currentStart;
          currentStart = block.start;
          currentEnd = block.end;
        }
      }

      if (currentStart != null && currentEnd != null) {
        totalMinutes += currentEnd - currentStart;
      }

      if (totalMinutes > 600) {
        errors.add(
          'Día ${entry.key}: excede el máximo '
          'de 10 horas declaradas.',
        );
      }

      // Detectar traslapes internos y externos.
      for (var i = 1; i < blocks.length; i++) {
        for (var j = 0; j < i; j++) {
          final first = blocks[j];
          final second = blocks[i];

          if (first.end > second.start && second.end > first.start) {
            final overlapStart =
                first.start > second.start ? first.start : second.start;

            final overlapEnd = first.end < second.end ? first.end : second.end;

            errors.add(
              'Día ${entry.key}: traslape '
              '${formatMinutes(overlapStart)}–'
              '${formatMinutes(overlapEnd)} '
              'entre ${first.source} y ${second.source}.',
            );
          }
        }
      }
    }

    if ((internal - expected).abs() > 0.001) {
      errors.add(
        'Jornada institucional: '
        'esperadas ${expected.toStringAsFixed(2)} h, '
        'declaradas ${internal.toStringAsFixed(2)} h, '
        'diferencia ${(internal - expected).toStringAsFixed(2)} h.',
      );
    }

    return ValidationResult(errors, internal, outside, expected);
  }
}
