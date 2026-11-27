'use strict';

const actions = {
  CREADA: 'Creación de declaración',
  MODIFICADA: 'Actualización de borrador',
  validate: 'Declaración validada',
  submit: 'Declaración lista para firma',
  signOwner: 'Firma interna del declarante registrada',
  route: 'Declaración remitida al superior',
  signSuperior: 'Firma interna del superior registrada',
  return: 'Declaración devuelta para corrección',
  sendHr: 'Declaración enviada a Recursos Humanos',
  receive: 'Declaración recibida por Recursos Humanos',
  finish: 'Trámite de declaración finalizado',
  newVersion: 'Nueva versión para corrección',
  annul: 'Declaración anulada',
};

const email = value =>
  typeof value === 'string' &&
  value.length <= 254 &&
  /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(value);

function notice(event, declaration, name, id) {
  let title = actions[event.event];
  if (!title) return null;

  if (
    event.event === 'signSuperior' &&
    event.newStatus === 'ENVIADA_A_RRHH'
  ) {
    title = 'Declaración aceptada y enviada a Recursos Humanos';
  }

  const reason = event.event === 'return'
    ? String(event.observation || '').trim().slice(0, 500)
    : '';

  return {
    subject: 'DeclaraUCR | ' + title,
    text:
      'Estimado/a ' + (name || 'usuario/a') + ':\n\n' +
      'Se le informa que se ha registrado la siguiente acción: ' +
      title + '.\n\n' +
      'Persona declarante: ' +
      (declaration.ownerName || 'Sin nombre registrado') + '\n' +
      'Período: ' + (declaration.periodId || 'Sin período') + '\n' +
      'Referencia: ' + id + '\n' +
      'Versión: ' + event.version + '\n' +
      (reason ? '\nMotivo de devolución: ' + reason + '\n' : '') +
      '\nIngrese a DeclaraUCR para consultar el detalle y continuar ' +
      'con el trámite que corresponda.\n\n' +
      'Atentamente,\nDeclaraUCR\n' +
      'Sistema de Declaración Jurada de Horarios\n\n' +
      'Este mensaje fue generado automáticamente. ' +
      'No responda a este correo.',
  };
}

module.exports = { actions, email, notice };
