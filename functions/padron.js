const { createWriteStream } = require('node:fs');
const { mkdtemp, rm } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const { pipeline } = require('node:stream/promises');
const { getStorage } = require('firebase-admin/storage');

const bucketPadron = 'declarahorario-ucr-cff7a-padron-807844528626';

let descargaPadron;

async function descargarPadron() {
  const directorio = await mkdtemp(join(tmpdir(), 'padron-'));
  const ruta = join(directorio, 'padron.sqlite');

  try {
    const archivo = getStorage()
  .bucket(bucketPadron)
  .file('padron-v2.sqlite');
    await pipeline(archivo.createReadStream(), createWriteStream(ruta));
    return ruta;
  } catch (error) {
    await rm(directorio, { recursive: true, force: true }).catch(() => {});
    throw error;
  }

}

function obtenerRutaPadron() {
  if (process.env.PADRON_SQLITE_PATH) {
    return process.env.PADRON_SQLITE_PATH;
  }

  if (process.env.FUNCTIONS_EMULATOR === 'true') {
    throw new Error('Configurá PADRON_SQLITE_PATH para el emulador.');
  }

  if (!descargaPadron) {
    descargaPadron = descargarPadron().catch((error) => {
      descargaPadron = undefined;
      throw error;
    });
  }

  return descargaPadron;
}

async function consultarNombrePorCedula(cedula) {
  if (typeof cedula !== 'string' || !/^[0-9]{9}$/.test(cedula)) {
    throw new Error('Ingresá una cédula de 9 dígitos.');
  }

  const ruta = await obtenerRutaPadron();
  const db = new DatabaseSync(ruta, { readOnly: true });

  try {
    const fila = db.prepare(
      'SELECT nombre_completo FROM personas WHERE cedula = ?'
    ).get(cedula);

    return fila?.nombre_completo ?? null;
  } finally {
    db.close();
  }
}
async function consultarDatosPorCedula(cedula) {
  if (typeof cedula !== 'string' || !/^[0-9]{9}$/.test(cedula)) {
    throw new Error('Ingresá una cédula de 9 dígitos.');
  }

  const ruta = await obtenerRutaPadron();
  const db = new DatabaseSync(ruta, { readOnly: true });

  try {
    return db.prepare(`
      SELECT nombres, apellidos, nombre_completo AS nombreCompleto
      FROM personas
      WHERE cedula = ?
    `).get(cedula) ?? null;
  } finally {
    db.close();
  }
}

module.exports = { consultarNombrePorCedula, consultarDatosPorCedula };