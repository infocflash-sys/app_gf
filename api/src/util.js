/** Fecha de la DB ("YYYY-MM-DD HH:mm:ss", hora de Argentina) a ISO con offset. */
export const toIso = (s) => (s ? String(s).replace(' ', 'T') + '-03:00' : null);

/** Nombre de archivo seguro: evita rutas relativas y caracteres raros. */
export function safeName(name, extensions) {
  if (typeof name !== 'string') return null;
  const n = name.trim();
  if (!/^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,100}$/.test(n) || n.includes('..')) return null;
  if (extensions) {
    const ext = n.split('.').pop().toLowerCase();
    if (!extensions.includes(ext)) return null;
  }
  return n;
}

/**
 * Quita eventos repetidos: mismo estado dentro del mismo minuto.
 * Espera la lista ordenada del más nuevo al más viejo.
 */
export function dedupeEvents(events) {
  const out = [];
  for (const e of events) {
    const prev = out[out.length - 1];
    const same =
      prev &&
      prev.estadoId === e.estadoId &&
      Math.abs(new Date(prev.fecha) - new Date(e.fecha)) < 60_000;
    if (same) {
      // si el repetido trae foto o firma y el que quedó no, conservarlas
      prev.foto ||= e.foto;
      prev.firma ||= e.firma;
      prev.fotoEventoId ??= e.fotoEventoId;
      continue;
    }
    out.push({ ...e });
  }
  return out;
}

export class TtlCache {
  constructor(max = 500) {
    this.m = new Map();
    this.inflight = new Map();
    this.max = max;
  }

  /** Devuelve el valor en caché o lo carga una sola vez aunque lo pidan muchos a la vez. */
  async get(key, ttlMs, loader) {
    const hit = this.m.get(key);
    if (hit && hit.exp > Date.now()) return hit.v;
    if (this.inflight.has(key)) return this.inflight.get(key);
    const p = (async () => {
      try {
        const v = await loader();
        this.m.set(key, { v, exp: Date.now() + ttlMs });
        if (this.m.size > this.max) this.m.delete(this.m.keys().next().value);
        return v;
      } finally {
        this.inflight.delete(key);
      }
    })();
    this.inflight.set(key, p);
    return p;
  }

  delete(key) {
    this.m.delete(key);
  }
}
