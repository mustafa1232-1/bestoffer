import { pool } from "../../config/db.js";
import { env } from "../../config/env.js";
import { createNotificationAndAwaitDelivery } from "../notifications/notifications.repo.js";

/**
 * Notification outbox sender (delivery closure §1, §2, §3, §5).
 *
 * The business transaction writes a `notification_outbox` row atomically with
 * the state change (e.g. grouped assignment). This worker delivers those rows
 * with TRUTHFUL states — creating an app_notification is NOT provider acceptance;
 * only a real Firebase result advances a row to PUSH_ACCEPTED/PUSH_PARTIAL.
 *
 * Crash safety: a row is leased (status=PROCESSING, lease_expires_at). If a
 * worker dies mid-flight, the lease expires and another worker recovers the row.
 * Because app_notification is inserted idempotently by event_id
 * (createNotificationAndAwaitDelivery), recovery never duplicates the in-app
 * notification — it only re-attempts push, bounded by the attempt policy.
 *
 * Push is not the source of truth (§13): couriers/stores also recover state via
 * API bootstrap, so a dropped push is self-healing.
 */

const OUTBOX_WORKER_LOCK_KEY = 482917664;
const DEFAULT_BATCH_SIZE = 50;
const DEFAULT_INTERVAL_MS = 10000;
const MAX_ATTEMPTS = 6;
const BASE_BACKOFF_SEC = 15;
const LEASE_SECONDS = 60;

let workerTimer = null;
let workerRunPromise = null;

function parsePositiveInt(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.floor(parsed);
}

// Authoritative surface per role (mirrors resolveRoleAppSurface). The courier
// surface is `delivery`, never `courier`.
const ROLE_TO_SURFACE = {
  user: "user",
  owner: "store",
  employee: "store",
  delivery: "delivery",
  taxi: "taxi",
  company: "company",
  admin: "company",
};

// Map an outbox event to the urgent Android channel + human copy. The channel
// id must be one of the allow-listed urgent channels (§4).
function describeEvent(row) {
  const payload = row.payload_json || {};
  const stores = Number(payload.stores || payload.numberOfStores || 1) || 1;
  switch (row.event_type) {
    case "COURIER_MULTI_STORE_DELIVERY_ASSIGNED":
      return {
        type: "delivery_grouped_assigned",
        title: `تم إسناد توصيل من ${stores} متاجر إليك`,
        body: `مهمة توصيل مجمّعة${payload.orderGroupId ? ` #${payload.orderGroupId}` : ""}: استلم من ${stores} متاجر وسلّمها للزبون.`,
        textEn: {
          title: `Multi-store delivery assigned (${stores} stores)`,
          body: `Grouped delivery${payload.orderGroupId ? ` #${payload.orderGroupId}` : ""}: pick up from ${stores} stores.`,
        },
        target: "courier_orders_current",
        urgentChannelId: "maslaki_courier_assignments_urgent_v2",
        surface: "delivery",
      };
    case "COURIER_DELIVERY_ASSIGNED":
      return {
        type: "delivery_grouped_assigned",
        title: `تم إسناد طلب توصيل إليك${payload.orderGroupId ? ` #${payload.orderGroupId}` : ""}`,
        body: "افتح الطلبات الحالية لمشاهدة المتجر وعنوان الزبون.",
        textEn: {
          title: `Delivery assigned to you${payload.orderGroupId ? ` #${payload.orderGroupId}` : ""}`,
          body: "Open current orders to see the store and customer address.",
        },
        target: "courier_orders_current",
        urgentChannelId: "maslaki_courier_assignments_urgent_v2",
        surface: "delivery",
      };
    case "STORE_NEW_ORDER":
    case "COURIER_ASSIGNED_TO_STORE_ORDER":
    case "COURIER_ARRIVED_AT_STORE":
    case "COURIER_COLLECTED_STORE_ORDER": {
      const orderRef = payload.orderId ? ` #${payload.orderId}` : "";
      const storeCopy = {
        STORE_NEW_ORDER: [`طلب جديد${orderRef}`, "افتح الطلب لقبوله وبدء التحضير.", `New order${orderRef}`, "Open the order to accept it."],
        COURIER_ASSIGNED_TO_STORE_ORDER: [`تم تعيين دلفري للطلب${orderRef}`, "الدلفري في الطريق لاستلام الطلب.", `Courier assigned to order${orderRef}`, "The courier is on the way to pick it up."],
        COURIER_ARRIVED_AT_STORE: [`الدلفري وصل لاستلام الطلب${orderRef}`, "سلّم الطلب للدلفري.", `Courier arrived for order${orderRef}`, "Hand the order to the courier."],
        COURIER_COLLECTED_STORE_ORDER: [`الدلفري استلم الطلب${orderRef}`, "الطلب خرج من المتجر باتجاه الزبون.", `Courier collected order${orderRef}`, "The order left the store."],
      }[row.event_type];
      return {
        type: String(row.event_type).toLowerCase(),
        title: storeCopy[0],
        body: storeCopy[1],
        textEn: { title: storeCopy[2], body: storeCopy[3] },
        target: "owner_orders",
        urgentChannelId: "maslaki_store_orders_urgent_v2",
        surface: "store",
      };
    }
    case "MERCHANT_REVIEW_CREATED": {
      const rating = Number(payload.rating || 0);
      return {
        type: "merchant_review_created",
        title: rating > 0 ? `تقييم جديد لمتجرك: ${rating}/5` : "تقييم جديد لمتجرك",
        body: payload.orderId
          ? `زبون قيّم الطلب #${payload.orderId}. افتح الطلب لمشاهدة التقييم.`
          : "زبون أضاف تقييماً موثقاً لمتجرك.",
        textEn: {
          title: rating > 0 ? `New store review: ${rating}/5` : "New store review",
          body: payload.orderId
            ? `A customer reviewed order #${payload.orderId}.`
            : "A customer left a verified review for your store.",
        },
        target: payload.orderId ? "merchant_order_details" : "merchant_reports",
        urgentChannelId: null,
        surface: "store",
      };
    }
    default:
      return {
        type: String(row.event_type || "delivery_event").toLowerCase(),
        title: "تحديث على مهمة التوصيل",
        body: "افتح الطلبات الحالية لمشاهدة آخر تحديث.",
        urgentChannelId: null,
        surface: null,
      };
  }
}

function boundedResult(delivery) {
  // Safe, bounded provider result — NO tokens, NO secrets.
  return {
    firebaseConfigured: !!delivery.firebaseConfigured,
    totalTokens: Number(delivery.totalTokens || 0),
    acceptedTokens: Number(delivery.acceptedTokens || 0),
    deadTokens: Number(delivery.deadTokens || 0),
    retryableFailures: Number(delivery.retryableFailures || 0),
    permanentFailures: Number(delivery.permanentFailures || 0),
    providerMessageIds: Array.isArray(delivery.providerMessageIds)
      ? delivery.providerMessageIds.slice(0, 10)
      : [],
    errorCode: delivery.errorCode ? String(delivery.errorCode).slice(0, 64) : null,
  };
}

// Decide the truthful terminal/retry state from the provider result.
function decideState(delivery, attemptCount) {
  const total = Number(delivery.totalTokens || 0);
  const accepted = Number(delivery.acceptedTokens || 0);
  const retryable = Number(delivery.retryableFailures || 0);
  const attemptsSoFar = Number(attemptCount || 0) + 1;
  const exhausted = attemptsSoFar >= MAX_ATTEMPTS;

  const retry = () =>
    exhausted
      ? { status: "DEAD_LETTER", terminal: true }
      : {
          status: "PUSH_RETRY",
          terminal: false,
          backoffSec: BASE_BACKOFF_SEC * Math.pow(2, attemptsSoFar - 1),
        };

  if (!delivery.firebaseConfigured) return retry(); // config may appear later
  if (total === 0) return { status: "PUSH_FAILED", terminal: true }; // nothing to deliver
  if (accepted >= total) return { status: "PUSH_ACCEPTED", terminal: true };
  if (accepted > 0) return { status: "PUSH_PARTIAL", terminal: true };
  if (retryable > 0) return retry();
  return { status: "PUSH_FAILED", terminal: true }; // only permanent/dead
}

async function leaseDueRows(client, limit) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || DEFAULT_BATCH_SIZE));
  const rows = (
    await client.query(
      `SELECT o.id, o.event_id, o.event_type, o.recipient_user_id, o.target_surface,
              o.target_entity_type, o.target_entity_id, o.payload_json, o.attempt_count,
              o.app_notification_id, u.role AS recipient_role
         FROM notification_outbox o
         JOIN app_user u ON u.id = o.recipient_user_id
        WHERE (
                (o.status IN ('CREATED','PUSH_RETRY') AND o.next_attempt_at <= NOW())
                OR (o.status IN ('PROCESSING','NOTIFICATION_CREATED')
                    AND o.lease_expires_at IS NOT NULL AND o.lease_expires_at <= NOW())
              )
        ORDER BY o.next_attempt_at ASC, o.id ASC
        LIMIT $1
        FOR UPDATE SKIP LOCKED`,
      [safeLimit]
    )
  ).rows;
  if (rows.length > 0) {
    await client.query(
      `UPDATE notification_outbox
          SET status='PROCESSING', processing_started_at=NOW(),
              lease_expires_at = NOW() + ($2 || ' seconds')::interval
        WHERE id = ANY($1::bigint[])`,
      [rows.map((r) => Number(r.id)), String(LEASE_SECONDS)]
    );
  }
  return rows;
}

async function finalizeRow(client, id, state, appNotificationId, resultJson) {
  const nextAttempt =
    state.status === "PUSH_RETRY" && state.backoffSec
      ? `NOW() + INTERVAL '${Math.floor(state.backoffSec)} seconds'`
      : "next_attempt_at";
  await client.query(
    `UPDATE notification_outbox
        SET status=$2::text,
            attempt_count = attempt_count + 1,
            app_notification_id = COALESCE($3::bigint, app_notification_id),
            provider_result_json = $4::jsonb,
            lease_expires_at = NULL,
            next_attempt_at = ${nextAttempt},
            completed_at = CASE WHEN $5::boolean THEN NOW() ELSE completed_at END,
            sent_at = CASE WHEN $2::text IN ('PUSH_ACCEPTED','PUSH_PARTIAL') THEN NOW() ELSE sent_at END,
            last_error_code = $6::text
      WHERE id=$1::bigint`,
    [
      id,
      state.status,
      appNotificationId == null ? null : Number(appNotificationId),
      JSON.stringify(resultJson || {}),
      state.terminal === true,
      resultJson?.errorCode || null,
    ]
  );
}

/**
 * Drain due/recoverable outbox rows once. Each row is processed independently.
 */
export async function drainNotificationOutbox({ limit = DEFAULT_BATCH_SIZE } = {}) {
  const loader = await pool.connect();
  let rows = [];
  const summary = {
    processed: 0,
    accepted: 0,
    partial: 0,
    retry: 0,
    failed: 0,
    deadLettered: 0,
    suppressed: 0,
  };
  try {
    await loader.query("BEGIN");
    rows = await leaseDueRows(loader, limit);
    await loader.query("COMMIT");
  } catch (error) {
    await loader.query("ROLLBACK").catch(() => {});
    console.error("[notification-outbox-worker] lease failed", error);
    return summary;
  } finally {
    loader.release();
  }

  for (const row of rows) {
    summary.processed += 1;
    const client = await pool.connect();
    try {
      const copy = describeEvent(row);
      const payload = row.payload_json || {};
      const targetSurface = String(row.target_surface || "").trim().toLowerCase();
      const expectedSurface = ROLE_TO_SURFACE[String(row.recipient_role || "").toLowerCase()] || null;

      // §5: fail closed on wrong-surface delivery. Do NOT send a courier event
      // to a non-delivery recipient (or a mismatched target_surface).
      if (!expectedSurface || targetSurface !== expectedSurface) {
        await client.query("BEGIN");
        await finalizeRow(
          client,
          row.id,
          { status: "PUSH_FAILED", terminal: true },
          row.app_notification_id,
          { suppressed: "surface_mismatch", targetSurface, expectedSurface }
        );
        await client.query("COMMIT");
        summary.suppressed += 1;
        continue;
      }

      // Mark NOTIFICATION_CREATED before creating the row so a crash after
      // creation but before finalize is recoverable (idempotent by event_id).
      await client.query(
        `UPDATE notification_outbox SET status='NOTIFICATION_CREATED' WHERE id=$1`,
        [row.id]
      );

      const { notificationId, delivery } = await createNotificationAndAwaitDelivery({
        userId: Number(row.recipient_user_id),
        type: copy.type,
        title: copy.title,
        body: copy.body,
        textEn: copy.textEn || null,
        orderId: Number(payload.orderId) > 0 ? Number(payload.orderId) : null,
        merchantId: null,
        eventId: row.event_id,
        payload: {
          ...payload,
          eventId: row.event_id,
          eventType: row.event_type,
          schemaVersion: 1,
          appSurface: expectedSurface,
          targetSurface,
          urgentChannelId: copy.urgentChannelId || undefined,
          ...(copy.target && !payload.target ? { target: copy.target } : {}),
          requiresAction: true,
          targetEntityType: row.target_entity_type,
          targetEntityId: Number(row.target_entity_id) || null,
        },
      });

      const state = decideState(delivery, row.attempt_count);
      await client.query("BEGIN");
      await finalizeRow(client, row.id, state, notificationId, boundedResult(delivery));
      await client.query("COMMIT");

      if (state.status === "PUSH_ACCEPTED") summary.accepted += 1;
      else if (state.status === "PUSH_PARTIAL") summary.partial += 1;
      else if (state.status === "PUSH_RETRY") summary.retry += 1;
      else if (state.status === "DEAD_LETTER") summary.deadLettered += 1;
      else summary.failed += 1;
    } catch (error) {
      await client.query("ROLLBACK").catch(() => {});
      // Leave the row in PROCESSING with an expired-soon lease so it recovers.
      try {
        await client.query(
          `UPDATE notification_outbox
              SET status='PUSH_RETRY', attempt_count = attempt_count + 1,
                  lease_expires_at = NULL,
                  next_attempt_at = NOW() + INTERVAL '30 seconds',
                  last_error_code = $2
            WHERE id=$1`,
          [row.id, String(error?.code || error?.message || "worker_exception").slice(0, 64)]
        );
      } catch (inner) {
        console.error("[notification-outbox-worker] recovery bookkeeping failed", inner);
      }
      summary.retry += 1;
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
    if (!lockAcquired) return { processed: 0, locked: false };
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
