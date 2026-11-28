'use strict';

const https = require('firebase-functions/v2/https');
const { getFirestore } = require('firebase-admin/firestore');
const { state } = require('./account-access-policy');

async function requireActive(request, allowMissingProfile = false) {
  // Cada handler conserva sus comprobaciones de autenticación y rol.
  if (!request.auth) return;

  const profile = await getFirestore()
    .collection('users')
    .doc(request.auth.uid)
    .get();

  if (!profile.exists && allowMissingProfile) return;

  const status = state(profile.data());

  if (!['active', 'legacy'].includes(status)) {
    throw new https.HttpsError(
      'failed-precondition',
      status === 'expired'
        ? 'La invitación venció. Solicitá a Administración que la renueve.'
        : 'Completá la activación de tu cuenta antes de continuar.',
      { accountAccess: status }
    );
  }
}

function wrap(allowMissingProfile) {
  return function onCall(options, handler) {
    if (typeof options === 'function') {
      handler = options;
      options = {};
    }

    return https.onCall(options, async (request, response) => {
      await requireActive(request, allowMissingProfile);
      return handler(request, response);
    });
  };
}

module.exports = {
  ...https,
  onCall: wrap(false),
  requireActive,
  wrap,
};
