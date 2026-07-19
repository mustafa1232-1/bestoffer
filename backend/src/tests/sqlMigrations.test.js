import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { isNumberedSqlMigrationFileName } from "../config/sqlMigrations.js";

const repoSqlDir = path.resolve(process.cwd(), "sql");

function isDiagnosticSqlFile(fileName) {
  return String(fileName || "").trim().toLowerCase().startsWith("diag_");
}

function migrationIdFromFileName(fileName) {
  const normalized = String(fileName || "").trim();
  if (!isNumberedSqlMigrationFileName(normalized)) return null;
  return normalized.replace(/\.sql$/i, "");
}

async function scanSqlMigrationInventory(directories) {
  const roots = (Array.isArray(directories) ? directories : [directories])
    .map((dir) => path.resolve(dir))
    .filter(Boolean);
  const inventory = new Map();

  for (const root of roots) {
    const entries = await fs.readdir(root, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isFile()) continue;
      const fileName = entry.name;
      if (isDiagnosticSqlFile(fileName)) continue;
      const migrationId = migrationIdFromFileName(fileName);
      if (migrationId == null) continue;
      const current = inventory.get(migrationId) ?? [];
      current.push(path.join(root, fileName));
      inventory.set(migrationId, current);
    }
  }

  return inventory;
}

function assertUniqueSqlMigrationInventory(inventory) {
  const duplicates = [...inventory.entries()].filter(([, fileNames]) => fileNames.length > 1);
  if (duplicates.length > 0) {
    const summary = duplicates
      .map(([migrationId, fileNames]) => `${migrationId}: ${fileNames.join(", ")}`)
      .join("\n");
    throw new Error(`DUPLICATE_SQL_MIGRATIONS\n${summary}`);
  }
}

async function createTempSqlTree(filesByName) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "sql-migrations-"));
  for (const [fileName, contents] of Object.entries(filesByName)) {
    await fs.writeFile(path.join(root, fileName), contents, "utf8");
  }
  return root;
}

test("sql migrations only accept numbered migration file names", () => {
  assert.equal(isNumberedSqlMigrationFileName("001_init.sql"), true);
  assert.equal(isNumberedSqlMigrationFileName("090.sql"), true);
  assert.equal(isNumberedSqlMigrationFileName("090a.sql"), true);
  assert.equal(isNumberedSqlMigrationFileName("090a_social_scope_core.sql"), true);
  assert.equal(isNumberedSqlMigrationFileName("131_order_item_display_snapshot.sql"), true);
  assert.equal(isNumberedSqlMigrationFileName("diag_order_181_delivery_assignment.sql"), false);
  assert.equal(isNumberedSqlMigrationFileName("notes.sql"), false);
});

test("sql migration inventory passes on a clean checkout without dirty migrations", async () => {
  const inventory = await scanSqlMigrationInventory(repoSqlDir);
  assert.ok(inventory.size > 0, "expected the repository to contain numbered SQL migrations");
  assert.doesNotThrow(() => assertUniqueSqlMigrationInventory(inventory));
});

test("sql migration inventory ignores non-numbered diagnostic SQL files", async () => {
  const root = await createTempSqlTree({
    "diag_order_181_delivery_assignment.sql": "select 1;",
    "notes.sql": "select 2;",
    "157_social_story_audio.sql": "select 3;",
  });

  const inventory = await scanSqlMigrationInventory(root);
  assert.deepEqual([...inventory.keys()], ["157_social_story_audio"]);
});

test("sql migration inventory accepts suffix migrations like 090 and 090a", async () => {
  const root = await createTempSqlTree({
    "090.sql": "select 1;",
    "090a.sql": "select 2;",
  });

  const inventory = await scanSqlMigrationInventory(root);
  assert.equal(inventory.size, 2);
  assert.deepEqual([...inventory.keys()].sort(), ["090", "090a"]);
  assert.doesNotThrow(() => assertUniqueSqlMigrationInventory(inventory));
});

test("sql migration inventory fails when the same migration id appears in two roots", async () => {
  const rootA = await createTempSqlTree({
    "155_services_booking_contract.sql": "select 1;",
  });
  const rootB = await createTempSqlTree({
    "155_services_booking_contract.sql": "select 2;",
  });

  const inventory = await scanSqlMigrationInventory([rootA, rootB]);
  assert.throws(
    () => assertUniqueSqlMigrationInventory(inventory),
    /DUPLICATE_SQL_MIGRATIONS/,
  );
});
