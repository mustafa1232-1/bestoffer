import assert from "node:assert/strict";
import test from "node:test";

import {
  __realtimeOutboxTestApi,
  computeOutboxDedupeKey,
  enqueueRealtimeOutbox,
  processRealtimeOutboxBatch,
} from "../shared/realtime/realtime-outbox.js";
import { createRealtimeError } from "../shared/realtime/realtime-resilience.js";

test.afterEach(() => {
  __realtimeOutboxTestApi.reset();
});

/**
 * Fake pg pool/client that records the status transitions the worker applies.
 * `claimRows` are the rows returned by the claim query (already attempts+1, as
 * the real SQL increments on claim).
 */
function makeFakePool(claimRows) {
  const updates = [];
  const client = {
    async query(text, params = []) {
      if (text.includes("pg_try_advisory_lock")) return { rows: [{ locked: true }] };
      if (text.includes("pg_advisory_unlock")) return { rows: [] };
      if (text.includes("FOR UPDATE SKIP LOCKED")) return { rows: claimRows };
      if (text.includes("SET status = 'published'")) {
        updates.push({ type: "published", id: params[0] });
        return { rows: [] };
      }
      if (text.includes("SET status = 'pending'")) {
        updates.push({ type: "retry", id: params[0], lastError: params[1] });
        return { rows: [] };
      }
      if (text.includes("SET status = 'failed'")) {
        updates.push({ type: "failed", id: params[0], lastError: params[1] });
        return { rows: [] };
      }
      return { rows: [] };
    },
    release() {},
  };
  return { pool: { connect: async () => client }, updates };
}

test("Supabase 520 keeps the event pending for retry (attempts not exhausted)", async () => {
  const { pool, updates } = makeFakePool([
    { id: 11, topic: "order:4", event: "order_status_changed", payload: {}, attempts: 1 },
  ]);
  __realtimeOutboxTestApi.setStatusResolver(() => ({ canUseSupabase: true }));
  __realtimeOutboxTestApi.setPoolFactory(() => pool);
  __realtimeOutboxTestApi.setPublisher(async () => {
    throw createRealtimeError("SUPABASE_BROADCAST_FAILED", { status: 520 });
  });

  const summary = await processRealtimeOutboxBatch();
  assert.equal(summary.processed, 1);
  assert.equal(summary.retried, 1);
  assert.equal(summary.failed, 0);
  assert.equal(updates[0].type, "retry");
});

test("a single bad event does not break the worker (others still publish)", async () => {
  const { pool, updates } = makeFakePool([
    { id: 1, topic: "order:1", event: "order_status_changed", payload: {}, attempts: 1 },
    { id: 2, topic: "order:2", event: "order_status_changed", payload: {}, attempts: 1 },
    { id: 3, topic: "order:3", event: "order_status_changed", payload: {}, attempts: 1 },
  ]);
  __realtimeOutboxTestApi.setStatusResolver(() => ({ canUseSupabase: true }));
  __realtimeOutboxTestApi.setPoolFactory(() => pool);
  __realtimeOutboxTestApi.setPublisher(async (topic) => {
    if (topic === "order:2") throw createRealtimeError("BOOM", { status: 520 });
    return null;
  });

  const summary = await processRealtimeOutboxBatch();
  assert.equal(summary.processed, 3);
  assert.equal(summary.published, 2);
  assert.equal(summary.retried, 1);
  const byId = Object.fromEntries(updates.map((u) => [u.id, u.type]));
  assert.equal(byId[1], "published");
  assert.equal(byId[2], "retry");
  assert.equal(byId[3], "published");
});

test("successful publish marks the event published", async () => {
  const { pool, updates } = makeFakePool([
    { id: 5, topic: "user:9", event: "notification", payload: {}, attempts: 2 },
  ]);
  __realtimeOutboxTestApi.setStatusResolver(() => ({ canUseSupabase: true }));
  __realtimeOutboxTestApi.setPoolFactory(() => pool);
  __realtimeOutboxTestApi.setPublisher(async () => ({ ok: true }));

  const summary = await processRealtimeOutboxBatch();
  assert.equal(summary.published, 1);
  assert.equal(updates[0].type, "published");
});

test("event is dead-lettered (failed) after max attempts are exhausted", async () => {
  const { pool, updates } = makeFakePool([
    // attempts at/above SUPABASE_REALTIME_OUTBOX_MAX_ATTEMPTS (default 8).
    { id: 99, topic: "order:4", event: "order_status_changed", payload: {}, attempts: 8 },
  ]);
  __realtimeOutboxTestApi.setStatusResolver(() => ({ canUseSupabase: true }));
  __realtimeOutboxTestApi.setPoolFactory(() => pool);
  __realtimeOutboxTestApi.setPublisher(async () => {
    throw createRealtimeError("SUPABASE_BROADCAST_FAILED", { status: 520 });
  });

  const summary = await processRealtimeOutboxBatch();
  assert.equal(summary.failed, 1);
  assert.equal(updates[0].type, "failed");
});

test("last_error is sanitized (no HTML) when stored on retry", async () => {
  const { pool, updates } = makeFakePool([
    { id: 7, topic: "order:4", event: "order_status_changed", payload: {}, attempts: 1 },
  ]);
  __realtimeOutboxTestApi.setStatusResolver(() => ({ canUseSupabase: true }));
  __realtimeOutboxTestApi.setPoolFactory(() => pool);
  __realtimeOutboxTestApi.setPublisher(async () => {
    const error = new Error(
      "<!DOCTYPE html><html><body><h1>Error 520</h1></body></html>"
    );
    error.status = 520;
    throw error;
  });

  await processRealtimeOutboxBatch();
  const lastError = updates[0].lastError || "";
  assert.equal(lastError.includes("<"), false);
  assert.equal(lastError.length <= 300, true);
});

test("processing is skipped when Supabase cannot be used", async () => {
  __realtimeOutboxTestApi.setStatusResolver(() => ({ canUseSupabase: false }));
  const summary = await processRealtimeOutboxBatch();
  assert.equal(summary.skipped, true);
  assert.equal(summary.processed, 0);
});

test("dedupe key is stable for identical events and differs for distinct ones", () => {
  const base = {
    topic: "order:4",
    event: "order_status_changed",
    payload: {
      id: 111,
      createdAt: "2026-06-26T10:00:00Z",
      entityType: "order",
      entityId: 4,
      actorUserId: 200,
      data: { status: "on_the_way" },
    },
  };
  // Same logical event, different volatile envelope id + timestamp => same key.
  const duplicate = {
    ...base,
    payload: { ...base.payload, id: 999, createdAt: "2026-06-26T10:05:00Z" },
  };
  assert.equal(computeOutboxDedupeKey(base), computeOutboxDedupeKey(duplicate));

  // Different status => different key.
  const differentStatus = {
    ...base,
    payload: { ...base.payload, data: { status: "delivered" } },
  };
  assert.notEqual(computeOutboxDedupeKey(base), computeOutboxDedupeKey(differentStatus));

  // Different order => different key.
  const differentOrder = {
    ...base,
    topic: "order:5",
    payload: { ...base.payload, entityId: 5 },
  };
  assert.notEqual(computeOutboxDedupeKey(base), computeOutboxDedupeKey(differentOrder));
});

test("enqueue passes a dedupe_key and sanitized error to the insert", async () => {
  const calls = [];
  __realtimeOutboxTestApi.setQuery(async (text, params) => {
    calls.push({ text, params });
    return { rows: [{ id: 1 }] };
  });

  const id = await enqueueRealtimeOutbox({
    topic: "order:4",
    event: "order_status_changed",
    payload: { entityType: "order", entityId: 4, data: { status: "ready" } },
    error: new Error("<html><body>520 boom</body></html>"),
  });

  assert.equal(id, 1);
  assert.equal(calls.length, 1);
  const params = calls[0].params;
  // [topic, event, payloadJson, lastError, dedupeKey]
  assert.equal(params[0], "order:4");
  assert.equal(typeof params[4], "string");
  assert.equal(params[4].length > 0, true);
  assert.equal(String(params[3]).includes("<"), false); // sanitized error
});
