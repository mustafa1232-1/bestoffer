import assert from "node:assert/strict";
import test from "node:test";

import { isNumberedSqlMigrationFileName } from "../config/sqlMigrations.js";

test("sql migrations only accept numbered migration file names", () => {
  assert.equal(isNumberedSqlMigrationFileName("001_init.sql"), true);
  assert.equal(isNumberedSqlMigrationFileName("090a_social_scope_core.sql"), true);
  assert.equal(isNumberedSqlMigrationFileName("131_order_item_display_snapshot.sql"), true);
  assert.equal(isNumberedSqlMigrationFileName("diag_order_181_delivery_assignment.sql"), false);
  assert.equal(isNumberedSqlMigrationFileName("notes.sql"), false);
});
