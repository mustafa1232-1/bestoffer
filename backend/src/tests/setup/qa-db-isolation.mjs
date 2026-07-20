// Shared helpers for per-test-file database isolation.
//
// `node --test` runs every test file in its own process, in parallel. They all
// used to share one database, so one file's teardown could delete another
// file's rows mid-test (FK 23503 on app_user / merchant / customer_address).
// Each file now gets its own database cloned from a migrated template, which
// removes that entire class of failure without serialising the suite.

import crypto from "node:crypto";
import path from "node:path";

// Every generated database starts with this prefix so leftovers from a killed
// run can be dropped wholesale before the next one.
export const QA_DB_PREFIX = "qa_f_";
export const TEMPLATE_DB_NAME = "qa_template";

export function parseDatabaseUrl(rawUrl) {
  const url = new URL(String(rawUrl || ""));
  const database = decodeURIComponent(url.pathname.replace(/^\//, ""));
  return { url, database };
}

/** Returns the same connection string pointed at a different database. */
export function withDatabase(rawUrl, databaseName) {
  const url = new URL(String(rawUrl || ""));
  url.pathname = `/${encodeURIComponent(databaseName)}`;
  return url.toString();
}

/**
 * Deterministic per-file database name.
 *
 * Derived from the repo-relative test path so a file always maps to the same
 * database (easy to inspect after a failure) while staying inside Postgres'
 * 63-byte identifier limit.
 */
export function databaseNameForTestFile(testFilePath) {
  const normalized = path
    .relative(process.cwd(), String(testFilePath || ""))
    .split(path.sep)
    .join("/");
  const digest = crypto
    .createHash("sha1")
    .update(normalized)
    .digest("hex")
    .slice(0, 12);
  const slug = path
    .basename(normalized)
    .replace(/\.test\.m?js$/i, "")
    .replace(/[^a-zA-Z0-9]+/g, "_")
    .toLowerCase()
    .slice(0, 32);
  return `${QA_DB_PREFIX}${slug}_${digest}`;
}

export function assertSafeDatabaseName(name) {
  if (!/^[a-z0-9_]+$/.test(String(name || ""))) {
    throw new Error(`UNSAFE_DATABASE_NAME: ${name}`);
  }
  return name;
}
