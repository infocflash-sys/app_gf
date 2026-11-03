import { config } from './config.js';
import { ident, query } from './db.js';
import { TtlCache, toIso } from './util.js';

const R = ident(config.ruteoDb);
const POS_TTL_MS = 15_000;
const circuitCache = new TtlCache(2000);
const recentCache = new TtlCache(2000);
// La app del cartero captura una coordenada cada 20 s pero sube el lote una vez por minuto.
const RECENT_TRAIL_MAX = 3;

// ---------------------------------------------------------------------------
// Lógica pura (con tests)
// ---------------------------------------------------------------------------

/**
 * Elige el punto de la pieza dentro del recorrido: si la pieza espera un retiro se muestra el retiro,
 * si no la entrega (y si solo hay retiro, el retiro). Las coordenadas vienen como texto en la DB.
 */
export function pickStop(rows, estadoNombre = '') {
  const stops = rows
    .filter((r) => r.tipo === 'ENTREGA' || r.tipo === 'RETIRO')
    .map((r) => ({ tipo: r.tipo, lat: parseFloat(r.latitud), lng: parseFloat(r.longitud), orden: r.orden_recorrido }))
    .filter((s) => Number.isFinite(s.lat) && Number.isFinite(s.lng) && (s.lat !== 0 || s.lng !== 0));
  const retiro = stops.find((s) => s.tipo === 'RETIRO');
  const entrega = stops.find((s) => s.tipo === 'ENTREGA');
  if (/retiro/i.test(estadoNombre) && retiro) return retiro;
  return entrega || retiro || null;
}

/** Posición del vehículo con su antigüedad y si se considera "sin señal reciente". */
export function describePosition(pos, nowMs = Date.now()) {
  if (!pos) return null;
  const segundos = Math.max(0, Math.round((nowMs - new Date(pos.fecha).getTime()) / 1000));
  return {
    lat: pos.lat,
    lng: pos.lng,
    fecha: toIso(pos.fechaDb),
    segundos,
    sinSenal: segundos > config.segundosSinSenal,
  };
}

// ---------------------------------------------------------------------------
// Última posición de cada cartero: UNA consulta compartida para todos los que se están mirando,
// sin importar cuántos usuarios la pidan (ventana de 24 h, desempate por id).
// ---------------------------------------------------------------------------
const positions = new Map(); // carteroId -> { lat, lng, fecha(ms), fechaDb } | null
const demand = new Map(); // carteroId -> última vez que alguien lo pidió
let refreshing = null;
let lastRefresh = 0;

async function refreshPositions() {
  const now = Date.now();
  for (const [id, t] of demand) if (now - t > 120_000) demand.delete(id); // ya nadie lo mira
  const ids = [...demand.keys()];
  if (!ids.length) return;
  const rows = await query(
    `SELECT g.id, g.cartero_id, g.Latitude AS lat, g.Longitude AS lng, g.FechaLocal AS fecha
     FROM cartero_gps g
     JOIN (SELECT cartero_id, MAX(FechaLocal) AS m
           FROM cartero_gps
           WHERE FechaLocal >= NOW() - INTERVAL 24 HOUR AND cartero_id IN (?)
           GROUP BY cartero_id) x ON x.cartero_id = g.cartero_id AND x.m = g.FechaLocal
     WHERE g.FechaLocal >= NOW() - INTERVAL 24 HOUR`,
    [ids],
  );
  const best = new Map();
  for (const r of rows) {
    const cur = best.get(r.cartero_id);
    if (!cur || r.id > cur.id) best.set(r.cartero_id, r);
  }
  for (const id of ids) {
    const r = best.get(id);
    positions.set(
      id,
      r ? { lat: Number(r.lat), lng: Number(r.lng), fecha: new Date(toIso(r.fecha)).getTime(), fechaDb: r.fecha } : null,
    );
  }
}

function runRefresh() {
  return (refreshing ??= refreshPositions().finally(() => {
    refreshing = null;
    lastRefresh = Date.now();
  }));
}

export async function positionOf(carteroId) {
  demand.set(carteroId, Date.now());
  if (Date.now() - lastRefresh > POS_TTL_MS) await runRefresh();
  // si este cartero recién empezó a pedirse, la consulta en curso quizá no lo incluía
  for (let i = 0; i < 2 && !positions.has(carteroId); i++) await runRefresh();
  return positions.get(carteroId) ?? null;
}

/**
 * Hasta las últimas RECENT_TRAIL_MAX posiciones del cartero (de más vieja a más nueva).
 * Mismo criterio que en api_php: en vez de animar solo la lectura más nueva y quedar
 * "congelada" hasta la próxima subida (una vez por minuto), se arma la cadena real.
 */
export async function recentPositions(carteroId) {
  return recentCache.get(`r:${carteroId}`, POS_TTL_MS, async () => {
    const rows = await query(
      `SELECT Latitude AS lat, Longitude AS lng, FechaLocal AS fecha
       FROM cartero_gps
       WHERE cartero_id = ? AND FechaLocal >= NOW() - INTERVAL 24 HOUR
       ORDER BY FechaLocal DESC, id DESC LIMIT ${RECENT_TRAIL_MAX}`,
      [carteroId],
    );
    return rows.reverse().map((r) => ({ lat: Number(r.lat), lng: Number(r.lng), fecha: toIso(r.fecha) }));
  });
}

// ---------------------------------------------------------------------------
// Circuito: flash_piezas.id -> ruteo.piezas.pieza_id -> ruteo.piezas.id -> asignacion.pieza_id
//           -> asignacion.grupo_asignacion_id (= recorrido) -> grupo_asignacion.id (estado 0) -> id_cartero
// ---------------------------------------------------------------------------
async function circuitOf(piezaId) {
  return circuitCache.get(`c:${piezaId}`, 10_000, async () => {
    const [row] = await query(
      `SELECT rp.id AS rid, a.grupo_asignacion_id AS recorrido, ga.id_cartero AS cartero
       FROM ${R}.piezas rp
       JOIN ${R}.asignacion a ON a.pieza_id = rp.id
       JOIN ${R}.grupo_asignacion ga ON ga.id = a.grupo_asignacion_id
       WHERE rp.pieza_id = ? AND ga.estado = ?
       ORDER BY ga.id DESC LIMIT 1`,
      [piezaId, config.recorridoAbierto],
    );
    return row || null;
  });
}

/** Ids (de flash_piezas) que están hoy en un recorrido abierto, para marcar "en vivo" en la lista. */
export async function liveIds(piezaIds) {
  if (!piezaIds.length) return new Set();
  const rows = await query(
    `SELECT DISTINCT rp.pieza_id
     FROM ${R}.piezas rp
     JOIN ${R}.asignacion a ON a.pieza_id = rp.id
     JOIN ${R}.grupo_asignacion ga ON ga.id = a.grupo_asignacion_id
     WHERE rp.pieza_id IN (?) AND ga.estado = ?`,
    [piezaIds, config.recorridoAbierto],
  );
  return new Set(rows.map((r) => r.pieza_id));
}

/** El seguimiento en vivo solo existe mientras la pieza está "En distribución". */
export const enDistribucion = (estadoId) => Number(estadoId) === config.estadoEnDistribucion;

/**
 * Seguimiento de una pieza. Solo se busca la posición del móvil si se cumplen las dos condiciones:
 *  1) la pieza está "En distribución", y
 *  2) su recorrido está ABIERTO (ruteo.grupo_asignacion.estado = 0).
 */
export async function trackingOf(piezaId, { estadoId, estado = '' } = {}) {
  if (!enDistribucion(estadoId)) return { activo: false };
  const c = await circuitOf(piezaId);
  if (!c) return { activo: false };

  const detalle = await query(
    `SELECT tipo, latitud, longitud, orden_recorrido
     FROM ${R}.grupo_asignacion_pieza_detalle
     WHERE grupo_asignacion_id = ? AND pieza_id = ?`,
    [c.recorrido, c.rid],
  );
  const stop = pickStop(detalle, estado);
  const pos = c.cartero ? await positionOf(c.cartero) : null;

  return {
    activo: true,
    recorrido: c.recorrido,
    tipo: stop?.tipo ?? null,
    destino: stop ? { lat: stop.lat, lng: stop.lng } : null,
    vehiculo: describePosition(pos),
    puntosRecientes: c.cartero ? await recentPositions(c.cartero) : [],
  };
}
