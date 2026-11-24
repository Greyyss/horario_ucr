import 'package:flutter/material.dart';

import '../models/declaration.dart';
import '../pages/declaration_observation_tools.dart';
import '../services/validation_service.dart';

class DeclaredHoursSummary extends StatelessWidget {
  const DeclaredHoursSummary({
    super.key,
    required this.blocks,
    required this.expectedHours,
    this.compact = false,
    this.position,
  });

  final List<TimeBlock> blocks;
  final double expectedHours;
  final bool compact;
  final String? position;

  String _duration(int minutes) => '${minutes ~/ 60} h ${minutes % 60} min';

  @override
  Widget build(BuildContext context) {
    final teaching = position == null
        ? blocks.isEmpty || blocks.any((block) => block.activityType != null)
        : DeclarationObservationTools.isTeaching(position!);

    final totals = <String, int>{
      'CONTACTO': 0,
      'CONSULTA': 0,
      'PREPARACION': 0,
    };

    var total = 0;

    for (final block in blocks) {
      final minutes = ValidationService.minutes(block.end) -
          ValidationService.minutes(block.start);

      total += minutes;

      if (totals.containsKey(block.activityType)) {
        totals[block.activityType!] = totals[block.activityType]! + minutes;
      }
    }

    final expected = (expectedHours * 60).round();
    final remaining = expected - total;

    final pending = remaining < 0
        ? 'Excede la jornada por ${_duration(-remaining)}'
        : remaining == 0
            ? 'Jornada completa'
            : 'Pendiente de distribuir: ${_duration(remaining)}';

    final labels = <(String, String)>[
      if (teaching) ...[
        ('Contacto', _duration(totals['CONTACTO']!)),
        ('Consulta', _duration(totals['CONSULTA']!)),
        ('Preparación', _duration(totals['PREPARACION']!)),
      ] else
        ('Actividad', _duration(total)),
    ];

    Widget line(
      String label,
      String value, {
      bool strong = false,
    }) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );

    final pendingStyle = TextStyle(
      fontSize: 12,
      color: remaining < 0
          ? Theme.of(context).colorScheme.error
          : const Color(0xFF40546A),
    );

    if (compact) {
      final compactLabels = [
        ...labels,
        (
          'Total UCR',
          '${_duration(total)} / ${_duration(expected)}',
        ),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 0,
            runSpacing: 6,
            children: [
              for (var index = 0; index < compactLabels.length; index++)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 12,
                  ),
                  decoration: index == 0
                      ? null
                      : const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Color(0xFFCED7E0),
                            ),
                          ),
                        ),
                  child: Text(
                    '${compactLabels[index].$1}: '
                    '${compactLabels[index].$2}',
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF34485D),
                      fontWeight: index == compactLabels.length - 1
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(pending, style: pendingStyle),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC5D5E6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in labels) line(item.$1, item.$2),
          const Divider(height: 12),
          line(
            'Total declarado',
            '${_duration(total)} / ${_duration(expected)}',
            strong: true,
          ),
          Text(pending, style: pendingStyle),
        ],
      ),
    );
  }
}
