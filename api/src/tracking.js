import { config } from './config.js';
import { ident, query } from './db.js';
import { TtlCache, toIso } from './util.js';

const R = ident(config.ruteoDb);
const POS_TTL_MS = 15_000;
const circuitCache = new TtlCache(2000);
const recentCache = new TtlCache(2000);
// La app del cartero captura una coordenada cada 20 s pero sube el lote una vez por minuto
// (~3 puntos nuevos por subida). Se piden bastantes más de los 3 mínimos para mantener un colchón
// de lecturas: así la animación nunca se queda sin tramos para encadenar aunque algún sondeo del
// cliente se pierda, y la app arranca con más historial para una curva más fluida.
const RECENT_TRAIL_MAX = 12;

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

/**
 * true si, dentro del mismo recorrido, ninguna otra pieza con parada de ENTREGA todavía
 * pendiente ("En distribución") tiene un orden_recorrido menor que miOrden: o sea, es la
 * próxima que el cartero va a entregar. No mira retiros ni piezas ya resueltas.
 */
const proximaCache = new TtlCache(2000);
async function esProximaEntrega(recorridoId, miOrden) {
  return proximaCache.get(`p:${recorridoId}:${miOrden}`, 10_000, async () => {
    const [row] = await query(
      `SELECT MIN(d.orden_recorrido) AS mino
       FROM ${R}.grupo_asignacion_pieza_detalle d
       JOIN ${R}.piezas rp ON rp.id = d.pieza_id
       JOIN flash_piezas p ON p.id = rp.pieza_id
       WHERE d.grupo_asignacion_id = ? AND d.tipo = 'ENTREGA' AND p.estado_id = ?`,
      [recorridoId, config.estadoEnDistribucion],
    );
    return row?.mino != null && Number(row.mino) === miOrden;
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
 * Despacho abierto (sin recepcionar) que contiene esta pieza: traslado interno entre sucursales
 * (novedades "Enviado a...", "En tránsito", etc.), distinto del recorrido de reparto al
 * destinatario final. `transporte_id` es el id de cartero del transportista asignado (misma
 * tabla `flash_sucursales_carteros`, misma `cartero_gps`).
 */
const despachoCache = new TtlCache(2000);
async function despachoAbiertoDe(piezaId) {
  return despachoCache.get(`d:${piezaId}`, 10_000, async () => {
    const [row] = await query(
      `SELECT d.id AS despacho_id, d.transporte_id, d.destino_id
       FROM flash_piezas_despacho_piezas dp
       JOIN flash_piezas_despacho d ON d.id = dp.despacho_id
       WHERE dp.pieza_id = ? AND d.fecha_recepcion IS NULL
       ORDER BY d.id DESC LIMIT 1`,
      [piezaId],
    );
    return row || null;
  });
}

/** Coordenadas registradas de una sucursal (no todas las tienen cargadas). */
const sucCoordCache = new TtlCache(2000);
async function coordenadasSucursal(sucursalId) {
  return sucCoordCache.get(`s:${sucursalId}`, 300_000, async () => {
    const [row] = await query(
      `SELECT s.nombre, c.latitud, c.longitud
       FROM flash_sucursales_coordenadas c
       JOIN flash_sucursales s ON s.id = c.sucursal_id
       WHERE c.sucursal_id = ? LIMIT 1`,
      [sucursalId],
    );
    return row || null;
  });
}

/** Seguimiento de una pieza en traslado entre sucursales (vía despacho), no en reparto. */
async function trackingPorDespacho(piezaId) {
  const d = await despachoAbiertoDe(piezaId);
  if (!d) return { activo: false };
  const cartero = d.transporte_id ?? null;
  const pos = cartero ? await positionOf(cartero) : null;
  const suc = d.destino_id ? await coordenadasSucursal(d.destino_id) : null;

  return {
    activo: true,
    recorrido: null,
    tipo: 'TRASLADO',
    destino: suc ? { lat: Number(suc.latitud), lng: Number(suc.longitud) } : null,
    destinoNombre: suc?.nombre ?? null,
    vehiculo: describePosition(pos),
    puntosRecientes: cartero ? await recentPositions(cartero) : [],
    proximaEntrega: false,
  };
}

/**
 * Seguimiento de una pieza. Dos circuitos posibles:
 *  1) "En distribución" con recorrido ABIERTO (ruteo.grupo_asignacion.estado = 0): reparto al
 *     destinatario final.
 *  2) Cualquier otro estado con un despacho ABIERTO (traslado entre sucursales, vía
 *     flash_piezas_despacho): el vehículo es el transportista de ese despacho, no un cartero de
 *     reparto, y el destino es la sucursal, no el domicilio.
 */
export async function trackingOf(piezaId, { estadoId, estado = '' } = {}) {
  if (!enDistribucion(estadoId)) return trackingPorDespacho(piezaId);
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

  const mio = detalle.find((d) => d.tipo === 'ENTREGA');
  const miOrden = mio ? Number(mio.orden_recorrido) : null;

  return {
    activo: true,
    recorrido: c.recorrido,
    tipo: stop?.tipo ?? null,
    destino: stop ? { lat: stop.lat, lng: stop.lng } : null,
    vehiculo: describePosition(pos),
    puntosRecientes: c.cartero ? await recentPositions(c.cartero) : [],
    proximaEntrega: miOrden != null ? await esProximaEntrega(c.recorrido, miOrden) : false,
  };
}
