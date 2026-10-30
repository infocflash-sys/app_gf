import * as ftp from 'basic-ftp';
import { config } from './config.js';

/**
 * Pool chico de conexiones FTP. El FTP del hosting no tolera muchas conexiones
 * simultáneas, así que las pedidas por encima del tope esperan en cola.
 */
class FtpPool {
  constructor(size) {
    this.size = size;
    this.idle = [];
    this.waiters = [];
    this.total = 0;
  }

  async #connect() {
    const c = new ftp.Client(30_000);
    await c.access({
      host: config.ftp.host,
      user: config.ftp.user,
      password: config.ftp.password,
      secure: false,
    });
    return c;
  }

  acquire() {
    if (this.idle.length) return Promise.resolve(this.idle.pop());
    if (this.total < this.size) {
      this.total += 1;
      return this.#connect().catch((e) => {
        this.total -= 1;
        throw e;
      });
    }
    return new Promise((resolve, reject) => this.waiters.push({ resolve, reject }));
  }

  release(client, broken = false) {
    if (broken) {
      try {
        client.close();
      } catch {}
      this.total -= 1;
      const w = this.waiters.shift();
      if (w) this.acquire().then(w.resolve, w.reject);
      return;
    }
    const w = this.waiters.shift();
    if (w) w.resolve(client);
    else this.idle.push(client);
  }
}

const pool = new FtpPool(config.ftp.poolSize);
const isNotFound = (e) => e instanceof ftp.FTPError && e.code === 550;

/** Ejecuta fn con una conexión; si la conexión estaba caída reintenta una vez con otra nueva. */
async function withClient(fn) {
  for (let attempt = 0; ; attempt++) {
    const client = await pool.acquire();
    try {
      const out = await fn(client);
      pool.release(client);
      return out;
    } catch (e) {
      if (isNotFound(e)) {
        pool.release(client);
        throw e;
      }
      pool.release(client, true);
      if (attempt >= 1) throw e;
    }
  }
}

/** Tamaño en bytes, o null si el archivo no existe. */
export async function ftpSize(path) {
  try {
    return await withClient((c) => c.size(path));
  } catch (e) {
    if (isNotFound(e)) return null;
    throw e;
  }
}

/** Descarga a un archivo local. */
export async function ftpDownload(remotePath, localPath) {
  await withClient((c) => c.downloadTo(localPath, remotePath));
}
