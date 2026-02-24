import fs from "fs/promises";
import path from "path";

import { pool, q } from "./db.js";

const migrationsDir = path.resolve(process.cwd(), "sql");
const migrationTable = "schema_migration";

function isEnabledFromEnv() {
  const value = String(process.env.RUN_SQL_MIGRATIONS || "")
    .trim()
    .toLowerCase();
  return value === "1" || value === "true" || value === "yes";
}

async function ensureMigrationTable() {
  await q(`
    CREATE TABLE IF NOT EXISTS ${migrationTable} (
      id BIGSERIAL PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
}

export async function runSqlMigrations({ force = false } = {}) {
  if (!force && !isEnabledFromEnv()) return;

  await ensureMigrationTable();

  let entries = [];
  try {
    entries = await fs.readdir(migrationsDir, { withFileTypes: true });
  } catch (error) {
    console.warn(`[migrate] SQL directory not found: ${migrationsDir}`);
    return;
  }

  const files = entries
    .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".sql"))
    .map((entry) => entry.name)
    .sort((a, b) =>
      a.localeCompare(b, undefined, {
        numeric: true,
        sensitivity: "base",
      })
    );

  for (const fileName of files) {
    const alreadyApplied = await q(
      `SELECT 1 FROM ${migrationTable} WHERE name = $1`,
      [fileName]
    );
    if (alreadyApplied.rowCount > 0) continue;

    const fullPath = path.join(migrationsDir, fileName);
    const sql = (await fs.readFile(fullPath, "utf8")).trim();

    if (!sql) {
      await q(`INSERT INTO ${migrationTable} (name) VALUES ($1)`, [fileName]);
      console.log(`[migrate] skipped empty file ${fileName}`);
      continue;
    }

    const client = await pool.connect();
    try {
      await client.query(sql);
      await client.query(`INSERT INTO ${migrationTable} (name) VALUES ($1)`, [
        fileName,
      ]);
      console.log(`[migrate] applied ${fileName}`);
    } finally {
      client.release();
    }
  }
}
