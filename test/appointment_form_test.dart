import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horario_ucr_integrador/models/declaration.dart';
import 'package:horario_ucr_integrador/pages/dashboard.dart';

const _requiredMessage =
    'Completá institución, puesto, una jornada numérica mayor que cero y al menos un horario.';
const _dateMessage =
    'Seleccioná fechas válidas; el fin no puede ser anterior al inicio.';

Appointment fixture({
  String workplace = 'UCR',
  String position = 'Docente',
  double expected = 4,
  String startDate = '2026-08-01',
  String endDate = '2026-12-01',
  List<TimeBlock> blocks = const [
    TimeBlock(day: 1, start: '08:00', end: '12:00'),
  ],
}) => Appointment(
  workplace: workplace,
  position: position,
  expectedHours: expected,
  startDate: startDate,
  endDate: endDate,
  blocks: blocks,
);

class FormResult {
  bool returned = false;
  Appointment? value;
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<FormResult> openForm(
  WidgetTester tester, {
  Appointment? existing,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 1800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final result = FormResult();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result.value = await Navigator.of(context).push<Appointment>(
                  MaterialPageRoute(
                    builder: (_) => AppointmentPage(existing: existing),
                  ),
                );
                result.returned = true;
              },
              child: const Text('Abrir formulario de prueba'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir formulario de prueba'));
  await tester.pumpAndSettle();
  expect(find.byType(AppointmentPage), findsOneWidget);
  return result;
}

Future<void> submit(WidgetTester tester) async {
  final button = find.byType(FilledButton);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void blocked(WidgetTester tester, FormResult result, String message) {
  expect(result.returned, isFalse, reason: 'El formulario no debe cerrarse.');
  expect(result.value, isNull);
  expect(find.byType(AppointmentPage), findsOneWidget);
  expect(find.widgetWithText(SnackBar, message), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> chooseToday(WidgetTester tester, String label) async {
  await tester.ensureVisible(field(label));
  await tester.tap(field(label));
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsOneWidget);
  await tester.tap(find.text('Aceptar'));
  await tester.pumpAndSettle();
}

Future<void> fillNew(WidgetTester tester) async {
  await tester.enterText(field('Lugar de trabajo / institución'), '  UCR  ');
  await tester.enterText(field('Cargo o categoría'), '  Docente  ');
  await tester.enterText(field('Jornada semanal esperada (horas)'), '4');
  await chooseToday(tester, 'Inicio de vigencia');
  await chooseToday(tester, 'Fin de vigencia');
  await tester.ensureVisible(find.byTooltip('Agregar bloque horario'));
  await tester.tap(find.byTooltip('Agregar bloque horario'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'W01: crear nombramiento valido devuelve los datos y recorta espacios',
    (tester) async {
      final result = await openForm(tester);
      await fillNew(tester);
      await submit(tester);
      expect(result.returned, isTrue);
      expect(result.value, isNotNull);
      expect(result.value!.workplace, 'UCR');
      expect(result.value!.position, 'Docente');
      expect(result.value!.expectedHours, 4);
      expect(result.value!.blocks, hasLength(1));
      expect(result.value!.blocks.single.start, '08:00');
      expect(result.value!.blocks.single.end, '12:00');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('W02: editar nombramiento permite guardar un puesto nuevo', (
    tester,
  ) async {
    final result = await openForm(tester, existing: fixture());
    await tester.enterText(field('Cargo o categoría'), 'Investigador');
    await submit(tester);
    expect(result.returned, isTrue);
    expect(result.value!.position, 'Investigador');
    expect(result.value!.startDate, '2026-08-01');
    expect(tester.takeException(), isNull);
  });

  for (final label in ['Lugar de trabajo / institución', 'Cargo o categoría']) {
    for (final text in ['', '   ']) {
      testWidgets('W03: bloquea "$label" vacio o espacios (${text.length})', (
        tester,
      ) async {
        final result = await openForm(tester, existing: fixture());
        await tester.enterText(field(label), text);
        await submit(tester);
        blocked(tester, result, _requiredMessage);
      });
    }
  }

  for (final text in ['', 'abc', '0', '-2', 'NaN', 'Infinity', '-Infinity']) {
    testWidgets('W04: bloquea jornada "$text" al pulsar Guardar', (
      tester,
    ) async {
      final result = await openForm(tester, existing: fixture());
      await tester.enterText(field('Jornada semanal esperada (horas)'), text);
      await submit(tester);
      blocked(tester, result, _requiredMessage);
    });
  }

  testWidgets('W05: bloquea formulario sin bloques horarios', (tester) async {
    final result = await openForm(tester, existing: fixture(blocks: []));
    await submit(tester);
    blocked(tester, result, _requiredMessage);
  });

  // Los campos de fecha son de solo lectura. Estos casos representan datos
  // antiguos invalidos al abrir el editor, sin escribir en controles privados.
  for (final date in ['', '2026-02-29', '2026-04-31', '2025-13-01']) {
    testWidgets('W06: bloquea fecha inicial antigua invalida "$date"', (
      tester,
    ) async {
      final result = await openForm(tester, existing: fixture(startDate: date));
      await submit(tester);
      blocked(tester, result, _dateMessage);
    });
  }
  testWidgets('W07: bloquea fecha final antigua inexistente', (tester) async {
    final result = await openForm(
      tester,
      existing: fixture(endDate: '2026-11-31'),
    );
    await submit(tester);
    blocked(tester, result, _dateMessage);
  });
  testWidgets('W08: bloquea fin anterior a inicio', (tester) async {
    final result = await openForm(
      tester,
      existing: fixture(startDate: '2026-12-01', endDate: '2026-08-01'),
    );
    await submit(tester);
    blocked(tester, result, _dateMessage);
  });
  testWidgets('W09: permite inicio y fin iguales', (tester) async {
    final result = await openForm(
      tester,
      existing: fixture(startDate: '2026-08-01', endDate: '2026-08-01'),
    );
    await submit(tester);
    expect(result.returned, isTrue);
    expect(result.value!.endDate, '2026-08-01');
    expect(tester.takeException(), isNull);
  });
  testWidgets('W10: No aplica deshabilita fecha final y permite guardar', (
    tester,
  ) async {
    final result = await openForm(tester, existing: fixture());
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    final endField = tester.widget<TextField>(field('Fin de vigencia'));
    expect(endField.enabled, isFalse);
    expect(endField.controller!.text, isEmpty);
    await submit(tester);
    expect(result.returned, isTrue);
    expect(result.value!.endDate, 'No aplica');
    expect(tester.takeException(), isNull);
  });
  testWidgets('W11: desmarcar No aplica exige volver a elegir fin', (
    tester,
  ) async {
    final result = await openForm(
      tester,
      existing: fixture(endDate: 'No aplica'),
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await submit(tester);
    blocked(tester, result, _dateMessage);
  });
  testWidgets('W12: No aplica no permite inicio invalido', (tester) async {
    final result = await openForm(
      tester,
      existing: fixture(startDate: '2026-04-31', endDate: 'No aplica'),
    );
    await submit(tester);
    blocked(tester, result, _dateMessage);
  });
  testWidgets('W13: eliminar ultimo bloque impide guardar', (tester) async {
    final result = await openForm(tester, existing: fixture());
    await tester.ensureVisible(find.byTooltip('Quitar bloque'));
    await tester.tap(find.byTooltip('Quitar bloque'));
    await tester.pumpAndSettle();
    await submit(tester);
    blocked(tester, result, _requiredMessage);
  });
  testWidgets('W14: despues de un error se puede corregir y guardar', (
    tester,
  ) async {
    final result = await openForm(tester, existing: fixture());
    await tester.enterText(field('Cargo o categoría'), '');
    await submit(tester);
    blocked(tester, result, _requiredMessage);
    await tester.ensureVisible(field('Cargo o categoría'));
    await tester.enterText(field('Cargo o categoría'), 'Docente');
    await submit(tester);
    expect(result.returned, isTrue);
    expect(result.value!.position, 'Docente');
    expect(tester.takeException(), isNull);
  });
  testWidgets('W15: formulario nuevo completamente vacio no se cierra', (
    tester,
  ) async {
    final result = await openForm(tester);
    await submit(tester);
    blocked(tester, result, _requiredMessage);
  });
  testWidgets('W16: cancelar no devuelve un nombramiento', (tester) async {
    final result = await openForm(tester, existing: fixture());
    await tester.tap(find.byTooltip('Atrás'));
    await tester.pumpAndSettle();
    expect(result.returned, isTrue);
    expect(result.value, isNull);
    expect(tester.takeException(), isNull);
  });
}
