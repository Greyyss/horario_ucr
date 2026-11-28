'use strict';

const nodemailer = require('nodemailer');

let input = '';

process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => input += chunk);

process.stdin.on('end', async () => {
  let config;

  try {
    config = JSON.parse(
      input.replace(/^\uFEFF/, '').trim()
    );
  } catch {
    input = '';
    console.error(
      'No se pudo leer la configuración. No se imprimió el secreto.'
    );
    process.exitCode = 1;
    return;
  }

  input = '';

  let transport;

  try {
    const port = Number(config.port || 587);

    if (
      !config.host ||
      !config.user ||
      !config.password ||
      !config.from ||
      ![465, 587].includes(port)
    ) {
      throw Object.assign(
        new Error('Configuración incompleta.'),
        { code: 'CONFIG' }
      );
    }

    transport = nodemailer.createTransport({
      host: config.host,
      port,
      secure: port === 465,
      requireTLS: port === 587,
      auth: {
        user: config.user,
        pass: config.password,
      },
      connectionTimeout: 15000,
      greetingTimeout: 15000,
      socketTimeout: 30000,
      tls: {
        minVersion: 'TLSv1.2',
      },
      logger: false,
      debug: false,
    });

    await transport.verify();

    console.log(JSON.stringify({
      conexionYAutenticacion: 'CORRECTAS',
      servidor: config.host,
      remitente: config.from,
      redireccionDePruebas: config.testRecipient || null,
      mensaje: 'No se enviaron correos.'
    }, null, 2));
  } catch (error) {
    const code = String(error.code || 'SMTP_ERROR')
      .replace(/[^A-Za-z0-9_-]/g, '')
      .slice(0, 40);

    console.error(JSON.stringify({
      resultado: 'FALLO',
      codigo: code,
      respuestaSMTP: Number.isInteger(error.responseCode)
        ? error.responseCode
        : null,
      mensaje: code === 'EAUTH'
        ? 'Gmail rechazó la autenticación.'
        : 'No se completó la comprobación SMTP.'
    }, null, 2));

    process.exitCode = 1;
  } finally {
    transport?.close();
    config.password = '';
  }
});
