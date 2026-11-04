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

/**
 * Estados ("enviado a...") con el despacho todavía EN CIRCULACIÓN (sin recepcionar): las 21
 * variantes "Enviado a <sucursal>"/"Enviado Suc <sucursal>", "En tránsito" y "En tránsito a
 * Cliente". Deliberadamente más angosto que el agrupador `pieza_estado_id = 4` del catálogo (ese
 * grupo mezcla "En distribución", "Pendiente de Retiro/Recepción" y despachos vía Correo, que no
 * aplican acá).
 */
const ESTADOS_EN_TRANSITO = new Set([
  15, 34, 35, 36, 37, 38, 39, 40, 56, 61, 66, 67, 69, 71, 73, 75, 77, 79, 87, 89, 92, 96, 97,
]);

/**
 * Estados "Recibido en <sucursal>" (despacho ya recepcionado, pieza parada en esa sucursal
 * esperando su próximo movimiento). No incluye los "Recibido en/despacho Sucursal de Correo"
 * (33, 52): esos los maneja Correo Argentino y no tienen despacho interno con coordenadas.
 */
const ESTADOS_RECIBIDO_EN_SUCURSAL = new Set([
  41, 42, 43, 44, 45, 46, 57, 60, 64, 65, 70, 72, 74, 76, 78, 80, 88, 90, 94, 98, 99,
]);

/**
 * Despacho que contiene esta pieza (traslado interno entre sucursales), el más reciente que
 * cumpla la condición pedida: abierto=true busca uno EN CIRCULACIÓN (sin recepcionar),
 * abierto=false busca el último YA RECEPCIONADO (para el pin estático en destino). `transporte_id`
 * es el id de cartero del transportista asignado (misma tabla `flash_sucursales_carteros`, misma
 * `cartero_gps`).
 */
const despachoCache = new TtlCache(2000);
async function despachoDe(piezaId, abierto) {
  const cond = abierto ? 'd.fecha_recepcion IS NULL' : 'd.fecha_recepcion IS NOT NULL';
  return despachoCache.get(`d${abierto ? 'a' : 'r'}:${piezaId}`, 10_000, async () => {
    const [row] = await query(
      `SELECT d.id AS despacho_id, d.transporte_id, d.destino_id, d.fecha_recepcion
       FROM flash_piezas_despacho_piezas dp
       JOIN flash_piezas_despacho d ON d.id = dp.despacho_id
       WHERE dp.pieza_id = ? AND ${cond}
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

/** B) Pieza en circulación entre sucursales (despacho sin recepcionar): sigue al transportista. */
async function trackingEnTransito(piezaId) {
  const d = await despachoDe(piezaId, true);
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

/** C) Pieza parada en una sucursal (despacho ya recepcionado): pin fijo, sin vehículo. */
async function trackingEnSucursal(piezaId) {
  const d = await despachoDe(piezaId, false);
  const suc = d?.destino_id ? await coordenadasSucursal(d.destino_id) : null;
  if (!suc) return { activo: false };

  return {
    activo: true,
    recorrido: null,
    tipo: 'EN_SUCURSAL',
    destino: { lat: Number(suc.latitud), lng: Number(suc.longitud) },
    destinoNombre: suc.nombre,
    vehiculo: null,
    puntosRecientes: [],
    proximaEntrega: false,
  };
}

/**
 * Seguimiento de una pieza. Tres circuitos posibles, en este orden de prioridad:
 *  A) Recorrido ABIERTO en ruteo (grupo_asignacion.estado = 0), sin importar el estado_id: cubre
 *     tanto el reparto al destinatario final como el retiro de tipos de gestión 1/2 (el recorrido
 *     de retiro se crea ANTES que la HDR, con la pieza todavía en "Pendiente de Retiro"). Si el
 *     mismo recorrido trae retiro Y entrega (gestión tipo 1, mismo día), se devuelven AMBAS
 *     paradas en `paradas`.
 *  B) Sin recorrido abierto, pero el estado es "Enviado a.../En tránsito" (ESTADOS_EN_TRANSITO):
 *     traslado interno entre sucursales, todavía circulando. Sigue al transportista del despacho,
 *     no a un cartero de reparto.
 *  C) Sin recorrido abierto, estado "Recibido en..." (ESTADOS_RECIBIDO_EN_SUCURSAL): el despacho
 *     ya fue recepcionado. Pin fijo en esa sucursal, sin vehículo (nada se mueve hasta que se le
 *     asigne un nuevo recorrido, que automáticamente vuelve a priorizar A).
 */
export async function trackingOf(piezaId, { estadoId, estado = '' } = {}) {
  const c = await circuitOf(piezaId);
  if (!c) {
    const id = Number(estadoId);
    if (ESTADOS_EN_TRANSITO.has(id)) return trackingEnTransito(piezaId);
    if (ESTADOS_RECIBIDO_EN_SUCURSAL.has(id)) return trackingEnSucursal(piezaId);
    return { activo: false };
  }

  const detalle = await query(
    `SELECT tipo, latitud, longitud, orden_recorrido
     FROM ${R}.grupo_asignacion_pieza_detalle
     WHERE grupo_asignacion_id = ? AND pieza_id = ?`,
    [c.recorrido, c.rid],
  );
  const stop = pickStop(detalle, estado);
  const pos = c.cartero ? await positionOf(c.cartero) : null;

  // Todas las paradas distintas de este recorrido para esta pieza (normalmente 1; en gestión
  // tipo 1 -retiro y entrega el mismo día- puede haber 2: RETIRO y ENTREGA).
  const paradas = [];
  const vistos = new Set();
  let miOrden = null;
  for (const d of detalle) {
    if (d.tipo === 'ENTREGA' && miOrden === null) miOrden = Number(d.orden_recorrido);
    if ((d.tipo === 'RETIRO' || d.tipo === 'ENTREGA') && !vistos.has(d.tipo)) {
      const lat = parseFloat(d.latitud);
      const lng = parseFloat(d.longitud);
      if (Number.isFinite(lat) && Number.isFinite(lng)) {
        vistos.add(d.tipo);
        paradas.push({ tipo: d.tipo, lat, lng });
      }
    }
  }

  return {
    activo: true,
    recorrido: c.recorrido,
    tipo: stop?.tipo ?? null,
    destino: stop ? { lat: stop.lat, lng: stop.lng } : null,
    paradas,
    vehiculo: describePosition(pos),
    puntosRecientes: c.cartero ? await recentPositions(c.cartero) : [],
    proximaEntrega: miOrden != null ? await esProximaEntrega(c.recorrido, miOrden) : false,
  };
}
