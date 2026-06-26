import assert from "node:assert/strict";
import test from "node:test";

import { CircuitBreaker } from "../shared/realtime/realtime-resilience.js";
import {
  __realtimeMembershipTestApi,
  allowUsersOnChannel,
  syncOrderMembers,
} from "../shared/realtime/realtime-membership.js";

test.beforeEach(() => {
  // Fresh circuit + instant sleeper so retries don't slow the suite.
  __realtimeMembershipTestApi.setCircuit(
    new CircuitBreaker({ failureThreshold: 50, cooldownMs: 1000 })
  );
  __realtimeMembershipTestApi.setSleeper(async () => {});
});

test.afterEach(() => {
  __realtimeMembershipTestApi.reset();
});

function makeClient(upsertImpl) {
  return {
    from() {
      return {
        upsert: upsertImpl,
        select() {
          return { eq: async () => ({ data: [], error: null }) };
        },
        delete() {
          return {
            eq() {
              return { in: async () => ({ error: null }), eq: async () => ({ error: null }) };
            },
          };
        },
      };
    },
  };
}

test("allowUsersOnChannel handles Supabase 520 gracefully (no throw, structured result)", async () => {
  const logs = [];
  __realtimeMembershipTestApi.setStatusResolver(() => ({ canUseSupabase: true }));
  __realtimeMembershipTestApi.setLogger({ warn: (msg, info) => logs.push({ msg, info }) });
  __realtimeMembershipTestApi.setAdminClientFactory(() =>
    makeClient(async () => ({
      error: {
        status: 520,
        message:
          "<!DOCTYPE html><html><body><h1>Error 520</h1>Web server is returning an unknown error</body></html>",
      },
    }))
  );

  const result = await allowUsersOnChannel([1, 2, 3], "order:4");

  assert.equal(result.ok, false);
  assert.equal(result.provider, "supabase");
  assert.equal(result.statusCode, 520);
  assert.equal(result.retryable, true);
  assert.equal(result.fallback, "polling");
  assert.equal(result.userCount, 3);

  // The log must NOT contain raw HTML.
  assert.equal(logs.length >= 1, true);
  const serialized = JSON.stringify(logs);
  assert.equal(serialized.includes("<html>"), false);
  assert.equal(serialized.includes("<h1>"), false);
  assert.equal(serialized.includes("<!DOCTYPE"), false);
});

test("allowUsersOnChannel retries a transient 520 then succeeds", async () => {
  let attempts = 0;
  __realtimeMembershipTestApi.setStatusResolver(() => ({ canUseSupabase: true }));
  __realtimeMembershipTestApi.setAdminClientFactory(() =>
    makeClient(async () => {
      attempts += 1;
      if (attempts < 3) return { error: { status: 520, message: "520 transient" } };
      return { error: null };
    })
  );

  const result = await allowUsersOnChannel([1, 2], "order:7");
  assert.equal(result.ok, true);
  assert.equal(attempts, 3); // 1 try + 2 retries
});

test("allowUsersOnChannel does not retry a non-retryable 403", async () => {
  let attempts = 0;
  __realtimeMembershipTestApi.setStatusResolver(() => ({ canUseSupabase: true }));
  __realtimeMembershipTestApi.setAdminClientFactory(() =>
    makeClient(async () => {
      attempts += 1;
      return { error: { status: 403, message: "forbidden" } };
    })
  );

  const result = await allowUsersOnChannel([1], "order:9");
  assert.equal(result.ok, false);
  assert.equal(result.statusCode, 403);
  assert.equal(result.retryable, false);
  assert.equal(attempts, 1);
});

test("allowUsersOnChannel skips cleanly when Supabase is unavailable", async () => {
  __realtimeMembershipTestApi.setStatusResolver(() => ({ canUseSupabase: false }));
  const result = await allowUsersOnChannel([1, 2], "order:4");
  assert.equal(result.ok, false);
  assert.equal(result.skipped, true);
  assert.equal(result.reason, "supabase_unavailable");
});

test("circuit breaker fails fast after repeated membership failures", async () => {
  let calls = 0;
  __realtimeMembershipTestApi.setStatusResolver(() => ({ canUseSupabase: true }));
  __realtimeMembershipTestApi.setCircuit(
    new CircuitBreaker({ failureThreshold: 2, cooldownMs: 60000 })
  );
  __realtimeMembershipTestApi.setAdminClientFactory(() =>
    makeClient(async () => {
      calls += 1;
      return { error: { status: 520, message: "520" } };
    })
  );

  // No retries here so each call records exactly one circuit failure.
  __realtimeMembershipTestApi.setSleeper(async () => {});

  const first = await allowUsersOnChannel([1], "order:1");
  assert.equal(first.ok, false);
  const callsAfterFirst = calls;

  // After the threshold the circuit is open; subsequent calls should not reach
  // the Supabase client at all (fail fast).
  await allowUsersOnChannel([1], "order:2");
  await allowUsersOnChannel([1], "order:3");
  await allowUsersOnChannel([1], "order:4");
  assert.equal(calls <= callsAfterFirst + 2, true, `expected fail-fast, got ${calls} calls`);
});

test("syncOrderMembers authorizes exactly the order's parties (no unrelated users)", async () => {
  const upserts = [];
  __realtimeMembershipTestApi.setStatusResolver(() => ({ canUseSupabase: true }));
  // Order 4: customer 100, delivery 200, merchant owner 300 — and nobody else.
  __realtimeMembershipTestApi.setQuery(async () => ({
    rows: [{ user_id: 100 }, { user_id: 200 }, { user_id: 300 }],
  }));
  __realtimeMembershipTestApi.setAdminClientFactory(() => ({
    from() {
      return {
        async upsert(rows) {
          upserts.push(...rows);
          return { error: null };
        },
        select() {
          return { eq: async () => ({ data: [], error: null }) };
        },
        delete() {
          return { eq() { return { in: async () => ({ error: null }) }; } };
        },
      };
    },
  }));

  const result = await syncOrderMembers(4);
  assert.equal(result.ok, true);
  const authorizedIds = upserts.map((row) => row.user_id).sort();
  assert.deepEqual(authorizedIds, [100, 200, 300]);
  for (const row of upserts) {
    assert.equal(row.channel, "order:4");
  }
});
