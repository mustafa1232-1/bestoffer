import fs from "fs/promises";
import path from "path";

import { env } from "./env.js";
import { pool, q } from "./db.js";

const migrationsDir = path.resolve(process.cwd(), "sql");
const migrationTable = "schema_migration";
const migrationLockKey = 719_244_381;
const migrationSplitMarker = /^\s*--\s*@SPLIT\s*$/gim;
const numberedSqlMigrationFilePattern = /^\d+[a-z]?(?:_.*)?\.sql$/i;
const migrationQueryOptions = {
  query_timeout: 120_000,
  statement_timeout: 120_000,
};

function asSqlIdentifier(identifier) {
  const normalized = String(identifier || "").trim();
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(normalized)) {
    throw new Error(`INVALID_SQL_IDENTIFIER: ${normalized}`);
  }
  return `"${normalized.replace(/"/g, "\"\"")}"`;
}

const migrationTableId = asSqlIdentifier(migrationTable);

async function ensureMigrationTable() {
  await q(`
    CREATE TABLE IF NOT EXISTS ${migrationTableId} (
      id BIGSERIAL PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
}

async function ensureBootstrapTablesBeforePushTokenSurfaceMigration() {
  // Migration 124 assumes `user_push_token` exists after the core auth tables
  // have already been created. Fresh-database upgrades reach this point only
  // after `app_user` and `user_session` exist, so we bootstrap the table right
  // before the migration instead of rewriting historical files.
  await q(`
    CREATE TABLE IF NOT EXISTS user_push_token (
      id              BIGSERIAL PRIMARY KEY,
      user_id         BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
      push_token      TEXT NOT NULL UNIQUE,
      platform        VARCHAR(24),
      app_version     VARCHAR(48),
      device_model    VARCHAR(120),
      locale          VARCHAR(8),
      auth_session_id BIGINT REFERENCES user_session(id) ON DELETE SET NULL,
      app_surface     VARCHAR(24),
      device_fingerprint TEXT,
      is_active       BOOLEAN NOT NULL DEFAULT TRUE,
      last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
}

function splitMigrationSql(sql) {
  return String(sql || "")
    .split(migrationSplitMarker)
    .map((chunk) => chunk.trim())
    .filter(Boolean);
}

export function isNumberedSqlMigrationFileName(fileName) {
  return numberedSqlMigrationFilePattern.test(String(fileName || "").trim());
}

export async function runSqlMigrations({ force = false } = {}) {
  const shouldSkipForcedRailwayScriptRun =
    force &&
    env.externalRailwayScriptRuntime &&
    !["1", "true", "yes", "on"].includes(
      String(process.env.E2E_FORCE_SQL_MIGRATIONS || "").trim().toLowerCase()
    );
  if (shouldSkipForcedRailwayScriptRun) return;
  if (!force && !env.runSqlMigrations) return;

  await ensureMigrationTable();

  let entries = [];
  try {
    entries = await fs.readdir(migrationsDir, { withFileTypes: true });
  } catch (error) {
    console.warn(`[migrate] SQL directory not found: ${migrationsDir}`);
    return;
  }

  const files = entries
    .filter(
      (entry) =>
        entry.isFile() && isNumberedSqlMigrationFileName(entry.name)
    )
    .map((entry) => entry.name)
    .sort((a, b) =>
      a.localeCompare(b, undefined, {
        numeric: true,
        sensitivity: "base",
      })
    );

  const client = await pool.connect();
  let migrationError = null;
  try {
    await client.query({
      text: "SELECT pg_advisory_lock($1)",
      values: [migrationLockKey],
      ...migrationQueryOptions,
    });

    for (const fileName of files) {
      if (fileName.startsWith("124_")) {
        await ensureBootstrapTablesBeforePushTokenSurfaceMigration();
      }
      const alreadyApplied = await client.query({
        text: `SELECT 1 FROM ${migrationTableId} WHERE name = $1`,
        values: [fileName],
        ...migrationQueryOptions,
      });
      if (alreadyApplied.rowCount > 0) continue;

      const fullPath = path.join(migrationsDir, fileName);
      const sql = (await fs.readFile(fullPath, "utf8")).trim();

      if (!sql) {
        await client.query({
          text: `INSERT INTO ${migrationTableId} (name)
           VALUES ($1)
           ON CONFLICT (name) DO NOTHING`,
          values: [fileName],
          ...migrationQueryOptions,
        });
        console.log(`[migrate] skipped empty file ${fileName}`);
        continue;
      }

      const statements = splitMigrationSql(sql);
      for (const statement of statements) {
        await client.query({
          text: statement,
          ...migrationQueryOptions,
        });
      }
      await client.query({
        text: `INSERT INTO ${migrationTableId} (name)
         VALUES ($1)
         ON CONFLICT (name) DO NOTHING`,
        values: [fileName],
        ...migrationQueryOptions,
      });
      console.log(`[migrate] applied ${fileName}`);
    }
  } catch (error) {
    migrationError = error;
    try {
      await client.query({
        text: "ROLLBACK",
        ...migrationQueryOptions,
      });
    } catch {
      // Ignore rollback failures; we want the original migration error.
    }
    throw error;
  } finally {
    try {
      await client.query({
        text: "SELECT pg_advisory_unlock($1)",
        values: [migrationLockKey],
        ...migrationQueryOptions,
      });
    } catch (unlockError) {
      if (!migrationError) throw unlockError;
      console.error("[migrate] advisory unlock skipped after migration failure:", unlockError);
    } finally {
      client.release();
    }
  }
}
