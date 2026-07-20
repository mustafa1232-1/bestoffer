// Per-test-file database provisioning.
//
// Loaded with `node --import` so it runs BEFORE the test file's own imports —
// critical, because src/config/db.js builds its pool from env.databaseUrl at
// import time. By the time any module is loaded, DATABASE_URL already points at
// this file's private clone of the migrated template.
//
// Cloning is a filesystem copy in Postgres, so it is far cheaper than replaying
// every migration per file.

import pg from "pg";

import {
  TEMPLATE_DB_NAME,
  assertSafeDatabaseName,
  databaseNameForTestFile,
  parseDatabaseUrl,
  withDatabase,
} from "./qa-db-isolation.mjs";

const testFilePath = process.argv[1];
const baseUrl = process.env.DATABASE_URL;

// Only provision when we are actually running a test file against a database.
if (testFilePath && baseUrl && /\.test\.m?js$/i.test(testFilePath)) {
  const dbName = assertSafeDatabaseName(databaseNameForTestFile(testFilePath));
  const { database: adminDatabase } = parseDatabaseUrl(baseUrl);

  // Connect to the run's control database to issue CREATE/DROP.
  const admin = new pg.Client({ connectionString: baseUrl });
  await admin.connect();
  try {
    if (adminDatabase === dbName) {
      throw new Error("QA_ISOLATION_CONTROL_DB_COLLISION");
    }
    await admin.query(`DROP DATABASE IF EXISTS "${dbName}"`);

    // Concurrent CREATE ... TEMPLATE calls contend on the template; Postgres
    // reports 55006 when another session is still attached to it. Retry rather
    // than fail the whole file.
    let created = false;
    let lastError = null;
    for (let attempt = 0; attempt < 12 && !created; attempt++) {
      try {
        await admin.query(
          `CREATE DATABASE "${dbName}" TEMPLATE "${TEMPLATE_DB_NAME}"`
        );
        created = true;
      } catch (error) {
        lastError = error;
        if (error?.code !== "55006" && error?.code !== "23505") throw error;
        await new Promise((resolve) => setTimeout(resolve, 150 + attempt * 100));
      }
    }
    if (!created) throw lastError || new Error("QA_ISOLATION_CREATE_FAILED");

    process.env.DATABASE_URL = withDatabase(baseUrl, dbName);
    if (process.env.MERCHANT_REVIEW_MIGRATION_DATABASE_URL) {
      process.env.MERCHANT_REVIEW_MIGRATION_DATABASE_URL =
        process.env.DATABASE_URL;
    }
  } finally {
    await admin.end().catch(() => {});
  }
}
