// Prepares the QA database layout used by the test suite.
//
// 1. Drops per-file databases left over from an earlier (possibly killed) run
//    so disk usage stays bounded to a single run.
// 2. Ensures a fully migrated template database exists, which each test file
//    then clones cheaply. Migrations run ONCE per run instead of once per file.
//
// Run automatically via the `pretest` npm hook.

import { spawn } from "node:child_process";
import pg from "pg";

import {
  QA_DB_PREFIX,
  TEMPLATE_DB_NAME,
  withDatabase,
} from "./qa-db-isolation.mjs";

const baseUrl = process.env.DATABASE_URL;
if (!baseUrl) {
  console.error("[qa-db] DATABASE_URL is required (expected from .env.test)");
  process.exitCode = 1;
} else {
  const admin = new pg.Client({ connectionString: baseUrl });
  await admin.connect();

  try {
    const leftovers = await admin.query(
      `SELECT datname FROM pg_database WHERE datname LIKE $1`,
      [`${QA_DB_PREFIX}%`]
    );
    for (const row of leftovers.rows) {
      await admin.query(`DROP DATABASE IF EXISTS "${row.datname}"`);
    }
    if (leftovers.rowCount > 0) {
      console.log(`[qa-db] dropped ${leftovers.rowCount} leftover test databases`);
    }

    // Rebuild the template from scratch each run so a half-migrated template can
    // never silently poison every file.
    await admin.query(`DROP DATABASE IF EXISTS "${TEMPLATE_DB_NAME}"`);
    await admin.query(`CREATE DATABASE "${TEMPLATE_DB_NAME}"`);
    console.log(`[qa-db] migrating template "${TEMPLATE_DB_NAME}"...`);
  } finally {
    await admin.end().catch(() => {});
  }

  const templateUrl = withDatabase(baseUrl, TEMPLATE_DB_NAME);
  const exitCode = await new Promise((resolve) => {
    const child = spawn(
      process.execPath,
      ["src/scripts/migrate.js"],
      {
        stdio: ["ignore", "pipe", "inherit"],
        env: {
          ...process.env,
          DATABASE_URL: templateUrl,
          MERCHANT_REVIEW_MIGRATION_DATABASE_URL: templateUrl,
        },
      }
    );
    // Migration chatter is noisy; only surface the tail on failure.
    const buffered = [];
    child.stdout.on("data", (chunk) => buffered.push(String(chunk)));
    child.on("close", (code) => {
      if (code !== 0) process.stdout.write(buffered.join(""));
      resolve(code ?? 1);
    });
  });

  if (exitCode !== 0) {
    console.error("[qa-db] template migration failed");
    process.exitCode = exitCode;
  } else {
    console.log("[qa-db] template ready");
  }
}
