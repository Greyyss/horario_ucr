'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const publisherPath = path.resolve(
  'functions/publicar-nombramiento.js'
);

const workerPath = path.resolve(
  'functions/declaration-mail.js'
);

const originalPublisher = fs.readFileSync(
  publisherPath,
  'utf8'
);

const originalWorker = fs.readFileSync(
  workerPath,
  'utf8'
);

let publisher = originalPublisher;
let worker = originalWorker;

if (
  publisher.includes('// MAIL_HANDOFF_POLICY_V2') ||
  worker.includes('// MAIL_HANDOFF_POLICY_V2')
) {
  throw Error(
    'El actualizador ya fue aplicado o quedó parcialmente aplicado. ' +
    'No se guardó nada.'
  );
}

const start = publisher.indexOf('    const emails = [');

const tailPattern =
  /\r?\n  \}\);\r?\n\s*return \{ id \};/g;

const tails = [...publisher.matchAll(tailPattern)];

if (start < 0 || tails.length !== 1 || tails[0].index <= start) {
  throw Error(
    'El bloque de correos del nombramiento es diferente. ' +
    'No se guardó nada.'
  );
}

const replacement = `    // MAIL_HANDOFF_POLICY_V2
    const {
      email,
      message,
      appointmentDetails,
    } = require('./mail-helpers');

    const details = appointmentDetails({
      workplace: 'Universidad de Costa Rica',
      unit: declarant.get('unit') || '',
      position,
      expectedHours,
      startDate,
      endDate,
      workloadFraction:
        fractions[expectedHours] || workloadFraction || '',
      blocks: checked.map(({ from, to, ...block }) => block),
    });

    const recipients = [
      {
        user: declarant,
        suffix: 'declarante',
        type: 'NOMBRAMIENTO_DECLARANTE',
        role: 'declarante',
      },
      {
        user: superior,
        suffix: 'superior',
        type: 'COPIA_SUPERIOR',
        role: 'superior',
      },
    ];

    for (const recipient of recipients) {
      const to = String(
        recipient.user.get('email') || ''
      ).trim();

      if (!email(to)) continue;

      tx.create(
        db.collection('_declarationMailOutbox')
          .doc(id + '-' + recipient.suffix),
        {
          ...message(recipient.type, {
            name: recipient.user.get('name'),
            ownerName: declarant.get('name'),
            superiorName: superior.get('name'),
            period: periodName,
            reference: id,
            details,
          }),
          to,
          recipientUid: recipient.user.id,
          expectedRole: recipient.role,
          appointmentId: id,
          status: 'pending',
          createdAt,
        }
      );
    }`;

publisher =
  publisher.slice(0, start) +
  replacement +
  publisher.slice(tails[0].index);

const importPattern =
  /const \{ email \} = require\('\.\/mail-helpers'\);/;

if (!importPattern.test(worker)) {
  throw Error(
    'No se encontró el import esperado del procesador SMTP. ' +
    'No se guardó nada.'
  );
}

worker = worker.replace(
  importPattern,
  "const { email, MAIL_TYPES } = require('./mail-helpers');"
);

const dataPattern = /const data = current\.data\(\);/g;

if ([...worker.matchAll(dataPattern)].length !== 1) {
  throw Error(
    'No se encontró un único bloque de lectura del correo. ' +
    'No se guardó nada.'
  );
}

worker = worker.replace(
  dataPattern,
  `const data = current.data();

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
    }`
);

const recipientPattern =
  /recipient\.exists &&\s*String\(recipient\.get\('email'\) \|\| ''\)/;

if (!recipientPattern.test(worker)) {
  throw Error(
    'No se encontró la validación esperada del destinatario. ' +
    'No se guardó nada.'
  );
}

worker = worker.replace(
  recipientPattern,
  `recipient.exists &&
        recipient.get('role') === data.expectedRole &&
        String(recipient.get('email') || '')`
);

const backup = fs.mkdtempSync(
  path.join(os.tmpdir(), 'declara-correos-')
);

fs.writeFileSync(
  path.join(backup, 'publicar-nombramiento.js'),
  originalPublisher
);

fs.writeFileSync(
  path.join(backup, 'declaration-mail.js'),
  originalWorker
);

fs.writeFileSync(publisherPath, publisher);
fs.writeFileSync(workerPath, worker);

console.log('Correos de cambios de manos actualizados.');
console.log('Respaldo: ' + backup);
console.log('Todavía no se desplegaron.');