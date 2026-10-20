
const WebSocket = require('ws');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

initializeApp({
  projectId: 'declarahorario-ucr-cff7a'
});

const db = getFirestore();

const server = new WebSocket.Server({
  port: 8080
});

const clients = new Map();
const previousStatuses = new Map();

function sendToUser(userId, message) {
  if (typeof userId !== 'string' || userId.trim() === '') {
    console.log('No hay destinatario válido');
    return;
  }

  const connections = clients.get(userId);

  if (!connections || connections.size === 0) {
    console.log(
      'El destinatario no tiene una conexión WebSocket activa'
    );
    return;
  }

  let sent = 0;

  for (const client of connections) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(message));
      sent++;
    }
  }

  console.log('Notificaciones enviadas:', sent);
}

async function testFirestore() {
  try {
    const document = await db
      .collection('periods')
      .doc('2026-II')
      .get();

    if (document.exists) {
      console.log('Firestore conectado correctamente');
    } else {
      console.log(
        'Firestore conectado, pero no se encontró el período'
      );
    }
  } catch (error) {
    console.error(
      'Error al consultar Firestore:',
      error.message
    );
  }
}

function watchDeclarations() {
  db.collection('declarations').onSnapshot(
    (snapshot) => {
      for (const change of snapshot.docChanges()) {
        const declarationId = change.doc.id;

        if (change.type === 'removed') {
          previousStatuses.delete(declarationId);
          continue;
        }

        const declaration = change.doc.data();
        const status = declaration.status;

        const previousStatus = previousStatuses.get(declarationId);

        previousStatuses.set(declarationId, status);

        // No notificar documentos cargados inicialmente.
        if (change.type !== 'modified') {
          continue;
        }

        console.log(
          'Declaración modificada. Estado:',
          status
        );

        // Evitar notificaciones si el estado no cambió.
        if (
          previousStatus === undefined ||
          previousStatus === status
        ) {
          continue;
        }

        let recipientId = null;
        let notification = null;

        if (status === 'PENDIENTE_FIRMA_SUPERIOR') {
          recipientId = declaration.superiorId;
          notification =
            'Tenés una declaración pendiente de revisión';
        }

        if (status === 'DEVUELTA') {
          recipientId = declaration.ownerId;
          notification =
            'Una declaración fue devuelta para corrección';
        }

        if (recipientId && notification) {
          sendToUser(recipientId, {
            type: 'notification',
            message: notification
          });
        }
      }
    },
    (error) => {
      console.error(
        'Error al observar declaraciones:',
        error.message
      );
    }
  );
}

server.on('connection', (client) => {
  console.log(
    'Cliente conectado, esperando autenticación'
  );

  client.userId = null;

  client.on('message', async (data) => {
    try {
      const message = JSON.parse(data.toString());

      if (message.type === 'auth') {
        if (client.userId) {
          client.close(1008, 'Sesión ya autenticada');
          return;
        }

        if (typeof message.token !== 'string') {
          client.close(1008, 'Token requerido');
          return;
        }

        const decoded = await getAuth().verifyIdToken(
          message.token,
          true
        );

        if (client.readyState !== WebSocket.OPEN) {
          return;
        }

        client.userId = decoded.uid;

        if (!clients.has(client.userId)) {
          clients.set(client.userId, new Set());
        }

        clients.get(client.userId).add(client);

        client.send(JSON.stringify({
          type: 'authenticated',
          message: 'Usuario autenticado correctamente'
        }));

        client.send(JSON.stringify({
          type: 'ready',
          message: 'Notificaciones disponibles'
        }));

        console.log(
          'Usuario autenticado correctamente'
        );

        return;
      }

      if (!client.userId) {
        client.close(1008, 'Usuario no autenticado');
        return;
      }

      // Los clientes no pueden generar notificaciones.
      client.send(JSON.stringify({
        type: 'info',
        message: 'Conexión activa'
      }));

    } catch (error) {
      console.error(
        'Error de WebSocket:',
        error.message
      );

      if (client.readyState === WebSocket.OPEN) {
        client.close(1008, 'Solicitud inválida');
      }
    }
  });

  client.on('close', () => {
    if (client.userId) {
      const connections = clients.get(client.userId);

      if (connections) {
        connections.delete(client);

        if (connections.size === 0) {
          clients.delete(client.userId);
        }
      }
    }

    console.log('Cliente desconectado');
  });
});

server.on('error', (error) => {
  console.error(
    'Error del servidor WebSocket:',
    error.message
  );
});

server.on('listening', () => {
  console.log(
    'Servidor WebSocket ejecutándose en puerto 8080'
  );

  testFirestore();
  watchDeclarations();
});
