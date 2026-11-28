'use strict';

const { wrap, ...https } = require('./activation-https');

// Permite completar el registro antes de que exista un perfil.
// Si ya existe y está pendiente o vencido, se bloquea.
module.exports = {
  ...https,
  onCall: wrap(true),
};
