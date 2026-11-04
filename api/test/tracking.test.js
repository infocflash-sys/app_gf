process.env.DB_HOST ||= 'x';
process.env.DB_USER ||= 'x';
process.env.DB_PASS ||= 'x';
process.env.DB_NAME ||= 'x';
process.env.FTP_USER ||= 'x';
process.env.FTP_PASS ||= 'x';
process.env.JWT_SECRET ||= 'test-secret';

import test from 'node:test';
import assert from 'node:assert/strict';

const { pickStop, describePosition } = await import('../src/tracking.js');

// `trackingOf()` ahora siempre consulta `ruteo` (recorrido abierto) antes de mirar el estado_id
// -ya no hay un gate que evite la consulta-, así que ya no se puede probar sin una DB real; queda
// cubierto por las pruebas manuales de lectura hechas al validar la lógica con datos reales.

const detalle = [
  { tipo: 'ORIGEN/DESTINO', latitud: '-24.2064098', longitud: '-65.2832773', orden_recorrido: 1 },
  { tipo: 'RETIRO', latitud: '-24.1973729', longitud: '-65.3100605', orden_recorrido: 2 },
  { tipo: 'ENTREGA', latitud: '-24.1875629', longitud: '-65.2944976', orden_recorrido: 3 },
];

test('pickStop: la entrega por defecto, el retiro si la pieza espera retiro', () => {
  assert.equal(pickStop(detalle, 'En distribucion').tipo, 'ENTREGA');
  assert.equal(pickStop(detalle, 'Pendiente de Retiro').tipo, 'RETIRO');
  assert.equal(pickStop([detalle[1]], 'En distribucion').tipo, 'RETIRO'); // solo hay retiro
  assert.equal(pickStop([detalle[0]], 'x'), null); // el depósito no es un punto de la pieza
  assert.equal(pickStop([], 'x'), null);
});

test('pickStop: convierte las coordenadas de texto y descarta las inválidas', () => {
  const s = pickStop(detalle, 'En distribucion');
  assert.equal(typeof s.lat, 'number');
  assert.ok(Math.abs(s.lat - -24.1875629) < 1e-9);
  assert.equal(pickStop([{ tipo: 'ENTREGA', latitud: '0', longitud: '0', orden_recorrido: 1 }], 'x'), null);
  assert.equal(pickStop([{ tipo: 'ENTREGA', latitud: 'abc', longitud: '1', orden_recorrido: 1 }], 'x'), null);
});

test('describePosition: antigüedad y "sin señal" a los 15 minutos', () => {
  const now = Date.parse('2026-10-29T15:00:00-03:00');
  const fresh = describePosition({ lat: 1, lng: 2, fecha: now - 20_000, fechaDb: '2026-10-29 14:59:40' }, now);
  assert.equal(fresh.segundos, 20);
  assert.equal(fresh.sinSenal, false);
  assert.equal(fresh.fecha, '2026-10-29T14:59:40-03:00');
  const old = describePosition({ lat: 1, lng: 2, fecha: now - 16 * 60_000, fechaDb: '2026-10-29 14:44:00' }, now);
  assert.equal(old.sinSenal, true);
  assert.equal(describePosition(null, now), null);
});
