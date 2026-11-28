'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const file = path.resolve('firestore.rules');
const original = fs.readFileSync(file, 'utf8');

const marker =
  /match\s+\/declarations\/\{id\}\s*\{/g;

const matches = [...original.matchAll(marker)];

if (matches.length !== 1) {
  throw Error(
    'Se esperaba un único bloque declarations/{id}. ' +
    'No se guardó nada.'
  );
}

const start = matches[0].index;
const open = start + matches[0][0].length - 1;

let depth = 0;
let quote = null;
let line = false;
let comment = false;
let end = -1;

for (let i = open; i < original.length; i++) {
  const character = original[i];
  const next = original[i + 1];

  if (line) {
    if (character === '\n') line = false;
    continue;
  }

  if (comment) {
    if (character === '*' && next === '/') {
      comment = false;
      i++;
    }
    continue;
  }

  if (quote) {
    if (character === '\\') {
      i++;
    } else if (character === quote) {
      quote = null;
    }
    continue;
  }

  if (character === '/' && next === '/') {
    line = true;
    i++;
    continue;
  }

  if (character === '/' && next === '*') {
    comment = true;
    i++;
    continue;
  }

  if (character === "'" || character === '"') {
    quote = character;
    continue;
  }

  if (character === '{') depth++;

  if (character === '}' && --depth === 0) {
    end = i + 1;
    break;
  }
}

if (end < 0) {
  throw Error(
    'No se pudo delimitar el bloque. No se guardó nada.'
  );
}

const replacement = `match /declarations/{id} {
      function finalDigitalPdf() {
        let v = resource.data.version;
        let a = get(/databases/$(database)/documents/declarations/$(id)/versions/$(v)/artifacts/finalPdf).data;
        let key = id + '--v' + string(v);
        let w = get(/databases/$(database)/documents/_signatureWorkflows/$(key)).data;

        return a.method == 'DIGITAL_PDF'
          && a.version == v
          && w.version == v
          && w.ownerId == resource.data.ownerId
          && w.superiorId == resource.data.superiorId
          && w.superior.sha256 == a.sha256;
      }

      allow read: if signed()
        && role() != 'admin'
        && canRead(resource.data);

      allow create, delete: if false;

      allow update: if signed()
        && role() != 'admin'
        && request.resource.data.version == resource.data.version
        && request.resource.data.diff(resource.data).affectedKeys()
          .hasOnly(['status', 'updatedAt', 'returnNote'])
        && (
          (
            owner(resource.data)
            && (
              (
                resource.data.status == 'VALIDADA'
                && request.resource.data.status == 'PENDIENTE_FIRMA_DECLARANTE'
              )
              || (
                resource.data.status in ['BORRADOR', 'VALIDADA']
                && request.resource.data.status == 'ANULADA'
              )
            )
          )
          || (
            superior(resource.data)
            && resource.data.status == 'PENDIENTE_FIRMA_SUPERIOR'
            && request.resource.data.status == 'DEVUELTA'
            && request.resource.data.returnNote is string
            && request.resource.data.returnNote.size() > 0
          )
          || (
            role() == 'rrhh'
            && (
              (
                resource.data.status == 'ENVIADA_A_RRHH'
                && request.resource.data.status == 'RECIBIDA_RRHH'
              )
              || (
                resource.data.status == 'RECIBIDA_RRHH'
                && request.resource.data.status == 'FINALIZADA'
              )
            )
            && finalDigitalPdf()
          )
        );

      match /versions/{version} {
        allow read: if signed()
          && role() != 'admin'
          && canRead(declarationBefore(id));

        allow write: if false;

        match /artifacts/{artifactId} {
          allow read: if signed()
            && role() != 'admin'
            && artifactId == 'finalPdf'
            && canRead(declarationBefore(id));

          allow write: if false;
        }

        match /signatures/{signatureId} {
          allow read: if signed()
            && role() != 'admin'
            && canRead(declarationBefore(id));

          allow write: if false;
        }
      }

      match /events/{eventId} {
        allow read: if signed()
          && role() != 'admin'
          && canRead(declarationBefore(id));

        allow create: if signed()
          && role() != 'admin'
          && request.resource.data.userId == request.auth.uid
          && request.resource.data.event in [
            'submit', 'annul', 'return', 'receive', 'finish'
          ]
          && validTransitionEvent(id);

        allow update, delete: if false;
      }
    }`;

const updated =
  original.slice(0, start) +
  replacement +
  original.slice(end);

const backupDir = fs.mkdtempSync(
  path.join(os.tmpdir(), 'declara-reglas-firmas-')
);

fs.writeFileSync(
  path.join(backupDir, 'firestore.rules'),
  original
);

fs.writeFileSync(file, updated);

console.log(
  'Reglas locales actualizadas. Respaldo: ' +
  backupDir
);

console.log('Todavía no se desplegaron.');