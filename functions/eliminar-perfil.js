const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

exports.eliminarPerfil = onCall({
  region: 'us-east1',
  maxInstances: 2,
  timeoutSeconds: 540,
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true',
}, async (request) => {
  const actor = request.auth?.uid;
  const uid = request.data?.uid;

  if (!actor) {
    throw new HttpsError('unauthenticated', 'Iniciá sesión.');
  }

  if (typeof uid !== 'string' ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(uid) ||
      uid === actor) {
    throw new HttpsError('invalid-argument', 'Seleccioná otro usuario.');
  }

  const db = getFirestore();
  const users = db.collection('users');
  const profile = users.doc(uid);

  await db.runTransaction(async (tx) => {
    const admin = await tx.get(users.doc(actor));
    if (admin.get('role') !== 'admin') {
      throw new HttpsError(
        'permission-denied',
        'Esta opción es para administración.',
      );
    }

    const target = await tx.get(profile);
    if (target.exists) {
      tx.update(profile, { role: 'eliminando' });
    }
  });

  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }

  const declarations = await db.collection('declarations')
    .where('ownerId', '==', uid).get();

  for (const declaration of declarations.docs) {
    // El PDF está en Cloud Storage y se conserva.
    await db.recursiveDelete(declaration.ref);
  }

  const assigned = await users.where('superiorId', '==', uid).get();
  for (const declarant of assigned.docs) {
    await db.runTransaction(async (tx) => {
      const current = await tx.get(declarant.ref);
      if (current.exists && current.get('superiorId') === uid) {
        tx.update(declarant.ref, {
          superiorId: FieldValue.delete(),
          superiorName: FieldValue.delete(),
        });
      }
    });
  }

  const reservations = db.collection('_registeredCedulas');
  const registered = await reservations.where('uid', '==', uid).get();
  for (const reservation of registered.docs) {
    await db.runTransaction(async (tx) => {
      const current = await tx.get(reservation.ref);
      if (current.exists && current.get('uid') === uid) {
        tx.delete(reservation.ref);
      }
    });
  }

  await db.collection('_serverLimits').doc(`registroPadron_${uid}`).delete();
  await db.recursiveDelete(profile);
  return { eliminado: true };
});