'use strict';

const { createHash } = require('node:crypto');

const MAX_BYTES = 5 * 1024 * 1024;

const FIELDS = [
  'ownerId',
  'ownerName',
  'identification',
  'phone',
  'email',
  'unit',
  'superiorId',
  'periodId',
  'version',
  'appointments',
  'externalJobs',
  'observations',
  'formatVersion',
  'assignmentFormatVersion',
  'observationsFormatVersion',
];

const digest = value =>
  createHash('sha256').update(value).digest('hex');

function canonical(value) {
  if (Array.isArray(value)) {
    return value.map(canonical);
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map(key => [key, canonical(value[key])])
    );
  }

  return value;
}

function contentHash(data) {
  const content = Object.fromEntries(
    FIELDS
      .filter(key => data[key] !== undefined)
      .map(key => [key, data[key]])
  );

  return digest(JSON.stringify(canonical(content)));
}

function createSignedPdfHandlers({
  db,
  bucket,
  FieldValue,
  HttpsError,
  validator,
}) {
  function fail(code, message) {
    throw new HttpsError(code, message);
  }

  const ownerStates = [
    'VALIDADA',
    'PENDIENTE_FIRMA_DECLARANTE',
  ];

  const timestamp = () => FieldValue.serverTimestamp();

  function bytesOf(value) {
    if (
      typeof value !== 'string' ||
      value.length > 7 * 1024 * 1024 ||
      !/^[A-Za-z0-9+/]*={0,2}$/.test(value)
    ) {
      fail('invalid-argument', 'El archivo PDF es inválido.');
    }

    const bytes = Buffer.from(value, 'base64');

    if (
      !bytes.length ||
      bytes.length > MAX_BYTES ||
      bytes.subarray(0, 5).toString() !== '%PDF-' ||
      bytes.toString('base64') !== value
    ) {
      fail(
        'invalid-argument',
        'Seleccioná un PDF de hasta 5 MiB.'
      );
    }

    return bytes;
  }

  function refs(request) {
    const uid = request.auth?.uid;

    if (!uid) {
      fail('unauthenticated', 'Iniciá sesión.');
    }

    const {
      declarationId: id,
      version,
    } = request.data ?? {};

    if (
      typeof id !== 'string' ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(id) ||
      !Number.isSafeInteger(version) ||
      version < 1
    ) {
      fail(
        'invalid-argument',
        'Declaración o versión inválida.'
      );
    }

    return {
      uid,
      id,
      version,
      declaration: db.collection('declarations').doc(id),
      workflow: db
        .collection('_signatureWorkflows')
        .doc(`${id}--v${version}`),
    };
  }

  async function load(r, tx) {
    const get = ref => tx ? tx.get(ref) : ref.get();

    const [
      snapshot,
      actor,
      workflow,
    ] = await Promise.all([
      get(r.declaration),
      get(db.collection('users').doc(r.uid)),
      get(r.workflow),
    ]);

    if (!snapshot.exists) {
      fail('not-found', 'La declaración no existe.');
    }

    const d = snapshot.data();

    if (d.version !== r.version) {
      fail(
        'failed-precondition',
        'La versión cambió. Actualizá la pantalla.'
      );
    }

    const role = actor.get('role');

    const owner =
      role === 'declarante' &&
      d.ownerId === r.uid;

    const superior =
      role === 'superior' &&
      d.superiorId === r.uid;

    if (!owner && !superior && role !== 'rrhh') {
      fail(
        'permission-denied',
        'No tenés acceso a esta declaración.'
      );
    }

    const w = workflow.data();

    if (
      w &&
      (
        w.contentHash !== contentHash(d) ||
        w.declarationId !== r.id ||
        w.version !== r.version
      )
    ) {
      fail(
        'failed-precondition',
        'Los datos cambiaron después de preparar el PDF. ' +
        'Se requiere otra versión.'
      );
    }

    return {
      d,
      w,
      owner,
      superior,
      role,
    };
  }

  async function readFile(entry) {
    if (
      !entry?.path ||
      !entry.generation ||
      !entry.sha256
    ) {
      fail(
        'failed-precondition',
        'Falta el archivo de esta etapa.'
      );
    }

    const file = bucket.file(
      entry.path,
      { generation: entry.generation }
    );

    const [bytes] = await file.download();

    if (digest(bytes) !== entry.sha256) {
      fail(
        'data-loss',
        'El archivo no coincide con su registro.'
      );
    }

    return bytes;
  }

  async function saveFile(r, stage, bytes) {
    const sha256 = digest(bytes);

    const path =
      `signed-pdf/${r.id}/v${r.version}/` +
      `${stage}/${sha256}.pdf`;

    const file = bucket.file(path);

    try {
      await file.save(bytes, {
        resumable: false,
        contentType: 'application/pdf',
        preconditionOpts: {
          ifGenerationMatch: 0,
        },
      });
    } catch (error) {
      if (Number(error.code) !== 412) {
        throw error;
      }
    }

    const [metadata] = await file.getMetadata();

    const entry = {
      path,
      sha256,
      generation: String(metadata.generation),
    };

    await readFile(entry);

    return entry;
  }

  async function identities(r, c, tx) {
    const get = ref => tx ? tx.get(ref) : ref.get();

    const [owner, superior] = await Promise.all([
      get(db.collection('users').doc(c.d.ownerId)),
      get(db.collection('users').doc(c.d.superiorId)),
    ]);

    const ids = [
      owner.get('identification'),
      superior.get('identification'),
    ];

    if (
      owner.get('role') !== 'declarante' ||
      superior.get('role') !== 'superior' ||
      ids.some(
        id =>
          typeof id !== 'string' ||
          !/^[1-9]\d{8}$/.test(id)
      ) ||
      ids[0] !== c.d.identification ||
      ids[0] === ids[1]
    ) {
      fail(
        'failed-precondition',
        'Revisá las cédulas y los roles ' +
        'del declarante y del superior.'
      );
    }

    if (
      c.w &&
      (
        c.w.ownerIdentification !== ids[0] ||
        c.w.superiorIdentification !== ids[1]
      )
    ) {
      fail(
        'failed-precondition',
        'Cambió la identidad de un firmante. ' +
        'Se requiere una revisión.'
      );
    }

    return ids;
  }

  async function prepare(request) {
    const r = refs(request);
    const c = await load(r);

    if (
      !c.owner ||
      !ownerStates.includes(c.d.status)
    ) {
      fail(
        'failed-precondition',
        'Validá primero la declaración.'
      );
    }

    if (c.w?.layoutVersion === 'ucr-form-v2') return { prepared: true };
    if (c.w?.owner || c.w?.superior) fail('failed-precondition', 'El PDF ya fue firmado. No se puede cambiar su plantilla.');

    await identities(r, c);

    const rendered = await validator('/render', {
      declaration: c.d,
      declarationId: r.id,
    });

    const bytes = bytesOf(rendered.pdfBase64);

    const source = await saveFile(r, 'source', bytes);

    await db.runTransaction(async tx => {
      const current = await load(r, tx);
      const ids = await identities(r, current, tx);

      if (
        !current.owner ||
        !ownerStates.includes(current.d.status) ||
        contentHash(current.d) !== contentHash(c.d)
      ) {
        fail(
          'aborted',
          'La declaración cambió. Volvé a intentarlo.'
        );
      }

      if (current.w?.layoutVersion === 'ucr-form-v2') return;
      if (current.w?.owner || current.w?.superior) fail('failed-precondition', 'El PDF ya tiene una firma registrada.');
      if (current.w) {
        tx.update(r.workflow, { source, layoutVersion: 'ucr-form-v2' });
        return;
      }

      tx.create(r.workflow, {
        declarationId: r.id,
        version: r.version,
        contentHash: contentHash(current.d),
        ownerId: current.d.ownerId,
        superiorId: current.d.superiorId,
        ownerIdentification: ids[0],
        superiorIdentification: ids[1],
        source, layoutVersion: 'ucr-form-v2', createdAt: timestamp(),
      });
    });

    return { prepared: true };
  }

  async function status(request) {
    const r = refs(request);
    const c = await load(r);

    return {
      prepared: !!c.w,
      ownerVerified: !!c.w?.owner,
      superiorVerified: !!c.w?.superior,
      version: r.version,
    };
  }

  async function download(request) {
    const r = refs(request);
    const c = await load(r);

    const superiorDownloadStates = [
      'PENDIENTE_FIRMA_SUPERIOR',
      'ENVIADA_A_RRHH',
      'RECIBIDA_RRHH',
      'FINALIZADA',
    ];

    const hrDownloadStates = [
      'ENVIADA_A_RRHH',
      'RECIBIDA_RRHH',
      'FINALIZADA',
    ];

    let entry;

    if (c.owner) {
      entry =
        c.w?.superior ??
        c.w?.owner ??
        c.w?.source;
    } else if (
      c.superior &&
      superiorDownloadStates.includes(c.d.status)
    ) {
      entry = c.w?.superior ?? c.w?.owner;
    } else if (
      c.role === 'rrhh' &&
      hrDownloadStates.includes(c.d.status)
    ) {
      entry = c.w?.superior;
    } else {
      fail(
        'permission-denied',
        'El PDF todavía no está disponible para tu etapa.'
      );
    }

    const bytes = await readFile(entry);

    return {
      pdfBase64: bytes.toString('base64'),
      sha256: entry.sha256,
    };
  }

  async function upload(request) {
    const r = refs(request);
    const c = await load(r);

    let stage = null;

    if (
      c.owner &&
      ownerStates.includes(c.d.status)
    ) {
      stage = 'owner';
    } else if (
      c.superior &&
      c.d.status === 'PENDIENTE_FIRMA_SUPERIOR'
    ) {
      stage = 'superior';
    }

    if (!stage || !c.w) {
      fail(
        'failed-precondition',
        'Esta etapa no permite cargar el PDF.'
      );
    }

    if (c.w.layoutVersion !== 'ucr-form-v2') fail('failed-precondition', 'Descargá nuevamente el PDF con la plantilla institucional antes de firmarlo.');
    const ids = await identities(r, c);

    const bytes = bytesOf(request.data.pdfBase64);

    if (c.w[stage]) {
      if (c.w[stage].sha256 === digest(bytes)) {
        return {
          verified: true,
          alreadyUploaded: true,
        };
      }

      fail(
        'failed-precondition',
        'Esta versión ya tiene un PDF ' +
        'verificado para tu firma.'
      );
    }

    const baseEntry =
      stage === 'owner'
        ? c.w.source
        : c.w.owner;

    const base = await readFile(baseEntry);

    const result = await validator('/validate', {
      pdfBase64: bytes.toString('base64'),
      basePdfBase64: base.toString('base64'),
      expectedIdentifications:
        stage === 'owner' ? [ids[0]] : ids,
    });

    const expectedCount =
      stage === 'owner' ? 1 : 2;

    if (
      result.valid !== true ||
      result.sha256 !== digest(bytes) ||
      result.signers?.length !== expectedCount ||
      result.signers.some(
        (signer, index) =>
          signer.identification !== ids[index] ||
          !/^[a-f0-9]{64}$/.test(
            signer.certificateSha256
          )
      )
    ) {
      fail(
        'failed-precondition',
        'El verificador no confirmó ' +
        'las firmas requeridas.'
      );
    }

    if (
      stage === 'superior' &&
      result.signers[0].certificateSha256 !==
        c.w.owner.signers[0].certificateSha256
    ) {
      fail(
        'failed-precondition',
        'No se conservó el certificado del declarante.'
      );
    }

    const file = await saveFile(r, stage, bytes);

    await db.runTransaction(async tx => {
      const current = await load(r, tx);

      await identities(r, current, tx);

      if (
        current.d.status !== c.d.status ||
        !current.w ||
        (
          stage === 'owner'
            ? !current.owner
            : !current.superior
        ) ||
        ((stage === 'owner' ? current.w.source?.sha256 : current.w.owner?.sha256) !== baseEntry.sha256)
      ) {
        fail(
          'aborted',
          'La declaración cambió durante la verificación.'
        );
      }

      if (current.w[stage]) {
        if (
          current.w[stage].sha256 === file.sha256
        ) {
          return;
        }

        fail(
          'already-exists',
          'Ya se registró otro PDF firmado.'
        );
      }

      tx.update(r.workflow, {
        [stage]: {
          ...file,
          signers: result.signers,
          userId: r.uid,
          verifiedAt: timestamp(),
        },
      });

      const eventRef = r.declaration
        .collection('events')
        .doc(`pdf-${stage}-${file.sha256}`);

      tx.create(eventRef, {
        event:
          stage === 'owner'
            ? 'PDF_FIRMADO_DECLARANTE'
            : 'PDF_FIRMADO_SUPERIOR',
        userId: r.uid,
        version: r.version,
        dateTime: timestamp(),
        previousStatus: current.d.status,
        newStatus: current.d.status,
        observation:
          'Firma digital del PDF verificada.',
        sha256: file.sha256,
      });
    });

    return {
      verified: true,
      alreadyUploaded: false,
    };
  }

    const {
    send,
    accept,
  } = require('./signed-pdf-transitions')
    .createSignedPdfTransitions({
      db,
      bucket,
      refs,
      load,
      identities,
      readFile,
      ownerStates,
      fail,
      timestamp,
    });

  return {
    prepare,
    status,
    download,
    upload,
    send,
    accept,
  };
}

module.exports = {
  createSignedPdfHandlers,
  contentHash,
};