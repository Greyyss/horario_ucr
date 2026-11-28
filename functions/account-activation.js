'use strict';

const { onCall, HttpsError } =
  require('firebase-functions/v2/https');

const { onCall: guardedCall } = require('./activation-https');
const { getAuth } = require('firebase-admin/auth');

const {
  getFirestore,
  FieldValue,
} = require('firebase-admin/firestore');

const {
  state,
  millis,
  canActivate,
  newAccessFields,
} = require('./account-access-policy');

const options = {
  region: 'us-east1',
  maxInstances: 2,
  timeoutSeconds: 60,
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true',
};

exports.completeAccountActivation = onCall(
  options,
  async request => {
    const uid = request.auth?.uid;

    if (!uid) {
      throw new HttpsError('unauthenticated', 'Iniciá sesión.');
    }

    const account = await getAuth().getUser(uid);

    if (account.disabled) {
      throw new HttpsError(
        'permission-denied',
        'Cuenta deshabilitada.'
      );
    }

    const db = getFirestore();

    return db.runTransaction(async tx => {
      const ref = db.collection('users').doc(uid);
      const snapshot = await tx.get(ref);
      const profile = snapshot.data();
      const now = Date.now();
      const current = state(profile, now);

      if (current !== 'pending') {
        return { state: current };
      }

      if (!canActivate(profile, request.auth.token, now)) {
        throw new HttpsError(
          'failed-precondition',
          'Cerrá sesión e ingresá con tu correo y la contraseña que estableciste.'
        );
      }

      tx.update(ref, {
        accessState: 'active',
        accessActivatedAt: FieldValue.serverTimestamp(),
      });

      return { state: 'active' };
    });
  }
);

exports.renewAccountInvitation = guardedCall(
  options,
  async request => {
    const actor = request.auth?.uid;

    if (!actor) {
      throw new HttpsError('unauthenticated', 'Iniciá sesión.');
    }

    const { uid, operationId } = request.data || {};

    if (
      typeof uid !== 'string' ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(uid) ||
      uid === actor ||
      typeof operationId !== 'string' ||
      !/^[A-Za-z0-9_-]{16,80}$/.test(operationId)
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Seleccioná otro usuario válido.'
      );
    }

    const db = getFirestore();

    return db.runTransaction(async tx => {
      const actorRef = db.collection('users').doc(actor);
      const targetRef = db.collection('users').doc(uid);

      const [admin, target] = await Promise.all([
        tx.get(actorRef),
        tx.get(targetRef),
      ]);

      if (
        admin.get('role') !== 'admin' ||
        !['active', 'legacy'].includes(state(admin.data()))
      ) {
        throw new HttpsError(
          'permission-denied',
          'Esta opción es para Administración con acceso habilitado.'
        );
      }

      const profile = target.data();

      if (
        !profile ||
        !['pending', 'expired'].includes(state(profile))
      ) {
        throw new HttpsError(
          'failed-precondition',
          'La cuenta no tiene una invitación pendiente.'
        );
      }

      if (profile.accessRenewalOperation === operationId) {
        return {
          renewed: true,
          expiresAt: millis(profile.accessExpiresAt),
        };
      }

      const fields = newAccessFields();

      tx.update(targetRef, {
        ...fields,
        accessRenewalOperation: operationId,
        accessRenewedBy: actor,
      });

      return {
        renewed: true,
        expiresAt: millis(fields.accessExpiresAt),
      };
    });
  }
);
