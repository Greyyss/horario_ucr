'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const file = path.resolve('lib/pages/dashboard.dart');

let source = fs.readFileSync(file, 'utf8');

const marker =
  /Widget\s+_actionsFor\(Declaration\s+d,\s*String\s+uid\)\s*\{/g;

const matches = [...source.matchAll(marker)];

if (matches.length !== 1) {
  throw Error(
    'No encontré un único método _actionsFor. ' +
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

for (let i = open; i < source.length; i++) {
  const c = source[i];
  const next = source[i + 1];

  if (line) {
    if (c === '\n') line = false;
    continue;
  }

  if (comment) {
    if (c === '*' && next === '/') {
      comment = false;
      i++;
    }
    continue;
  }

  if (quote) {
    if (c === '\\') {
      i++;
    } else if (c === quote) {
      quote = null;
    }
    continue;
  }

  if (c === '/' && next === '/') {
    line = true;
    i++;
    continue;
  }

  if (c === '/' && next === '*') {
    comment = true;
    i++;
    continue;
  }

  if (c === "'" || c === '"') {
    quote = c;
    continue;
  }

  if (c === '{') depth++;

  if (c === '}' && --depth === 0) {
    end = i + 1;
    break;
  }
}

if (end < 0) {
  throw Error(
    'No se pudo delimitar _actionsFor. No se guardó nada.'
  );
}

const replacement = `Widget _actionsFor(Declaration d, String uid) {
    final owner = role == 'declarante' && d.ownerId == uid;
    final superior = role == 'superior' && d.superiorId == uid;

    final showSigning = (owner && [
      'VALIDADA',
      'PENDIENTE_FIRMA_DECLARANTE',
      'FIRMADA_POR_DECLARANTE',
      'PENDIENTE_FIRMA_SUPERIOR',
      'FIRMADA_POR_SUPERIOR',
      'ENVIADA_A_RRHH',
      'RECIBIDA_RRHH',
    ].contains(d.status)) || (superior && [
      'PENDIENTE_FIRMA_SUPERIOR',
      'FIRMADA_POR_SUPERIOR',
      'ENVIADA_A_RRHH',
      'RECIBIDA_RRHH',
    ].contains(d.status)) || (role == 'rrhh' && [
      'ENVIADA_A_RRHH',
      'RECIBIDA_RRHH',
    ].contains(d.status));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSigning) ...[
          SignedPdfPanel(
            key: ValueKey(
              'firma-' + d.id + '-' + d.version.toString(),
            ),
            declaration: d,
            role: role,
            extraActions: [
              if (
                superior &&
                d.status == 'PENDIENTE_FIRMA_SUPERIOR'
              )
                _action(d, 'return', 'Devolver'),

              if (
                role == 'rrhh' &&
                d.status == 'ENVIADA_A_RRHH'
              )
                _action(
                  d,
                  'receive',
                  'Recibir',
                  primary: true,
                ),

              if (
                role == 'rrhh' &&
                d.status == 'RECIBIDA_RRHH'
              )
                _action(
                  d,
                  'finish',
                  'Finalizar',
                  primary: true,
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],

        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            if (owner && d.status == 'BORRADOR') ...[
              _action(
                d,
                'validate',
                'Validar',
                primary: true,
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditorPage(existing: d),
                  ),
                ),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                ),
                label: const Text('Editar'),
              ),
            ],

            if (owner && d.status == 'DEVUELTA')
              _action(
                d,
                'newVersion',
                'Crear nueva versión',
                primary: true,
              ),

            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TimelinePage(id: d.id),
                ),
              ),
              icon: const Icon(Icons.history, size: 16),
              label: const Text('Historial'),
            ),

            if (d.status == 'BORRADOR')
              OutlinedButton.icon(
                onPressed: _pdfBusy.contains(d.id)
                    ? null
                    : () => _runPdf(d, 'preview'),
                icon: const Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 16,
                ),
                label: const Text('Vista previa PDF'),
              ),

            if (d.status == 'FINALIZADA')
              OutlinedButton.icon(
                onPressed: _pdfBusy.contains(d.id)
                    ? null
                    : () => _runPdf(d, 'open'),
                icon: const Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 16,
                ),
                label: const Text('Abrir PDF archivado'),
              ),

            if (_pdfBusy.contains(d.id))
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }`;

const original = source;

source =
  source.slice(0, start) +
  replacement +
  source.slice(end);

const importLine =
  "import '../widgets/signed_pdf_panel.dart';";

if (!source.includes(importLine)) {
  source = importLine + '\n' + source;
}

const backup = fs.mkdtempSync(
  path.join(os.tmpdir(), 'declara-panel-firmas-')
);

fs.writeFileSync(
  path.join(backup, 'dashboard.dart'),
  original
);

fs.writeFileSync(file, source);

console.log(
  'Panel instalado localmente. Respaldo: ' + backup
);