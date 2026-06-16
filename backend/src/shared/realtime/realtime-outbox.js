import { pool, q } from "../../config/db.js";
import { env } from "../../config/env.js";
import { getSupabaseRealtimeStatus } from "../../config/supabase.js";
import { publishSupabaseBroadcast } from "./realtime-supabase-publisher.js";

const OUTBOX_ADVISORY_LOCK_KEY = 927451803;
const OUTBOX_POLL_INTERVAL_MS = 1500;

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

export async function enqueueRealtimeOutbox({
  topic,
  event,
  payload,
  error = null,
} = {}) {
  const safeTopic = String(topic || "").trim();
  const safeEvent = String(event || "").trim();
  if (!safeTopic || !safeEvent) return null;

  try {
    const result = await dependencies.query(
      `INSERT INTO realtime_outbox
        (topic, event, payload, last_error)
       VALUES ($1,$2,$3::jsonb,$4)
       RETURNING id`,
      [
        safeTopic,
        safeEvent,
        JSON.stringify(normalizeJsonPayload(payload)),
        error ? String(error?.message || error).slice(0, 4000) : null,
      ]
    );
    return Number(result.rows[0]?.id || 0) || null;
  } catch (insertError) {
    dependencies.logger.error?.(
      "[realtime-outbox] enqueue failed",
      insertError?.message || insertError
    );
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
}

async function markOutboxRetry(client, id, attempts, error) {
  const delayMs = computeBackoffMs(attempts);
  await client.query(
    `UPDATE realtime_outbox
        SET status = 'pending',
            last_error = $2,
            next_attempt_at = NOW() + ($3 * INTERVAL '1 millisecond')
      WHERE id = $1`,
    [
      Number(id),
      String(error?.message || error || "SUPABASE_BROADCAST_FAILED").slice(0, 4000),
      delayMs,
    ]
  );
}

async function markOutboxFailed(client, id, error) {
  await client.query(
    `UPDATE realtime_outbox
        SET status = 'failed',
            last_error = $2
      WHERE id = $1`,
    [
      Number(id),
      String(error?.message || error || "SUPABASE_BROADCAST_FAILED").slice(0, 4000),
    ]
  );
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
