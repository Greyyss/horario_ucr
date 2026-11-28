'use strict';

const {
  onCall,
  HttpsError,
} = require('firebase-functions/v2/https');

const {
  initializeApp,
} = require('firebase-admin/app');

const {
  getFirestore,
  FieldValue,
} = require('firebase-admin/firestore');

const {
  getStorage,
} = require('firebase-admin/storage');

const {
  createSignedPdfHandlers,
} = require('../../../functions/signed-pdf-handlers');

const PROJECT = 'demo-declara-firmas';

initializeApp({
  projectId: PROJECT,
  storageBucket: `${PROJECT}.appspot.com`,
});

function assertLocal() {
  const valid =
    process.env.FUNCTIONS_EMULATOR === 'true' &&
    process.env.GCLOUD_PROJECT === PROJECT &&
    process.env.FIRESTORE_EMULATOR_HOST === '127.0.0.1:8080' &&
    process.env.FIREBASE_AUTH_EMULATOR_HOST === '127.0.0.1:9099' &&
    process.env.FIREBASE_STORAGE_EMULATOR_HOST === '127.0.0.1:9199';

  if (!valid) {
    throw new HttpsError(
      'failed-precondition',
      'Las firmas de prueba funcionan únicamente ' +
      'en los emuladores locales del proyecto demo.'
    );
  }
}

let handlers;

function getHandlers() {
  assertLocal();

  if (handlers) return handlers;

  handlers = createSignedPdfHandlers({
    db: getFirestore(),
    bucket: getStorage().bucket(`${PROJECT}.appspot.com`),
    FieldValue,
    HttpsError,

    validator: async (endpoint, data) => {
      assertLocal();

      const response = await fetch(
        'http://127.0.0.1:8088' + endpoint,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(data),
          signal: AbortSignal.timeout(90000),
        }
      );

      const result = await response.json();

      if (!response.ok) {
        throw new HttpsError(
          response.status === 422
            ? 'invalid-argument'
            : 'unavailable',
          result.error || 'El verificador local rechazó el PDF.'
        );
      }

      return result;
    },
  });

  return handlers;
}

const options = {
  region: 'us-east1',
  timeoutSeconds: 120,
  memory: '1GiB',
  maxInstances: 1,
  concurrency: 1,
  enforceAppCheck: false,
};

const endpoints = {
  prepareSigningPdf: 'prepare',
  getSigningPdfStatus: 'status',
  downloadSigningPdf: 'download',
  uploadSignedPdf: 'upload',
  sendDigitallySignedDeclaration: 'send',
  acceptDeclarationAndSendHr: 'accept',
};

for (const [name, method] of Object.entries(endpoints)) {
  exports[name] = onCall(options, request => {
    assertLocal();
    return getHandlers()[method](request);
  });
}