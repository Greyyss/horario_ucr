'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { createHash } = require('node:crypto');

const options = { region: 'us-east1', maxInstances: 2 };

function validId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function invalid() {
  throw new HttpsError('invalid-argument', 'Revisá los datos y los bloques del nombramiento.');
}

function minutes(value) {
  if (typeof value !== 'string' || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value)) invalid();
  const [hour, minute] = value.split(':').map(Number);
  return hour * 60 + minute;
}

function validDate(value) {
  return typeof value === 'string'
    && /^\d{4}-\d{2}-\d{2}$/.test(value)
    && Number.isFinite(Date.parse(value))
    && new Date(value).toISOString().slice(0, 10) === value;
}

exports.listarMisDeclarantes = onCall(options, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Iniciá sesión.');

  const users = getFirestore().collection('users');
  if ((await users.doc(uid).get()).get('role') !== 'superior') {
    throw new HttpsError('permission-denied', 'Esta opción es para superiores.');
  }

  const assigned = await users.where('superiorId', '==', uid).get();
  return assigned.docs
    .filter((doc) => doc.get('role') === 'declarante')
    .map((doc) => ({ uid: doc.id, name: doc.get('name') || 'Sin nombre' }));
});

exports.publicarNombramiento = onCall(options, async (request) => {
  const actor = request.auth?.uid;
  if (!actor) throw new HttpsError('unauthenticated', 'Iniciá sesión.');

  const { uid, periodId, operationId, appointment } = request.data ?? {};
  if (![uid, periodId, operationId].every(validId) || !appointment) invalid();

  const { position, expectedHours, startDate, endDate, workloadFraction, blocks } = appointment;
  if (typeof position !== 'string' || !position.trim() || position.length > 100
      || !Number.isFinite(expectedHours) || expectedHours <= 0 || expectedHours > 40
      || !validDate(startDate) || !validDate(endDate) || startDate > endDate
      || !Array.isArray(blocks) || blocks.length === 0 || blocks.length > 84) invalid();

  const checked = [];
  let total = 0;
  for (const block of blocks) {
    if (!block) invalid();
    const { day, start, end, courseCode } = block;
    const from = minutes(start);
    const to = minutes(end);

    if (!Number.isInteger(day) || day < 1 || day > 6
        || from < 420 || to > 1310 || from >= to
        || (from < 780 && to > 720)
        || typeof courseCode !== 'string'
        || !/^[A-Z0-9][A-Z0-9-]{1,19}$/.test(courseCode)
        || checked.some((other) => other.day === day && from < other.to && to > other.from)) invalid();

    total += to - from;
    checked.push({ day, start, end, courseCode, activityType: 'CONTACTO', from, to });
  }

  if (total > expectedHours * 60) {
    throw new HttpsError('invalid-argument', 'Las horas de contacto superan la jornada.');
  }

  const db = getFirestore();
  const users = db.collection('users');
  const owner = users.doc(uid);
  const id = createHash('sha256')
    .update(JSON.stringify([actor, uid, operationId]))
    .digest('hex');
  const pending = owner.collection('pendingAppointments').doc(id);

  await db.runTransaction(async (tx) => {
    const [superior, declarant, period, existing] = await Promise.all([
      tx.get(users.doc(actor)),
      tx.get(owner),
      tx.get(db.collection('periods').doc(periodId)),
      tx.get(pending),
    ]);

    if (superior.get('role') !== 'superior'
        || declarant.get('role') !== 'declarante'
        || declarant.get('superiorId') !== actor) {
      throw new HttpsError('permission-denied', 'El declarante debe estar asignado a tu perfil.');
    }
    if (existing.exists) return;
    if (period.get('enabled') !== true) {
      throw new HttpsError('failed-precondition', 'El período no está habilitado.');
    }

    const periodName = period.get('name') || period.get('label') || periodId;
    const createdAt = FieldValue.serverTimestamp();

    tx.create(pending, {
      superiorId: actor,
      periodId,
      periodName,
      unit: declarant.get('unit') || '',
      workplace: 'Universidad de Costa Rica',
      position: position.trim(),
      expectedHours,
      startDate,
      endDate,
      ...(typeof workloadFraction === 'string' ? { workloadFraction } : {}),
      blocks: checked.map(({ from, to, ...block }) => block),
      createdAt,
    });

    tx.create(owner.collection('notifications').doc(id), {
      title: 'Nombramiento pendiente',
      message: `Tu superior te asignó un nombramiento para ${periodName}.`,
      appointmentId: id,
      status: 'PENDIENTE',
      createdAt,
      read: false,
      readAt: null,
    });

    const emails = [
      [declarant, 'declarante', 'Nombramiento pendiente de completar',
        `Su superior le ha remitido un nombramiento para el período ${periodName}. Ingrese a DeclaraUCR y complete el horario desde Nueva declaración.`],
      [superior, 'superior', 'Confirmación de envío de nombramiento',
        `Se remitió a ${declarant.get('name') || 'la persona declarante'} el nombramiento correspondiente al período ${periodName}.`],
    ];

    for (const [recipient, suffix, subject, text] of emails) {
      const to = recipient.get('email');
      if (typeof to !== 'string' || !to.trim()) continue;
      tx.create(db.collection('_declarationMailOutbox').doc(`${id}-${suffix}`), {
        to: to.trim(),
        subject,
        text: `Estimado/a ${recipient.get('name') || 'usuario'}:\n\n${text}\n\nDeclaraUCR`,
        status: 'pending',
        createdAt,
      });
    }
  });

  return { id };
});