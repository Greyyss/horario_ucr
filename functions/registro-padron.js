const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore } = require('firebase-admin/firestore');
const {
  consultarNombrePorCedula,
  consultarDatosPorCedula,
} = require('./padron');

const mensajeCedulaRegistrada =
  'Esta cédula ya está registrada. Iniciá sesión con tu cuenta original.';

function referenciasCedula(db, cedula) {
  return {
    reserva: db.collection('_registeredCedulas').doc(cedula),
    perfiles: db.collection('users')
      .where('identification', '==', cedula)
      .limit(1),
  };
}

async function limitarConsultasPadron(clave, maximo, mensaje) {
  const db = getFirestore();
  const ref = db.collection('_serverLimits').doc(clave);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const minuto = Math.floor(Date.now() / 60_000);
    const actual = snapshot.data();
    const consultas = actual?.minuto === minuto ? actual.consultas : 0;

    if (consultas >= maximo) {
      throw new HttpsError('resource-exhausted', mensaje);
    }

    transaction.set(ref, { minuto, consultas: consultas + 1 });
  });
}

exports.registroPadron = onCall(
  {
    region: 'us-east1',
    memory: '1GiB',
    timeoutSeconds: 120,
    maxInstances: 2,
  },
  async (request) => {
    const uid = request.auth?.uid;
    const email = request.auth?.token.email;

    if (!uid || typeof email !== 'string') {
      throw new HttpsError('unauthenticated', 'Iniciá sesión para registrarte.');
    }

    const { accion, cedula, nombreMostrado } = request.data ?? {};

    if (
      !['consultar', 'confirmar'].includes(accion) ||
      typeof cedula !== 'string' ||
      !/^[0-9]{9}$/.test(cedula)
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Ingresá una cédula de 9 dígitos.'
      );
    }

    if (process.env.FUNCTIONS_EMULATOR !== 'true') {
      await limitarConsultasPadron(
        `registroPadron_${uid}`,
        5,
        'Demasiados intentos. Probá en un minuto.'
      );
    }

    const db = getFirestore();
    const perfil = db.collection('users').doc(uid);

    if ((await perfil.get()).exists) {
      throw new HttpsError('already-exists', 'Tu perfil ya está registrado.');
    }

    let nombre;
    try {
      nombre = await consultarNombrePorCedula(cedula);
    } catch (error) {
      console.error('Error al leer el padrón:', error);
      throw new HttpsError(
        'unavailable',
        'No se pudo consultar el padrón. Intentá de nuevo.'
      );
    }

    if (!nombre) {
      throw new HttpsError(
        'not-found',
        'La cédula no aparece en este corte del padrón.'
      );
    }

    if (accion === 'consultar') {
      return { nombre };
    }

    if (nombreMostrado !== nombre) {
      throw new HttpsError(
        'failed-precondition',
        'Consultá la cédula de nuevo antes de confirmar.'
      );
    }

    const { reserva, perfiles } = referenciasCedula(db, cedula);

    await db.runTransaction(async (transaction) => {
      const perfilActual = await transaction.get(perfil);

      if (perfilActual.exists) {
        throw new HttpsError('already-exists', 'Tu perfil ya está registrado.');
      }

      const reservaActual = await transaction.get(reserva);
      const perfilesExistentes = await transaction.get(perfiles);

      if (reservaActual.exists || !perfilesExistentes.empty) {
        throw new HttpsError('already-exists', mensajeCedulaRegistrada);
      }

      transaction.create(reserva, { uid });
      transaction.create(perfil, {
        name: nombre,
        identification: cedula,
        email,
        role: 'declarante',
        unit: '',
        phone: '',
        identitySource: 'padron',
      });
    });

    return { registrado: true };
  }
);

exports.consultarPadronRegistro = onCall(
  {
    region: 'us-east1',
    memory: '1GiB',
    timeoutSeconds: 120,
    enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true',
  },
  async (request) => {
    const { cedula, accion = 'consultar' } = request.data ?? {};

    if (
      typeof cedula !== 'string' ||
      !/^[0-9]{9}$/.test(cedula) ||
      !['consultar', 'verificarDisponibilidad'].includes(accion)
    ) {
      throw new HttpsError(
        'invalid-argument',
        'La solicitud de consulta de cédula no es válida.'
      );
    }

    if (process.env.FUNCTIONS_EMULATOR !== 'true') {
      await limitarConsultasPadron(
        'consultarPadronRegistro',
        30,
        'Hay muchas consultas en este momento. Intentá en un minuto.'
      );
    }

    if (accion === 'verificarDisponibilidad') {
      const { reserva, perfiles } = referenciasCedula(getFirestore(), cedula);
      const [reservaActual, perfilesExistentes] = await Promise.all([
        reserva.get(),
        perfiles.get(),
      ]);

      if (reservaActual.exists || !perfilesExistentes.empty) {
        throw new HttpsError('already-exists', mensajeCedulaRegistrada);
      }

      return { disponible: true };
    }

    let persona;
    try {
      persona = await consultarDatosPorCedula(cedula);
    } catch (error) {
      console.error('Error al leer el padrón:', error);
      throw new HttpsError(
        'unavailable',
        'No se pudo consultar el padrón. Intentá de nuevo.'
      );
    }

    if (!persona) {
      throw new HttpsError('not-found', 'La cédula no aparece en el padrón.');
    }

    return {
      nombres: persona.nombres,
      apellidos: persona.apellidos,
      nombreCompleto: persona.nombreCompleto,
    };
  }
);