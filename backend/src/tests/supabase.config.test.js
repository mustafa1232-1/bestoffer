import assert from "node:assert/strict";
import test from "node:test";
import jwt from "jsonwebtoken";

import {
  __supabaseConfigTestApi,
  getSupabaseRealtimeReadiness,
  issueSupabaseRealtimeToken,
} from "../config/supabase.js";

function createHealthySupabaseAdminClient() {
  return {
    from(tableName) {
      return {
        select() {
          return {
            limit() {
              return { error: null };
            },
          };
        },
        upsert() {
          return { error: null };
        },
        delete() {
          return {
            eq() {
              return {
                eq() {
                  return { error: null };
                },
              };
            },
          };
        },
        insert() {
          return {
            select() {
              return {
                single() {
                  if (tableName === "realtime_channel_audit") {
                    return { error: null, data: { id: 41 } };
                  }
                  return { error: null, data: null };
                },
              };
            },
          };
        },
      };
    },
  };
}

test.afterEach(() => {
  __supabaseConfigTestApi.reset();
});

test("issueSupabaseRealtimeToken embeds expected claims", async () => {
  __supabaseConfigTestApi.setEnv({
      SUPABASE_REALTIME_ENABLED: "true",
      supabaseRealtimeEnabled: true,
      supabaseRealtimeMode: "dual",
      supabaseUrl: "https://demo.supabase.co",
      supabaseAnonKey: "anon-key",
      supabaseServiceRoleKey: "service-role-key",
      supabaseJwtSecret: "x".repeat(40),
    });

  const issued = issueSupabaseRealtimeToken({
    userId: 88,
    appRole: "admin",
    expiresInSec: 600,
  });
  const decoded = jwt.verify(issued.token, "x".repeat(40));
  assert.equal(decoded.sub, "88");
  assert.equal(decoded.role, "authenticated");
  assert.equal(decoded.app_user_id, 88);
  assert.equal(decoded.app_role, "admin");
  assert.equal(issued.expiresIn, 600);
});

test("getSupabaseRealtimeReadiness is non-blocking in sse_only mode", async () => {
  __supabaseConfigTestApi.setEnv({
    supabaseRealtimeEnabled: true,
    supabaseRealtimeMode: "sse_only",
    supabaseUrl: "",
    supabaseAnonKey: "",
    supabaseServiceRoleKey: "",
    supabaseJwtSecret: "",
  });

  const readiness = await getSupabaseRealtimeReadiness();
  assert.equal(readiness.ok, true);
  assert.equal(readiness.releaseBlocking, false);
  assert.equal(readiness.reason, "sse_only_mode");
  assert.equal(readiness.checks.realtimeTokenIssuance, true);
});

test("getSupabaseRealtimeReadiness blocks dual mode when railway outbox table is missing", async () => {
  __supabaseConfigTestApi.setEnv({
    supabaseRealtimeEnabled: true,
    supabaseRealtimeMode: "dual",
    supabaseUrl: "https://demo.supabase.co",
    supabaseAnonKey: "anon-key",
    supabaseServiceRoleKey: "service-role-key",
    supabaseJwtSecret: "x".repeat(40),
  });
  __supabaseConfigTestApi.setQuery(async () => ({ rows: [] }));
  __supabaseConfigTestApi.setAdminClientFactory(createHealthySupabaseAdminClient);

  const readiness = await getSupabaseRealtimeReadiness();
  assert.equal(readiness.ok, false);
  assert.equal(readiness.releaseBlocking, true);
  assert.equal(readiness.reason, "missing_outbox_table");
  assert.deepEqual(readiness.missingObjects, ["realtime_outbox"]);
  assert.equal(readiness.checks.railwayOutboxTable, false);
});

test("getSupabaseRealtimeReadiness reports degraded shared topics when supabase authorization tables are missing", async () => {
  __supabaseConfigTestApi.setEnv({
    supabaseRealtimeEnabled: true,
    supabaseRealtimeMode: "dual",
    supabaseUrl: "https://demo.supabase.co",
    supabaseAnonKey: "anon-key",
    supabaseServiceRoleKey: "service-role-key",
    supabaseJwtSecret: "x".repeat(40),
  });
  __supabaseConfigTestApi.setQuery(async () => ({
    rows: [{ table_name: "realtime_outbox" }],
  }));
  __supabaseConfigTestApi.setAdminClientFactory(() => ({
    from(tableName) {
      return {
        select() {
          return {
            limit() {
              if (tableName == "realtime_channel_member") {
                return { error: null };
              }
              return { error: new Error("missing table") };
            },
          };
        },
        upsert() {
          return { error: null };
        },
        delete() {
          return {
            eq() {
              return {
                eq() {
                  return { error: null };
                },
              };
            },
          };
        },
        insert() {
          return {
            select() {
              return {
                single() {
                  return { error: null, data: { id: 7 } };
                },
              };
            },
          };
        },
      };
    },
  }));

  const readiness = await getSupabaseRealtimeReadiness();
  assert.equal(readiness.ok, false);
  assert.equal(readiness.releaseBlocking, true);
  assert.equal(readiness.reason, "shared_topics_degraded");
  assert.deepEqual(readiness.missingObjects, ["realtime_channel_audit"]);
  assert.equal(readiness.checks.sharedTopicAuthorizationTables, false);
  assert.equal(readiness.sharedTopicsReady, false);
});

test("getSupabaseRealtimeReadiness reports degraded shared topics when membership write probe fails", async () => {
  __supabaseConfigTestApi.setEnv({
    supabaseRealtimeEnabled: true,
    supabaseRealtimeMode: "dual",
    supabaseUrl: "https://demo.supabase.co",
    supabaseAnonKey: "anon-key",
    supabaseServiceRoleKey: "service-role-key",
    supabaseJwtSecret: "x".repeat(40),
  });
  __supabaseConfigTestApi.setQuery(async () => ({
    rows: [{ table_name: "realtime_outbox" }],
  }));
  __supabaseConfigTestApi.setAdminClientFactory(() => ({
    from() {
      return {
        select() {
          return {
            limit() {
              return { error: null };
            },
          };
        },
        upsert() {
          return {
            error: { message: "Could not find the table in the schema cache" },
          };
        },
      };
    },
  }));

  const readiness = await getSupabaseRealtimeReadiness();
  assert.equal(readiness.ok, false);
  assert.equal(readiness.releaseBlocking, true);
  assert.equal(readiness.reason, "shared_topics_degraded");
  assert.deepEqual(readiness.missingObjects, ["realtime_channel_member"]);
  assert.equal(readiness.checks.sharedTopicAuthorizationTables, false);
  assert.equal(readiness.sharedTopicsReady, false);
});

test("getSupabaseRealtimeReadiness succeeds when env, local schema, and supabase tables are healthy", async () => {
  __supabaseConfigTestApi.setEnv({
    supabaseRealtimeEnabled: true,
    supabaseRealtimeMode: "dual",
    supabaseUrl: "https://demo.supabase.co",
    supabaseAnonKey: "anon-key",
    supabaseServiceRoleKey: "service-role-key",
    supabaseJwtSecret: "x".repeat(40),
  });
  __supabaseConfigTestApi.setQuery(async () => ({
    rows: [{ table_name: "realtime_outbox" }],
  }));
  __supabaseConfigTestApi.setAdminClientFactory(createHealthySupabaseAdminClient);

  const readiness = await getSupabaseRealtimeReadiness();
  assert.equal(readiness.ok, true);
  assert.equal(readiness.releaseBlocking, false);
  assert.equal(readiness.reason, "ok");
  assert.deepEqual(readiness.missingKeys, []);
  assert.deepEqual(readiness.missingObjects, []);
});
