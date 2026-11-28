'use strict';

exports.acceptDeclarationAndSendHr = require('./signed-pdf').acceptDeclarationAndSendHr;
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { createHash } = require('node:crypto');

exports.acceptDeclarationAndSendHr = onCall(
  {
    region: 'us-east1',
    timeoutSeconds: 60,
    maxInstances: 2,
  },
  async (request) => {
    const uid = request.auth?.uid;

    if (!uid) {
      throw new HttpsError('unauthenticated', 'Iniciá sesión.');
    }

    const { declarationId, version } = request.data ?? {};

    if (
      typeof declarationId !== 'string' ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(declarationId) ||
      !Number.isSafeInteger(version) ||
      version < 1
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Declaración o versión inválida.'
      );
    }

    const db = getFirestore();
    const ref = db.collection('declarations').doc(declarationId);

    const versionRef = ref
      .collection('versions')
      .doc(String(version));

    const superiorSignature = versionRef
      .collection('signatures')
      .doc('superior');

    const ownerSignature = versionRef
      .collection('signatures')
      .doc('owner');

    const eventRef = ref
      .collection('events')
      .doc('accept-superior-v' + version);

    return db.runTransaction(async (tx) => {
      const [
        profile,
        snapshot,
        owner,
        signature,
        previousEvent,
      ] = await Promise.all([
        tx.get(db.collection('users').doc(uid)),
        tx.get(ref),
        tx.get(ownerSignature),
        tx.get(superiorSignature),
        tx.get(eventRef),
      ]);

      if (!snapshot.exists) {
        throw new HttpsError(
          'not-found',
          'La declaración no existe.'
        );
      }

      const current = snapshot.data();

      if (
        profile.get('role') !== 'superior' ||
        current.superiorId !== uid
      ) {
        throw new HttpsError(
          'permission-denied',
          'Solo el superior asignado puede aceptar esta declaración.'
        );
      }

      if (current.version !== version) {
        throw new HttpsError(
          'failed-precondition',
          'La versión cambió. Actualizá la pantalla.'
        );
      }

      // Un reintento no duplica la firma ni el historial.
      if (
        previousEvent.exists &&
        previousEvent.get('userId') === uid &&
        previousEvent.get('version') === version &&
        previousEvent.get('newStatus') === 'ENVIADA_A_RRHH' &&
        signature.get('userId') === uid &&
        signature.get('version') === version &&
        [
          'ENVIADA_A_RRHH',
          'RECIBIDA_RRHH',
          'FINALIZADA',
        ].includes(current.status)
      ) {
        return {
          accepted: true,
          alreadyAccepted: true,
        };
      }

      if (current.status !== 'PENDIENTE_FIRMA_SUPERIOR') {
        throw new HttpsError(
          'failed-precondition',
          'La declaración no está pendiente de revisión del superior.'
        );
      }

      if (
        !owner.exists ||
        owner.get('userId') !== current.ownerId ||
        owner.get('version') !== version
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Falta la firma interna del declarante para esta versión.'
        );
      }

      if (signature.exists || previousEvent.exists) {
        throw new HttpsError(
          'failed-precondition',
          'Ya existe una aprobación para esta versión. Actualizá la pantalla.'
        );
      }

      const dateTime = FieldValue.serverTimestamp();

      const canonical = JSON.stringify({
        ...current,
        version,
        updatedAt: null,
      });

      tx.create(superiorSignature, {
        userId: uid,
        name:
          profile.get('name') ||
          request.auth.token?.email ||
          'Superior',
        dateTime,
        version,
        signatureId: 'superior',
        hash: createHash('sha256')
          .update(canonical)
          .digest('hex'),
        type: 'SUPERIOR',
      });

      tx.update(ref, {
        status: 'ENVIADA_A_RRHH',
        updatedAt: dateTime,
      });

      tx.create(eventRef, {
        event: 'signSuperior',
        userId: uid,
        dateTime,
        version,
        previousStatus: current.status,
        newStatus: 'ENVIADA_A_RRHH',
        observation:
          'Declaración aceptada y enviada a Recursos Humanos.',
      });

      return {
        accepted: true,
        alreadyAccepted: false,
      };
    });
  }
);
