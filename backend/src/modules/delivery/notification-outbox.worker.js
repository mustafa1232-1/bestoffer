import { pool } from "../../config/db.js";
import { env } from "../../config/env.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";

/**
 * Notification outbox sender (delivery closure §11).
 *
 * The business transaction writes a `notification_outbox` row atomically with
 * the state change (e.g. grouped assignment). This worker delivers those rows
 * durably and idempotently:
 *   - polls CREATED / QUEUED / PROVIDER_REJECTED rows that are due
 *   - locks each with FOR UPDATE SKIP LOCKED (safe for parallel workers)
 *   - dispatches through the existing notification infrastructure
 *     (createManyNotifications → app_notification + push fan-out), reusing
 *     eventId as the idempotency key
 *   - records provider outcome, applies bounded exponential backoff, and moves
 *     exhausted rows to DEAD_LETTER
 *
 * Push is not the source of truth (§13): the courier also recovers assigned jobs
 * through the API bootstrap, so a dropped push is self-healing.
 */

const OUTBOX_WORKER_LOCK_KEY = 482917664;
const DEFAULT_BATCH_SIZE = 50;
const DEFAULT_INTERVAL_MS = 10000;
const MAX_ATTEMPTS = 6;
const BASE_BACKOFF_SEC = 15;

let workerTimer = null;
let workerRunPromise = null;

function parsePositiveInt(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.floor(parsed);
}

// Map an outbox event to the platform notification `type` + human copy. The
// courier surface is `delivery` in device-token registration terms.
function describeEvent(row) {
  const payload = row.payload_json || {};
  const stores = Number(payload.stores || payload.numberOfStores || 1) || 1;
  switch (row.event_type) {
    case "COURIER_MULTI_STORE_DELIVERY_ASSIGNED":
      return {
        type: "delivery_grouped_assigned",
        title: "تم إسناد طلب توصيل إليك",
        body: `تم إسناد طلب من ${stores} متاجر إليك.`,
      };
    case "COURIER_DELIVERY_ASSIGNED":
      return {
        type: "delivery_grouped_assigned",
        title: "تم إسناد طلب توصيل إليك",
        body: "تم إسناد طلب توصيل إليك.",
      };
    default:
      return {
        type: String(row.event_type || "delivery_event").toLowerCase(),
        title: "تحديث التوصيل",
        body: "لديك تحديث جديد على التوصيل.",
      };
  }
}

async function loadDueOutboxRows(client, limit) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || DEFAULT_BATCH_SIZE));
  return (
    await client.query(
      `SELECT id, event_id, event_type, recipient_user_id, target_surface,
              target_entity_type, target_entity_id, payload_json, attempt_count
         FROM notification_outbox
        WHERE status IN ('CREATED','QUEUED','PROVIDER_REJECTED')
          AND next_attempt_at <= NOW()
        ORDER BY next_attempt_at ASC, id ASC
        LIMIT $1
        FOR UPDATE SKIP LOCKED`,
      [safeLimit]
    )
  ).rows;
}

async function markAccepted(client, id) {
  await client.query(
    `UPDATE notification_outbox
        SET status='PROVIDER_ACCEPTED', sent_at=NOW(),
            last_error_code=NULL, last_error_message_safe=NULL
      WHERE id=$1`,
    [id]
  );
}

async function markFailure(client, id, attemptCount, errorCode) {
  const nextAttempts = Number(attemptCount || 0) + 1;
  if (nextAttempts >= MAX_ATTEMPTS) {
    await client.query(
      `UPDATE notification_outbox
          SET status='DEAD_LETTER', attempt_count=$2, last_error_code=$3
        WHERE id=$1`,
      [id, nextAttempts, String(errorCode || "SEND_FAILED").slice(0, 64)]
    );
    return;
  }
  const backoffSec = BASE_BACKOFF_SEC * Math.pow(2, nextAttempts - 1);
  await client.query(
    `UPDATE notification_outbox
        SET status='PROVIDER_REJECTED', attempt_count=$2,
            next_attempt_at = NOW() + ($3 || ' seconds')::interval,
            last_error_code=$4
      WHERE id=$1`,
    [id, nextAttempts, String(backoffSec), String(errorCode || "SEND_FAILED").slice(0, 64)]
  );
}

/**
 * Drain due outbox rows once. Each row is delivered in its own transaction so a
 * single bad row cannot roll back siblings.
 */
export async function drainNotificationOutbox({ limit = DEFAULT_BATCH_SIZE } = {}) {
  const loader = await pool.connect();
  let rows = [];
  const summary = { processed: 0, accepted: 0, failed: 0, deadLettered: 0 };
  try {
    await loader.query("BEGIN");
    rows = await loadDueOutboxRows(loader, limit);
    // Mark picked rows QUEUED inside the same lock window so a second drainer
    // does not re-pick them immediately.
    if (rows.length > 0) {
      await loader.query(
        `UPDATE notification_outbox SET status='QUEUED'
          WHERE id = ANY($1::bigint[])`,
        [rows.map((r) => Number(r.id))]
      );
    }
    await loader.query("COMMIT");
  } catch (error) {
    await loader.query("ROLLBACK").catch(() => {});
    console.error("[notification-outbox-worker] load failed", error);
    return summary;
  } finally {
    loader.release();
  }

  for (const row of rows) {
    summary.processed += 1;
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      const copy = describeEvent(row);
      const payload = row.payload_json || {};
      await createManyNotifications([
        {
          userId: Number(row.recipient_user_id),
          type: copy.type,
          title: copy.title,
          body: copy.body,
          orderId: null,
          merchantId: null,
          // eventId flows through so downstream push dedupes by it (§12).
          eventId: row.event_id,
          payload: {
            ...payload,
            eventId: row.event_id,
            targetSurface: row.target_surface,
            targetEntityType: row.target_entity_type,
            targetEntityId: Number(row.target_entity_id) || null,
          },
        },
      ]);
      await markAccepted(client, row.id);
      await client.query("COMMIT");
      summary.accepted += 1;
    } catch (error) {
      await client.query("ROLLBACK").catch(() => {});
      try {
        await client.query("BEGIN");
        await markFailure(client, row.id, row.attempt_count, error?.code || error?.message);
        await client.query("COMMIT");
        if (Number(row.attempt_count || 0) + 1 >= MAX_ATTEMPTS) summary.deadLettered += 1;
        else summary.failed += 1;
      } catch (inner) {
        await client.query("ROLLBACK").catch(() => {});
        console.error("[notification-outbox-worker] failure bookkeeping failed", inner);
      }
    } finally {
      client.release();
    }
  }

  return summary;
}

export async function processNotificationOutboxBatch({ limit = DEFAULT_BATCH_SIZE } = {}) {
  const client = await pool.connect();
  let lockAcquired = false;
  try {
    const lock = await client.query("SELECT pg_try_advisory_lock($1) AS locked", [
      OUTBOX_WORKER_LOCK_KEY,
    ]);
    lockAcquired = lock.rows[0]?.locked === true;
    if (!lockAcquired) return { processed: 0, accepted: 0, failed: 0, locked: false };
    const result = await drainNotificationOutbox({ limit });
    return { ...result, locked: true };
  } finally {
    if (lockAcquired) {
      await client
        .query("SELECT pg_advisory_unlock($1)", [OUTBOX_WORKER_LOCK_KEY])
        .catch(() => {});
    }
    client.release();
  }
}

export function startNotificationOutboxWorker() {
  if (workerTimer) return true;
  const intervalMs = parsePositiveInt(
    env.notificationOutboxIntervalMs,
    DEFAULT_INTERVAL_MS
  );
  workerTimer = setInterval(() => {
    if (workerRunPromise) return;
    workerRunPromise = processNotificationOutboxBatch({})
      .catch((error) => {
        console.error("[notification-outbox-worker] scheduled batch failed", error);
      })
      .finally(() => {
        workerRunPromise = null;
      });
  }, intervalMs);
  workerTimer.unref?.();
  return true;
}

export async function stopNotificationOutboxWorker() {
  if (workerTimer) {
    clearInterval(workerTimer);
    workerTimer = null;
  }
  await workerRunPromise;
}
