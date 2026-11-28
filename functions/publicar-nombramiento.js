'use strict';

const { onCall, HttpsError } = require('./activation-https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { createHash } = require('node:crypto');

const options = {
  region: 'us-east1',
  maxInstances: 2,
};

const teachingPositions = new Set([
  'Interino Bachiller',
  'Interino Licenciado',
  'Instructor',
  'Adjunto',
  'Asociado',
  'Catedrático',
]);

const positions = new Set([
  ...teachingPositions,
  'Coordinación de Carrera',
  'Coordinación de Docencia',
  'Coordinación de Investigación',
  'Coordinación de Acción Social',
  'Coordinación de Administración',
  'Proyectos',
]);

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

function validId(value) {
  return (
    typeof value === 'string' &&
    /^[A-Za-z0-9_-]{1,128}$/.test(value)
  );
}

function invalid() {
  throw new HttpsError(
    'invalid-argument',
    'Revisá los datos y los bloques del nombramiento.'
  );
}

function minutes(value) {
  if (
    typeof value !== 'string' ||
    !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value)
  ) {
    invalid();
  }

  const [hour, minute] = value.split(':').map(Number);
  return hour * 60 + minute;
}

function validDate(value) {
  return (
    typeof value === 'string' &&
    /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    Number.isFinite(Date.parse(value)) &&
    new Date(value).toISOString().slice(0, 10) === value
  );
}

exports.listarMisDeclarantes = onCall(options, async (request) => {
  const uid = request.auth?.uid;

  if (!uid) {
    throw new HttpsError('unauthenticated', 'Iniciá sesión.');
  }

  const users = getFirestore().collection('users');
  const superior = await users.doc(uid).get();

  if (superior.get('role') !== 'superior') {
    throw new HttpsError(
      'permission-denied',
      'Esta opción es para superiores.'
    );
  }

  const assigned = await users
    .where('superiorId', '==', uid)
    .get();

  return assigned.docs
    .filter((doc) => doc.get('role') === 'declarante')
    .map((doc) => ({
      uid: doc.id,
      name: doc.get('name') || 'Sin nombre',
    }));
});

exports.publicarNombramiento = onCall(options, async (request) => {
  const actor = request.auth?.uid;

  if (!actor) {
    throw new HttpsError('unauthenticated', 'Iniciá sesión.');
  }

  const {
    uid,
    periodId,
    operationId,
    appointment,
  } = request.data ?? {};

  if (
    ![uid, periodId, operationId].every(validId) ||
    !appointment
  ) {
    invalid();
  }

  const {
    position,
    expectedHours,
    startDate,
    endDate,
    workloadFraction,
    blocks,
  } = appointment;

  if (
    typeof position !== 'string' ||
    !positions.has(position) ||
    !Number.isFinite(expectedHours) ||
    expectedHours <= 0 ||
    expectedHours > 40 ||
    !validDate(startDate) ||
    !validDate(endDate) ||
    startDate > endDate ||
    !Array.isArray(blocks) ||
    blocks.length === 0 ||
    blocks.length > 84
  ) {
    invalid();
  }

  const teaching = teachingPositions.has(position);
  const checked = [];
  let total = 0;

  for (const block of blocks) {
    if (!block) invalid();

    const {
      day,
      start,
      end,
      courseCode,
      activityType,
      activityName,
    } = block;

    const from = minutes(start);
    const to = minutes(end);

    if (
      !Number.isInteger(day) ||
      day < 1 ||
      day > 6 ||
      from < 420 ||
      to > 1310 ||
      from >= to ||
      (from < 780 && to > 720) ||
      checked.some(
        (other) =>
          other.day === day &&
          from < other.to &&
          to > other.from
      )
    ) {
      invalid();
    }

    if (teaching) {
      if (
        typeof courseCode !== 'string' ||
        !/^[A-Z0-9][A-Z0-9-]{1,19}$/.test(courseCode) ||
        (
          activityType != null &&
          activityType !== 'CONTACTO'
        ) ||
        (
          activityName != null &&
          activityName !== ''
        )
      ) {
        invalid();
      }
    } else {
      if (
        typeof activityName !== 'string' ||
        activityName !== activityName.trim() ||
        activityName.length < 2 ||
        activityName.length > 150 ||
        /[\r\n\t]/.test(activityName) ||
        (courseCode != null && courseCode !== '') ||
        (activityType != null && activityType !== '')
      ) {
        invalid();
      }
    }

    total += to - from;

    checked.push({
      day,
      start,
      end,
      from,
      to,
      ...(teaching
        ? {
            courseCode,
            activityType: 'CONTACTO',
          }
        : {
            activityName,
          }),
    });
  }

  if (total > expectedHours * 60) {
    throw new HttpsError(
      'invalid-argument',
      'Las horas asignadas superan la jornada.'
    );
  }

  if (!teaching && total !== Math.round(expectedHours * 60)) {
    throw new HttpsError(
      'invalid-argument',
      'Completá el horario de la actividad hasta cubrir la jornada.'
    );
  }

  const db = getFirestore();
  const users = db.collection('users');
  const owner = users.doc(uid);

  const id = createHash('sha256')
    .update(JSON.stringify([actor, uid, operationId]))
    .digest('hex');

  const pending = owner
    .collection('pendingAppointments')
    .doc(id);

  await db.runTransaction(async (tx) => {
    const [superior, declarant, period, existing] =
      await Promise.all([
        tx.get(users.doc(actor)),
        tx.get(owner),
        tx.get(db.collection('periods').doc(periodId)),
        tx.get(pending),
      ]);

    if (
      superior.get('role') !== 'superior' ||
      declarant.get('role') !== 'declarante' ||
      declarant.get('superiorId') !== actor
    ) {
      throw new HttpsError(
        'permission-denied',
        'El declarante debe estar asignado a tu perfil.'
      );
    }

    if (existing.exists) return;

    if (period.get('enabled') !== true) {
      throw new HttpsError(
        'failed-precondition',
        'El período no está habilitado.'
      );
    }

    const periodName =
      period.get('name') ||
      period.get('label') ||
      periodId;

    const createdAt = FieldValue.serverTimestamp();

    tx.create(pending, {
      superiorId: actor,
      superiorName: superior.get('name') || 'Superior asignado',
      periodId,
      periodName,
      unit: declarant.get('unit') || '',
      workplace: 'Universidad de Costa Rica',
      position,
      expectedHours,
      startDate,
      endDate,
      workloadFraction:
        fractions[expectedHours] || workloadFraction || null,
      blocks: checked.map(({ from, to, ...block }) => block),
      createdAt,
    });

    tx.create(owner.collection('notifications').doc(id), {
      title: 'Nombramiento pendiente',
      message:
        `Tu superior te asignó un nombramiento para ${periodName}.`,
      appointmentId: id,
      status: 'PENDIENTE',
      createdAt,
      read: false,
      readAt: null,
    });

    // MAIL_HANDOFF_POLICY_V2
    const {
      email,
      message,
      appointmentDetails,
    } = require('./mail-helpers');

    const details = appointmentDetails({
      workplace: 'Universidad de Costa Rica',
      unit: declarant.get('unit') || '',
      position,
      expectedHours,
      startDate,
      endDate,
      workloadFraction:
        fractions[expectedHours] || workloadFraction || '',
      blocks: checked.map(({ from, to, ...block }) => block),
    });

    const recipients = [
      {
        user: declarant,
        suffix: 'declarante',
        type: 'NOMBRAMIENTO_DECLARANTE',
        role: 'declarante',
      },
      {
        user: superior,
        suffix: 'superior',
        type: 'COPIA_SUPERIOR',
        role: 'superior',
      },
    ];

    for (const recipient of recipients) {
      const to = String(
        recipient.user.get('email') || ''
      ).trim();

      if (!email(to)) continue;

      tx.create(
        db.collection('_declarationMailOutbox')
          .doc(id + '-' + recipient.suffix),
        {
          ...message(recipient.type, {
            name: recipient.user.get('name'),
            ownerName: declarant.get('name'),
            superiorName: superior.get('name'),
            period: periodName,
            reference: id,
            details,
          }),
          to,
          recipientUid: recipient.user.id,
          expectedRole: recipient.role,
          appointmentId: id,
          status: 'pending',
          createdAt,
        }
      );
    }
  });

  return { id };
});