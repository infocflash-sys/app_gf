import { config } from './config.js';
import { query } from './db.js';
import { authenticate, issueTokens, login, profileOf, refresh } from './auth.js';
import { getImage, getPdf, streamOf } from './files.js';
import { liveIds, trackingOf } from './tracking.js';
import { TtlCache, dedupeEvents, safeName, toIso } from './util.js';

const cache = new TtlCache(1000);
const DEFINITIVO = config.estadoDefinitivo;

// Pieza -> comprobante de ingreso -> cliente. Todo se filtra por los clientes de la sesión.
const FROM_OWNED = `
  FROM flash_piezas p
  JOIN flash_comprobantes_ingresos ci ON ci.id = p.comprobante_ingreso_id
  LEFT JOIN flash_piezas_estados_variables ev ON ev.id = p.estado_id`;

// En la pieza, localidad y provincia guardan el id de ubicacion_localidades / ubicacion_provincias.
// (si algún registro viejo trae el nombre en texto, se conserva tal cual)
const JOIN_LOC = `
  LEFT JOIN ubicacion_localidades ul ON ul.id = p.localidad_destino
  LEFT JOIN ubicacion_provincias pr ON pr.id = p.provincia_destino`;

const sendFile = (reply, f) =>
  reply
    .header('Cache-Control', 'private, max-age=86400')
    .type(f.mime)
    .send(streamOf(f.file));

const fail = (reply, r) => reply.code(r.status || 400).send({ error: r.error, code: r.code });

const sinceOf = (dias) => {
  const d = new Date(Date.now() - dias * 86_400_000 - 3 * 3_600_000); // hora de Argentina
  return d.toISOString().slice(0, 10);
};

const clean = (v) => (typeof v === 'string' ? v.trim() : '');

const mapPieza = (r) => {
  // El nº de seguimiento que ve el cliente es el código externo; si faltara, el código propio y por último el id.
  const tracking = clean(r.barcode_externo) || clean(r.barcode) || String(r.id);
  return {
    id: r.id,
    tracking,
    remito: clean(r.remito) && clean(r.remito) !== tracking ? clean(r.remito) : null,
    destinatario: r.destinatario,
    localidad: [r.localidad_destino, r.provincia].filter(Boolean).join(', '),
    cantidad: r.cantidad,
    estadoId: r.estado_id,
    estado: r.estado,
    definitivo: Number(r.grp) === DEFINITIVO, // true = tarjeta azul, false = verde (en gestión)
    fecha: toIso(r.fecha),
    actualizado: toIso(r.actualizado),
  };
};

export default async function routes(app) {
  // ---------- autenticación ----------
  app.post(
    '/auth/login',
    { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } },
    async (req, reply) => {
      const r = await login(req.body?.usuario, req.body?.clave);
      if (r.error) return fail(reply, r);
      return { ...(await issueTokens(r.session)), ...profileOf(r.session) };
    },
  );

  app.post('/auth/refresh', async (req, reply) => {
    const r = await refresh(req.body?.refreshToken);
    if (r.error) return fail(reply, r);
    return { ...(await issueTokens(r.session)), ...profileOf(r.session) };
  });

  // Se llama al abrir la app: valida que la cuenta siga activa y devuelve el nombre del cliente.
  app.get('/me', { preHandler: authenticate }, async (req) => profileOf(req.session));

  // ---------- piezas ----------
  app.get('/piezas', { preHandler: authenticate }, async (req) => {
    const ids = req.session.clientes.map((c) => c.id);
    const dias = Math.min(Math.max(parseInt(req.query.dias, 10) || config.piezasDiasDefault, 1), 365);
    const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
    const size = Math.min(Math.max(parseInt(req.query.size, 10) || 30, 1), 100);
    const q = String(req.query.q || '').trim().slice(0, 60);
    const grupo = req.query.grupo; // 'gestion' | 'finalizadas'

    const params = [ids, sinceOf(dias)];
    let filtro = '';
    if (q) {
      // buscador universal: id, código de barras (propio y externo), remito, destinatario, domicilio y localidad
      const like = `%${q}%`;
      filtro += ` AND (p.id = ? OR p.barcode LIKE ? OR p.barcode_externo LIKE ? OR p.remito LIKE ?
                  OR p.destinatario LIKE ? OR p.domicilio LIKE ? OR ul.nombre LIKE ? OR pr.nombre LIKE ?)`;
      params.push(/^\d{1,10}$/.test(q) ? Number(q) : 0, like, like, like, like, like, like, like);
    }
    if (grupo === 'finalizadas') filtro += ` AND ev.pieza_estado_id = ${DEFINITIVO}`;
    if (grupo === 'gestion') filtro += ` AND (ev.pieza_estado_id IS NULL OR ev.pieza_estado_id <> ${DEFINITIVO})`;

    const rows = await query(
      `SELECT p.id, p.barcode, p.barcode_externo, p.remito, p.destinatario,
              COALESCE(ul.nombre, p.localidad_destino) AS localidad_destino, pr.nombre AS provincia,
              p.cantidad, p.estado_id, ev.nombre AS estado, ev.pieza_estado_id AS grp,
              p.\`create\` AS fecha, p.\`update\` AS actualizado
       ${FROM_OWNED} ${JOIN_LOC}
       WHERE ci.cliente_id IN (?) AND p.\`create\` >= ? ${filtro}
       ORDER BY p.id DESC LIMIT ${size + 1} OFFSET ${(page - 1) * size}`,
      params,
    );

    const items = rows.slice(0, size).map(mapPieza);
    // "en vivo" = tiene recorrido abierto en ruteo, sin importar el estado_id (una sola consulta por página)
    const live = await liveIds(items.map((i) => i.id));
    for (const it of items) it.enVivo = live.has(it.id);
    const out = { page, size, hasMore: rows.length > size, items };

    if (page === 1) {
      out.resumen = await cache.get(`res:${ids.join(',')}:${dias}`, 30_000, async () => {
        const g = await query(
          `SELECT ev.pieza_estado_id AS grp, COUNT(*) AS n ${FROM_OWNED}
           WHERE ci.cliente_id IN (?) AND p.\`create\` >= ? GROUP BY ev.pieza_estado_id`,
          [ids, sinceOf(dias)],
        );
        const fin = g.filter((x) => Number(x.grp) === DEFINITIVO).reduce((a, x) => a + x.n, 0);
        const total = g.reduce((a, x) => a + x.n, 0);
        return { total, finalizadas: fin, enGestion: total - fin, dias };
      });
    }
    return out;
  });

  app.get('/piezas/:id', { preHandler: authenticate }, async (req, reply) => {
    const id = parseInt(req.params.id, 10);
    const ids = req.session.clientes.map((c) => c.id);
    const [p] = Number.isInteger(id)
      ? await query(
          `SELECT p.id, p.barcode, p.barcode_externo, p.remito, p.destinatario, p.domicilio, p.piso,
                  p.departamento_oficina, COALESCE(ul.nombre, p.localidad_destino) AS localidad_destino,
                  pr.nombre AS provincia, p.codigo_postal_destino AS cp, p.cantidad, p.docum_file, p.estado_id,
                  ev.nombre AS estado, ev.pieza_estado_id AS grp,
                  p.\`create\` AS fecha, p.\`update\` AS actualizado
           ${FROM_OWNED} ${JOIN_LOC}
           WHERE p.id = ? AND ci.cliente_id IN (?) LIMIT 1`,
          [id, ids],
        )
      : [];
    // si la pieza es de otro cliente se responde igual que si no existiera
    if (!p) return reply.code(404).send({ error: 'Pieza no encontrada.', code: 'NOT_FOUND' });

    const [paq] = await query('SELECT bultos, peso FROM flash_piezas_paquetes WHERE pieza_id = ? LIMIT 1', [id]);
    const tr = await query(
      `SELECT t.id, t.estado_id, ev.nombre AS estado, ev.pieza_estado_id AS grp,
              t.\`create\` AS fecha, t.foto, t.firma_img
       FROM flash_piezas_tracking t
       LEFT JOIN flash_piezas_estados_variables ev ON ev.id = t.estado_id
       WHERE t.pieza_id = ? ORDER BY t.\`create\` DESC, t.id DESC`,
      [id],
    );

    const eventos = dedupeEvents(
      tr.map((t) => ({
        id: t.id,
        estadoId: t.estado_id,
        estado: t.estado,
        definitivo: Number(t.grp) === DEFINITIVO,
        fecha: toIso(t.fecha),
        foto: !!safeName(t.foto, ['jpg', 'jpeg', 'png']),
        firma: !!safeName(t.firma_img, ['jpg', 'jpeg', 'png']),
        fotoEventoId: t.id,
      })),
    ).map(({ fotoEventoId, ...e }) => e);

    const base = mapPieza(p);
    // "en vivo" = tiene recorrido abierto en ruteo, sin importar el estado_id.
    const enVivo = (await liveIds([id])).has(id);
    return {
      ...base,
      enVivo,
      localidad: p.cp ? `${base.localidad} (CP ${p.cp})` : base.localidad,
      domicilio: [p.domicilio, p.piso && `Piso ${p.piso}`, p.departamento_oficina].filter(Boolean).join(', '),
      bultos: paq?.bultos ?? p.cantidad,
      pesoKg: paq?.peso ?? null,
      pdf: !!safeName(p.docum_file, ['pdf']),
      eventos,
    };
  });

  // ---------- archivos (siempre tras comprobar que la pieza es del cliente) ----------
  const owned = async (req, id) => {
    const ids = req.session.clientes.map((c) => c.id);
    const [p] = Number.isInteger(id)
      ? await query(
          `SELECT p.id, p.docum_file FROM flash_piezas p
           JOIN flash_comprobantes_ingresos ci ON ci.id = p.comprobante_ingreso_id
           WHERE p.id = ? AND ci.cliente_id IN (?) LIMIT 1`,
          [id, ids],
        )
      : [];
    return p;
  };
  const notFound = (reply) => reply.code(404).send({ error: 'Archivo no encontrado.', code: 'NOT_FOUND' });

  // kind: "foto" o "firma"; size: "thumb" o "full"
  app.get('/piezas/:id/eventos/:eid/:kind', { preHandler: authenticate }, async (req, reply) => {
    const id = parseInt(req.params.id, 10);
    const eid = parseInt(req.params.eid, 10);
    const { kind } = req.params;
    if (!['foto', 'firma'].includes(kind) || !(await owned(req, id))) return notFound(reply);
    const [t] = await query('SELECT foto, firma_img FROM flash_piezas_tracking WHERE id = ? AND pieza_id = ? LIMIT 1', [eid, id]);
    const name = safeName(kind === 'foto' ? t?.foto : t?.firma_img, ['jpg', 'jpeg', 'png']);
    if (!name) return notFound(reply);
    const f = await getImage(name, req.query.size === 'full' ? 'full' : 'thumb');
    return f ? sendFile(reply, f) : notFound(reply);
  });

  app.get('/piezas/:id/pdf', { preHandler: authenticate }, async (req, reply) => {
    const p = await owned(req, parseInt(req.params.id, 10));
    const name = safeName(p?.docum_file, ['pdf']);
    if (!name) return notFound(reply);
    const f = await getPdf(name);
    return f ? sendFile(reply, f) : notFound(reply);
  });

  // ---------- seguimiento en tiempo real ----------
  // Solo si la pieza es del cliente, está "En distribución" y su recorrido está abierto (estado 0).
  app.get('/piezas/:id/seguimiento', { preHandler: authenticate }, async (req, reply) => {
    const id = parseInt(req.params.id, 10);
    const ids = req.session.clientes.map((c) => c.id);
    const [p] = Number.isInteger(id)
      ? await query(
          `SELECT p.id, p.estado_id, ev.nombre AS estado
           ${FROM_OWNED}
           WHERE p.id = ? AND ci.cliente_id IN (?) LIMIT 1`,
          [id, ids],
        )
      : [];
    if (!p) return reply.code(404).send({ error: 'Pieza no encontrada.', code: 'NOT_FOUND' });
    reply.header('Cache-Control', 'no-store');
    return trackingOf(p.id, { estadoId: p.estado_id, estado: p.estado || '' });
  });
}
