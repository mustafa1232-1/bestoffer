import assert from "node:assert/strict";
import test from "node:test";

import {
  assertResetAllowed,
  verifyResetState,
} from "../scripts/resetDbKeepSuperAdmin.js";

function createFakeClient(counts) {
  return {
    async query(sql) {
      const text = String(sql || "");
      if (/FROM\s+app_user\s+WHERE\s+is_super_admin\s*=\s*TRUE/i.test(text)) {
        return {
          rowCount: 1,
          rows: [
            {
              id: 1,
              role: "admin",
              is_super_admin: true,
              phone: "07746515247",
            },
          ],
        };
      }
      const match = text.match(/FROM\s+("?)([a-zA-Z0-9_]+)\1/i);
      if (match) {
        const tableName = match[2];
        return {
          rowCount: 1,
          rows: [{ total: Number(counts[tableName] ?? 0) }],
        };
      }
      throw new Error(`UNEXPECTED_SQL:${text}`);
    },
  };
}

test("reset safety gate blocks without the destructive flag", () => {
  assert.throws(
    () =>
      assertResetAllowed({
        allowDestructiveReset: "false",
        allowProdOverride: "false",
        target: { host: "localhost", databaseName: "bestoffer_test" },
        isProduction: false,
      }),
    /ALLOW_DESTRUCTIVE_RESET=true/
  );
});

test("reset safety gate blocks production-like targets without the override", () => {
  assert.throws(
    () =>
      assertResetAllowed({
        allowDestructiveReset: "true",
        allowProdOverride: "false",
        target: { host: "db.production.example.com", databaseName: "bestoffer_prod" },
        isProduction: false,
      }),
    /ALLOW_DESTRUCTIVE_RESET_PROD_OVERRIDE=true/
  );
});

test("reset verification accepts a wiped database with only super_admin left", async () => {
  const client = createFakeClient({
    app_user: 1,
    user_session: 0,
    taxi_ride_request: 0,
    taxi_ride_bid: 0,
    taxi_ride_chat_message: 0,
  });

  const result = await verifyResetState(client, {
    tableNames: [
      "app_user",
      "user_session",
      "taxi_ride_request",
      "taxi_ride_bid",
      "taxi_ride_chat_message",
    ],
  });

  assert.equal(result.appUserCount, 1);
  assert.equal(result.superAdminId, 1);
  assert.deepEqual(result.nonZeroTables, []);
});

test("reset verification rejects leftover rows in any non-super-admin table", async () => {
  const client = createFakeClient({
    app_user: 1,
    user_session: 1,
    taxi_ride_request: 0,
  });

  await assert.rejects(
    () =>
      verifyResetState(client, {
        tableNames: ["app_user", "user_session", "taxi_ride_request"],
      }),
    /RESET_VERIFY_FAILED:non_zero_tables=user_session:1/
  );
});
