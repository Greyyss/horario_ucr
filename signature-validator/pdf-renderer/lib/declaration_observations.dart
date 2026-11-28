/// Genera el resumen a partir del contenido de una declaración.
/// No modifica Firestore ni los documentos firmados.
String generateDeclarationSummary(Map<String, dynamic> declaration) {
  const teaching = {
    'Interino Bachiller',
    'Interino Licenciado',
    'Instructor',
    'Adjunto',
    'Asociado',
    'Catedrático',
  };
  const labels = {
    'CONTACTO': 'horas contacto',
    'CONSULTA': 'horas de consulta',
    'PREPARACION': 'preparación',
  };
  const days = [
    '',
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
  ];

  String text(dynamic value) => value?.toString().trim() ?? '';
  List<Map<String, dynamic>> maps(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : [];

  int day(Map<String, dynamic> block) => (block['day'] as num?)?.toInt() ?? 0;
  int minutes(dynamic value) {
    final parts = text(value).split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  String ranges(List<Map<String, dynamic>> source) {
    final blocks = List<Map<String, dynamic>>.of(source)
      ..sort((a, b) {
        final byDay = day(a).compareTo(day(b));
        if (byDay != 0) return byDay;
        final byStart = minutes(a['start']).compareTo(minutes(b['start']));
        return byStart != 0
            ? byStart
            : minutes(a['end']).compareTo(minutes(b['end']));
      });
    return blocks.map((block) {
      final number = day(block);
      final name =
          number >= 1 && number <= 6 ? days[number] : 'día sin especificar';
      return '$name de ${text(block['start'])} a ${text(block['end'])}';
    }).join(', ');
  }

  final lines = <String>[];
  for (final job in maps(declaration['appointments'])) {
    final blocks = maps(job['blocks']);
    final position = text(job['position']);
    if (teaching.contains(position)) {
      final courses = <String, Map<String, List<Map<String, dynamic>>>>{};
      for (final block in blocks) {
        final code = text(block['courseCode']);
        final course = code.isEmpty ? 'Curso sin especificar' : code;
        final type = text(block['activityType']);
        courses.putIfAbsent(course, () => {});
        courses[course]!.putIfAbsent(type, () => []).add(block);
      }
      final codes = courses.keys.toList()..sort();
      for (final code in codes) {
        final types = courses[code]!;
        final parts = <String>[];
        for (final type in labels.keys) {
          if (types.containsKey(type))
            parts.add('${labels[type]}: ${ranges(types[type]!)}');
        }
        for (final type in types.keys.where(
          (type) => !labels.containsKey(type),
        )) {
          parts.add('actividad sin especificar: ${ranges(types[type]!)}');
        }
        lines.add('$code: ${parts.join('; ')}.');
      }
    } else {
      final activities = <String, List<Map<String, dynamic>>>{};
      for (final block in blocks) {
        final name = text(block['activityName']);
        final activity = name.isNotEmpty
            ? name
            : position.isNotEmpty
                ? position
                : 'Actividad institucional';
        activities.putIfAbsent(activity, () => []).add(block);
      }
      for (final entry in activities.entries) {
        lines.add('${entry.key}: ${ranges(entry.value)}.');
      }
    }
  }
  for (final job in maps(declaration['externalJobs'])) {
    final blocks = maps(job['blocks']);
    if (blocks.isNotEmpty) {
      lines.add(
        '${text(job['position'])} en ${text(job['workplace'])}: ${ranges(blocks)}.',
      );
    }
  }
  return lines.join('\n');
}

/// El PDF presenta siempre el resumen, incluso en estado DEVUELTA.
/// Conserva las observaciones guardadas; reconstruye solo si estaban vacías.
String declarationPdfObservations(Map<String, dynamic> declaration) {
  final saved = declaration['observations']?.toString().trim() ?? '';
  if (saved.isNotEmpty) return saved;
  final summary = generateDeclarationSummary(declaration);
  return summary.isEmpty
      ? 'No hay horarios registrados para generar el resumen.'
      : summary;
}

/// Encuentra el motivo de devolución más reciente para destacarlo en historial.
Map<String, dynamic>? latestDeclarationReturn(
  List<Map<String, dynamic>> newestFirst, {
  required String status,
  required String currentReturnNote,
  required int currentVersion,
}) {
  final currentNote = currentReturnNote.trim();
  if (status == 'DEVUELTA' && currentNote.isNotEmpty) {
    for (final event in newestFirst) {
      if (event['event'] == 'return' && event['version'] == currentVersion) {
        return {...event, 'observation': currentNote};
      }
    }
    return {'observation': currentNote, 'version': currentVersion};
  }
  for (final event in newestFirst) {
    if (event['event'] == 'return' &&
        (event['observation']?.toString().trim() ?? '').isNotEmpty) {
      return Map<String, dynamic>.from(event);
    }
  }
  return null;
}
