const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { createHash } = require("node:crypto");

initializeApp();
Object.assign(exports, require("./declaration-callables"));

const db = getFirestore();
const bucket = getStorage().bucket(
  "declarahorario-ucr-cff7a.firebasestorage.app"
);

const MAX_BYTES = 10 * 1024 * 1024;

// Comprueba los permisos y los documentos dentro de una transacción.
async function validateDeclaration(tx, uid, declarationRef, version) {
  const versionRef = declarationRef.collection("versions").doc(`${version}`);

  const [userDoc, declarationDoc, versionDoc, ownerDoc, superiorDoc] =
    await Promise.all([
      tx.get(db.collection("users").doc(uid)),
      tx.get(declarationRef),
      tx.get(versionRef),
      tx.get(versionRef.collection("signatures").doc("owner")),
      tx.get(versionRef.collection("signatures").doc("superior")),
    ]);

  if (!["rrhh", "admin"].includes(userDoc.data()?.role)) {
    throw new HttpsError(
      "permission-denied",
      "Solo RRHH o administración puede archivar el PDF."
    );
  }

  if (!declarationDoc.exists) {
    throw new HttpsError("not-found", "La declaración no existe.");
  }

  const declaration = declarationDoc.data();

  if (
    declaration.status !== "FINALIZADA" ||
    declaration.version !== version
  ) {
    throw new HttpsError(
      "failed-precondition",
      "La declaración debe estar finalizada y corresponder a esa versión."
    );
  }

  const saved = versionDoc.data();

  if (
    !saved ||
    saved.version !== version ||
    saved.ownerId !== declaration.ownerId ||
    saved.superiorId !== declaration.superiorId
  ) {
    throw new HttpsError(
      "failed-precondition",
      "La versión guardada no coincide con la declaración."
    );
  }

  const owner = ownerDoc.data();
  const superior = superiorDoc.data();

  if (
    !declaration.ownerId ||
    !declaration.superiorId ||
    !owner ||
    !superior ||
    owner.userId !== declaration.ownerId ||
    superior.userId !== declaration.superiorId ||
    owner.version !== version ||
    superior.version !== version
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Faltan firmas correspondientes a esta versión."
    );
  }
}

exports.archiveDeclarationPdf = onCall(
  {
    region: "us-east1",
    memory: "512MiB",
    timeoutSeconds: 120,
    minInstances: 0,
    maxInstances: 2,
    concurrency: 4,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Debés iniciar sesión."
      );
    }

    const uid = request.auth.uid;
    const { declarationId, version, pdfBase64 } = request.data ?? {};

    if (
      typeof declarationId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(declarationId) ||
      !Number.isSafeInteger(version) ||
      version < 1
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Identificador o versión inválidos."
      );
    }

    if (
      typeof pdfBase64 !== "string" ||
      pdfBase64.length === 0 ||
      pdfBase64.length > 4 * Math.ceil(MAX_BYTES / 3)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "El PDF está vacío o supera el tamaño permitido."
      );
    }

    const bytes = Buffer.from(pdfBase64, "base64");

    if (
      bytes.toString("base64") !== pdfBase64 ||
      bytes.length === 0 ||
      bytes.length >= MAX_BYTES ||
      bytes.subarray(0, 5).toString("ascii") !== "%PDF-"
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Se requiere un PDF válido de menos de 10 MiB."
      );
    }

    const declarationRef = db.collection("declarations").doc(declarationId);
    const artifactRef = declarationRef
      .collection("versions")
      .doc(`${version}`)
      .collection("artifacts")
      .doc("finalPdf");

    const storagePath = `pdf/${declarationId}/v${version}.pdf`;
    const file = bucket.file(storagePath);
    const sha256 = createHash("sha256").update(bytes).digest("hex");

    try {
      await db.runTransaction((tx) =>
        validateDeclaration(tx, uid, declarationRef, version)
      );

      let alreadyExists = false;

      try {
        await file.save(bytes, {
          resumable: false,
          validation: "crc32c",
          preconditionOpts: {
            ifGenerationMatch: 0,
          },
          metadata: {
            contentType: "application/pdf",
            cacheControl: "private, no-store",
            metadata: {
              declarationId,
              version: `${version}`,
              sha256,
              uploadedBy: uid,
            },
          },
        });
      } catch (error) {
        if (Number(error.code) !== 412) {
          throw error;
        }

        // Ya existe: conservamos el PDF original.
        alreadyExists = true;
      }

      const [metadata] = await file.getMetadata();
      const custom = metadata.metadata ?? {};

      if (
        metadata.contentType !== "application/pdf" ||
        custom.declarationId !== declarationId ||
        custom.version !== `${version}` ||
        !/^[a-f0-9]{64}$/.test(custom.sha256 ?? "") ||
        !custom.uploadedBy ||
        !metadata.generation ||
        !(Number(metadata.size) > 0 &&
          Number(metadata.size) < MAX_BYTES)
      ) {
        throw new HttpsError(
          "failed-precondition",
          "El archivo existente requiere revisión. No se sobrescribió."
        );
      }

      // Si Storage guardó el archivo pero Firestore falló,
      // un nuevo intento puede completar este registro.
      await db.runTransaction(async (tx) => {
        await validateDeclaration(tx, uid, declarationRef, version);
        const existing = await tx.get(artifactRef);

        if (existing.exists) {
          const data = existing.data();

          if (
            data.storagePath !== storagePath ||
            data.generation !== metadata.generation ||
            data.sha256 !== custom.sha256
          ) {
            throw new HttpsError(
              "failed-precondition",
              "El registro del PDF no coincide con el archivo guardado."
            );
          }

          return;
        }

        tx.create(artifactRef, {
          declarationId,
          version,
          bucket: bucket.name,
          storagePath,
          generation: metadata.generation,
          sha256: custom.sha256,
          size: Number(metadata.size),
          contentType: "application/pdf",
          createdBy: custom.uploadedBy,
          createdAt: FieldValue.serverTimestamp(),
        });
      });

      return {
        storagePath,
        version,
        sha256: custom.sha256,
        alreadyExists,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("No se pudo archivar el PDF", {
        declarationId,
        version,
        code: String(error.code ?? ""),
        message: error.message,
      });

      throw new HttpsError(
        "internal",
        "No se pudo completar el guardado. Podés volver a intentarlo."
      );
    }
  }
);

exports.downloadDeclarationPdf = onCall(
  {
    region: "us-east1",
    memory: "512MiB",
    timeoutSeconds: 120,
    minInstances: 0,
    maxInstances: 2,
    concurrency: 4,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Debés iniciar sesión.");
    }

    const uid = request.auth.uid;
    const { declarationId, version } = request.data ?? {};

    if (
      typeof declarationId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(declarationId) ||
      !Number.isSafeInteger(version) ||
      version < 1
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Identificador o versión inválidos."
      );
    }

    try {
      const declarationRef = db.collection("declarations").doc(declarationId);
      const artifactRef = declarationRef
        .collection("versions")
        .doc(`${version}`)
        .collection("artifacts")
        .doc("finalPdf");

      const artifact = await db.runTransaction(async (tx) => {
        const [userDoc, declarationDoc, artifactDoc] = await Promise.all([
          tx.get(db.collection("users").doc(uid)),
          tx.get(declarationRef),
          tx.get(artifactRef),
        ]);

        const declaration = declarationDoc.data();
        const role = userDoc.data()?.role;

        const allowed = declaration && (
          declaration.ownerId === uid ||
          ["rrhh", "admin"].includes(role) ||
          (declaration.superiorId === uid && role === "superior")
        );

        if (!allowed) {
          throw new HttpsError(
            "permission-denied",
            "No tenés permiso para consultar esta declaración."
          );
        }

        if (!artifactDoc.exists) {
          throw new HttpsError(
            "not-found",
            "Esta versión todavía no tiene un PDF archivado."
          );
        }

        return artifactDoc.data();
      });

      const storagePath = `pdf/${declarationId}/v${version}.pdf`;

      if (
        artifact.storagePath !== storagePath ||
        artifact.bucket !== bucket.name ||
        artifact.version !== version ||
        !/^[a-f0-9]{64}$/.test(artifact.sha256 ?? "")
      ) {
        throw new HttpsError(
          "failed-precondition",
          "El registro del PDF es inválido."
        );
      }

      const file = bucket.file(storagePath);
      const [metadata] = await file.getMetadata();

      if (
        metadata.generation !== artifact.generation ||
        metadata.contentType !== "application/pdf" ||
        !(Number(metadata.size) > 0 &&
          Number(metadata.size) < MAX_BYTES)
      ) {
        throw new HttpsError(
          "failed-precondition",
          "El archivo no coincide con el registro del PDF."
        );
      }

      const [bytes] = await file.download();
      const hash = createHash("sha256").update(bytes).digest("hex");

      if (hash !== artifact.sha256) {
        throw new HttpsError(
          "failed-precondition",
          "La huella del PDF no coincide con la registrada."
        );
      }

      return {
        pdfBase64: bytes.toString("base64"),
        sha256: hash,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("No se pudo descargar el PDF", {
        declarationId,
        version,
        code: String(error.code ?? ""),
        message: error.message,
      });

      throw new HttpsError(
        "internal",
        "No se pudo recuperar el PDF archivado."
      );
    }
  }
);