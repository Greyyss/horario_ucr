import 'package:flutter/material.dart';

import '../models/declaration.dart';
import '../services/validation_service.dart';
import 'declared_hours_summary.dart';

class DeclarationAssignmentCard extends StatelessWidget {
  const DeclarationAssignmentCard({
    super.key,
    required this.appointment,
    required this.period,
    required this.selected,
    required this.externalJobs,
    required this.onEdit,
    this.onAddExternal,
    required this.onEditExternal,
    required this.onRemoveExternal,
    this.busy = false,
  });

  final Appointment appointment;
  final String period;
  final bool selected;
  final List<Appointment> externalJobs;
  final VoidCallback onEdit;
  final VoidCallback? onAddExternal;
  final ValueChanged<Appointment> onEditExternal;
  final ValueChanged<Appointment> onRemoveExternal;
  final bool busy;

  int _minutes(Appointment job) {
    return job.blocks.fold<int>(
      0,
      (sum, block) =>
          sum +
          ValidationService.minutes(block.end) -
          ValidationService.minutes(block.start),
    );
  }

  String _duration(int value) {
    return '${value ~/ 60} h ${value % 60} min';
  }

  @override
  Widget build(BuildContext context) {
    final total = _minutes(appointment);

    final complete = selected &&
        total == (appointment.expectedHours * 60).round() &&
        ValidationService.validate(
          [appointment],
          externalJobs,
        ).valid;

    final status = !selected
        ? 'Pendiente'
        : complete
            ? 'Completo'
            : 'En edición';

    final courses = appointment.blocks
        .map((block) => block.courseCode?.trim() ?? '')
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final hours =
        appointment.expectedHours == appointment.expectedHours.roundToDouble()
            ? appointment.expectedHours.toInt().toString()
            : appointment.expectedHours.toString();

    final description =
        '${courses.isEmpty ? 'Sin curso registrado' : courses.join(', ')} | '
        '${period.isEmpty ? 'Sin período registrado' : period} | '
        'Jornada: $hours h';

    final internal = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Nombramiento UCR',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF53667B),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 9),
        DeclaredHoursSummary(
          blocks: appointment.blocks,
          expectedHours: appointment.expectedHours,
          compact: true,
        ),
      ],
    );

    final institutions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Otras instituciones',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF53667B),
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final job in externalJobs)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.workplace,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${job.position} | ${_duration(_minutes(job))}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF53667B),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Editar ${job.workplace}',
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      busy ? null : () => onEditExternal(job),
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar ${job.workplace}',
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      busy ? null : () => onRemoveExternal(job),
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Total externo: '
          '${_duration(externalJobs.fold<int>(
            0,
            (sum, job) => sum + _minutes(job),
          ))}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    final actions = PopupMenuButton<String>(
      tooltip: 'Acciones del nombramiento',
      enabled: !busy,
      onSelected: (action) {
        if (action == 'edit') {
          onEdit();
        } else {
          onAddExternal?.call();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: Text('Editar nombramiento'),
        ),
        PopupMenuItem(
          value: 'external',
          enabled: onAddExternal != null,
          child: const Text('Declarar otra institución'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: complete
              ? const Color(0xFFEBF4F5)
              : const Color(0xFFF0F4F8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFFD6E0E9),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              status,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF284969),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.expand_more,
              size: 18,
              color: Color(0xFF284969),
            ),
          ],
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: const Color(0xFFC5D5E6),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.position,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1D334A),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF53667B),
                    ),
                  ),
                ],
              );

              if (constraints.maxWidth < 480) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: 12),
                    actions,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 16),
                  actions,
                ],
              );
            },
          ),
          const Divider(
            height: 26,
            color: Color(0xFFE0E6ED),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              if (externalJobs.isEmpty) {
                return internal;
              }

              if (constraints.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    internal,
                    const Divider(height: 26),
                    institutions,
                  ],
                );
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: internal,
                    ),
                    const VerticalDivider(
                      width: 32,
                      thickness: 1,
                      color: Color(0xFFCED7E0),
                    ),
                    Expanded(
                      flex: 2,
                      child: institutions,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}