import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/models/declaration.dart';
import '../lib/widgets/declared_hours_summary.dart';

const contact = [
  TimeBlock(
    day: 2,
    start: '08:00',
    end: '12:00',
    courseCode: 'IF0013',
    activityType: 'CONTACTO',
  ),
  TimeBlock(
    day: 4,
    start: '08:00',
    end: '12:00',
    courseCode: 'IF0013',
    activityType: 'CONTACTO',
  ),
];
void main() {
  testWidgets('Asigna contacto y muestra las siete horas pendientes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeclaredHoursSummary(blocks: contact, expectedHours: 15),
        ),
      ),
    );
    expect(find.text('Contacto'), findsOneWidget);
    expect(find.text('Consulta'), findsOneWidget);
    expect(find.text('Preparación'), findsOneWidget);
    expect(find.text('8 h 0 min / 15 h 0 min'), findsOneWidget);
    expect(find.text('Pendiente de distribuir: 7 h 0 min'), findsOneWidget);
  });
  testWidgets('Actualiza total al distribuir consulta y preparación', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeclaredHoursSummary(
            expectedHours: 15,
            blocks: [
              ...contact,
              TimeBlock(
                day: 1,
                start: '08:00',
                end: '10:00',
                activityType: 'CONSULTA',
              ),
              TimeBlock(
                day: 3,
                start: '07:00',
                end: '12:00',
                activityType: 'PREPARACION',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('2 h 0 min'), findsOneWidget);
    expect(find.text('5 h 0 min'), findsOneWidget);
    expect(find.text('15 h 0 min / 15 h 0 min'), findsOneWidget);
    expect(find.text('Jornada completa'), findsOneWidget);
  });
  test('Conserva la referencia al serializar y reabrir el nombramiento', () {
    final original = Appointment(
      assignmentId: 'asignacion1',
      workplace: 'Universidad de Costa Rica',
      position: 'Interino Bachiller',
      startDate: '2027-01-04',
      endDate: '2027-03-06',
      expectedHours: 15,
      workloadFraction: '3/8',
      blocks: contact,
    );
    final reopened = Appointment.fromMap(original.toMap());
    expect(reopened.assignmentId, 'asignacion1');
    expect(reopened.blocks.length, 2);
    expect(reopened.workloadFraction, '3/8');
  });
}
