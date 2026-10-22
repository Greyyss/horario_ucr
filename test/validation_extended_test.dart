import 'package:flutter_test/flutter_test.dart';
import 'package:horario_ucr_integrador/models/declaration.dart';
import 'package:horario_ucr_integrador/services/validation_service.dart';

// Casos de negocio independientes del formulario y de Firebase.
Appointment job({
  String workplace = 'UCR',
  String position = 'Docente',
  String startDate = '2026-08-01',
  String endDate = '2026-12-01',
  double expected = 4,
  List<TimeBlock> blocks = const [
    TimeBlock(day: 1, start: '08:00', end: '12:00'),
  ],
}) => Appointment(
  workplace: workplace,
  position: position,
  startDate: startDate,
  endDate: endDate,
  expectedHours: expected,
  blocks: blocks,
);

void must(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void valid(ValidationResult result) {
  must(
    result.valid,
    'Se esperaba valido. Errores: ${result.errors.join('; ')}',
  );
}

void errorContaining(ValidationResult result, String fragment) {
  must(
    !result.valid && result.errors.any((e) => e.contains(fragment)),
    'Se esperaba error "$fragment". Resultado: ${result.errors}',
  );
}

void rejected(ValidationResult result) {
  must(!result.valid, 'Se aceptaron datos invalidos.');
}

void near(double actual, double expected) {
  must(
    actual.isFinite && (actual - expected).abs() < 0.000001,
    'Se esperaba $expected; se obtuvo $actual.',
  );
}

void main() {
  test('N01: nombramiento completo y cuatro horas validas', () {
    final r = ValidationService.validate([job()], []);
    valid(r);
    near(r.institutionalHours, 4);
    near(r.expectedHours, 4);
    near(r.externalHours, 0);
  });
  test('N02: debe existir al menos un nombramiento institucional', () {
    errorContaining(
      ValidationService.validate([], []),
      'al menos un nombramiento',
    );
  });
  test('N03: trabajo externo no sustituye nombramiento institucional', () {
    errorContaining(
      ValidationService.validate([], [job()]),
      'al menos un nombramiento',
    );
  });
  for (final workplace in ['', '   ']) {
    test('N04: institucion vacia o espacios ${workplace.length}', () {
      errorContaining(
        ValidationService.validate([job(workplace: workplace)], []),
        'Complete los datos',
      );
    });
  }
  for (final position in ['', '   ']) {
    test('N05: puesto vacio o espacios ${position.length}', () {
      errorContaining(
        ValidationService.validate([job(position: position)], []),
        'Complete los datos',
      );
    });
  }
  test('N06: nombramiento sin bloques', () {
    errorContaining(
      ValidationService.validate([job(blocks: [])], []),
      'al menos un horario',
    );
  });
  test('N07: jornada negativa rechazada', () {
    rejected(ValidationService.validate([job(expected: -4)], []));
  });
  test('N08: jornada cero rechazada', () {
    rejected(ValidationService.validate([job(expected: 0)], []));
  });
  test('N09: jornada NaN rechazada', () {
    rejected(ValidationService.validate([job(expected: double.nan)], []));
  });
  test('N10: jornada infinita rechazada', () {
    rejected(ValidationService.validate([job(expected: double.infinity)], []));
  });
  test('N11: jornada externa cero rechazada aunque no sume al total UCR', () {
    rejected(
      ValidationService.validate(
        [job()],
        [
          job(
            expected: 0,
            blocks: const [TimeBlock(day: 2, start: '08:00', end: '10:00')],
          ),
        ],
      ),
    );
  });
  test('N12: jornada externa negativa rechazada', () {
    rejected(
      ValidationService.validate(
        [job()],
        [
          job(
            expected: -2,
            blocks: const [TimeBlock(day: 2, start: '08:00', end: '10:00')],
          ),
        ],
      ),
    );
  });
  test('N13: jornada externa NaN rechazada', () {
    rejected(
      ValidationService.validate(
        [job()],
        [
          job(
            expected: double.nan,
            blocks: const [TimeBlock(day: 2, start: '08:00', end: '10:00')],
          ),
        ],
      ),
    );
  });
  test('N14: jornada externa infinita rechazada', () {
    rejected(
      ValidationService.validate(
        [job()],
        [
          job(
            expected: double.infinity,
            blocks: const [TimeBlock(day: 2, start: '08:00', end: '10:00')],
          ),
        ],
      ),
    );
  });
  test('F01: fechas iguales son validas', () {
    valid(
      ValidationService.validate([
        job(startDate: '2026-08-01', endDate: '2026-08-01'),
      ], []),
    );
  });
  test('F02: fin anterior al inicio', () {
    errorContaining(
      ValidationService.validate([
        job(startDate: '2026-12-01', endDate: '2026-08-01'),
      ], []),
      'Vigencia',
    );
  });
  test('F03: fecha inicial vacia', () {
    errorContaining(
      ValidationService.validate([job(startDate: '')], []),
      'Vigencia',
    );
  });
  test('F04: fecha final vacia', () {
    errorContaining(
      ValidationService.validate([job(endDate: '')], []),
      'Vigencia',
    );
  });
  test('F05: fecha inicial en texto libre', () {
    errorContaining(
      ValidationService.validate([job(startDate: 'ayer')], []),
      'Vigencia',
    );
  });
  test('F06: fecha final en texto libre', () {
    errorContaining(
      ValidationService.validate([job(endDate: 'luego')], []),
      'Vigencia',
    );
  });
  test('F07: No aplica permite omitir el fin', () {
    valid(ValidationService.validate([job(endDate: 'No aplica')], []));
  });
  test('F08: No aplica tolera espacios y mayusculas', () {
    valid(ValidationService.validate([job(endDate: '  NO APLICA  ')], []));
  });
  test('F09: No aplica no elimina la obligacion de fecha inicial', () {
    rejected(
      ValidationService.validate([
        job(startDate: '', endDate: 'No aplica'),
      ], []),
    );
  });
  test('F10: 29 febrero en anio bisiesto permitido', () {
    valid(
      ValidationService.validate([
        job(startDate: '2024-02-29', endDate: '2024-03-01'),
      ], []),
    );
  });
  test('F11: 29 febrero en anio no bisiesto rechazado', () {
    rejected(ValidationService.validate([job(startDate: '2026-02-29')], []));
  });
  test('F12: 31 abril rechazado', () {
    rejected(ValidationService.validate([job(startDate: '2026-04-31')], []));
  });
  test('F13: mes 13 rechazado', () {
    rejected(ValidationService.validate([job(startDate: '2025-13-01')], []));
  });
  test('F14: fecha final inexistente rechazada', () {
    rejected(ValidationService.validate([job(endDate: '2026-11-31')], []));
  });
  test('H01: parseo de medianoche y limite superior', () {
    must(ValidationService.minutes('00:00') == 0, 'Medianoche incorrecta');
    must(ValidationService.minutes('23:59') == 1439, 'Limite incorrecto');
  });
  for (final time in [
    '24:00',
    '12:60',
    '-1:00',
    'ab:cd',
    '0800',
    '08:00:00',
    '',
  ]) {
    test('H02: hora invalida "$time"', () {
      var caught = false;
      try {
        ValidationService.minutes(time);
      } on FormatException {
        caught = true;
      }
      must(caught, 'Se esperaba FormatException para $time');
    });
  }
  for (final day in [0, 7]) {
    test('H03: dia fuera de lunes a sabado $day', () {
      errorContaining(
        ValidationService.validate([
          job(
            blocks: [TimeBlock(day: day, start: '08:00', end: '12:00')],
          ),
        ], []),
        'lunes a sábado',
      );
    });
  }
  test('H04: sabado permitido', () {
    valid(
      ValidationService.validate([
        job(
          blocks: const [TimeBlock(day: 6, start: '08:00', end: '12:00')],
        ),
      ], []),
    );
  });
  test('H05: inicio y fin iguales rechazados', () {
    errorContaining(
      ValidationService.validate([
        job(
          blocks: const [TimeBlock(day: 1, start: '08:00', end: '08:00')],
        ),
      ], []),
      'posterior',
    );
  });
  test('H06: fin anterior rechazado', () {
    errorContaining(
      ValidationService.validate([
        job(
          blocks: const [TimeBlock(day: 1, start: '10:00', end: '08:00')],
        ),
      ], []),
      'posterior',
    );
  });
  test('H07: formato invalido produce error sin lanzar excepcion', () {
    errorContaining(
      ValidationService.validate([
        job(
          blocks: const [TimeBlock(day: 1, start: 'texto', end: '12:00')],
        ),
      ], []),
      'Formato de hora',
    );
  });
  test('H08: finalizar exactamente al mediodia permitido', () {
    valid(ValidationService.validate([job()], []));
  });
  test('H09: iniciar exactamente a las 13 permitido', () {
    valid(
      ValidationService.validate([
        job(
          expected: 2,
          blocks: const [TimeBlock(day: 1, start: '13:00', end: '15:00')],
        ),
      ], []),
    );
  });
  for (final times in [
    ('11:59', '12:01'),
    ('12:00', '13:00'),
    ('12:59', '13:01'),
  ]) {
    test('H10: invasion de almuerzo ${times.$1}-${times.$2}', () {
      errorContaining(
        ValidationService.validate([
          job(
            blocks: [TimeBlock(day: 1, start: times.$1, end: times.$2)],
          ),
        ], []),
        'Horario excluido',
      );
    });
  }
  test('H11: bloques contiguos no se traslapan', () {
    valid(
      ValidationService.validate([
        job(
          blocks: const [
            TimeBlock(day: 1, start: '08:00', end: '10:00'),
            TimeBlock(day: 1, start: '10:00', end: '12:00'),
          ],
        ),
      ], []),
    );
  });
  test('H12: traslape parcial interno', () {
    errorContaining(
      ValidationService.validate([
        job(
          expected: 5,
          blocks: const [
            TimeBlock(day: 1, start: '08:00', end: '11:00'),
            TimeBlock(day: 1, start: '10:00', end: '12:00'),
          ],
        ),
      ], []),
      'traslape',
    );
  });
  test('H13: bloque anidado dentro de otro', () {
    errorContaining(
      ValidationService.validate([
        job(
          expected: 5,
          blocks: const [
            TimeBlock(day: 1, start: '08:00', end: '12:00'),
            TimeBlock(day: 1, start: '09:00', end: '10:00'),
          ],
        ),
      ], []),
      'traslape',
    );
  });
  test('H14: duplicado exacto de bloque', () {
    errorContaining(
      ValidationService.validate([
        job(
          expected: 8,
          blocks: const [
            TimeBlock(day: 1, start: '08:00', end: '12:00'),
            TimeBlock(day: 1, start: '08:00', end: '12:00'),
          ],
        ),
      ], []),
      'traslape',
    );
  });
  test('H15: traslape entre nombramientos institucionales', () {
    errorContaining(
      ValidationService.validate([
        job(),
        job(
          workplace: 'Otra unidad',
          expected: 1,
          blocks: const [TimeBlock(day: 1, start: '09:00', end: '10:00')],
        ),
      ], []),
      'traslape',
    );
  });
  test('H16: traslape institucional con externo', () {
    errorContaining(
      ValidationService.validate(
        [job()],
        [
          job(
            workplace: 'Externo',
            expected: 1,
            blocks: const [TimeBlock(day: 1, start: '09:00', end: '10:00')],
          ),
        ],
      ),
      'traslape',
    );
  });
  test('H17: traslape entre dos externos', () {
    errorContaining(
      ValidationService.validate(
        [job()],
        [
          job(
            workplace: 'Externo A',
            blocks: const [TimeBlock(day: 2, start: '08:00', end: '12:00')],
          ),
          job(
            workplace: 'Externo B',
            expected: 1,
            blocks: const [TimeBlock(day: 2, start: '09:00', end: '10:00')],
          ),
        ],
      ),
      'traslape',
    );
  });
  test('H18: mismas horas en dias diferentes permitidas', () {
    valid(
      ValidationService.validate([
        job(
          expected: 8,
          blocks: const [
            TimeBlock(day: 1, start: '08:00', end: '12:00'),
            TimeBlock(day: 2, start: '08:00', end: '12:00'),
          ],
        ),
      ], []),
    );
  });
  test('H19: exactamente diez horas diarias permitidas', () {
    valid(
      ValidationService.validate([
        job(
          expected: 10,
          blocks: const [
            TimeBlock(day: 1, start: '06:00', end: '12:00'),
            TimeBlock(day: 1, start: '13:00', end: '17:00'),
          ],
        ),
      ], []),
    );
  });
  test('H20: diez horas y un minuto rechazados', () {
    errorContaining(
      ValidationService.validate([
        job(
          expected: 10 + 1 / 60,
          blocks: const [
            TimeBlock(day: 1, start: '06:00', end: '12:00'),
            TimeBlock(day: 1, start: '13:00', end: '17:01'),
          ],
        ),
      ], []),
      'máximo',
    );
  });
  test('H21: maximo diario incluye trabajos externos', () {
    errorContaining(
      ValidationService.validate(
        [
          job(
            expected: 6,
            blocks: const [TimeBlock(day: 1, start: '06:00', end: '12:00')],
          ),
        ],
        [
          job(
            expected: 5,
            blocks: const [TimeBlock(day: 1, start: '13:00', end: '18:00')],
          ),
        ],
      ),
      'máximo',
    );
  });
  test('H22: menos horas de las esperadas rechazado', () {
    errorContaining(
      ValidationService.validate([job(expected: 5)], []),
      'Jornada institucional',
    );
  });
  test('H23: mas horas de las esperadas rechazado', () {
    errorContaining(
      ValidationService.validate([job(expected: 3)], []),
      'Jornada institucional',
    );
  });
  test('H24: trabajo externo no completa jornada institucional faltante', () {
    errorContaining(
      ValidationService.validate(
        [job(expected: 6)],
        [
          job(
            expected: 2,
            blocks: const [TimeBlock(day: 2, start: '08:00', end: '10:00')],
          ),
        ],
      ),
      'Jornada institucional',
    );
  });
  test('H25: calculo de fracciones y total externo separado', () {
    final r = ValidationService.validate(
      [
        job(
          expected: 1.5,
          blocks: const [TimeBlock(day: 1, start: '08:00', end: '09:30')],
        ),
      ],
      [
        job(
          expected: 2.25,
          blocks: const [TimeBlock(day: 2, start: '08:00', end: '10:15')],
        ),
      ],
    );
    valid(r);
    near(r.institutionalHours, 1.5);
    near(r.expectedHours, 1.5);
    near(r.externalHours, 2.25);
  });
}
