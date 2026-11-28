'use strict';

const {
  onDocumentCreated,
  onDocumentUpdated,
} = require('firebase-functions/v2/firestore');

const { getAuth } = require('firebase-admin/auth');

const {
  getFirestore,
  FieldValue,
} = require('firebase-admin/firestore');

const { createHash } = require('node:crypto');
const { email } = require('./mail-helpers');
const { state } = require('./account-access-policy');

const roles = Object.freeze({
  declarante: 'Declarante',
  superior: 'Superior',
  rrhh: 'Recursos Humanos',
  admin: 'Administrador',
});

async function queueWelcome(snapshot) {
  if (!snapshot?.exists) return;

  const source = snapshot.data();
  const uid = snapshot.id;

  if (
    source.identitySource !== 'padron' ||
    typeof source.createdBy !== 'string' ||
    !source.createdBy ||
    !Object.hasOwn(roles, source.role)
  ) {
    return;
  }

  if (
    source.accessPolicy != null &&
    state(source) !== 'pending'
  ) {
    return;
  }

  const db = getFirestore();

  const id = createHash('sha256')
    .update(
      'welcome-v2:' + uid + ':' +
      (source.accessGeneration || 'legacy')
    )
    .digest('hex');

  const mailRef = db
    .collection('_declarationMailOutbox')
    .doc(id);

  if ((await mailRef.get()).exists) return;

  const current = await snapshot.ref.get();

  if (
    !current.exists ||
    current.get('role') !== source.role ||
    current.get('createdBy') !== source.createdBy ||
    current.get('accessGeneration') !== source.accessGeneration ||
    (
      source.accessPolicy != null &&
      state(current.data()) !== 'pending'
    )
  ) {
    return;
  }

  const address = String(current.get('email') || '')
    .trim()
    .toLowerCase();

  if (!email(address)) return;

  let account;

  try {
    account = await getAuth().getUser(uid);
  } catch (error) {
    if (error.code === 'auth/user-not-found') return;
    throw error;
  }

  if (
    account.disabled ||
    String(account.email || '').trim().toLowerCase() !== address
  ) {
    return;
  }

  const application = new URL(
    process.env.DECLARA_APP_URL ||
      'https://declarahorario-ucr-cff7a.web.app'
  );

  if (
    application.protocol !== 'https:' ||
    application.username ||
    application.password
  ) {
    throw Error('DECLARA_APP_URL debe ser una dirección HTTPS.');
  }

  // No imprimir ni registrar este enlace confidencial.
  const passwordLink = await getAuth()
    .generatePasswordResetLink(address, {
      url: application.toString(),
      handleCodeInApp: false,
    });

  await db.runTransaction(async tx => {
    const [profile, existingMail] = await Promise.all([
      tx.get(snapshot.ref),
      tx.get(mailRef),
    ]);

    if (existingMail.exists) return;

    if (
      !profile.exists ||
      profile.get('role') !== source.role ||
      profile.get('createdBy') !== source.createdBy ||
      profile.get('accessGeneration') !== source.accessGeneration ||
      String(profile.get('email') || '')
        .trim().toLowerCase() !== address ||
      (
        source.accessPolicy != null &&
        state(profile.data()) !== 'pending'
      )
    ) {
      return;
    }

    const renewed = Boolean(profile.get('accessRenewedBy'));

    const lines = [
      'Estimado/a ' + (profile.get('name') || 'usuario/a') + ':',
      '',
      renewed
        ? 'Se ha renovado su invitación de acceso a DeclaraUCR.'
        : 'Le damos la bienvenida a DeclaraUCR.',
      '',
      'Correo de acceso: ' + address,
      'Rol: ' + roles[source.role],
      'Unidad: ' + (profile.get('unit') || 'Sin unidad registrada'),
    ];

    if (source.role === 'declarante') {
      lines.push(
        'Superior asignado: ' +
        (profile.get('superiorName') || 'Superior asignado')
      );
    }

    if (source.accessPolicy === 1) {
      lines.push(
        '',
        'Debe establecer su contraseña y completar el primer ingreso ' +
          'dentro de los diez días siguientes a esta invitación.',
        'Si el plazo vence, Administración debe renovar la invitación.'
      );
    }

    lines.push(
      '',
      'Para establecer su contraseña, abra este enlace:',
      passwordLink,
      '',
      'Después ingrese a la aplicación:',
      application.toString(),
      '',
      'Si el enlace para establecer la contraseña venció, utilice ' +
        '“Olvidé mi contraseña”. Esto no amplía el plazo de activación.',
      '',
      'No comparta este enlace ni su contraseña.',
      '',
      'Atentamente,',
      'DeclaraUCR',
      'Sistema de Declaración Jurada de Horarios',
      '',
      'Este mensaje fue generado automáticamente. No responda a este correo.'
    );

    tx.create(mailRef, {
      mailPolicyVersion: 2,
      mailType: 'BIENVENIDA_USUARIO',
      recipientUid: uid,
      expectedRole: source.role,
      to: address,
      subject: renewed
        ? 'DeclaraUCR | Invitación de acceso renovada'
        : 'DeclaraUCR | Bienvenida y acceso a su cuenta',
      text: lines.join('\n'),
      status: 'pending',
      attempts: 0,
      createdAt: FieldValue.serverTimestamp(),
      ...(source.accessPolicy === 1
        ? { accessGeneration: source.accessGeneration }
        : {}),
    });
  });
}

const options = {
  document: 'users/{uid}',
  region: 'us-east1',
  timeoutSeconds: 120,
  maxInstances: 2,
  retry: true,
};

exports.queueUserWelcomeMail = onDocumentCreated(
  options,
  event => queueWelcome(event.data)
);

exports.queueRenewedWelcomeMail = onDocumentUpdated(
  options,
  async event => {
    if (!event.data) return;

    const before = event.data.before.data();
    const after = event.data.after.data();

    if (
      after.accessPolicy !== 1 ||
      after.accessState !== 'pending' ||
      !after.accessGeneration ||
      before.accessGeneration === after.accessGeneration
    ) {
      return;
    }

    await queueWelcome(event.data.after);
  }
);
