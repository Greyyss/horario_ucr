'use strict';

const {
  onDocumentUpdated,
} = require('firebase-functions/v2/firestore');

const {
  getFirestore,
  Timestamp,
} = require('firebase-admin/firestore');

const { createHash } = require('node:crypto');

exports.createDeclarationNotifications = onDocumentUpdated(
  {
    document: 'declarations/{declarationId}',
    region: 'us-east1',
    timeoutSeconds: 120,
    maxInstances: 2,
    retry: true,
  },
  async event => {
    if (!event.data) return;

    const before = event.data.before.data();
    const after = event.data.after.data();

    // Solo notificar cambios de estado.
    if (
      !before ||
      !after ||
      before.status === after.status
    ) {
      return;
    }

    if (
      !Number.isSafeInteger(after.version) ||
      after.version < 1
    ) {
      return;
    }

    const db = getFirestore();
    const recipients = new Map();

    let staffNotice = null;

    function add(
      uid,
      title,
      message,
      staffOnly = false
    ) {
      if (
        typeof uid !== 'string' ||
        !uid ||
        uid.includes('/')
      ) {
        return;
      }

      recipients.set(uid, {
        title,
        message,
        staffOnly,
      });
    }

    switch (after.status) {
      case 'PENDIENTE_FIRMA_SUPERIOR':
        add(
          after.superiorId,
          'Declaración pendiente de revisión',
          'Tenés una declaración pendiente de revisión y firma.'
        );
        break;

      case 'DEVUELTA': {
        const reason =
          typeof after.returnNote === 'string'
            ? after.returnNote.trim().slice(0, 500)
            : '';

        add(
          after.ownerId,
          'Declaración devuelta',
          'Tu declaración fue devuelta para corrección.' +
            (reason ? ` Motivo: ${reason}` : '')
        );
        break;
      }

            case 'FIRMADA_POR_SUPERIOR':
        add(
          after.ownerId,
          'Firma del superior registrada',
          'Tu superior firmó la declaración. Está pendiente del envío a RRHH.'
        );
        break;

      case 'ENVIADA_A_RRHH':
        add(
          after.ownerId,
          'Declaración enviada a RRHH',
          'Tu declaración fue enviada a Recursos Humanos.'
        );

        staffNotice = {
          title: 'Declaración pendiente de recepción',
          message:
            'Hay una declaración enviada a RRHH pendiente de recepción.',
        };
        break;

      case 'RECIBIDA_RRHH':
        add(
          after.ownerId,
          'Declaración recibida por RRHH',
          'Recursos Humanos recibió tu declaración.'
        );
        break;

      case 'FINALIZADA':
        add(
          after.ownerId,
          'Declaración finalizada',
          'El trámite de tu declaración fue finalizado.'
        );
        break;

      default:
        return;
    }

    // Administración y RRHH intervienen en estos trámites
    // según los permisos actuales del proyecto.
    if (staffNotice) {
      const staff = await db
        .collection('users')
        .where('role', '==', 'rrhh')
        .get();

      for (const user of staff.docs) {
        // Si también es declarante, conserva su aviso personal.
        if (!recipients.has(user.id)) {
          add(
            user.id,
            staffNotice.title,
            staffNotice.message,
            true
          );
        }
      }
    }

    // Cada evento tiene un identificador estable.
    // Reintentar su procesamiento no crea avisos duplicados.
    const notificationId = createHash('sha256')
      .update(event.id)
      .digest('hex');

    const createdAt =
      event.data.after.updateTime ||
      Timestamp.fromDate(new Date(event.time));

    const entries = [...recipients.entries()];

    // Procesar grupos pequeños de destinatarios.
    for (
      let offset = 0;
      offset < entries.length;
      offset += 20
    ) {
      await Promise.all(
        entries.slice(offset, offset + 20).map(
          ([uid, notice]) =>
            db.runTransaction(async transaction => {
              const userRef = db
                .collection('users')
                .doc(uid);

              const notificationRef = userRef
                .collection('notifications')
                .doc(notificationId);

              const [user, existing] = await Promise.all([
                transaction.get(userRef),
                transaction.get(notificationRef),
              ]);

              // No crear bandejas de usuarios inexistentes
              // ni sobrescribir avisos ya guardados.
              if (!user.exists || existing.exists) {
                return;
              }

              // Comprobar nuevamente el rol del destinatario
              // antes de guardar un aviso de trámite.
                        if (
            notice.staffOnly &&
            user.data().role !== 'rrhh'
          ) {
            return;
          }

              transaction.create(notificationRef, {
                title: notice.title,
                message: notice.message,
                declarationId: event.params.declarationId,
                version: after.version,
                status: after.status,
                createdAt,
                read: false,
                readAt: null,
              });
            })
        )
      );
    }
  }
);