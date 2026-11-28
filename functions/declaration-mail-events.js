'use strict';

const {
  onDocumentCreated,
} = require('firebase-functions/v2/firestore');

const {
  getFirestore,
  FieldValue,
} = require('firebase-admin/firestore');

const {
  createHash,
} = require('node:crypto');

const {
  email,
  message,
} = require('./mail-helpers');

exports.queueDeclarationActionMail = onDocumentCreated(
  {
    document: 'declarations/{declarationId}/events/{eventId}',
    region: 'us-east1',
    maxInstances: 2,
    timeoutSeconds: 120,
    retry: true,
  },
  async event => {
    if (!event.data) return;

    const action = event.data.data();

    // Solo cambios de manos. Los nombramientos nuevos
    // se notifican desde publicar-nombramiento.js.
    if (
      !['route', 'return', 'signSuperior'].includes(action.event) ||
      !Number.isSafeInteger(action.version) ||
      action.version < 1
    ) {
      return;
    }

    const db = getFirestore();

    const {
      declarationId,
      eventId,
    } = event.params;

    const declarationRef = db
      .collection('declarations')
      .doc(declarationId);

    const [current, savedVersion] = await Promise.all([
      declarationRef.get(),
      declarationRef
        .collection('versions')
        .doc(String(action.version))
        .get(),
    ]);

    if (!current.exists) return;
    if (current.get('mailTestOnly') === true) return;

    const declaration = savedVersion.exists
      ? savedVersion.data()
      : current.data();

    if (declaration.version !== action.version) return;

    const recipients = [];

    if (
      action.event === 'return' &&
      action.previousStatus === 'PENDIENTE_FIRMA_SUPERIOR' &&
      action.newStatus === 'DEVUELTA' &&
      action.userId === declaration.superiorId
    ) {
      recipients.push({
        uid: declaration.ownerId,
        role: 'declarante',
        type: 'DEVOLUCION_DECLARANTE',
      });
    } else if (
      action.event === 'route' ||
      action.event === 'signSuperior'
    ) {
      const workflow = await db
        .collection('_signatureWorkflows')
        .doc(`${declarationId}--v${action.version}`)
        .get();

      const proof = workflow.data();

      if (
        !proof ||
        proof.declarationId !== declarationId ||
        proof.version !== action.version ||
        proof.ownerId !== declaration.ownerId ||
        proof.superiorId !== declaration.superiorId ||
        typeof action.sha256 !== 'string' ||
        !/^[a-f0-9]{64}$/.test(action.sha256)
      ) {
        return;
      }

      if (
        action.event === 'route' &&
        action.newStatus === 'PENDIENTE_FIRMA_SUPERIOR' &&
        action.userId === declaration.ownerId &&
        proof.owner?.sha256 === action.sha256 &&
        proof.owner?.userId === declaration.ownerId
      ) {
        recipients.push({
          uid: declaration.superiorId,
          role: 'superior',
          type: 'DECLARACION_SUPERIOR',
        });
      } else if (
        action.event === 'signSuperior' &&
        action.previousStatus === 'PENDIENTE_FIRMA_SUPERIOR' &&
        action.newStatus === 'ENVIADA_A_RRHH' &&
        action.userId === declaration.superiorId &&
        proof.superior?.sha256 === action.sha256 &&
        proof.superior?.userId === declaration.superiorId
      ) {
        recipients.push({
          uid: declaration.ownerId,
          role: 'declarante',
          type: 'ENVIO_RRHH_DECLARANTE',
        });

        const staff = await db
          .collection('users')
          .where('role', '==', 'rrhh')
          .get();

        for (const user of staff.docs) {
          recipients.push({
            uid: user.id,
            role: 'rrhh',
            type: 'DECLARACION_RRHH',
          });
        }
      }
    }

    for (const recipient of recipients) {
      if (
        typeof recipient.uid !== 'string' ||
        !/^[A-Za-z0-9_-]{1,128}$/.test(recipient.uid)
      ) {
        continue;
      }

      const key = createHash('sha256')
        .update(JSON.stringify([
          declarationId,
          eventId,
          recipient.uid,
        ]))
        .digest('hex');

      const mailRef = db
        .collection('_declarationMailOutbox')
        .doc('event-' + key);

      await db.runTransaction(async tx => {
        const userRef = db
          .collection('users')
          .doc(recipient.uid);

        const [user, existing] = await Promise.all([
          tx.get(userRef),
          tx.get(mailRef),
        ]);

        if (
          !user.exists ||
          existing.exists ||
          user.get('role') !== recipient.role
        ) {
          return;
        }

        const to = String(
          user.get('email') || ''
        ).trim();

        if (!email(to)) return;

        tx.create(mailRef, {
          ...message(recipient.type, {
            name: user.get('name'),
            ownerName: declaration.ownerName,
            period: declaration.periodId,
            reference: declarationId,
            version: action.version,
            reason:
              recipient.type === 'DEVOLUCION_DECLARANTE'
                ? action.observation
                : '',
          }),
          to,
          recipientUid: recipient.uid,
          expectedRole: recipient.role,
          declarationId,
          version: action.version,
          eventId,
          status: 'pending',
          createdAt: FieldValue.serverTimestamp(),
        });
      });
    }
  }
);