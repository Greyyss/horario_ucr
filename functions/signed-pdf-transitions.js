'use strict';

const { createHash } = require('node:crypto');

const digest = bytes =>
  createHash('sha256').update(bytes).digest('hex');

function createSignedPdfTransitions({
  db,
  bucket,
  refs,
  load,
  identities,
  readFile,
  ownerStates,
  fail,
  timestamp,
}) {
  const signatureRef = (r, who) =>
    r.declaration
      .collection('versions')
      .doc(String(r.version))
      .collection('signatures')
      .doc(who);

  async function send(request) {
    const r = refs(request);

    return db.runTransaction(async tx => {
      const c = await load(r, tx);

      await identities(r, c, tx);

      const eventRef = r.declaration
        .collection('events')
        .doc(`digital-route-v${r.version}`);

      const [signature, event] = await Promise.all([
        tx.get(signatureRef(r, 'owner')),
        tx.get(eventRef),
      ]);

      if (
        !c.owner ||
        !c.w?.owner ||
        c.w.owner.userId !== r.uid
      ) {
        fail(
          'failed-precondition',
          'Subí primero el PDF con tu firma digital verificada.'
        );
      }

      const alreadySent = [
        'PENDIENTE_FIRMA_SUPERIOR',
        'ENVIADA_A_RRHH',
        'RECIBIDA_RRHH',
        'FINALIZADA',
      ].includes(c.d.status);

      if (
        alreadySent &&
        event.exists &&
        signature.get('method') === 'DIGITAL_PDF' &&
        signature.get('hash') === c.w.owner.sha256
      ) {
        return {
          sent: true,
          alreadySent: true,
        };
      }

      if (
        !ownerStates.includes(c.d.status) ||
        signature.exists ||
        event.exists
      ) {
        fail(
          'failed-precondition',
          'Esta versión no permite el envío. Actualizá la pantalla.'
        );
      }

      tx.create(signatureRef(r, 'owner'), {
        userId: r.uid,
        name: c.d.ownerName || 'Declarante',
        version: r.version,
        signatureId: 'owner',
        type: 'DECLARANTE',
        method: 'DIGITAL_PDF',
        hash: c.w.owner.sha256,
        dateTime: timestamp(),
      });

      tx.update(r.declaration, {
        status: 'PENDIENTE_FIRMA_SUPERIOR',
        updatedAt: timestamp(),
      });

      tx.create(eventRef, {
        event: 'route',
        userId: r.uid,
        version: r.version,
        dateTime: timestamp(),
        previousStatus: c.d.status,
        newStatus: 'PENDIENTE_FIRMA_SUPERIOR',
        observation:
          'PDF con firma digital verificada enviado al superior.',
        sha256: c.w.owner.sha256,
      });

      return {
        sent: true,
        alreadySent: false,
      };
    });
  }

  async function accept(request) {
    const r = refs(request);
    const c = await load(r);

    const allowedStates = [
      'PENDIENTE_FIRMA_SUPERIOR',
      'ENVIADA_A_RRHH',
      'RECIBIDA_RRHH',
      'FINALIZADA',
    ];

    if (
      !c.superior ||
      !c.w?.owner ||
      !c.w?.superior ||
      c.w.superior.userId !== r.uid ||
      !allowedStates.includes(c.d.status)
    ) {
      fail(
        'failed-precondition',
        'Se requiere el PDF con ambas firmas digitales verificadas.'
      );
    }

    await identities(r, c);

    const bytes = await readFile(c.w.superior);

    const storagePath =
      `pdf/${r.id}/v${r.version}.pdf`;

    const file = bucket.file(storagePath);

    try {
      await file.save(bytes, {
        resumable: false,
        validation: 'crc32c',
        preconditionOpts: {
          ifGenerationMatch: 0,
        },
        metadata: {
          contentType: 'application/pdf',
          cacheControl: 'private, no-store',
          metadata: {
            declarationId: r.id,
            version: String(r.version),
            sha256: digest(bytes),
            uploadedBy: r.uid,
          },
        },
      });
    } catch (error) {
      if (Number(error.code) !== 412) {
        throw error;
      }
    }

    const [metadata] = await file.getMetadata();

    const artifact = {
      declarationId: r.id,
      version: r.version,
      bucket: bucket.name,
      storagePath,
      generation: String(metadata.generation),
      sha256: digest(bytes),
      size: bytes.length,
      contentType: 'application/pdf',
      createdBy: r.uid,
      method: 'DIGITAL_PDF',
    };

    if (
      metadata.contentType !== 'application/pdf' ||
      metadata.metadata?.sha256 !== artifact.sha256 ||
      metadata.metadata?.declarationId !== r.id ||
      metadata.metadata?.version !== String(r.version)
    ) {
      fail(
        'failed-precondition',
        'El PDF archivado existente requiere revisión. ' +
        'No se sobrescribió.'
      );
    }

    await readFile({
      path: storagePath,
      generation: artifact.generation,
      sha256: artifact.sha256,
    });

    return db.runTransaction(async tx => {
      const current = await load(r, tx);

      await identities(r, current, tx);

      const artifactRef = r.declaration
        .collection('versions')
        .doc(String(r.version))
        .collection('artifacts')
        .doc('finalPdf');

      const eventRef = r.declaration
        .collection('events')
        .doc(`digital-accept-v${r.version}`);

      const [
        owner,
        superior,
        existingArtifact,
        event,
      ] = await Promise.all([
        tx.get(signatureRef(r, 'owner')),
        tx.get(signatureRef(r, 'superior')),
        tx.get(artifactRef),
        tx.get(eventRef),
      ]);

      if (
        !current.superior ||
        current.w?.superior?.sha256 !== artifact.sha256 ||
        current.w?.owner?.sha256 !== c.w.owner.sha256 ||
        owner.get('method') !== 'DIGITAL_PDF' ||
        owner.get('userId') !== current.d.ownerId ||
        owner.get('version') !== r.version ||
        owner.get('hash') !== current.w.owner.sha256
      ) {
        fail(
          'failed-precondition',
          'Las firmas no corresponden a esta declaración.'
        );
      }

      const alreadyAccepted = [
        'ENVIADA_A_RRHH',
        'RECIBIDA_RRHH',
        'FINALIZADA',
      ].includes(current.d.status);

      if (
        event.exists &&
        superior.get('method') === 'DIGITAL_PDF' &&
        superior.get('userId') === r.uid &&
        superior.get('hash') === artifact.sha256 &&
        existingArtifact.get('sha256') === artifact.sha256 &&
        existingArtifact.get('generation') === artifact.generation &&
        alreadyAccepted
      ) {
        return {
          accepted: true,
          alreadyAccepted: true,
        };
      }

      if (
        current.d.status !== 'PENDIENTE_FIRMA_SUPERIOR' ||
        superior.exists ||
        existingArtifact.exists ||
        event.exists
      ) {
        fail(
          'failed-precondition',
          'Esta versión no permite la aceptación. ' +
          'Actualizá la pantalla.'
        );
      }

      tx.create(signatureRef(r, 'superior'), {
        userId: r.uid,
        version: r.version,
        signatureId: 'superior',
        type: 'SUPERIOR',
        method: 'DIGITAL_PDF',
        hash: artifact.sha256,
        dateTime: timestamp(),
      });

      tx.create(artifactRef, {
        ...artifact,
        createdAt: timestamp(),
      });

      tx.update(r.declaration, {
        status: 'ENVIADA_A_RRHH',
        updatedAt: timestamp(),
      });

      tx.create(eventRef, {
        event: 'signSuperior',
        userId: r.uid,
        version: r.version,
        dateTime: timestamp(),
        previousStatus: current.d.status,
        newStatus: 'ENVIADA_A_RRHH',
        observation:
          'PDF con ambas firmas digitales aceptado y enviado a RRHH.',
        sha256: artifact.sha256,
      });

      return {
        accepted: true,
        alreadyAccepted: false,
      };
    });
  }

  return {
    send,
    accept,
  };
}

module.exports = {
  createSignedPdfTransitions,
};