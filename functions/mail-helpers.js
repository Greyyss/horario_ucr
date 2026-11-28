'use strict';

const MAIL_TYPES = Object.freeze([
  'NOMBRAMIENTO_DECLARANTE',
  'COPIA_SUPERIOR',
  'DECLARACION_SUPERIOR',
  'DEVOLUCION_DECLARANTE',
  'DECLARACION_RRHH',
  'ENVIO_RRHH_DECLARANTE',
]);

const email = value =>
  typeof value === 'string' &&
  value.length <= 254 &&
  /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(value);

function applicationUrl() {
  const value =
    process.env.DECLARA_APP_URL ||
    'https://declarahorario-ucr-cff7a.web.app';

  const url = new URL(value);

  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password
  ) {
    throw Error('DECLARA_APP_URL debe ser una dirección HTTPS.');
  }

  return url.toString();
}

function appointmentDetails(appointment) {
  const days = [
    '',
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
  ];

  return [
    `Institución: ${
      appointment.workplace || 'Universidad de Costa Rica'
    }`,
    `Unidad: ${appointment.unit || 'Sin unidad registrada'}`,
    `Cargo o categoría: ${appointment.position}`,
    `Jornada: ${appointment.workloadFraction || ''} ` +
      `(${appointment.expectedHours} horas semanales)`,
    `Vigencia: ${appointment.startDate} a ${appointment.endDate}`,
    'Horario asignado:',
    ...(appointment.blocks || []).map(block =>
      [
        days[block.day] || 'Día sin especificar',
        `${block.start} a ${block.end}`,
        block.courseCode,
        block.activityName || block.activityType,
      ]
        .filter(Boolean)
        .join(' | ')
    ),
  ].join('\n');
}

function message(type, data) {
  if (!MAIL_TYPES.includes(type)) {
    throw Error('Tipo de correo no permitido.');
  }

  const owner = data.ownerName || 'la persona declarante';

  const titles = {
    NOMBRAMIENTO_DECLARANTE:
      'Nuevo nombramiento pendiente de completar',
    COPIA_SUPERIOR:
      'Copia del nombramiento remitido',
    DECLARACION_SUPERIOR:
      'Declaración firmada pendiente de revisión',
    DEVOLUCION_DECLARANTE:
      'Declaración devuelta para corrección',
    DECLARACION_RRHH:
      'Nueva declaración para trámite',
    ENVIO_RRHH_DECLARANTE:
      'Declaración enviada a Recursos Humanos',
  };

  const bodies = {
    NOMBRAMIENTO_DECLARANTE:
      `Su superior, ${data.superiorName || 'el superior asignado'}, ` +
      'le ha remitido un nuevo nombramiento. Ingrese a DeclaraUCR ' +
      'para revisarlo y completar la declaración que corresponda.',

    COPIA_SUPERIOR:
      `Se confirma el envío del nombramiento a ${owner}. ` +
      'A continuación encontrará una copia de los datos remitidos.',

    DECLARACION_SUPERIOR:
      `${owner} ha completado y enviado su declaración con la firma ` +
      'digital del PDF verificada. Ingrese a DeclaraUCR para revisar ' +
      'el documento y continuar con su firma o devolverlo con observaciones.',

    DEVOLUCION_DECLARANTE:
      'Su superior ha devuelto la declaración para que realice las ' +
      'correcciones indicadas. Ingrese a DeclaraUCR, revise el motivo ' +
      'y prepare una nueva versión. La nueva versión requerirá ' +
      'nuevamente las firmas correspondientes.',

    DECLARACION_RRHH:
      `Se ha remitido a Recursos Humanos la declaración de ${owner}, ` +
      'aceptada por su superior y con ambas firmas digitales del PDF ' +
      'verificadas. Ingrese a DeclaraUCR para revisar el documento ' +
      'y continuar con el trámite.',

    ENVIO_RRHH_DECLARANTE:
      'Su superior ha aceptado la declaración y la ha enviado a ' +
      'Recursos Humanos con ambas firmas digitales del PDF verificadas. ' +
      'Puede consultar el estado del trámite en DeclaraUCR.',
  };

  const lines = [
    `Estimado/a ${data.name || 'usuario/a'}:`,
    '',
    bodies[type],
    '',
    `Persona declarante: ${owner}`,
    `Período: ${data.period || 'Sin período'}`,
    `Referencia: ${data.reference}`,
  ];

  if (data.version != null) {
    lines.push(`Versión: ${data.version}`);
  }

  if (data.reason) {
    lines.push(
      '',
      'Motivo de devolución:',
      String(data.reason).trim().slice(0, 2000)
    );
  }

  if (data.details) {
    lines.push(
      '',
      'Datos del nombramiento:',
      data.details
    );
  }

  lines.push(
    '',
    'Acceda a la aplicación:',
    applicationUrl(),
    '',
    'Atentamente,',
    'DeclaraUCR',
    'Sistema de Declaración Jurada de Horarios',
    '',
    'Este mensaje fue generado automáticamente. ' +
      'No responda a este correo.'
  );

  return {
    mailPolicyVersion: 2,
    mailType: type,
    subject: 'DeclaraUCR | ' + titles[type],
    text: lines.join('\n'),
  };
}

module.exports = {
  MAIL_TYPES,
  email,
  message,
  appointmentDetails,
};