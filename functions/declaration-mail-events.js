'use strict';

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { createHash } = require('node:crypto');
const { actions, email, notice } = require('./mail-helpers');

exports.queueDeclarationActionMail = onDocumentCreated({
  document: 'declarations/{declarationId}/events/{eventId}',
  region: 'us-east1',
  maxInstances: 2,
  timeoutSeconds: 120,
  retry: true,
}, async event => {
  if (!event.data) return;

  const action = event.data.data();

  if (
    !Object.hasOwn(actions, action.event) ||
    !Number.isSafeInteger(action.version) ||
    action.version < 1
  ) return;

  const db = getFirestore();
  const { declarationId, eventId } = event.params;
  const ref = db.collection('declarations').doc(declarationId);
  const current = await ref.get();

  if (!current.exists) return;

  const version = await ref
    .collection('versions')
    .doc(String(action.version))
    .get();

  const declaration = version.exists
    ? version.data()
    : current.data();

  const recipients = new Map();

  function add(uid, staffOnly = false) {
    if (
      typeof uid === 'string' &&
      /^[A-Za-z0-9_-]{1,128}$/.test(uid) &&
      !recipients.has(uid)
    ) {
      recipients.set(uid, staffOnly);
    }
  }

  add(declaration.ownerId);
  add(declaration.superiorId);
  add(action.userId, true);

  if (action.newStatus === 'ENVIADA_A_RRHH') {
    const staff = await db.collection('users')
      .where('role', '==', 'rrhh')
      .get();

    for (const user of staff.docs) add(user.id, true);
  }

  for (const [uid, staffOnly] of recipients) {
    const key = createHash('sha256')
      .update(JSON.stringify([declarationId, eventId, uid]))
      .digest('hex');

    const mailRef = db.collection('_declarationMailOutbox')
      .doc('event-' + key);

    await db.runTransaction(async tx => {
      const [user, existing] = await Promise.all([
        tx.get(db.collection('users').doc(uid)),
        tx.get(mailRef),
      ]);

      if (
        !user.exists ||
        existing.exists ||
        (staffOnly && user.get('role') !== 'rrhh')
      ) return;

      const to = String(user.get('email') || '').trim();
      if (!email(to)) return;

      tx.create(mailRef, {
        ...notice(action, declaration, user.get('name'), declarationId),
        to,
        recipientUid: uid,
        declarationId,
        version: action.version,
        eventId,
        status: 'pending',
        createdAt: FieldValue.serverTimestamp(),
      });
    });
  }
});
