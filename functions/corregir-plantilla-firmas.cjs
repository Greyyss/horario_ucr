'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const root = process.cwd();

const sourcePath = path.join(
  root,
  'lib/services/declaration_pdf_layout.dart'
);

const observationsPath = path.join(
  root,
  'lib/services/declaration_observations.dart'
);

const logoPath = path.join(
  root,
  'assets/images/logo_ucr.png'
);

for (const file of [
  sourcePath,
  observationsPath,
  logoPath,
]) {
  if (!fs.existsSync(file)) {
    throw Error('Falta el archivo: ' + file);
  }
}

let source = fs.readFileSync(sourcePath, 'utf8');

function replaceOnce(pattern, value, label) {
  const matches = [
    ...source.matchAll(
      new RegExp(
        pattern.source,
        'g' + (pattern.multiline ? 'm' : '')
      )
    ),
  ];

  if (matches.length !== 1) {
    throw Error(
      'La plantilla tiene una estructura diferente: ' +
      label +
      '. No se escribió nada.'
    );
  }

  source = source.replace(pattern, value);
}

replaceOnce(
  /^import ['"]package:cloud_firestore\/cloud_firestore.dart['"] show Timestamp;[ \t]*\r?\n/m,
  '',
  'import Timestamp'
);

replaceOnce(
  /    if \(value is Timestamp\) \{\s*return value.toDate\(\);\s*\}\s*/,
  '',
  'conversión Timestamp'
);

if (/\bTimestamp\b/.test(source)) {
  throw Error(
    'Quedan dependencias de Timestamp. No se escribió nada.'
  );
}

source = source.replaceAll(
  "'Pendiente de firma'",
  "'Consultar firma digital del PDF'"
);

replaceOnce(
  /'Registro electrónico interno académico\. '\s*'No equivale a firma digital certificada\.'/,
  "'Las firmas digitales se consultan en el panel de firmas del archivo PDF.'",
  'pie de firma'
);

const lock = fs.readFileSync(
  path.join(root, 'pubspec.lock'),
  'utf8'
);

const version = lock.match(
  /^  pdf:\r?\n[\s\S]*?^    version: "([0-9.]+)"/m
)?.[1];

if (!version) {
  throw Error(
    'No se encontró la versión de pdf en pubspec.lock.'
  );
}

const handlersPath = path.join(
  root,
  'functions/signed-pdf-handlers.js'
);

const originalHandlers = fs.readFileSync(
  handlersPath,
  'utf8'
);

let content = originalHandlers;

if (!content.includes('ucr-form-v2')) {
  function changeHandlers(pattern, replacement, label) {
    const matches = [
      ...content.matchAll(
        new RegExp(pattern.source, pattern.flags + 'g')
      ),
    ];

    if (matches.length !== 1) {
      throw Error(
        'No se encontró un único bloque: ' +
        label +
        '. No se guardó nada.'
      );
    }

    content = content.replace(pattern, replacement);
  }

  changeHandlers(
    /if\s*\(c\.w\)\s*(?:\{\s*)?return\s*\{\s*prepared:\s*true\s*\};(?:\s*\})?/,
    `if (c.w?.layoutVersion === 'ucr-form-v2') return { prepared: true };
    if (c.w?.owner || c.w?.superior) fail('failed-precondition', 'El PDF ya fue firmado. No se puede cambiar su plantilla.');`,
    'preparación'
  );

  changeHandlers(
    /if\s*\(current\.w\)\s*(?:\{\s*)?return;(?:\s*\})?/,
    `if (current.w?.layoutVersion === 'ucr-form-v2') return;
      if (current.w?.owner || current.w?.superior) fail('failed-precondition', 'El PDF ya tiene una firma registrada.');
      if (current.w) {
        tx.update(r.workflow, { source, layoutVersion: 'ucr-form-v2' });
        return;
      }`,
    'registro existente'
  );

  changeHandlers(
    /source,\s*createdAt:/,
    "source, layoutVersion: 'ucr-form-v2', createdAt:",
    'registro nuevo'
  );

  changeHandlers(
    /const\s+ids\s*=\s*await\s+identities\(r,\s*c\);/,
    `if (c.w.layoutVersion !== 'ucr-form-v2') fail('failed-precondition', 'Descargá nuevamente el PDF con la plantilla institucional antes de firmarlo.');
    const ids = await identities(r, c);`,
    'comprobación al subir'
  );

  changeHandlers(
    /\(\s*stage\s*===\s*'superior'\s*&&\s*current\.w\.owner\?\.sha256\s*!==\s*baseEntry\.sha256\s*\)/,
    "((stage === 'owner' ? current.w.source?.sha256 : current.w.owner?.sha256) !== baseEntry.sha256)",
    'archivo base'
  );
}

const rendererPython = String.raw`import io
import json
import os
import subprocess

from pyhanko.pdf_utils.generic import DictionaryObject, NumberObject, pdf_string
from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
from pyhanko.sign.fields import SigFieldSpec, append_signature_field


def render_declaration(data, declaration_id):
    executable = os.environ.get("PDF_RENDERER_PATH", "/app/render-pdf")

    result = subprocess.run(
        [executable],
        input=json.dumps(
            {"declaration": data},
            ensure_ascii=False,
        ).encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=60,
    )

    if not result.stdout.startswith(b"%PDF-"):
        raise ValueError("El generador no devolvió un PDF válido.")

    writer = IncrementalPdfFileWriter(
        io.BytesIO(result.stdout)
    )

    writer.set_info(DictionaryObject({
        "/Title": pdf_string(
            "Declaración jurada de horario y jornada de trabajo"
        ),
        "/DeclaraDeclarationId": pdf_string(
            str(declaration_id)
        ),
        "/DeclaraVersion": NumberObject(
            int(data["version"])
        ),
    }))

    append_signature_field(
        writer,
        SigFieldSpec("Declarante"),
    )

    append_signature_field(
        writer,
        SigFieldSpec("Superior"),
    )

    writer.root["/AcroForm"]["/SigFlags"] = NumberObject(3)
    writer.update_container(writer.root["/AcroForm"])

    output = io.BytesIO()
    writer.write(output)

    return output.getvalue()
`;

const dockerfile = String.raw`FROM dart:stable AS pdf_builder

WORKDIR /renderer

COPY pdf-renderer/pubspec.yaml ./
RUN dart pub get

COPY pdf-renderer/lib/ lib/
COPY pdf-renderer/bin/ bin/

RUN mkdir -p /out && dart compile exe bin/render.dart -o /out/render-pdf

FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --from=pdf_builder /out/render-pdf /app/render-pdf

COPY main.py render.py ./
COPY trust/ trust/
COPY assets/ assets/

ENV PORT=8080

CMD ["sh", "-c", "exec gunicorn --bind :$PORT --timeout 110 --workers 1 --threads 1 main:app"]
`;

const dartMain = String.raw`import 'dart:convert';
import 'dart:io';

import '../lib/declaration_pdf_layout.dart';

Future<void> main() async {
  try {
    final payload = jsonDecode(
      await stdin.transform(utf8.decoder).join(),
    ) as Map;

    final declaration = Map<String, dynamic>.from(
      payload['declaration'] as Map,
    );

    final bytes = await buildDeclarationPdfTables(
      declaration: declaration,
      signatures: <Map<String, dynamic>>[],
      logoBytes: await File(
        Platform.environment['PDF_LOGO_PATH'] ??
            '/app/assets/logo_ucr.png',
      ).readAsBytes(),
    );

    stdout.add(bytes);
    await stdout.flush();
  } catch (error) {
    stderr.writeln(
      'No se pudo generar la plantilla de declaración: $error',
    );

    exitCode = 1;
  }
}
`;

const backup = fs.mkdtempSync(
  path.join(os.tmpdir(), 'declara-formato-pdf-')
);

for (const relative of [
  'functions/signed-pdf-handlers.js',
  'signature-validator/render.py',
  'signature-validator/Dockerfile',
]) {
  const original = path.join(root, relative);

  if (fs.existsSync(original)) {
    fs.copyFileSync(
      original,
      path.join(backup, path.basename(relative))
    );
  }
}

const target = path.join(
  root,
  'signature-validator/pdf-renderer'
);

fs.mkdirSync(path.join(target, 'lib'), {
  recursive: true,
});

fs.mkdirSync(path.join(target, 'bin'), {
  recursive: true,
});

fs.mkdirSync(
  path.join(root, 'signature-validator/assets'),
  { recursive: true }
);

fs.writeFileSync(
  path.join(target, 'lib/declaration_pdf_layout.dart'),
  source
);

fs.copyFileSync(
  observationsPath,
  path.join(target, 'lib/declaration_observations.dart')
);

fs.copyFileSync(
  logoPath,
  path.join(root, 'signature-validator/assets/logo_ucr.png')
);

fs.writeFileSync(
  path.join(target, 'pubspec.yaml'),
  `name: signature_pdf_renderer
environment:
  sdk: '>=3.4.0 <4.0.0'
dependencies:
  pdf: ${version}
`
);

fs.writeFileSync(
  path.join(target, 'bin/render.dart'),
  dartMain
);

fs.writeFileSync(
  path.join(root, 'signature-validator/render.py'),
  rendererPython
);

fs.writeFileSync(
  path.join(root, 'signature-validator/Dockerfile'),
  dockerfile
);

fs.writeFileSync(handlersPath, content);

console.log(
  'Plantilla original conectada al generador de firmas.'
);

console.log('Respaldo: ' + backup);
