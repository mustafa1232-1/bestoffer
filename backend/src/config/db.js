// src/config/db.js
import pg from "pg";

export const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  idleTimeoutMillis: 30_000,
});

export async function q(text, params) {
  const res = await pool.query(text, params);
  return res;
}