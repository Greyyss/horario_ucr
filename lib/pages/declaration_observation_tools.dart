import '../models/declaration.dart';

class DeclarationObservationTools {
  static const teachingPositions = <String>{
    'Interino Bachiller',
    'Interino Licenciado',
    'Instructor',
    'Adjunto',
    'Asociado',
    'Catedrático',
  };

  static const activityLabels = <String, String>{
    'CONTACTO': 'horas contacto',
    'CONSULTA': 'horas de consulta',
    'PREPARACION': 'preparación',
  };

  static const dayNames = <String>[
    '',
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
  ];

  static bool isTeaching(String position) {
    return teachingPositions.contains(position.trim());
  }

  static String normalizeCode(String value) {
    return value.trim().toUpperCase();
  }

  static String? blockError(
    TimeBlock block,
    String position,
    bool isExternal,
  ) {
    // Los trabajos externos no requieren datos de cursos UCR.
    if (isExternal) return null;

    if (isTeaching(position)) {
      final code = block.courseCode ?? '';

      if (code != normalizeCode(code) ||
          !RegExp(r'^[A-Z0-9][A-Z0-9-]{1,19}$').hasMatch(code)) {
        return 'Ingresá las siglas del curso: de 2 a 20 letras, '
            'números o guiones, sin espacios.';
      }

      if (!activityLabels.containsKey(block.activityType)) {
        return 'Seleccioná contacto, consulta o preparación.';
      }

      if ((block.activityName ?? '').trim().isNotEmpty) {
        return 'El cargo cambió: editá este bloque y asignale '
            'curso y tipo de actividad.';
      }
    } else {
      final name = block.activityName ?? '';

      if (name != name.trim() ||
          name.length < 2 ||
          name.length > 150 ||
          RegExp(r'[\r\n\t]').hasMatch(name)) {
        return 'Indicá el nombre de la actividad, '
            'entre 2 y 150 caracteres.';
      }

      if ((block.courseCode ?? '').isNotEmpty ||
          (block.activityType ?? '').isNotEmpty) {
        return 'El cargo cambió: editá este bloque e indicá '
            'una actividad sin curso.';
      }
    }

    return null;
  }

  static String? firstError(List<Appointment> jobs) {
    for (var i = 0; i < jobs.length; i++) {
      for (var j = 0; j < jobs[i].blocks.length; j++) {
        final error = blockError(
          jobs[i].blocks[j],
          jobs[i].position,
          false,
        );

        if (error != null) {
          return 'Nombramiento ${i + 1}, bloque ${j + 1}: $error';
        }
      }
    }

    return null;
  }

  static String blockDescription(TimeBlock block) {
    final code = (block.courseCode ?? '').trim();

    if (code.isNotEmpty) {
      final activity =
          activityLabels[block.activityType] ?? 'actividad sin especificar';

      return '$code · $activity';
    }

    return (block.activityName ?? '').trim();
  }

  static String ranges(List<TimeBlock> source) {
    final blocks = List<TimeBlock>.of(source)
      ..sort((a, b) {
        final byDay = a.day.compareTo(b.day);

        if (byDay != 0) return byDay;

        final byStart = a.start.compareTo(b.start);

        return byStart != 0 ? byStart : a.end.compareTo(b.end);
      });

    return blocks.map((block) {
      final day = block.day >= 1 && block.day <= 6
          ? dayNames[block.day]
          : 'día sin especificar';

      return '$day de ${block.start} a ${block.end}';
    }).join(', ');
  }

  static String generate(
    List<Appointment> jobs,
    List<Appointment> external,
  ) {
    final lines = <String>[];

    for (final job in jobs) {
      if (isTeaching(job.position)) {
        final courses = <String, Map<String, List<TimeBlock>>>{};

        for (final block in job.blocks) {
          final code = (block.courseCode ?? '').trim();

          final course = code.isEmpty ? 'Curso sin especificar' : code;

          final type = block.activityType ?? '';

          courses.putIfAbsent(
            course,
            () => <String, List<TimeBlock>>{},
          );

          courses[course]!.putIfAbsent(type, () => <TimeBlock>[]).add(block);
        }

        final codes = courses.keys.toList()..sort();

        for (final code in codes) {
          final types = courses[code]!;
          final parts = <String>[];

          for (final type in activityLabels.keys) {
            if (types.containsKey(type)) {
              parts.add(
                '${activityLabels[type]}: '
                '${ranges(types[type]!)}',
              );
            }
          }

          for (final type in types.keys.where(
            (type) => !activityLabels.containsKey(type),
          )) {
            parts.add(
              'actividad sin especificar: '
              '${ranges(types[type]!)}',
            );
          }

          lines.add('$code: ${parts.join('; ')}.');
        }
      } else {
        final activities = <String, List<TimeBlock>>{};

        for (final block in job.blocks) {
          final name = (block.activityName ?? '').trim();

          final activity = name.isEmpty ? job.position : name;

          activities.putIfAbsent(activity, () => <TimeBlock>[]).add(block);
        }

        for (final entry in activities.entries) {
          lines.add(
            '${entry.key}: ${ranges(entry.value)}.',
          );
        }
      }
    }

    for (final job in external) {
      if (job.blocks.isNotEmpty) {
        lines.add(
          '${job.position} en ${job.workplace}: '
          '${ranges(job.blocks)}.',
        );
      }
    }

    return lines.join('\n');
  }
}

// ============================================================
// FORMULARIO DE DECLARACIÓN
// ============================================================

