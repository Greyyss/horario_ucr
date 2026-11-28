const { newAccessFields } = require('./account-access-policy');
'use strict';

const {
  onCall,
  HttpsError,
} = require('./activation-https');

const {
  getAuth,
} = require('firebase-admin/auth');

const {
  getFirestore,
  FieldValue,
} = require('firebase-admin/firestore');

const {
  randomBytes,
  createHash,
} = require('node:crypto');

const {
  consultarNombrePorCedula,
} = require('./padron');

const roles = [
  'declarante',
  'superior',
  'rrhh',
  'admin',
];

function fail(code, message) {
  throw new HttpsError(code, message);
}

function text(value) {
  return typeof value === 'string'
    ? value.trim()
    : '';
}

exports.adminCrearUsuario = onCall(
  {
    region: 'us-east1',
    memory: '1GiB',
    timeoutSeconds: 120,
    maxInstances: 2,
    enforceAppCheck:
      process.env.FUNCTIONS_EMULATOR !== 'true',
  },
  async request => {
    const actorId = request.auth?.uid;

    if (!actorId) {
      fail('unauthenticated', 'Iniciá sesión.');
    }

    const data = request.data ?? {};

    const cedula = text(data.cedula);
    const correo = text(data.correo).toLowerCase();
    const telefono = text(data.telefono);
    const unidad = text(data.unidad);
    const rol = text(data.rol);
    const operationId = text(data.operationId);

    const superiorId = rol === 'declarante'
      ? text(data.superiorId)
      : null;

    if (
      !/^[0-9]{9}$/.test(cedula) ||
      correo.length > 254 ||
      !/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(correo) ||
      !/^[0-9]{8}$/.test(telefono) ||
      unidad.length < 2 ||
      unidad.length > 150 ||
      /[\r\n\t]/.test(unidad) ||
      !roles.includes(rol) ||
      !/^[A-Za-z0-9_-]{16,80}$/.test(operationId)
    ) {
      fail(
        'invalid-argument',
        'Revisá la cédula, correo, teléfono, unidad y rol.'
      );
    }

    if (
      rol === 'declarante' &&
      !/^[A-Za-z0-9_-]{1,128}$/.test(superiorId)
    ) {
      fail(
        'invalid-argument',
        'Seleccioná un superior para el declarante.'
      );
    }

    const db = getFirestore();
    const auth = getAuth();
    const users = db.collection('users');

    const actorRef = users.doc(actorId);

    if ((await actorRef.get()).get('role') !== 'admin') {
      fail(
        'permission-denied',
        'Solo Administración puede crear usuarios desde esta opción.'
      );
    }

    // Una misma solicitud conserva el mismo UID.
    // Así se puede recuperar un intento cuya respuesta se perdió.
    const uid = createHash('sha256')
      .update(`${actorId}:${operationId}`)
      .digest('hex');

    const fingerprint = createHash('sha256')
      .update(JSON.stringify([
        cedula,
        correo,
        telefono,
        unidad,
        rol,
        superiorId,
      ]))
      .digest('hex');

    const profileRef = users.doc(uid);
    const reservationRef = db
      .collection('_registeredCedulas')
      .doc(cedula);

    const duplicates = users
      .where('identification', '==', cedula)
      .limit(1);

    function sameRequest(snapshot) {
      return (
        snapshot.exists &&
        snapshot.get('createdBy') === actorId &&
        snapshot.get('adminCreationOperation') === operationId &&
        snapshot.get('creationFingerprint') === fingerprint
      );
    }

    function result(snapshot, alreadyCreated) {
      return {
        uid,
        nombre: snapshot.get('name'),
        rol: snapshot.get('role'),
        alreadyCreated,
      };
    }

    const existing = await profileRef.get();

    if (existing.exists) {
      if (!sameRequest(existing)) {
        fail(
          'failed-precondition',
          'La solicitud cambió. Abrí nuevamente el formulario.'
        );
      }

      let account;

      try {
        account = await auth.getUser(uid);
      } catch {
        fail(
          'failed-precondition',
          'El perfil existe, pero su cuenta de acceso requiere revisión.'
        );
      }

      if (account.email?.toLowerCase() !== correo) {
        fail(
          'failed-precondition',
          'La cuenta existente requiere revisión.'
        );
      }

      return result(existing, true);
    }

    const [reservation, profiles] = await Promise.all([
      reservationRef.get(),
      duplicates.get(),
    ]);

    if (reservation.exists || !profiles.empty) {
      fail(
        'already-exists',
        'La cédula ya está registrada.'
      );
    }

    if (superiorId) {
      const superior = await users.doc(superiorId).get();

      if (
        !superior.exists ||
        superior.get('role') !== 'superior'
      ) {
        fail(
          'failed-precondition',
          'El superior seleccionado ya no está disponible.'
        );
      }
    }

    let nombre;

    try {
      nombre = await consultarNombrePorCedula(cedula);
    } catch (error) {
      console.error(
        'No se pudo consultar el padrón.',
        { code: error.code || 'PADRON_ERROR' }
      );

      fail(
        'unavailable',
        'No se pudo consultar el padrón. Intentá nuevamente.'
      );
    }

    if (
      typeof nombre !== 'string' ||
      !nombre.trim()
    ) {
      fail(
        'not-found',
        'La cédula no aparece en el padrón.'
      );
    }

    nombre = nombre.trim();

    try {
      await auth.createUser({
        uid,
        email: correo,
        displayName: nombre,
        password: randomBytes(32).toString('base64url'),
      });
    } catch (error) {
      // Si la cuenta se creó en un intento anterior de esta
      // misma operación, continuamos sin crear otra.
      let recovered = null;

      try {
        recovered = await auth.getUser(uid);
      } catch {
        // Se maneja a continuación.
      }

      if (
        !recovered ||
        recovered.email?.toLowerCase() !== correo
      ) {
        if (
          error.code === 'auth/email-already-exists' ||
          error.code === 'auth/uid-already-exists'
        ) {
          fail(
            'already-exists',
            'El correo ya está registrado.'
          );
        }

        if (error.code === 'auth/invalid-email') {
          fail(
            'invalid-argument',
            'El correo electrónico no es válido.'
          );
        }

        console.error(
          'No se pudo crear la cuenta de acceso.',
          { code: error.code || 'AUTH_ERROR' }
        );

        fail(
          'unavailable',
          'No se pudo crear la cuenta de acceso. Intentá nuevamente.'
        );
      }
    }

    try {
      return await db.runTransaction(async tx => {
        const [
          actor,
          reserved,
          profilesNow,
          profileNow,
          superior,
        ] = await Promise.all([
          tx.get(actorRef),
          tx.get(reservationRef),
          tx.get(duplicates),
          tx.get(profileRef),
          superiorId
            ? tx.get(users.doc(superiorId))
            : Promise.resolve(null),
        ]);

        if (actor.get('role') !== 'admin') {
          fail(
            'permission-denied',
            'Tu cuenta ya no tiene permisos de Administración.'
          );
        }

        if (profileNow.exists) {
          if (!sameRequest(profileNow)) {
            fail(
              'already-exists',
              'La cuenta ya tiene otro perfil registrado.'
            );
          }

          return result(profileNow, true);
        }

        if (reserved.exists || !profilesNow.empty) {
          fail(
            'already-exists',
            'La cédula ya está registrada.'
          );
        }

        if (
          superiorId &&
          (
            !superior.exists ||
            superior.get('role') !== 'superior'
          )
        ) {
          fail(
            'failed-precondition',
            'El superior seleccionado ya no está disponible.'
          );
        }

        tx.create(reservationRef, { uid });

        tx.create(profileRef, {
          ...newAccessFields(),
          name: nombre,
          identification: cedula,
          email: correo,
          phone: telefono,
          unit: unidad,
          role: rol,
          identitySource: 'padron',
          createdBy: actorId,
          createdAt: FieldValue.serverTimestamp(),
          adminCreationOperation: operationId,
          creationFingerprint: fingerprint,
          ...(superiorId
            ? {
                superiorId,
                superiorName:
                  superior.get('name') || 'Superior asignado',
              }
            : {}),
        });

        return {
          uid,
          nombre,
          rol,
          alreadyCreated: false,
        };
      });
    } catch (error) {
      try {
        // No borrar una cuenta cuyo perfil sí quedó guardado.
        if (!(await profileRef.get()).exists) {
          await auth.deleteUser(uid);
        }
      } catch (cleanupError) {
        console.error(
          'No se pudo completar la reversión del alta.',
          {
            uid,
            code: cleanupError.code || 'CLEANUP_ERROR',
          }
        );
      }

      throw error;
    }
  }
);