'use strict';

const { isDeepStrictEqual } = require('node:util');

const {
  ScheduleValidationError,
  validateDeclarationData,
  generateDeclarationObservations,
  fields,
} = require('./schedule-validation');

// El SDK Admin omite las reglas de Firestore.
// Los permisos y las validaciones se comprueban aquí.
function createDeclarationHandlers({
  db,
  FieldValue,
  HttpsError,
}) {
  const deny = (code, message) => {
    throw new HttpsError(code, message);
  };

  function uidOf(request) {
    if (!request.auth?.uid) {
      deny('unauthenticated', 'Debés iniciar sesión.');
    }

    return request.auth.uid;
  }

  function idOf(value) {
    if (
      typeof value !== 'string' ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(value)
    ) {
      deny('invalid-argument', 'Identificador inválido.');
    }

    return value;
  }

  function versionOf(value) {
    if (!Number.isSafeInteger(value) || value < 1) {
      deny('invalid-argument', 'Versión inválida.');
    }

    return value;
  }

  function validate(
    data,
    complete = false,
    requireInstitutionalFraction = false,
    requireActivityDetails = false
  ) {
    try {
      return validateDeclarationData(data, {
        complete,
        requireInstitutionalFraction,
        requireActivityDetails,
      });
    } catch (error) {
      if (error instanceof ScheduleValidationError) {
        deny('invalid-argument', error.message);
      }

      throw error;
    }
  }

  function buildObservations(data) {
    try {
      return generateDeclarationObservations({
        ...data,
        observations: '',
      });
    } catch (error) {
      if (error instanceof ScheduleValidationError) {
        deny('invalid-argument', error.message);
      }

      throw error;
    }
  }

  function hasActivityDetails(data) {
    return data.appointments.some(job =>
      job.blocks.some(block =>
        ['courseCode', 'activityType', 'activityName']
          .some(key => block[key] != null)
      )
    );
  }

  function checkOwner(current, uid, version, status) {
    if (!current) {
      deny('not-found', 'La declaración no existe.');
    }

    if (current.ownerId !== uid) {
      deny(
        'permission-denied',
        'No podés modificar esta declaración.'
      );
    }

    if (
      current.status !== status ||
      current.version !== version
    ) {
      deny(
        'failed-precondition',
        'La declaración cambió o no está en el estado requerido. ' +
        'Volvé a abrirla.'
      );
    }
  }

  function checkProfileIdentification(
    profile,
    identification
  ) {
    if (!profile) {
      deny(
        'failed-precondition',
        'No se encontró tu perfil. Contactá al administrador.'
      );
    }

    const registeredId = profile.identification;

    if (
      typeof registeredId !== 'string' ||
      !/^[0-9]{9}$/.test(registeredId)
    ) {
      deny(
        'failed-precondition',
        'Primero registrá una cédula válida ' +
        'en Mis datos personales.'
      );
    }

    if (identification !== registeredId) {
      deny(
        'failed-precondition',
        'La cédula de la declaración no coincide con tu perfil. ' +
        'Revisá tus datos.'
      );
    }
  }

  function checkSuperior(snapshot, uid) {
    if (
      !snapshot.exists ||
      snapshot.data().role !== 'superior' ||
      snapshot.id === uid
    ) {
      deny(
        'failed-precondition',
        'Seleccioná un superior válido de la lista. ' +
        'No podés seleccionarte a vos mismo.'
      );
    }
  }

  async function listSuperiors(request) {
    const uid = uidOf(request);

    const profile = await db
      .collection('users')
      .doc(uid)
      .get();

    if (!profile.exists) {
      deny(
        'permission-denied',
        'No se encontró tu perfil de usuario.'
      );
    }

    // Solo devuelve los datos necesarios para el selector.
    const snapshot = await db
      .collection('users')
      .where('role', '==', 'superior')
      .select('name', 'unit')
      .get();

    const superiors = snapshot.docs
      .filter(doc =>
        doc.id !== uid &&
        typeof doc.data().name === 'string' &&
        doc.data().name.trim().length > 0
      )
      .map(doc => ({
        uid: doc.id,
        name: doc.data().name.trim(),
        unit:
          typeof doc.data().unit === 'string'
            ? doc.data().unit.trim()
            : '',
      }));

    superiors.sort((a, b) =>
      a.name.localeCompare(b.name, 'es') ||
      a.unit.localeCompare(b.unit, 'es') ||
      a.uid.localeCompare(b.uid)
    );

    return { superiors };
  }

  function event(
    tx,
    ref,
    uid,
    type,
    version,
    from,
    to,
    extra = {}
  ) {
    const eventRef = ref.collection('events').doc();

    tx.set(eventRef, {
      event: type,
      userId: uid,
      dateTime: FieldValue.serverTimestamp(),
      version,
      previousStatus: from,
      newStatus: to,
      observation: '',
      ...extra,
    });

    return eventRef;
  }

  // ==========================================================
  // GUARDAR BORRADOR
  // ==========================================================

  async function save(request) {
    const uid = uidOf(request);
    const input = request.data;

    if (
      !input ||
      typeof input !== 'object' ||
      Array.isArray(input)
    ) {
      deny('invalid-argument', 'Datos inválidos.');
    }

    // Los marcadores de formato los establece el servidor.
    // El cliente no puede enviarlos ni modificarlos.
    const allowed = [
      'id',
      'version',
      'periodId',
      'superiorId',
      ...fields,
    ];

    if (
      Object.keys(input).some(
        key => !allowed.includes(key)
      )
    ) {
      deny(
        'invalid-argument',
        'Se recibieron campos no permitidos.'
      );
    }

    // El texto recibido del cliente no determina
    // las observaciones que se guardan.
    const payload = {
      ...input,
      observations: '',
    };

    const isNew = payload.id === '';

    const ref = isNew
      ? db.collection('declarations').doc()
      : db.collection('declarations').doc(
          idOf(payload.id)
        );

    const version = versionOf(payload.version);

    if (isNew && version !== 1) {
      deny(
        'invalid-argument',
        'Una declaración nueva comienza en versión 1.'
      );
    }

    idOf(payload.periodId);
    idOf(payload.superiorId);

    // Comprobación inicial de estructura y datos.
    validate(payload);

    return db.runTransaction(async tx => {
      const versionRef = ref
        .collection('versions')
        .doc(String(version));

      const [
        snapshot,
        versionSnapshot,
        period,
        profileSnapshot,
        superiorSnapshot,
      ] = await Promise.all([
        tx.get(ref),
        tx.get(versionRef),
        tx.get(
          db.collection('periods').doc(payload.periodId)
        ),
        tx.get(
          db.collection('users').doc(uid)
        ),
        tx.get(
          db.collection('users').doc(payload.superiorId)
        ),
      ]);

      if (!isNew) {
        const current = snapshot.data();

        checkOwner(
          current,
          uid,
          version,
          'BORRADOR'
        );

        if (
          current.periodId !== payload.periodId ||
          current.superiorId !== payload.superiorId
        ) {
          deny(
            'failed-precondition',
            'No se puede cambiar el período ni el superior ' +
            'de un borrador existente.'
          );
        }

        if (
          current.identification !== payload.identification
        ) {
          deny(
            'failed-precondition',
            'No se puede cambiar la cédula de una declaración ' +
            'existente. Si el dato es incorrecto, solicitá ' +
            'una revisión al administrador.'
          );
        }
      } else if (snapshot.exists) {
        deny(
          'already-exists',
          'La declaración ya existe.'
        );
      }

      checkProfileIdentification(
        profileSnapshot.data(),
        payload.identification
      );

      checkSuperior(superiorSnapshot, uid);

      const current = snapshot.data();

      const scheduleChanged =
        !isNew &&
        ['appointments', 'externalJobs'].some(key =>
          !isDeepStrictEqual(
            current[key],
            payload[key]
          )
        );

      // Las declaraciones nuevas usan observaciones automáticas.
      //
      // Los borradores anteriores se incorporan cuando cambian
      // sus nombramientos o incluyen los datos de actividades.
      //
      // Una declaración que ya usa este formato no puede
      // volver al formato anterior borrando sus metadatos.
      const automatic =
        isNew ||
        current?.observationsFormatVersion === 1 ||
        scheduleChanged ||
        hasActivityDetails(payload);

      validate(
        payload,
        false,
        isNew || current?.formatVersion === 2,
        automatic
      );

      const normalized = {
        ...payload,
        observations: automatic
          ? buildObservations(payload)
          : (current.observations ?? ''),
      };

      // Se calcula dentro de cada intento de la transacción.
      const editable = Object.fromEntries(
        fields.map(key => [key, normalized[key]])
      );

      const enablingAutomatic =
        automatic &&
        current?.observationsFormatVersion !== 1;

      // Los permisos y el perfil ya se comprobaron,
      // incluso cuando no hay cambios para guardar.
      if (
        !isNew &&
        !enablingAutomatic &&
        fields.every(key =>
          isDeepStrictEqual(
            current[key],
            editable[key]
          )
        )
      ) {
        return {
          id: ref.id,
          saved: false,
        };
      }

      if (
        !period.exists ||
        period.data().enabled !== true
      ) {
        deny(
          'failed-precondition',
          'El período no está habilitado.'
        );
      }

      const stamp = FieldValue.serverTimestamp();

      if (isNew) {
        const data = {
          ...editable,
          formatVersion: 2,
          observationsFormatVersion: 1,
          ownerId: uid,
          periodId: payload.periodId,
          superiorId: payload.superiorId,
          status: 'BORRADOR',
          version: 1,
          updatedAt: stamp,
        };

        tx.create(ref, data);

        tx.create(versionRef, {
          ...data,
          createdAt: stamp,
        });

        event(
          tx,
          ref,
          uid,
          'CREADA',
          1,
          'BORRADOR',
          'BORRADOR'
        );
      } else {
        const eventRef = event(
          tx,
          ref,
          uid,
          'MODIFICADA',
          version,
          'BORRADOR',
          'BORRADOR'
        );

        const patch = {
          ...editable,
          ...(automatic
            ? { observationsFormatVersion: 1 }
            : {}),
          updatedAt: stamp,
          lastEditEventId: eventRef.id,
        };

        tx.update(ref, patch);

        if (versionSnapshot.exists) {
          const saved = versionSnapshot.data();

          if (
            saved.ownerId !== uid ||
            saved.periodId !== payload.periodId ||
            saved.superiorId !== payload.superiorId ||
            saved.version !== version
          ) {
            deny(
              'failed-precondition',
              'La versión guardada no coincide ' +
              'con la declaración.'
            );
          }

          tx.update(versionRef, patch);
        } else {
          tx.create(versionRef, {
            ...current,
            ...patch,
            createdAt: stamp,
          });
        }
      }

      return {
        id: ref.id,
        saved: true,
      };
    });
  }

  // ==========================================================
  // VALIDAR DECLARACIÓN GUARDADA
  // ==========================================================

  async function validateStored(request) {
    const uid = uidOf(request);
    const id = idOf(request.data?.id);
    const version = versionOf(request.data?.version);

    const ref = db
      .collection('declarations')
      .doc(id);

    return db.runTransaction(async tx => {
      const [
        snapshot,
        versionSnapshot,
        profileSnapshot,
      ] = await Promise.all([
        tx.get(ref),
        tx.get(
          ref.collection('versions').doc(
            String(version)
          )
        ),
        tx.get(
          db.collection('users').doc(uid)
        ),
      ]);

      const current = snapshot.data();

      checkOwner(
        current,
        uid,
        version,
        'BORRADOR'
      );

      checkProfileIdentification(
        profileSnapshot.data(),
        current.identification
      );

      const superiorSnapshot = await tx.get(
        db.collection('users').doc(
          idOf(current.superiorId)
        )
      );

      checkSuperior(superiorSnapshot, uid);

      // Conserva todas las reglas de horarios,
      // incluido el máximo de diez horas diarias.
      const totals = validate(
        current,
        true,
        current.formatVersion === 2,
        current.observationsFormatVersion === 1
      );

      // El resumen guardado debe corresponder exactamente
      // a los cursos, actividades y horarios de esta versión.
      if (
        current.observationsFormatVersion === 1 &&
        current.observations !== buildObservations(current)
      ) {
        deny(
          'failed-precondition',
          'Las observaciones no coinciden con los horarios. ' +
          'Abrí el borrador y guardalo nuevamente.'
        );
      }

      const saved = versionSnapshot.data();

      if (
        !saved ||
        saved.ownerId !== uid ||
        saved.version !== version ||
        saved.periodId !== current.periodId ||
        saved.superiorId !== current.superiorId ||
        (saved.observationsFormatVersion ?? 0) !==
          (current.observationsFormatVersion ?? 0) ||
        fields.some(key =>
          !isDeepStrictEqual(
            saved[key],
            current[key]
          )
        )
      ) {
        deny(
          'failed-precondition',
          'La versión no coincide con la declaración. ' +
          'Abrí el borrador, corregí los datos y guardalo.'
        );
      }

      tx.update(ref, {
        status: 'VALIDADA',
        updatedAt: FieldValue.serverTimestamp(),
      });

      event(
        tx,
        ref,
        uid,
        'validate',
        version,
        'BORRADOR',
        'VALIDADA'
      );

      return {
        id,
        status: 'VALIDADA',
        ...totals,
      };
    });
  }

  // ==========================================================
  // CREAR NUEVA VERSIÓN
  // ==========================================================

  async function newVersion(request) {
    const uid = uidOf(request);
    const id = idOf(request.data?.id);
    const version = versionOf(request.data?.version);

    if (!Number.isSafeInteger(version + 1)) {
      deny(
        'invalid-argument',
        'Versión fuera de rango.'
      );
    }

    const ref = db
      .collection('declarations')
      .doc(id);

    return db.runTransaction(async tx => {
      const versionRef = ref
        .collection('versions')
        .doc(String(version + 1));

      const [
        snapshot,
        next,
        profileSnapshot,
      ] = await Promise.all([
        tx.get(ref),
        tx.get(versionRef),
        tx.get(
          db.collection('users').doc(uid)
        ),
      ]);

      const current = snapshot.data();

      checkOwner(
        current,
        uid,
        version,
        'DEVUELTA'
      );

      checkProfileIdentification(
        profileSnapshot.data(),
        current.identification
      );

      if (next.exists) {
        deny(
          'already-exists',
          'La nueva versión ya existe.'
        );
      }

      // Copia el contenido y su formato.
      // Las versiones históricas no se reescriben.
      const patch = {
        status: 'BORRADOR',
        version: version + 1,
        updatedAt: FieldValue.serverTimestamp(),
      };

      tx.update(ref, patch);

      tx.create(versionRef, {
        ...current,
        ...patch,
        createdAt: FieldValue.serverTimestamp(),
      });

      event(
        tx,
        ref,
        uid,
        'newVersion',
        version + 1,
        'DEVUELTA',
        'BORRADOR'
      );

      return {
        id,
        version: version + 1,
      };
    });
  }

  return {
    save,
    validateStored,
    newVersion,
    listSuperiors,
  };
}

module.exports = {
  createDeclarationHandlers,
};