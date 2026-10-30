process.env.DB_HOST ||= 'x';
process.env.DB_USER ||= 'x';
process.env.DB_PASS ||= 'x';
process.env.DB_NAME ||= 'x';
process.env.FTP_USER ||= 'x';
process.env.FTP_PASS ||= 'x';
process.env.JWT_SECRET ||= 'test-secret';
process.env.CACHE_DIR ||= './cache-test';

import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const { ionAuthVerify, welcomeName } = await import('../src/auth.js');
const { safeName, dedupeEvents, toIso } = await import('../src/util.js');

const hashOf = (pw, salt) =>
  salt + crypto.createHash('sha1').update(salt + pw).digest('hex').slice(0, -10);

test('ionAuthVerify acepta la clave correcta y rechaza otras', () => {
  const h = hashOf('abcd1234', '48781a2b3c');
  assert.equal(h.length, 40);
  assert.equal(ionAuthVerify('abcd1234', h), true);
  assert.equal(ionAuthVerify('abcd1235', h), false);
  assert.equal(ionAuthVerify('', h), false);
  assert.equal(ionAuthVerify('abcd1234', 'corto'), false);
  assert.equal(ionAuthVerify(null, h), false);
});

test('safeName bloquea rutas y extensiones no permitidas', () => {
  assert.equal(safeName('1793205049206.jpg', ['jpg']), '1793205049206.jpg');
  assert.equal(safeName('firma_1793231631837.jpg', ['jpg']), 'firma_1793231631837.jpg');
  assert.equal(safeName('191617-1.pdf', ['pdf']), '191617-1.pdf');
  assert.equal(safeName('../../etc/passwd', ['jpg']), null);
  assert.equal(safeName('a/b.jpg', ['jpg']), null);
  assert.equal(safeName('a..b.jpg', ['jpg']), null);
  assert.equal(safeName('foto.exe', ['jpg']), null);
  assert.equal(safeName('', ['jpg']), null);
  assert.equal(safeName(null, ['jpg']), null);
});

test('dedupeEvents une repetidos del mismo minuto y conserva la foto', () => {
  const ev = [
    { id: 3, estadoId: 13, fecha: '2026-08-07T16:03:00-03:00', foto: true, firma: false, fotoEventoId: 3 },
    { id: 2, estadoId: 79, fecha: '2026-08-07T01:53:10-03:00', foto: false, firma: false, fotoEventoId: 2 },
    { id: 1, estadoId: 79, fecha: '2026-08-07T01:53:40-03:00', foto: false, firma: false, fotoEventoId: 1 },
    { id: 0, estadoId: 79, fecha: '2026-08-06T01:53:40-03:00', foto: false, firma: false, fotoEventoId: 0 },
  ];
  const out = dedupeEvents(ev);
  assert.equal(out.length, 3);
  assert.equal(out[0].foto, true);
});

test('toIso agrega la zona horaria de Argentina', () => {
  assert.equal(toIso('2026-08-07 16:03:00'), '2026-08-07T16:03:00-03:00');
  assert.equal(toIso(null), null);
});

test('welcomeName: un cliente usa su nombre; varios clientes usan el nombre del usuario', () => {
  const user = { username: 'GRUPOCEL', nombre: 'Ana ', apellido: ' Pérez ' };
  assert.equal(welcomeName([{ nombre: 'CELSUR SA' }], user), 'CELSUR SA');
  assert.equal(welcomeName([{ nombre: 'CELSUR SA' }, { nombre: 'CELSUR LOGISTICA' }], user), 'Ana Pérez');
  // sin nombre cargado se usa el usuario
  assert.equal(welcomeName([{ nombre: 'A' }, { nombre: 'B' }], { username: 'GRUPOCEL', nombre: ' ', apellido: null }), 'GRUPOCEL');
});
