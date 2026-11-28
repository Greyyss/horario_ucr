'use strict';

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { defineJsonSecret } = require('firebase-functions/params');
const {
  getFirestore, FieldValue, Timestamp,
} = require('firebase-admin/firestore');
const { randomUUID, createHash } = require('node:crypto');
const nodemailer = require('nodemailer');
const { email, MAIL_TYPES } = require('./mail-helpers');

const smtp = defineJsonSecret('DECLARA_SMTP');

exports.deliverDeclarationMail = onDocumentCreated({
  document: '_declarationMailOutbox/{id}',
  region: 'us-east1',
  maxInstances: 2,
  concurrency: 1,
  timeoutSeconds: 120,
  retry: true,
  secrets: [smtp],
}, async event => {
  if (!event.data) return;

  const db = getFirestore();
  const ref = event.data.ref;
  const lease = randomUUID();

  const mail = await db.runTransaction(async tx => {
    const current = await tx.get(ref);

    if (
      !current.exists ||
      ['sent', 'failed', 'cancelled', 'unknown']
        .includes(current.get('status'))
    ) return null;

    if (current.get('leaseUntil')?.toMillis() > Date.now()) {
      throw Error('Envío en proceso.');
    }

    if (current.get('status') === 'processing') {
      tx.update(ref, {
        status: 'unknown',
        errorCode: 'EXPIRED_LEASE',
        updatedAt: FieldValue.serverTimestamp(),
      });
      return null;
    }

    const data = current.data();

    // MAIL_HANDOFF_POLICY_V2
    if (
      data.mailPolicyVersion !== 2 ||
      !MAIL_TYPES.includes(data.mailType) ||
      !data.recipientUid ||
      !data.expectedRole
    ) {
      tx.update(ref, {
        status: 'cancelled',
        errorCode: 'OLD_MAIL_POLICY',
        updatedAt: FieldValue.serverTimestamp(),
      });
      return null;
    }

    if (
      !email(data.to) ||
      typeof data.subject !== 'string' ||
      data.subject.length > 200 ||
      /[\r\n]/.test(data.subject) ||
      typeof data.text !== 'string' ||
      data.text.length > 12000
    ) {
      tx.update(ref, {
        status: 'failed',
        errorCode: 'INVALID_MESSAGE',
      });
      return null;
    }

    const recipient = data.recipientUid
      ? await tx.get(db.collection('users').doc(data.recipientUid))
      : await tx.get(
          db.collection('users')
            .where('email', '==', data.to)
            .limit(1)
        );

    const validRecipient = data.recipientUid
      ? recipient.exists &&
        recipient.get('role') === data.expectedRole &&
        String(recipient.get('email') || '').trim().toLowerCase() ===
          data.to.toLowerCase()
      : !recipient.empty;

    if (
      data.mailType === 'BIENVENIDA_USUARIO' &&
      recipient.get('accessPolicy') === 1 &&
      (
        data.accessGeneration !== recipient.get('accessGeneration') ||
        recipient.get('accessState') !== 'pending' ||
        !(recipient.get('accessExpiresAt')?.toMillis() > Date.now())
      )
    ) {
      tx.update(ref, {
        status: 'cancelled',
        errorCode: 'INVITATION_SUPERSEDED_OR_EXPIRED',
        updatedAt: FieldValue.serverTimestamp(),
      });
      return null;
    }

    if (!validRecipient) {
      tx.update(ref, {
        status: 'cancelled',
        errorCode: 'RECIPIENT_UNAVAILABLE',
      });
      return null;
    }

    const attempts = (data.attempts || 0) + 1;

    if (attempts > 5) {
      tx.update(ref, {
        status: 'failed',
        errorCode: 'MAX_ATTEMPTS',
      });
      return null;
    }

    tx.update(ref, {
      status: 'processing',
      attempts,
      lease,
      leaseUntil: Timestamp.fromMillis(Date.now() + 180000),
    });

    return { ...data, attempts };
  });

  if (!mail) return;

  let transport;
  let accepted = false;

  try {
    const config = smtp.value();

    if (
      typeof config.host !== 'string' ||
      !email(config.from) ||
      !config.user ||
      !config.password ||
      (config.testRecipient && !email(config.testRecipient))
    ) {
      throw Object.assign(
        Error('Configuración SMTP inválida.'),
        { code: 'CONFIG' }
      );
    }

    const port = Number(config.port || 587);

    if (![465, 587].includes(port)) {
      throw Object.assign(
        Error('Puerto SMTP inválido.'),
        { code: 'CONFIG' }
      );
    }

    transport = nodemailer.createTransport({
      host: config.host,
      port,
      secure: port === 465,
      requireTLS: port !== 465,
      auth: {
        user: config.user,
        pass: config.password,
      },
      connectionTimeout: 15000,
      greetingTimeout: 15000,
      socketTimeout: 30000,
      tls: { minVersion: 'TLSv1.2' },
    });

    const id = createHash('sha256')
      .update(event.params.id)
      .digest('hex');

    const result = await transport.sendMail({
      from: { name: 'DeclaraUCR', address: config.from },
      to: config.testRecipient || mail.to,
      subject: mail.subject,
      text:
        (config.testRecipient
          ? '[PRUEBA: destinatario original ' + mail.to + ']\n\n'
          : '') + mail.text,
      messageId:
        '<' + id + '@' + config.from.split('@')[1] + '>',
      disableFileAccess: true,
      disableUrlAccess: true,
    });

    if (!result.accepted?.length) {
      throw Object.assign(
        Error('Destinatario rechazado.'),
        { responseCode: 550 }
      );
    }

    accepted = true;

    await ref.update({
      status: 'sent',
      sentAt: FieldValue.serverTimestamp(),
      testMode: Boolean(config.testRecipient),
      messageId: result.messageId,
      lease: FieldValue.delete(),
      leaseUntil: FieldValue.delete(),
    });
  } catch (error) {
    const retry =
      !accepted &&
      error.code !== 'CONFIG' &&
      !(error.responseCode >= 500) &&
      mail.attempts < 5;

    await db.runTransaction(async tx => {
      const current = await tx.get(ref);

      if (current.get('lease') !== lease) return;

      tx.update(ref, {
        status: accepted ? 'unknown' : retry ? 'retrying' : 'failed',
        errorCode: accepted
          ? 'SMTP_ACCEPTED_SAVE_FAILED'
          : String(
              error.code || error.responseCode || 'SMTP_ERROR'
            ).slice(0, 50),
        updatedAt: FieldValue.serverTimestamp(),
        lease: FieldValue.delete(),
        leaseUntil: FieldValue.delete(),
      });
    });

    if (retry) {
      throw Error('Fallo temporal de correo; se reintentará.');
    }
  } finally {
    transport?.close();
  }
});
