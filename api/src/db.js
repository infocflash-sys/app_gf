import mysql from 'mysql2/promise';
import { config } from './config.js';

// Pool chico a propósito: el hosting permite 100 conexiones por usuario en total.
export const pool = mysql.createPool({
  ...config.db,
  connectionLimit: 8,
  queueLimit: 200,
  waitForConnections: true,
  dateStrings: true,
  connectTimeout: 15_000,
  enableKeepAlive: true,
});

export const query = async (sql, params = []) => (await pool.query(sql, params))[0];

/** Nombre de base escapado, para consultas entre bases del mismo servidor (ej. intran23_ruteo). */
export const ident = (name) => mysql.escapeId(name);
