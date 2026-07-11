import assert from "node:assert/strict";
import test from "node:test";

import {
  assertSafeE2EDatabaseTarget,
  formatDatabaseTarget,
  isProductionLikeDatabaseTarget,
  parseDatabaseTarget,
} from "../scripts/e2eDbSafety.js";

test("parses and formats a safe non-production database target", () => {
  const target = parseDatabaseTarget(
    "postgres://bestoffer:test@127.0.0.1:55432/bestoffer_test"
  );

  assert.equal(target.protocol, "postgres:");
  assert.equal(target.host, "127.0.0.1");
  assert.equal(target.port, 55432);
  assert.equal(target.databaseName, "bestoffer_test");
  assert.equal(target.username, "bestoffer");
  assert.equal(target.hasPassword, true);
  assert.equal(
    isProductionLikeDatabaseTarget(target, { isProduction: false }),
    false
  );

  const pretty = formatDatabaseTarget(target);
  assert.equal(pretty.host, "127.0.0.1");
  assert.equal(pretty.port, "55432");
  assert.equal(pretty.database, "bestoffer_test");
  assert.ok(
    ["development", "test"].includes(pretty.environment),
    `unexpected environment ${pretty.environment}`
  );
});

test("refuses a production-like target unless the override flag is enabled", () => {
  assert.throws(
    () =>
      assertSafeE2EDatabaseTarget({
        scriptName: "phase-1c-check",
        databaseUrl: "postgres://bestoffer:test@bestoffer-production.up.railway.app:5432/bestoffer_prod",
        isProduction: false,
      }),
    /production-like database target/i
  );
});

test("allows an explicit production override for runtime checks", () => {
  const result = assertSafeE2EDatabaseTarget({
    scriptName: "phase-1c-check",
    databaseUrl: "postgres://bestoffer:test@bestoffer-production.up.railway.app:5432/bestoffer_prod",
    allowProductionOverride: "true",
    isProduction: false,
  });

  assert.equal(result.productionLike, true);
  assert.equal(result.allowedOverride, true);
});
