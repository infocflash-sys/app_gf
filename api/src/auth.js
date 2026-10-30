import crypto from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import { config } from './config.js';
import { query } from './db.js';
import { TtlCache } from './util.js';

const key = new TextEncoder().encode(config.jwtSecret);
const sessions = new TtlCache(2000);
const SESSION_TTL_MS = 60_000; // el estado activo se revalida como máximo cada minuto

const MESSAGES = {
  ACCOUNT_DISABLED: 'Tu cuenta no está habilitada. Comunicate con Grupo Flash.',
  NOT_CLIENT: 'Esta aplicación es solo para clientes.',
  CLIENT_DISABLED: 'Tu cuenta de cliente no está activa. Comunicate con Grupo Flash.',
  REVOKED: 'Tu sesión ya no es válida. Ingresá nuevamente.',
};

/**
 * Verifica la clave con el esquema de Ion Auth que usa el ERP:
 * hash = sal(10) + sha1(sal + clave) sin los últimos 10 caracteres.
 */
export function ionAuthVerify(password, stored) {
  if (typeof password !== 'string' || typeof stored !== 'string' || stored.length !== 40) return false;
  const salt = stored.slice(0, 10);
  const calc = salt + crypto.createHash('sha1').update(salt + password).digest('hex').slice(0, -10);
  const a = Buffer.from(calc);
  const b = Buffer.from(stored);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** Huella de la clave: si la clave cambia en el ERP, las sesiones viejas dejan de valer. */
const fingerprint = (hash) =>
  crypto.createHmac('sha256', config.jwtSecret).update(hash || '').digest('hex').slice(0, 16);

async function loadAccount(userId) {
  const [u] = await query(
    'SELECT id, active, password, username, nombre, apellido FROM users WHERE id = ? LIMIT 1',
    [userId],
  );
  if (!u) return null;
  const groups = (await query('SELECT group_id FROM users_groups WHERE user_id = ?', [userId])).map(
    (r) => r.group_id,
  );
  const clientes = await query(
    'SELECT id, nombre, cliente_estado_id AS estado FROM flash_clientes WHERE user_id = ?',
    [userId],
  );
  return {
    id: u.id,
    username: u.username,
    nombre: u.nombre,
    apellido: u.apellido,
    active: Number(u.active) === 1,
    hash: u.password,
    isCliente: groups.includes(config.groupCliente),
    clientes,
  };
}

/** Reglas de acceso: usuario activo, del grupo Cliente y con al menos un cliente Activo. */
function evaluate(acc) {
  if (!acc || !acc.active) return { ok: false, code: 'ACCOUNT_DISABLED' };
  if (!acc.isCliente) return { ok: false, code: 'NOT_CLIENT' };
  const activos = acc.clientes.filter((c) => Number(c.estado) === config.clienteActivo);
  if (!activos.length) return { ok: false, code: 'CLIENT_DISABLED' };
  const clientes = activos.map((c) => ({ id: c.id, nombre: String(c.nombre).trim() }));
  return {
    ok: true,
    userId: acc.id,
    fp: fingerprint(acc.hash),
    nombre: welcomeName(clientes, acc),
    clientes,
  };
}

/**
 * Nombre para la bienvenida: con un solo cliente, el nombre del cliente;
 * si el usuario tiene varios clientes, el nombre del usuario (o su usuario si no tiene nombre cargado).
 */
export function welcomeName(clientes, user) {
  if (clientes.length <= 1) return clientes[0].nombre;
  const full = `${user.nombre ?? ''} ${user.apellido ?? ''}`.replace(/\s+/g, ' ').trim();
  return full || String(user.username ?? '').trim() || clientes[0].nombre;
}

export const messageFor = (code) => MESSAGES[code] || 'No se pudo validar la sesión.';

async function sign(claims, ttl, typ) {
  return new SignJWT({ ...claims, typ })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(ttl)
    .sign(key);
}

export async function issueTokens(s) {
  const claims = { sub: String(s.userId), fp: s.fp };
  return {
    accessToken: await sign(claims, config.accessTtl, 'access'),
    refreshToken: await sign(claims, config.refreshTtl, 'refresh'),
  };
}

export const profileOf = (s) => ({
  cliente: s.nombre, // nombre para la bienvenida (ver welcomeName)
  clientes: s.clientes,
});

// ---- bloqueo por intentos fallidos (en memoria) ----
const fails = new Map();
const MAX_FAILS = 5;
const LOCK_MS = 5 * 60_000;

function locked(user) {
  const f = fails.get(user.toLowerCase());
  return f && f.until > Date.now();
}
function registerFail(user) {
  const k = user.toLowerCase();
  const f = fails.get(k) || { n: 0, until: 0 };
  f.n += 1;
  if (f.n >= MAX_FAILS) {
    f.until = Date.now() + LOCK_MS;
    f.n = 0;
  }
  fails.set(k, f);
}

export async function login(username, password) {
  const user = String(username || '').trim();
  if (!user || !password) return { error: 'Completá usuario y clave.', code: 'EMPTY', status: 400 };
  if (locked(user)) {
    return { error: 'Demasiados intentos. Probá de nuevo en unos minutos.', code: 'LOCKED', status: 429 };
  }
  const [row] = await query('SELECT id FROM users WHERE username = ? LIMIT 1', [user]);
  const acc = row ? await loadAccount(row.id) : null;
  // la clave se verifica ANTES de decir nada sobre el estado de la cuenta
  if (!acc || !ionAuthVerify(password, acc.hash)) {
    registerFail(user);
    return { error: 'Usuario o clave incorrectos.', code: 'BAD_CREDENTIALS', status: 401 };
  }
  fails.delete(user.toLowerCase());
  const s = evaluate(acc);
  if (!s.ok) return { error: messageFor(s.code), code: s.code, status: 403 };
  sessions.delete(String(s.userId));
  return { session: s };
}

/** Estado vigente de una sesión (con caché corta). */
export async function getSession(userId, fp) {
  const s = await sessions.get(String(userId), SESSION_TTL_MS, async () => evaluate(await loadAccount(userId)));
  if (!s.ok) return s;
  if (fp && s.fp !== fp) return { ok: false, code: 'REVOKED' };
  return s;
}

async function verify(token, typ) {
  const { payload } = await jwtVerify(token, key, { algorithms: ['HS256'] });
  if (payload.typ !== typ) throw new Error('tipo de token incorrecto');
  return payload;
}

export async function refresh(refreshToken) {
  let p;
  try {
    p = await verify(refreshToken, 'refresh');
  } catch {
    return { error: 'Sesión no válida.', code: 'BAD_TOKEN', status: 401 };
  }
  const s = await getSession(Number(p.sub), p.fp);
  if (!s.ok) return { error: messageFor(s.code), code: s.code, status: s.code === 'REVOKED' ? 401 : 403 };
  return { session: s };
}

/** preHandler de Fastify: exige sesión válida y deja req.session con los clientes habilitados. */
export async function authenticate(req, reply) {
  const m = /^Bearer (.+)$/.exec(req.headers.authorization || '');
  if (!m) return reply.code(401).send({ error: 'Sesión requerida.', code: 'NO_TOKEN' });
  let p;
  try {
    p = await verify(m[1], 'access');
  } catch (e) {
    const expired = e?.code === 'ERR_JWT_EXPIRED';
    return reply.code(401).send({
      error: expired ? 'Sesión vencida.' : 'Sesión no válida.',
      code: expired ? 'TOKEN_EXPIRED' : 'BAD_TOKEN',
    });
  }
  const s = await getSession(Number(p.sub), p.fp);
  if (!s.ok) {
    return reply
      .code(s.code === 'REVOKED' ? 401 : 403)
      .send({ error: messageFor(s.code), code: s.code });
  }
  req.session = s;
}
