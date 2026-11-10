'use strict';

class ScheduleValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ScheduleValidationError';
  }
}

const fail = message => {
  throw new ScheduleValidationError(message);
};

const isMap = value =>
  value !== null &&
  typeof value === 'object' &&
  !Array.isArray(value);

const letters =
  'A-Za-zÁÉÍÓÚÜÑáéíóúüñÀÈÌÒÙàèìòùÂÊÎÔÛâêîôûÄËÏÖäëïöÇç';

const namePattern = new RegExp(
  `^[${letters}]+(?:[-'’][${letters}]+)*` +
  `(?: [${letters}]+(?:[-'’][${letters}]+)*)+$`
);

const fields = [
  'ownerName',
  'identification',
  'phone',
  'email',
  'unit',
  'observations',
  'appointments',
  'externalJobs',
];

const positions = new Set([
  'Interino Bachiller',
  'Interino Licenciado',
  'Instructor',
  'Adjunto',
  'Asociado',
  'Catedrático',
  'Coordinación de Carrera',
  'Coordinación de Docencia',
  'Coordinación de Investigación',
  'Coordinación de Acción Social',
  'Coordinación de Administración',
  'Proyectos',
]);

const teachingPositions = new Set([
  'Interino Bachiller',
  'Interino Licenciado',
  'Instructor',
  'Adjunto',
  'Asociado',
  'Catedrático',
]);

const activityLabels = Object.freeze({
  CONTACTO: 'horas contacto',
  CONSULTA: 'horas de consulta',
  PREPARACION: 'preparación',
});

const dayNames = [
  '',
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
];

// Horas semanales. El máximo diario se valida por separado.
const workloadHours = Object.freeze({
  '1/8': 5,
  '1/4': 10,
  '3/8': 15,
  '1/2': 20,
  '5/8': 25,
  '3/4': 30,
  '7/8': 35,
  '1 TC': 40,
});

// ============================================================
// VALIDACIONES GENERALES
// ============================================================

function text(value, label) {
  if (typeof value !== 'string' || !value.trim()) {
    fail(`${label}: el campo es obligatorio.`);
  }

  return value;
}

function dateValue(value) {
  if (
    typeof value !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}$/.test(value)
  ) {
    return null;
  }

  const [year, month, day] = value.split('-').map(Number);

  if (
    year < 1 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > 31
  ) {
    return null;
  }

  const leap =
    year % 4 === 0 &&
    (year % 100 !== 0 || year % 400 === 0);

  const days = [
    31,
    leap ? 29 : 28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];

  if (day > days[month - 1]) {
    return null;
  }

  return year * 10000 + month * 100 + day;
}

function minutes(value) {
  if (
    typeof value !== 'string' ||
    !/^\d{1,2}:\d{1,2}$/.test(value)
  ) {
    fail('Formato de hora inválido.');
  }

  const [hour, minute] = value.split(':').map(Number);

  if (hour > 23 || minute > 59) {
    fail('Formato de hora inválido.');
  }

  return hour * 60 + minute;
}

function personal(data) {
  if (!isMap(data)) {
    fail('Datos personales inválidos.');
  }

  const name = data.ownerName;

  if (
    typeof name !== 'string' ||
    name.length < 5 ||
    name.length > 100 ||
    !namePattern.test(name)
  ) {
    fail('Nombre completo inválido.');
  }

  if (
    typeof data.identification !== 'string' ||
    !/^[0-9]{9}$/.test(data.identification)
  ) {
    fail('La cédula debe tener nueve dígitos.');
  }

  if (
    typeof data.phone !== 'string' ||
    !/^[0-9]{8}$/.test(data.phone)
  ) {
    fail('El teléfono debe tener ocho dígitos.');
  }

  if (
    typeof data.email !== 'string' ||
    data.email.length > 254 ||
    !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(data.email)
  ) {
    fail('Correo inválido.');
  }

  const unit = data.unit;

  if (
    typeof unit !== 'string' ||
    unit !== unit.trim() ||
    unit.length < 2 ||
    unit.length > 150 ||
    /[\r\n\t]/.test(unit)
  ) {
    fail('Unidad inválida.');
  }

  if (
    typeof data.observations !== 'string' ||
    data.observations.length > 2000
  ) {
    fail('Observaciones inválidas.');
  }
}

// ============================================================
// VALIDAR CURSO Y ACTIVIDAD DE CADA BLOQUE
// ============================================================

function validateBlockActivity(
  block,
  position,
  outside,
  required
) {
  const keys = [
    'courseCode',
    'activityType',
    'activityName',
  ];

  const hasDetails = keys.some(
    key => block[key] != null
  );

  for (const key of keys) {
    if (
      block[key] != null &&
      typeof block[key] !== 'string'
    ) {
      fail(
        'Los datos de curso y actividad deben ser texto.'
      );
    }
  }

  // Las otras instituciones conservan su esquema por horas.
  if (outside) {
    if (hasDetails) {
      fail(
        'Los trabajos externos se declaran sin datos ' +
        'de cursos o actividades UCR.'
      );
    }

    return;
  }

  // Los bloques antiguos sin estos campos siguen siendo legibles.
  // Si envían información nueva, se comprueba aunque no sea obligatoria.
  if (!required && !hasDetails) {
    return;
  }

  if (!positions.has(position)) {
    fail('Seleccioná un cargo válido de la lista.');
  }

  if (teachingPositions.has(position)) {
    const code = block.courseCode;

    if (
      typeof code !== 'string' ||
      code !== code.trim() ||
      !/^[A-Z0-9][A-Z0-9-]{1,19}$/.test(code)
    ) {
      fail(
        'Ingresá las siglas del curso: de 2 a 20 letras ' +
        'mayúsculas, números o guiones, sin espacios.'
      );
    }

    if (
      typeof block.activityType !== 'string' ||
      !Object.hasOwn(activityLabels, block.activityType)
    ) {
      fail(
        'Seleccioná contacto, consulta o preparación.'
      );
    }

    if (
      (block.activityName ?? '').trim().length > 0
    ) {
      fail(
        'Un bloque de curso debe indicar siglas y tipo ' +
        'de actividad, sin nombre de actividad adicional.'
      );
    }
  } else {
    const name = block.activityName;

    if (
      typeof name !== 'string' ||
      name !== name.trim() ||
      name.length < 2 ||
      name.length > 150 ||
      /[\r\n\t]/.test(name)
    ) {
      fail(
        'Indicá el nombre de la actividad, ' +
        'entre 2 y 150 caracteres.'
      );
    }

    if (
      (block.courseCode ?? '').length > 0 ||
      (block.activityType ?? '').length > 0
    ) {
      fail(
        'Las actividades de coordinaciones y proyectos ' +
        'no deben incluir datos de curso.'
      );
    }
  }
}

// ============================================================
// VALIDAR DECLARACIÓN
// ============================================================

// complete:
// Comprueba traslapes, pausa, máximo diario y horas esperadas.
//
// requireInstitutionalFraction:
// Exige las fracciones de jornada del formulario UCR.
//
// requireActivityDetails:
// Exige los datos necesarios para generar las observaciones.
// Lo activa el servidor según el formato de la declaración.
function validateDeclarationData(
  data,
  {
    complete = false,
    requireInstitutionalFraction = false,
    requireActivityDetails = false,
  } = {}
) {
  personal(data);

  if (
    !Array.isArray(data.appointments) ||
    !data.appointments.length
  ) {
    fail(
      'Debe registrar un nombramiento institucional.'
    );
  }

  if (!Array.isArray(data.externalJobs)) {
    fail(
      'La lista de trabajos externos es inválida.'
    );
  }

  const byDay = new Map();

  let internal = 0;
  let external = 0;
  let expected = 0;

  for (const [jobs, outside] of [
    [data.appointments, false],
    [data.externalJobs, true],
  ]) {
    for (const job of jobs) {
      if (!isMap(job)) {
        fail('Nombramiento inválido.');
      }

      text(job.workplace, 'Institución');
      text(job.position, 'Puesto');

      if (
        typeof job.expectedHours !== 'number' ||
        !Number.isFinite(job.expectedHours) ||
        job.expectedHours <= 0
      ) {
        fail(
          'La jornada debe ser finita y mayor que cero.'
        );
      }

      const fraction = job.workloadFraction;

      if (
        requireInstitutionalFraction &&
        !positions.has(job.position)
      ) {
        fail(
          'Seleccioná un cargo válido de la lista.'
        );
      }

      if (!outside) {
        if (
          requireInstitutionalFraction &&
          job.workplace !== 'Universidad de Costa Rica'
        ) {
          fail(
            'El lugar de trabajo institucional debe ser ' +
            'Universidad de Costa Rica.'
          );
        }

        if (
          requireInstitutionalFraction &&
          fraction == null
        ) {
          fail(
            'Seleccioná la fracción de jornada ' +
            'del nombramiento UCR.'
          );
        }

        if (fraction != null) {
          if (
            typeof fraction !== 'string' ||
            !Object.hasOwn(workloadHours, fraction)
          ) {
            fail(
              'Fracción de jornada UCR inválida.'
            );
          }

          if (
            Math.abs(
              job.expectedHours - workloadHours[fraction]
            ) > 0.001
          ) {
            fail(
              'La fracción de jornada no coincide ' +
              'con las horas esperadas.'
            );
          }

          if (
            job.workplace !== 'Universidad de Costa Rica' ||
            !positions.has(job.position)
          ) {
            fail(
              'Los datos del nombramiento UCR ' +
              'no corresponden al catálogo.'
            );
          }
        }
      } else if (fraction != null) {
        fail(
          'Las jornadas externas se indican en horas, ' +
          'sin aplicar fracciones UCR.'
        );
      }

      const start = dateValue(job.startDate);
      const end = dateValue(job.endDate);

      const noEnd =
        typeof job.endDate === 'string' &&
        job.endDate.trim().toLowerCase() === 'no aplica';

      if (
        start === null ||
        (!noEnd && (end === null || end < start))
      ) {
        fail('Vigencia inválida.');
      }

      if (
        !Array.isArray(job.blocks) ||
        !job.blocks.length
      ) {
        fail(
          'Agregue un horario al nombramiento.'
        );
      }

      if (!outside) {
        expected += job.expectedHours;
      }

      for (const block of job.blocks) {
        if (
          !isMap(block) ||
          !Number.isInteger(block.day) ||
          block.day < 1 ||
          block.day > 6
        ) {
          fail('Día de horario inválido.');
        }

        validateBlockActivity(
          block,
          job.position,
          outside,
          requireActivityDetails
        );

        const a = minutes(block.start);
        const b = minutes(block.end);

        if (b <= a) {
          fail(
            'La hora final debe ser posterior a la inicial.'
          );
        }

        // Se conserva la exclusión de 12:00 a 13:00.
        if (complete && a < 780 && b > 720) {
          fail(
            'Horario excluido de 12:00 a 13:00.'
          );
        }

        if (outside) {
          external += (b - a) / 60;
        } else {
          internal += (b - a) / 60;
        }

        if (!byDay.has(block.day)) {
          byDay.set(block.day, []);
        }

        // Se suman los trabajos UCR y externos.
        byDay.get(block.day).push({
          start: a,
          end: b,
        });
      }
    }
  }

  if (
    ![internal, external, expected].every(Number.isFinite)
  ) {
    fail(
      'Totales de jornada fuera de rango.'
    );
  }

  if (complete) {
    for (const blocks of byDay.values()) {
      blocks.sort(
        (a, b) => a.start - b.start
      );

      let total = 0;
      let start;
      let end;

      for (const block of blocks) {
        if (end === undefined) {
          start = block.start;
          end = block.end;
        } else if (block.start < end) {
          fail(
            'Existen traslapes entre horarios.'
          );
        } else {
          total += end - start;
          start = block.start;
          end = block.end;
        }
      }

      if (end !== undefined) {
        total += end - start;
      }

      // REQUISITO DEL PROFESOR:
      // Máximo de diez horas diarias, equivalentes a 600 minutos.
      if (total > 600) {
        fail(
          'Se excede el máximo diario de diez horas.'
        );
      }
    }

    if (Math.abs(internal - expected) > 0.001) {
      fail(
        'Las horas institucionales no coinciden ' +
        'con la jornada esperada.'
      );
    }
  }

  return {
    institutionalHours: internal,
    externalHours: external,
    expectedHours: expected,
  };
}

// ============================================================
// GENERAR OBSERVACIONES AUTOMÁTICAS
// ============================================================

function formatRanges(source) {
  const compareText = (a, b) =>
    a < b ? -1 : a > b ? 1 : 0;

  // Se ordena una copia para no modificar los bloques originales.
  const blocks = [...source].sort((a, b) =>
    a.day - b.day ||
    compareText(a.start, b.start) ||
    compareText(a.end, b.end)
  );

  return blocks.map(block =>
    `${dayNames[block.day]} de ${block.start} a ${block.end}`
  ).join(', ');
}

function generateDeclarationObservations(data) {
  // Antes de generar el resumen se exige información completa
  // de los cursos y las actividades.
  validateDeclarationData(data, {
    requireActivityDetails: true,
  });

  const lines = [];

  for (const job of data.appointments) {
    if (teachingPositions.has(job.position)) {
      const courses = new Map();

      for (const block of job.blocks) {
        const code = block.courseCode;

        if (!courses.has(code)) {
          courses.set(code, new Map());
        }

        const types = courses.get(code);

        if (!types.has(block.activityType)) {
          types.set(block.activityType, []);
        }

        types.get(block.activityType).push(block);
      }

      const codes = [...courses.keys()].sort();

      for (const code of codes) {
        const types = courses.get(code);
        const parts = [];

        // Conserva el mismo orden de la vista previa en Flutter:
        // contacto, consulta y preparación.
        for (const type of Object.keys(activityLabels)) {
          if (types.has(type)) {
            parts.push(
              `${activityLabels[type]}: ` +
              formatRanges(types.get(type))
            );
          }
        }

        lines.push(
          `${code}: ${parts.join('; ')}.`
        );
      }
    } else {
      const activities = new Map();

      for (const block of job.blocks) {
        const name = block.activityName;

        if (!activities.has(name)) {
          activities.set(name, []);
        }

        activities.get(name).push(block);
      }

      for (const [name, blocks] of activities) {
        lines.push(
          `${name}: ${formatRanges(blocks)}.`
        );
      }
    }
  }

  for (const job of data.externalJobs) {
    lines.push(
      `${job.position} en ${job.workplace}: ` +
      `${formatRanges(job.blocks)}.`
    );
  }

  // El resumen se construye exclusivamente desde los horarios.
  // No se utiliza el texto de observaciones enviado por Flutter.
  const result = lines.join('\n');

  // Se mantiene el límite actual del sistema.
  // No se recorta el resumen ni se pierden horarios silenciosamente.
  if (result.length > 2000) {
    fail(
      'El resumen automático supera los 2000 caracteres permitidos.'
    );
  }

  return result;
}

module.exports = {
  ScheduleValidationError,
  validateDeclarationData,
  generateDeclarationObservations,
  fields,
  dateValue,
  minutes,
};