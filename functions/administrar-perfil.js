const { onCall, HttpsError } = require('./activation-https');
const { getFirestore } = require('firebase-admin/firestore');

exports.asignarSuperior = onCall(
  {
    region: 'us-east1',
    maxInstances: 2,
  },
  async (request) => {
    const adminId = request.auth?.uid;

    if (!adminId) {
      throw new HttpsError('unauthenticated', 'Iniciá sesión.');
    }

    const { uid, superiorId } = request.data ?? {};
    const validId = (id) =>
      typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);

    if (!validId(uid) || !validId(superiorId) || uid === superiorId) {
      throw new HttpsError(
        'invalid-argument',
        'Seleccioná un declarante y un superior válidos.'
      );
    }

    const db = getFirestore();
    const users = db.collection('users');

    await db.runTransaction(async (transaction) => {
      const admin = await transaction.get(users.doc(adminId));

      if (admin.get('role') !== 'admin') {
        throw new HttpsError(
          'permission-denied',
          'Solo un administrador puede asignar un superior.'
        );
      }

      const declarante = await transaction.get(users.doc(uid));
      const superior = await transaction.get(users.doc(superiorId));

      if (declarante.get('role') !== 'declarante') {
        throw new HttpsError(
          'failed-precondition',
          'El usuario seleccionado debe tener el rol Declarante.'
        );
      }

      if (superior.get('role') !== 'superior') {
        throw new HttpsError(
          'failed-precondition',
          'La persona asignada debe tener el rol Superior.'
        );
      }

      transaction.update(declarante.ref, {
        superiorId,
        superiorName: superior.get('name') || 'Superior asignado',
      });
    });

    return { asignado: true };
  }
);