import { createHash } from "node:crypto";

import { pool, q } from "../../config/db.js";
import { env } from "../../config/env.js";
import { getSupabaseRealtimeStatus } from "../../config/supabase.js";
import { publishSupabaseBroadcast } from "./realtime-supabase-publisher.js";
import {
  REALTIME_METRICS,
  incMetric,
  sanitizeErrorForLog,
} from "./realtime-resilience.js";

const OUTBOX_ADVISORY_LOCK_KEY = 927451803;
const OUTBOX_POLL_INTERVAL_MS = 1500;

function safeOutboxError(error, fallback = "SUPABASE_BROADCAST_FAILED") {
  const safe = sanitizeErrorForLog(error);
  return (safe?.message || fallback).slice(0, 300);
}

/**
 * Stable idempotency key for an outbox entry. Excludes volatile fields (event
 * id, createdAt) so two logically-identical events collapse to one pending row,
 * but includes the topic + logical entity + payload so genuinely distinct events
 * (and re-sends after publish) are kept separate.
 */
export function computeOutboxDedupeKey({ topic, event, payload } = {}) {
  const envelope = payload && typeof payload === "object" ? payload : {};
  const basis = JSON.stringify({
    topic: String(topic || ""),
    event: String(event || ""),
    entityType: envelope.entityType ?? null,
    entityId: envelope.entityId ?? null,
    actorUserId: envelope.actorUserId ?? null,
    recipientUserId: envelope.recipientUserId ?? null,
    data: envelope.data ?? null,
  });
  return createHash("sha1").update(basis).digest("hex");
}

function isUndefinedColumnError(error) {
  // Postgres 42703 = undefined_column (dedupe_key migration not applied yet).
  return (
    error?.code === "42703" ||
    /column .*dedupe_key.* does not exist/i.test(String(error?.message || ""))
  );
}

const dependencies = {
  query: (text, params) => q(text, params),
  getPool: () => pool,
  publish: (topic, event, payload, options) =>
    publishSupabaseBroadcast(topic, event, payload, options),
  getStatus: () => getSupabaseRealtimeStatus(),
  logger: console,
};

let outboxTimer = null;
let outboxRunPromise = null;

function computeBackoffMs(attempts) {
  const safeAttempts = Math.max(1, Number(attempts) || 1);
  const baseDelay = Math.max(
    100,
    Number(env.supabaseRealtimeOutboxBaseDelayMs) || 1000
  );
  return Math.min(baseDelay * 2 ** Math.max(0, safeAttempts - 1), 60 * 60 * 1000);
}

function normalizeJsonPayload(payload) {
  if (payload == null) return {};
  if (typeof payload === "string") {
    try {
      return JSON.parse(payload);
    } catch (_) {
      return { raw: payload };
    }
  }
  if (typeof payload === "object") return payload;
  return { value: payload };
}

async function insertOutboxRow({ topic, event, payloadJson, lastError, dedupeKey }) {
  // Idempotent insert: if an identical event is already pending/processing we
  // reuse that row (returning its id) instead of queuing a duplicate.
  const withDedupe = await dependencies.query(
    `INSERT INTO realtime_outbox
        (topic, event, payload, last_error, dedupe_key)
       VALUES ($1,$2,$3::jsonb,$4,$5)
       ON CONFLICT (dedupe_key) WHERE status IN ('pending','processing')
       DO UPDATE SET last_error = COALESCE(realtime_outbox.last_error, EXCLUDED.last_error)
       RETURNING id`,
    [topic, event, payloadJson, lastError, dedupeKey]
  );
  return Number(withDedupe.rows[0]?.id || 0) || null;
}

export async function enqueueRealtimeOutbox({
  topic,
  event,
  payload,
  error = null,
} = {}) {
  const safeTopic = String(topic || "").trim();
  const safeEvent = String(event || "").trim();
  if (!safeTopic || !safeEvent) return null;

  const payloadJson = JSON.stringify(normalizeJsonPayload(payload));
  const lastError = error ? safeOutboxError(error) : null;
  const dedupeKey = computeOutboxDedupeKey({
    topic: safeTopic,
    event: safeEvent,
    payload,
  });

  try {
    return await insertOutboxRow({
      topic: safeTopic,
      event: safeEvent,
      payloadJson,
      lastError,
      dedupeKey,
    });
  } catch (insertError) {
    // Backward compatibility: if the dedupe_key migration has not yet been
    // applied, fall back to the plain insert so events are never lost.
    if (isUndefinedColumnError(insertError)) {
      try {
        const result = await dependencies.query(
          `INSERT INTO realtime_outbox
            (topic, event, payload, last_error)
           VALUES ($1,$2,$3::jsonb,$4)
           RETURNING id`,
          [safeTopic, safeEvent, payloadJson, lastError]
        );
        return Number(result.rows[0]?.id || 0) || null;
      } catch (fallbackError) {
        dependencies.logger.error?.("[realtime-outbox] enqueue failed", {
          event: "realtime_outbox_enqueue_failed",
          topic: safeTopic,
          error: safeOutboxError(fallbackError),
        });
        return null;
      }
    }
    dependencies.logger.error?.("[realtime-outbox] enqueue failed", {
      event: "realtime_outbox_enqueue_failed",
      topic: safeTopic,
      error: safeOutboxError(insertError),
    });
    return null;
  }
}

async function claimPendingOutboxEntries(client, limit = 50) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 50));
  const result = await client.query(
    `WITH picked AS (
       SELECT id
       FROM realtime_outbox
       WHERE status = 'pending'
         AND next_attempt_at <= NOW()
       ORDER BY next_attempt_at ASC, id ASC
       LIMIT $1
       FOR UPDATE SKIP LOCKED
     )
     UPDATE realtime_outbox o
        SET status = 'processing',
            attempts = attempts + 1
       FROM picked
      WHERE o.id = picked.id
     RETURNING o.id, o.topic, o.event, o.payload, o.attempts`,
    [safeLimit]
  );
  return result.rows || [];
}

async function markOutboxPublished(client, id) {
  await client.query(
    `UPDATE realtime_outbox
        SET status = 'published',
            published_at = NOW(),
            last_error = NULL
      WHERE id = $1`,
    [Number(id)]
  );
  incMetric(REALTIME_METRICS.OUTBOX_PUBLISHED);
}

async function markOutboxRetry(client, id, attempts, error) {
  const delayMs = computeBackoffMs(attempts);
  await client.query(
    `UPDATE realtime_outbox
        SET status = 'pending',
            last_error = $2,
            next_attempt_at = NOW() + ($3 * INTERVAL '1 millisecond')
      WHERE id = $1`,
    [Number(id), safeOutboxError(error), delayMs]
  );
  incMetric(REALTIME_METRICS.OUTBOX_RETRY);
}

async function markOutboxFailed(client, id, error) {
  // Dead-letter: attempts exhausted. Kept in-table with status 'failed' for
  // inspection/replay; never deleted automatically.
  await client.query(
    `UPDATE realtime_outbox
        SET status = 'failed',
            last_error = $2
      WHERE id = $1`,
    [Number(id), safeOutboxError(error)]
  );
  incMetric(REALTIME_METRICS.OUTBOX_DEAD_LETTER);
}

export async function processRealtimeOutboxBatch({ limit = 50 } = {}) {
  const status = dependencies.getStatus();
  if (!status.canUseSupabase) {
    return { processed: 0, published: 0, retried: 0, failed: 0, skipped: true };
  }

  const client = await dependencies.getPool().connect();
  let lockAcquired = false;
  try {
    const lockResult = await client.query(
      "SELECT pg_try_advisory_lock($1) AS locked",
      [OUTBOX_ADVISORY_LOCK_KEY]
    );
    lockAcquired = lockResult.rows[0]?.locked === true;
    if (!lockAcquired) {
      return {
        processed: 0,
        published: 0,
        retried: 0,
        failed: 0,
        locked: false,
      };
    }

    const rows = await claimPendingOutboxEntries(client, limit);
    const summary = {
      processed: rows.length,
      published: 0,
      retried: 0,
      failed: 0,
      locked: true,
    };

    for (const row of rows) {
      try {
        await dependencies.publish(
          row.topic,
          row.event,
          normalizeJsonPayload(row.payload),
          { private: true }
        );
        await markOutboxPublished(client, row.id);
        summary.published += 1;
      } catch (error) {
        const safeAttempts = Number(row.attempts || 1);
        if (safeAttempts >= Number(env.supabaseRealtimeOutboxMaxAttempts || 8)) {
          await markOutboxFailed(client, row.id, error);
          summary.failed += 1;
        } else {
          await markOutboxRetry(client, row.id, safeAttempts, error);
          summary.retried += 1;
        }
      }
    }

    return summary;
  } finally {
    if (lockAcquired) {
      await client
        .query("SELECT pg_advisory_unlock($1)", [OUTBOX_ADVISORY_LOCK_KEY])
        .catch(() => {});
    }
    client.release();
  }
}

export function startRealtimeOutboxPump() {
  if (outboxTimer) return true;
  if (!dependencies.getStatus().canUseSupabase) return false;
  outboxTimer = setInterval(() => {
    if (outboxRunPromise) return;
    outboxRunPromise = processRealtimeOutboxBatch()
      .catch((error) => {
        dependencies.logger.warn?.(
          "[realtime-outbox] batch failed",
          error?.message || error
        );
      })
      .finally(() => {
        outboxRunPromise = null;
      });
  }, OUTBOX_POLL_INTERVAL_MS);
  outboxTimer.unref?.();
  return true;
}

export async function stopRealtimeOutboxPump() {
  if (outboxTimer) {
    clearInterval(outboxTimer);
    outboxTimer = null;
  }
  await outboxRunPromise;
}

export const __realtimeOutboxTestApi = {
  computeBackoffMs,
  computeOutboxDedupeKey,
  safeOutboxError,
  setQuery(fn) {
    dependencies.query = fn;
  },
  setPoolFactory(fn) {
    dependencies.getPool = fn;
  },
  setPublisher(fn) {
    dependencies.publish = fn;
  },
  setStatusResolver(fn) {
    dependencies.getStatus = fn;
  },
  reset() {
    dependencies.query = (text, params) => q(text, params);
    dependencies.getPool = () => pool;
    dependencies.publish = (topic, event, payload, options) =>
      publishSupabaseBroadcast(topic, event, payload, options);
    dependencies.getStatus = () => getSupabaseRealtimeStatus();
    dependencies.logger = console;
    outboxRunPromise = null;
  },
};
