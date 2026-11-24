import 'package:flutter/material.dart';

class DeclarationPersonalSummary extends StatelessWidget {
  const DeclarationPersonalSummary({
    super.key,
    required this.name,
    required this.identification,
    required this.email,
    required this.unit,
    required this.superior,
  });

  final String name;
  final String identification;
  final String email;
  final String unit;
  final String superior;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('Nombre', name),
      ('Cédula', identification),
      ('Correo', email),
      ('Unidad', unit),
      ('Superior', superior),
    ];

    Widget field(String label, String value) {
      final text = value.trim().isEmpty ? 'Sin registrar' : value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF53667B),
            ),
          ),
          const SizedBox(height: 5),
          Tooltip(
            message: text,
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1D334A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC5D5E6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 980) {
            const flex = [3, 2, 4, 3, 3];

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < values.length; i++) ...[
                  if (i > 0) const SizedBox(width: 20),
                  Expanded(
                    flex: flex[i],
                    child: field(values[i].$1, values[i].$2),
                  ),
                ],
              ],
            );
          }

          final width = constraints.maxWidth < 460
              ? constraints.maxWidth
              : (constraints.maxWidth - 20) / 2;

          return Wrap(
            spacing: 20,
            runSpacing: 16,
            children: [
              for (final value in values)
                SizedBox(
                  width: width,
                  child: field(value.$1, value.$2),
                ),
            ],
          );
        },
      ),
    );
  }
}