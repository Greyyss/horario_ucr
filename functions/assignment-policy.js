'use strict';

const { isDeepStrictEqual } = require('node:util');

const teachingPositions = new Set([
  'Interino Bachiller',
  'Interino Licenciado',
  'Instructor',
  'Adjunto',
  'Asociado',
  'Catedrático',
]);

const isTeaching = (position) =>
  teachingPositions.has(position);

const fractions = {
  5: '1/8',
  10: '1/4',
  15: '3/8',
  20: '1/2',
  25: '5/8',
  30: '3/4',
  35: '7/8',
  40: '1 TC',
};

const fixed = [
  'workplace',
  'position',
  'startDate',
  'endDate',
  'expectedHours',
];

const personal = [
  'ownerName',
  'identification',
  'phone',
  'email',
  'unit',
];

const duration = (block) => {
  const minutes = (value) => {
    const [hour, minute] = value.split(':').map(Number);
    return hour * 60 + minute;
  };

  return minutes(block.end) - minutes(block.start);
};

// Compara los datos del bloque sin depender del orden
// de sus propiedades.
const blockKey = (block) =>
  JSON.stringify([
    block.day,
    block.start,
    block.end,
    block.courseCode ?? '',
    block.activityType ?? '',
    block.activityName ?? '',
  ]);

// Docencia: el superior fija únicamente los bloques de contacto.
// Coordinaciones y proyectos: el superior fija todos los bloques.
const fixedBlocks = (job) => {
  const blocks = isTeaching(job.position)
    ? job.blocks.filter(
        (block) => block.activityType === 'CONTACTO'
      )
    : job.blocks;

  return blocks.map(blockKey).sort();
};

async function enforceAssignments({
  db,
  tx,
  uid,
  payload,
  current,
  profile,
  declarationId,
  deny,
  complete = false,
}) {
  const ids = new Set();
  const bindings = [];
  const jobs = [];

  for (let index = 0; index < payload.appointments.length; index++) {
    const job = payload.appointments[index];

    if (job.relatedAssignmentId != null) {
      deny(
        'invalid-argument',
        'Un nombramiento interno no puede usar una referencia externa.'
      );
    }

    if (!job.assignmentId) {
      const previous = current?.appointments?.[index];

      if (
        !previous ||
        previous.assignmentId ||
        current.assignmentFormatVersion === 1
      ) {
        deny(
          'failed-precondition',
          'Seleccioná un nombramiento enviado por tu superior.'
        );
      }

      if (
        fixed.some(
          (key) => !isDeepStrictEqual(job[key], previous[key])
        ) ||
        (job.workloadFraction ?? null) !==
          (previous.workloadFraction ?? null) ||
        !isDeepStrictEqual(
          fixedBlocks(job),
          fixedBlocks(previous)
        )
      ) {
        deny(
          'permission-denied',
          'No podés modificar los datos ni el horario fijado por el superior.'
        );
      }

      jobs.push(job);
      continue;
    }

    const id = job.assignmentId;

    if (
      typeof id !== 'string' ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(id) ||
      ids.has(id)
    ) {
      deny(
        'invalid-argument',
        'La referencia del nombramiento es inválida o está repetida.'
      );
    }

    ids.add(id);

    const ref = db
      .collection('users')
      .doc(uid)
      .collection('pendingAppointments')
      .doc(id);

    const source = await tx.get(ref);

    if (!source.exists) {
      deny(
        'not-found',
        'El nombramiento asignado ya no está disponible.'
      );
    }

    const assigned = source.data();
    const teaching = isTeaching(assigned.position);

    if (
      assigned.superiorId !== payload.superiorId ||
      assigned.periodId !== payload.periodId ||
      (
        current == null &&
        profile.superiorId !== assigned.superiorId
      )
    ) {
      deny(
        'permission-denied',
        'El nombramiento no corresponde al período o al superior asignado.'
      );
    }

    if (
      assigned.declarationId &&
      assigned.declarationId !== declarationId
    ) {
      deny(
        'already-exists',
        'Este nombramiento ya está incluido en otra declaración. ' +
          'Abrí el borrador desde Mis declaraciones.'
      );
    }

    if (
      fixed.some(
        (key) => !isDeepStrictEqual(job[key], assigned[key])
      )
    ) {
      deny(
        'permission-denied',
        'El cargo, la jornada y la vigencia solo los establece el superior.'
      );
    }

    const fraction =
      assigned.workloadFraction ??
      fractions[assigned.expectedHours];

    if (
      !fraction ||
      (
        job.workloadFraction != null &&
        job.workloadFraction !== fraction
      )
    ) {
      deny(
        'permission-denied',
        'La fracción de jornada no coincide con la asignada.'
      );
    }

    if (
      !isDeepStrictEqual(
        fixedBlocks(job),
        fixedBlocks(assigned)
      )
    ) {
      deny(
        'permission-denied',
        teaching
          ? 'No podés modificar, agregar ni quitar horas de contacto.'
          : 'El horario de esta actividad lo fija el superior. ' +
              'No podés modificar, agregar ni quitar sus bloques.'
      );
    }

    if (teaching) {
      const courses = new Set(
        assigned.blocks
          .filter(
            (block) => block.activityType === 'CONTACTO'
          )
          .map((block) => block.courseCode)
      );

      for (const block of job.blocks) {
        if (block.activityType === 'CONTACTO') {
          continue;
        }

        if (
          !['CONSULTA', 'PREPARACION'].includes(
            block.activityType
          ) ||
          !courses.has(block.courseCode)
        ) {
          deny(
            'permission-denied',
            'Solo podés declarar consulta y preparación de los cursos asignados.'
          );
        }
      }
    }

    const minutes = job.blocks.reduce(
      (sum, block) => sum + duration(block),
      0
    );

    const expected = Math.round(
      assigned.expectedHours * 60
    );

    if (minutes > expected) {
      deny(
        'failed-precondition',
        'Las horas declaradas superan la jornada asignada.'
      );
    }

    if (complete && minutes !== expected) {
      deny(
        'failed-precondition',
        teaching
          ? 'Completá las horas pendientes de consulta y preparación de cada nombramiento.'
          : 'El horario asignado no cubre la jornada. ' +
              'Solicitá al superior que revise el nombramiento.'
      );
    }

    if (payload.unit !== assigned.unit) {
      deny(
        'permission-denied',
        'La unidad debe coincidir con la del nombramiento asignado.'
      );
    }

    jobs.push({
      ...job,
      workloadFraction: fraction,
    });

    bindings.push({
      ref,
      source: assigned,
    });
  }

  for (const previous of current?.appointments ?? []) {
    if (
      previous.assignmentId &&
      !ids.has(previous.assignmentId)
    ) {
      deny(
        'permission-denied',
        'No podés quitar un nombramiento asignado del borrador.'
      );
    }
  }

  if (
    current &&
    current.appointments.filter(
      (job) => !job.assignmentId
    ).length !==
      jobs.filter((job) => !job.assignmentId).length
  ) {
    deny(
      'permission-denied',
      'No podés quitar un nombramiento histórico del borrador.'
    );
  }

  for (const job of payload.externalJobs) {
    const related = job.relatedAssignmentId;

    if (
      related != null &&
      (
        typeof related !== 'string' ||
        !/^[A-Za-z0-9_-]{1,128}$/.test(related) ||
        !ids.has(related)
      )
    ) {
      deny(
        'permission-denied',
        'La otra institución debe vincularse a un nombramiento de esta declaración.'
      );
    }
  }

  if (
    payload.externalJobs.some(
      (job) => job.assignmentId != null
    )
  ) {
    deny(
      'invalid-argument',
      'Un trabajo externo no puede usar una asignación interna.'
    );
  }

  if (
    bindings.length ||
    current?.assignmentFormatVersion === 1
  ) {
    const authoritative = current ?? {
      ownerName: profile.name,
      identification: profile.identification,
      phone: profile.phone,
      email: profile.email,
      unit: payload.unit,
    };

    if (
      personal.some(
        (key) => payload[key] !== authoritative[key]
      )
    ) {
      deny(
        'permission-denied',
        'Los datos personales de la declaración no se pueden modificar desde el horario.'
      );
    }
  }

  return {
    payload: {
      ...payload,
      appointments: jobs,
    },
    bindings,
  };
}

module.exports = {
  enforceAssignments,
};