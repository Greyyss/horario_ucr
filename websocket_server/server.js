'use strict';

const http = require('node:http');
const WebSocket = require('ws');

const {
  initializeApp,
  getApps,
} = require('firebase-admin/app');

const { getAuth } = require('firebase-admin/auth');

const {
  getFirestore,
  FieldValue,
} = require('firebase-admin/firestore');

function createNotificationServer({
  db,
  auth,
  port = Number(process.env.PORT || 8080),
  host = '0.0.0.0',
  authTimeoutMs = 10000,
  heartbeatMs = 30000,
}) {
  const httpServer = http.createServer((request, response) => {
    response.writeHead(200, {
      'Content-Type': 'application/json',
    });

    response.end(JSON.stringify({
      service: 'DeclaraHorario notifications',
      status: 'ok',
    }));
  });

  const server = new WebSocket.Server({
    server: httpServer,
    maxPayload: 16 * 1024,
    perMessageDeflate: false,
  });

  // Enviar únicamente si la conexión sigue abierta.
  function send(client, message) {
    if (client.readyState !== WebSocket.OPEN) return;

    client.send(JSON.stringify(message), error => {
      if (error) client.terminate();
    });
  }

  function dateText(value) {
    if (!value || typeof value.toDate !== 'function') {
      return null;
    }

    return value.toDate().toISOString();
  }

  // Campos que recibe Flutter.
  function notificationData(document) {
    const data = document.data();

    return {
      id: document.id,
      title: typeof data.title === 'string'
        ? data.title
        : 'Notificación',
      message: typeof data.message === 'string'
        ? data.message
        : '',
      declarationId: typeof data.declarationId === 'string'
        ? data.declarationId
        : '',
      version: Number.isSafeInteger(data.version)
        ? data.version
        : null,
      status: typeof data.status === 'string'
        ? data.status
        : '',
      createdAt: dateText(data.createdAt),
      read: data.read === true,
      readAt: dateText(data.readAt),
    };
  }

  server.on('connection', client => {
    client.userId = null;
    client.isAlive = true;

    let authenticating = false;
    let unsubscribe = null;
    let expirationTimer = null;

    // No permitir conexiones sin autenticar indefinidamente.
    const authTimer = setTimeout(() => {
      client.close(1008, 'Autenticación requerida');
    }, authTimeoutMs);

    authTimer.unref?.();

    client.on('pong', () => {
      client.isAlive = true;
    });

    client.on('message', async (raw, isBinary) => {
      try {
        if (isBinary) {
          throw new Error('Se requiere un mensaje JSON');
        }

        const message = JSON.parse(raw.toString());

        if (
          !message ||
          typeof message !== 'object' ||
          Array.isArray(message)
        ) {
          throw new Error('Mensaje inválido');
        }

        // ==================================================
        // AUTENTICACIÓN
        // ==================================================

        if (message.type === 'auth') {
          if (client.userId || authenticating) {
            client.close(
              1008,
              'La autenticación ya comenzó'
            );
            return;
          }

          if (
            typeof message.token !== 'string' ||
            !message.token
          ) {
            client.close(1008, 'Token requerido');
            return;
          }

          authenticating = true;

          const decoded = await auth.verifyIdToken(
            message.token,
            true
          );

          if (client.readyState !== WebSocket.OPEN) {
            return;
          }

          if (
            typeof decoded.uid !== 'string' ||
            !decoded.uid ||
            decoded.uid.includes('/') ||
            !Number.isFinite(decoded.exp) ||
            decoded.exp * 1000 <= Date.now()
          ) {
            throw new Error('Sesión inválida');
          }

          client.userId = decoded.uid;
          clearTimeout(authTimer);

          // Flutter deberá reconectar con un token vigente.
          expirationTimer = setTimeout(() => {
            client.close(4001, 'Renová la sesión');
          }, Math.min(
            decoded.exp * 1000 - Date.now(),
            2147483647
          ));

          expirationTimer.unref?.();

          send(client, {
            type: 'authenticated',
            message: 'Usuario autenticado correctamente',
          });

          // Cada conexión consulta exclusivamente
          // la bandeja de su usuario autenticado.
          let firstSnapshot = true;

          unsubscribe = db
            .collection('users')
            .doc(client.userId)
            .collection('notifications')
            .orderBy('createdAt', 'desc')
            .limit(100)
            .onSnapshot(
              snapshot => {
                // Recuperar y sincronizar los últimos 100 avisos.
                send(client, {
                  type: 'notifications_sync',
                  notifications: snapshot.docs.map(
                    notificationData
                  ),
                });

                // Los avisos recuperados al conectar no generan
                // una alerta emergente por cada documento.
                if (firstSnapshot) {
                  firstSnapshot = false;

                  send(client, {
                    type: 'ready',
                    message:
                      'Bandeja de notificaciones sincronizada',
                  });

                  return;
                }

                // Avisar cuando aparece una notificación nueva.
                for (const change of snapshot.docChanges()) {
                  if (
                    change.type === 'added' &&
                    change.doc.data().read !== true
                  ) {
                    send(client, {
                      type: 'notification',
                      ...notificationData(change.doc),
                    });
                  }
                }
              },
              error => {
                console.error(
                  'Error de lectura de notificaciones:',
                  error.code || 'desconocido'
                );

                send(client, {
                  type: 'error',
                  message:
                    'No se pudo cargar la bandeja de notificaciones.',
                });

                client.close(
                  1011,
                  'No se pudo sincronizar la bandeja'
                );
              }
            );

          return;
        }

        if (!client.userId) {
          client.close(1008, 'Usuario no autenticado');
          return;
        }

        const inbox = db
          .collection('users')
          .doc(client.userId)
          .collection('notifications');

        // ==================================================
        // MARCAR UNA NOTIFICACIÓN COMO LEÍDA
        // ==================================================

        if (message.type === 'mark_read') {
          if (
            typeof message.id !== 'string' ||
            !/^[A-Za-z0-9_-]{1,200}$/.test(message.id)
          ) {
            send(client, {
              type: 'error',
              message:
                'Identificador de notificación inválido.',
            });
            return;
          }

          const reference = inbox.doc(message.id);

          const found = await db.runTransaction(
            async transaction => {
              const document = await transaction.get(
                reference
              );

              if (!document.exists) return false;

              if (document.data().read !== true) {
                transaction.update(reference, {
                  read: true,
                  readAt: FieldValue.serverTimestamp(),
                });
              }

              return true;
            }
          );

          if (found) {
            send(client, {
              type: 'read_confirmed',
              id: message.id,
            });
          } else {
            send(client, {
              type: 'error',
              message:
                'La notificación no existe en tu bandeja.',
            });
          }

          return;
        }

        // ==================================================
        // MARCAR TODAS COMO LEÍDAS
        // ==================================================

        if (message.type === 'mark_all_read') {
          const unread = await inbox
            .where('read', '==', false)
            .get();

          for (
            let index = 0;
            index < unread.docs.length;
            index += 450
          ) {
            const batch = db.batch();

            const documents = unread.docs.slice(
              index,
              index + 450
            );

            for (const document of documents) {
              batch.update(document.ref, {
                read: true,
                readAt: FieldValue.serverTimestamp(),
              });
            }

            await batch.commit();
          }

          send(client, {
            type: 'all_read_confirmed',
            count: unread.size,
          });

          return;
        }

        if (message.type === 'ping') {
          send(client, { type: 'pong' });
          return;
        }

        // El cliente no puede crear avisos ni elegir
        // a otro usuario como destinatario.
        send(client, {
          type: 'error',
          message: 'Acción no permitida.',
        });
      } catch (error) {
       console.error(
  'Error de WebSocket:',
  error.code || error.name,
  error.message
);

        if (!client.userId) {
          client.close(
            1008,
            'No se pudo autenticar la conexión'
          );
        } else {
          send(client, {
            type: 'error',
            message:
              'No se pudo completar la operación.',
          });
        }
      }
    });

    client.on('error', error => {
      console.error(
        'Error de conexión WebSocket:',
        error.code || 'desconocido'
      );
    });

    client.on('close', () => {
      clearTimeout(authTimer);
      clearTimeout(expirationTimer);

      if (unsubscribe) {
        unsubscribe();
      }
    });
  });

  // Detectar conexiones interrumpidas.
  const heartbeat = setInterval(() => {
    for (const client of server.clients) {
      if (!client.isAlive) {
        client.terminate();
        continue;
      }

      client.isAlive = false;
      client.ping();
    }
  }, heartbeatMs);

  heartbeat.unref?.();

  server.on('error', error => {
    console.error(
      'Error del servidor WebSocket:',
      error.code || error.message
    );
  });

  httpServer.on('error', error => {
    console.error(
      'Error del servidor HTTP:',
      error.code || error.message
    );
  });

  httpServer.listen(port, host, () => {
    console.log(
      'Servidor de notificaciones en puerto',
      httpServer.address().port
    );
  });

  async function close() {
    clearInterval(heartbeat);

    for (const client of server.clients) {
      client.terminate();
    }

    await new Promise(resolve => {
      server.close(resolve);
    });

    await new Promise(resolve => {
      httpServer.close(resolve);
    });
  }

  return {
    httpServer,
    server,
    close,
  };
}

// Arranque al ejecutar este archivo con Node.
if (require.main === module) {
  if (!getApps().length) {
    initializeApp({
      projectId: 'declarahorario-ucr-cff7a',
    });
  }

  const app = createNotificationServer({
    db: getFirestore(),
    auth: getAuth(),
  });

  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.once(signal, () => {
      app.close()
        .then(() => process.exit(0))
        .catch(() => process.exit(1));
    });
  }
}

module.exports = {
  createNotificationServer,
};