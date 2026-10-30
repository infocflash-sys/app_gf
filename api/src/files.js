import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import sharp from 'sharp';
import { config } from './config.js';
import { ftpDownload, ftpSize } from './ftp.js';

// Carpetas de imágenes: las recientes están en "acuses"; el resto son históricas.
const IMAGE_FOLDERS = [
  'acuses', 'acuses2', 'acuses4', 'acuses5', 'acuses6', 'acuses_sispoapp', 'eventos', 'ago-sep-24', 'oct-24',
];
const SIZES = { thumb: 360, full: 1280 };

const where = new Map(); // nombre -> carpeta | null (con vencimiento para los no encontrados)
const inflight = new Map();

await fsp.mkdir(config.cacheDir, { recursive: true });
const cachePath = (key, ext) =>
  path.join(config.cacheDir, crypto.createHash('sha1').update(key).digest('hex') + ext);

const exists = (p) => fsp.access(p).then(() => true, () => false);

/** Evita descargar dos veces lo mismo si lo piden varios usuarios a la vez. */
function once(key, fn) {
  if (inflight.has(key)) return inflight.get(key);
  const p = fn().finally(() => inflight.delete(key));
  inflight.set(key, p);
  return p;
}

async function locateImage(name) {
  const known = where.get(name);
  if (known && (known.folder || known.until > Date.now())) return known.folder;
  for (const f of IMAGE_FOLDERS) {
    if ((await ftpSize(`${config.ftp.root}/imagenes/${f}/${name}`)) !== null) {
      where.set(name, { folder: f });
      return f;
    }
  }
  where.set(name, { folder: null, until: Date.now() + 10 * 60_000 });
  return null;
}

/** Imagen reducida y cacheada en disco. Devuelve { file, mime } o null si no existe. */
export async function getImage(name, size = 'thumb') {
  const width = SIZES[size] || SIZES.thumb;
  const out = cachePath(`img:${name}:${width}`, '.jpg');
  if (!(await exists(out))) {
    await once(out, async () => {
      const folder = await locateImage(name);
      if (!folder) return;
      const raw = cachePath(`raw:${name}`, '.bin');
      await ftpDownload(`${config.ftp.root}/imagenes/${folder}/${name}`, raw);
      try {
        // con una sola descarga se generan todos los tamaños
        for (const w of Object.values(SIZES)) {
          const dest = cachePath(`img:${name}:${w}`, '.jpg');
          await sharp(raw).rotate().resize({ width: w, withoutEnlargement: true }).jpeg({ quality: 76 }).toFile(dest);
        }
      } finally {
        await fsp.rm(raw, { force: true });
      }
    });
  }
  return (await exists(out)) ? { file: out, mime: 'image/jpeg' } : null;
}

/** PDF cacheado en disco. Devuelve { file, mime } o null si no existe. */
export async function getPdf(name) {
  const out = cachePath(`pdf:${name}`, '.pdf');
  if (!(await exists(out))) {
    await once(out, async () => {
      const remote = `${config.ftp.root}/archivos/documentacion/${name}`;
      if ((await ftpSize(remote)) === null) return;
      const tmp = out + '.part';
      await ftpDownload(remote, tmp);
      await fsp.rename(tmp, out);
    });
  }
  return (await exists(out)) ? { file: out, mime: 'application/pdf' } : null;
}

export const streamOf = (file) => fs.createReadStream(file);
