const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { randomBytes } = require('node:crypto');
const { consultarNombrePorCedula } = require('./padron');

exports.registrarDeclarante = onCall(
  {
    region: 'us-east1',
    memory: '1GiB',
    timeoutSeconds: 120,
    maxInstances: 2,
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true',
  },
  async (request) => {
    const superiorId = request.auth?.uid;
    if (!superiorId) {
      throw new HttpsError('unauthenticated', 'Iniciá sesión.');
    }

    const db = getFirestore();
    const users = db.collection('users');
    const superior = users.doc(superiorId);

    if ((await superior.get()).get('role') !== 'superior') {
      throw new HttpsError(
        'permission-denied',
        'Esta opción es para superiores.'
      );
    }

    const data = request.data ?? {};
    const cedula = typeof data.cedula === 'string' ? data.cedula.trim() : '';
    const correo = typeof data.correo === 'string' ? data.correo.trim() : '';
    const telefono = typeof data.telefono === 'string' ? data.telefono.trim() : '';
    const unidad = typeof data.unidad === 'string' ? data.unidad.trim() : '';

    if (
      !/^[0-9]{9}$/.test(cedula) ||
      correo.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo) ||
      !/^[0-9]{8}$/.test(telefono) ||
      unidad.length < 2 ||
      unidad.length > 150
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Revisá la cédula, el correo, el teléfono y la unidad.'
      );
    }

    const reserva = db.collection('_registeredCedulas').doc(cedula);
    const perfiles = users.where('identification', '==', cedula).limit(1);

    const [reservaActual, perfilesActuales] = await Promise.all([
      reserva.get(),
      perfiles.get(),
    ]);
    if (reservaActual.exists || !perfilesActuales.empty) {
      throw new HttpsError('already-exists', 'La cédula ya está registrada.');
    }

    let nombre;
    try {
      nombre = await consultarNombrePorCedula(cedula);
    } catch (error) {
      console.error('Error al consultar el padrón:', error);
      throw new HttpsError('unavailable', 'No se pudo consultar el padrón.');
    }
    if (!nombre) {
      throw new HttpsError('not-found', 'La cédula no aparece en el padrón.');
    }

    const auth = getAuth();
    let cuenta;
    try {
      cuenta = await auth.createUser({
        email: correo,
        displayName: nombre,
        password: randomBytes(32).toString('base64url'),
      });
    } catch (error) {
      if (error.code === 'auth/email-already-exists') {
        throw new HttpsError('already-exists', 'El correo ya está registrado.');
      }
      throw error;
    }

    const perfil = users.doc(cuenta.uid);
    try {
      await db.runTransaction(async (tx) => {
        const superiorActual = await tx.get(superior);
        const cedulaReservada = await tx.get(reserva);
        const perfilesExistentes = await tx.get(perfiles);

        if (superiorActual.get('role') !== 'superior') {
          throw new HttpsError(
            'permission-denied',
            'Esta opción es para superiores.'
          );
        }
        if (cedulaReservada.exists || !perfilesExistentes.empty) {
          throw new HttpsError('already-exists', 'La cédula ya está registrada.');
        }

        tx.create(reserva, { uid: cuenta.uid });
        tx.create(perfil, {
          superiorId,
          superiorName: superiorActual.get('name') || 'Superior asignado',
          name: nombre,
          identification: cedula,
          email: correo,
          phone: telefono,
          unit: unidad,
          role: 'declarante',
          identitySource: 'padron',
        });
      });
    } catch (error) {
      try {
        if (!(await perfil.get()).exists) {
          await auth.deleteUser(cuenta.uid);
        }
      } catch (cleanupError) {
        console.error('No se pudo revertir el alta:', cuenta.uid, cleanupError);
      }
      throw error;
    }

    return { nombre };
  }
);