'use strict';

const { randomUUID } = require('node:crypto');

const TEN_DAYS_MS = 10 * 24 * 60 * 60 * 1000;

function millis(value) {
  return value && typeof value.toMillis === 'function'
    ? value.toMillis()
    : NaN;
}

function state(profile, now = Date.now()) {
  if (!profile || profile.role === 'eliminando') {
    return 'unavailable';
  }

  if (profile.accessPolicy == null) return 'legacy';
  if (profile.accessPolicy !== 1) return 'unavailable';
  if (profile.accessState === 'active') return 'active';
  if (profile.accessState !== 'pending') return 'unavailable';

  const deadline = millis(profile.accessExpiresAt);
  const invited = millis(profile.accessInvitedAt);

  if (
    !Number.isFinite(deadline) ||
    !Number.isFinite(invited) ||
    deadline <= invited
  ) {
    return 'unavailable';
  }

  return now >= deadline ? 'expired' : 'pending';
}

function newAccessFields(now = Date.now()) {
  const { Timestamp } = require('firebase-admin/firestore');

  return {
    accessPolicy: 1,
    accessState: 'pending',
    accessGeneration: randomUUID(),
    accessInvitedAt: Timestamp.fromMillis(now),
    accessExpiresAt: Timestamp.fromMillis(now + TEN_DAYS_MS),
  };
}

function canActivate(profile, token, now = Date.now()) {
  return (
    state(profile, now) === 'pending' &&
    token?.firebase?.sign_in_provider === 'password' &&
    Number.isSafeInteger(token.auth_time) &&
    token.auth_time >=
      Math.floor(millis(profile.accessInvitedAt) / 1000) &&
    token.auth_time <= Math.floor(now / 1000)
  );
}

module.exports = {
  state,
  millis,
  newAccessFields,
  canActivate,
  TEN_DAYS_MS,
};
