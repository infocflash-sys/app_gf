import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { config } from './config.js';
import { pool } from './db.js';
import routes from './routes.js';

const app = Fastify({ logger: { level: 'info' }, bodyLimit: 20_000 });

await app.register(rateLimit, { max: 600, timeWindow: '1 minute' });

app.get('/health', async () => {
  await pool.query('SELECT 1');
  return { ok: true };
});

await app.register(routes);

app.setErrorHandler((err, req, reply) => {
  if (err.statusCode && err.statusCode < 500) {
    return reply.code(err.statusCode).send({ error: err.message, code: 'REQUEST_ERROR' });
  }
  req.log.error(err);
  reply.code(500).send({ error: 'Error interno. Intentá de nuevo en un momento.', code: 'SERVER_ERROR' });
});

await app.listen({ port: config.port, host: config.host });
