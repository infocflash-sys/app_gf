// Prueba de punta a punta contra una API en marcha.
// Uso: SMOKE_USER=... SMOKE_PASS=... [API=http://localhost:3000] [OTHER_PIEZA=191610] node scripts/smoke.mjs
const API = process.env.API || 'http://localhost:3000';
const { SMOKE_USER, SMOKE_PASS } = process.env;
const OTHER = process.env.OTHER_PIEZA || '191610'; // pieza de OTRO cliente: no debe verse

let failed = 0;
const check = (name, ok, extra = '') => {
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name} ${extra}`);
  if (!ok) failed++;
};
const call = async (path, opts = {}, token) => {
  const r = await fetch(API + path, {
    ...opts,
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }), ...opts.headers },
  });
  const ct = r.headers.get('content-type') || '';
  return { status: r.status, ct, body: ct.includes('json') ? await r.json() : Buffer.from(await r.arrayBuffer()) };
};

const bad = await call('/auth/login', { method: 'POST', body: JSON.stringify({ usuario: SMOKE_USER, clave: 'incorrecta' }) });
check('login con clave incorrecta -> 401', bad.status === 401, bad.body.code);

const noTok = await call('/piezas');
check('sin token -> 401', noTok.status === 401);

const login = await call('/auth/login', { method: 'POST', body: JSON.stringify({ usuario: SMOKE_USER, clave: SMOKE_PASS }) });
check('login correcto', login.status === 200 && !!login.body.accessToken, `cliente="${login.body.cliente}"`);
if (login.status !== 200) process.exit(1);
const { accessToken, refreshToken } = login.body;

const me = await call('/me', {}, accessToken);
check('/me devuelve el nombre del cliente', me.status === 200 && !!me.body.cliente, me.body.cliente);

const rf = await call('/auth/refresh', { method: 'POST', body: JSON.stringify({ refreshToken }) });
check('refresh de sesión', rf.status === 200 && !!rf.body.accessToken);

const list = await call('/piezas?dias=365', {}, accessToken);
check('lista de piezas', list.status === 200, `items=${list.body.items?.length} resumen=${JSON.stringify(list.body.resumen)}`);
for (const it of list.body.items || []) {
  console.log(`      #${it.id} ${it.tracking} | ${it.estado} | ${it.definitivo ? 'AZUL (definitivo)' : 'VERDE (en gestión)'}`);
}

const other = await call(`/piezas/${OTHER}`, {}, accessToken);
check(`pieza ${OTHER} de otro cliente -> 404`, other.status === 404);
const otherPdf = await call(`/piezas/${OTHER}/pdf`, {}, accessToken);
check(`PDF de pieza ${OTHER} de otro cliente -> 404`, otherPdf.status === 404);

for (const it of list.body.items || []) {
  const d = await call(`/piezas/${it.id}`, {}, accessToken);
  if (d.status !== 200) { check(`detalle ${it.id}`, false); continue; }
  const conFoto = d.body.eventos.filter((e) => e.foto);
  const conFirma = d.body.eventos.filter((e) => e.firma);
  check(`detalle ${it.id}`, true, `eventos=${d.body.eventos.length} fotos=${conFoto.length} firmas=${conFirma.length} pdf=${d.body.pdf}`);
  for (const e of conFoto) {
    const img = await call(`/piezas/${it.id}/eventos/${e.id}/foto?size=thumb`, {}, accessToken);
    check(`  foto del evento ${e.id}`, img.status === 200 && img.ct.startsWith('image/'), `${img.status} ${img.body.length ?? ''} bytes`);
  }
  for (const e of conFirma) {
    const img = await call(`/piezas/${it.id}/eventos/${e.id}/firma?size=thumb`, {}, accessToken);
    check(`  firma del evento ${e.id}`, img.status === 200 && img.ct.startsWith('image/'), `${img.status}`);
  }
  if (d.body.pdf) {
    const pdf = await call(`/piezas/${it.id}/pdf`, {}, accessToken);
    check(`  PDF de la pieza ${it.id}`, pdf.status === 200 && pdf.ct.includes('pdf'), `${pdf.status} ${pdf.body.length ?? ''} bytes`);
  }
}

console.log(failed ? `\n${failed} verificación(es) fallaron` : '\nTodo OK');
process.exit(failed ? 1 : 0);
