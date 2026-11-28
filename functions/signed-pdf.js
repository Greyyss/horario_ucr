'use strict';

const {
  onCall,
  HttpsError,
} = require('firebase-functions/v2/https');

const {
  defineString,
} = require('firebase-functions/params');

const {
  getFirestore,
  FieldValue,
} = require('firebase-admin/firestore');

const {
  getStorage,
} = require('firebase-admin/storage');

const {
  GoogleAuth,
} = require('google-auth-library');

const {
  createSignedPdfHandlers,
} = require('./signed-pdf-handlers');

const validatorUrl = defineString(
  'SIGNATURE_VALIDATOR_URL'
);

const bucketName = defineString(
  'SIGNED_PDF_BUCKET'
);

const serviceAccount = defineString(
  'SIGNATURE_CALLER_SERVICE_ACCOUNT'
);

let handlers;

function getHandlers() {
  if (handlers) {
    return handlers;
  }

  handlers = createSignedPdfHandlers({
    db: getFirestore(),
    FieldValue,
    HttpsError,

    bucket: getStorage().bucket(
      bucketName.value()
    ),

    validator: async (path, data) => {
      const origin = validatorUrl
        .value()
        .replace(/\/$/, '');

      if (
        !/^https:\/\/[a-z0-9-]+\.a\.run\.app$/.test(origin)
      ) {
        throw new HttpsError(
          'failed-precondition',
          'La URL del verificador no es válida.'
        );
      }

      try {
        const client = await new GoogleAuth()
          .getIdTokenClient(origin);

        const response = await client.request({
          url: origin + path,
          method: 'POST',
          data,
          timeout: 90000,
        });

        return response.data;
      } catch (error) {
        const rejected =
          error.response?.status === 422;

        throw new HttpsError(
          rejected
            ? 'invalid-argument'
            : 'unavailable',
          rejected
            ? 'El PDF fue rechazado. Revisá las firmas, ' +
              'el archivo y las cédulas.'
            : 'No se pudo completar la verificación. ' +
              'Intentá de nuevo.'
        );
      }
    },
  });

  return handlers;
}

const options = {
  region: 'us-east1',
  timeoutSeconds: 120,
  memory: '1GiB',
  maxInstances: 2,
  concurrency: 1,
  serviceAccount,
  enforceAppCheck:
    process.env.FUNCTIONS_EMULATOR !== 'true',
};

exports.prepareSigningPdf = onCall(
  options,
  request => getHandlers().prepare(request)
);

exports.getSigningPdfStatus = onCall(
  options,
  request => getHandlers().status(request)
);

exports.downloadSigningPdf = onCall(
  options,
  request => getHandlers().download(request)
);

exports.uploadSignedPdf = onCall(
  options,
  request => getHandlers().upload(request)
);

exports.sendDigitallySignedDeclaration = onCall(
  options,
  request => getHandlers().send(request)
);

exports.acceptDeclarationAndSendHr = onCall(
  options,
  request => getHandlers().accept(request)
);