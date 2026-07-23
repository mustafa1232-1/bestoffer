import { pool, q } from "../../config/db.js";
import { env } from "../../config/env.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import { directAssignDeliveryOrderTx } from "../commerce/commerce.repo.js";
import {
  loadAssignableGroupOrderIds,
  runGroupedAssignmentForGroupTx,
  settleGroupedJobIfChildrenTerminalTx,
} from "../delivery/delivery-job.service.js";
import { drainNotificationOutbox } from "../delivery/notification-outbox.worker.js";

const DELIVERY_ASSIGNMENT_WORKER_LOCK_KEY = 482917663;
const DEFAULT_BATCH_SIZE = 25;
const DEFAULT_INTERVAL_MS = 15000;

let workerTimer = null;
let workerRunPromise = null;

function parsePositiveInt(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.floor(parsed);
}

function workerConfig() {
  return {
    batchSize: parsePositiveInt(
      env.deliveryAssignmentRecoveryBatchSize,
      DEFAULT_BATCH_SIZE
    ),
    intervalMs: parsePositiveInt(
      env.deliveryAssignmentRecoveryIntervalMs,
      DEFAULT_INTERVAL_MS
    ),
  };
}

// Order states after which a courier must NOT be considered busy anymore.
const TERMINAL_ORDER_STATUS_SQL = `(
  'delivered',
  'delivered_by_courier',
  'received_by_customer',
  'completed',
  'cancelled',
  'cancelled_by_store',
  'cancelled_by_customer',
  'cancelled_by_admin',
  'failed_delivery',
  'returned_if_needed',
  'expired'
)`;

/**
 * Self-healing pass: release couriers that finished (or lost) their work but are
 * still flagged busy.
 *
 * A courier is excluded from every dispatch while an open `courier_assignment`
 * row or an `ASSIGNED` order still points at them, and the partial unique index
 * uq_courier_assignment_open_courier makes a leftover open row reject each new
 * assignment INSERT with 23505. Any write path that finishes an order without
 * closing both markers therefore retires that driver permanently.
 *
 * The write paths now close them at the source; this sweep is the safety net —
 * it repairs rows stranded by older builds and by any path we have not reached
 * yet. Every condition below is strictly terminal, so a courier mid-delivery is
 * never touched.
 */
export async function reconcileStaleCourierAssignments(client) {
  const summary = {
    closedTerminalOrderAssignments: 0,
    closedDetachedAssignments: 0,
    closedExpiredOffers: 0,
    closedTerminalJobAssignments: 0,
    settledFinishedGroupedJobs: 0,
    clearedOrderFlags: 0,
  };

  // 0. Grouped jobs whose child orders all finished, but whose job row was left
  //    ASSIGNED. This happens when the courier completes a multi-store delivery
  //    through the per-order screens: the children go terminal while
  //    delivery_job keeps holding the courier as `busy_grouped_job`.
  const finishedGroups = (
    await client.query(
      `SELECT j.order_group_id
         FROM delivery_job j
        WHERE j.assignment_status NOT IN ('COMPLETED', 'CANCELLED', 'FAILED')
          AND EXISTS (
            SELECT 1 FROM customer_order o WHERE o.order_group_id = j.order_group_id
          )
          AND NOT EXISTS (
            SELECT 1
              FROM customer_order o
             WHERE o.order_group_id = j.order_group_id
               AND o.status::text NOT IN ${TERMINAL_ORDER_STATUS_SQL}
          )
        LIMIT 100`
    )
  ).rows;
  for (const row of finishedGroups) {
    const settled = await settleGroupedJobIfChildrenTerminalTx(
      client,
      Number(row.order_group_id)
    );
    if (settled) summary.settledFinishedGroupedJobs += 1;
  }

  // 1. Open assignment on an order that already reached a terminal state.
  summary.closedTerminalOrderAssignments = (
    await client.query(
      `UPDATE courier_assignment ca
       SET ended_at = COALESCE(ca.ended_at, NOW()),
           ended_reason = COALESCE(
             ca.ended_reason,
             CASE
               WHEN o.status::text IN ('delivered','delivered_by_courier','received_by_customer','completed')
                 THEN 'COMPLETED'
               ELSE 'ORDER_CANCELLED'
             END
           ),
           status = CASE
             WHEN ca.status IN ('pending','assigned','accepted')
               AND o.status::text IN ('delivered','delivered_by_courier','received_by_customer','completed')
               THEN 'completed'
             WHEN ca.status IN ('pending','assigned','accepted') THEN 'cancelled'
             ELSE ca.status
           END
       FROM customer_order o
       WHERE o.id = ca.order_id
         AND ca.ended_at IS NULL
         AND o.status::text IN ${TERMINAL_ORDER_STATUS_SQL}`
    )
  ).rowCount;

  // 2. Open assignment whose order no longer belongs to that courier.
  summary.closedDetachedAssignments = (
    await client.query(
      `UPDATE courier_assignment ca
       SET ended_at = COALESCE(ca.ended_at, NOW()),
           ended_reason = COALESCE(ca.ended_reason, 'RELEASED'),
           status = CASE
             WHEN ca.status IN ('pending','assigned','accepted') THEN 'released'
             ELSE ca.status
           END
       FROM customer_order o
       WHERE o.id = ca.order_id
         AND ca.ended_at IS NULL
         AND ca.status IN ('assigned', 'accepted')
         AND o.delivery_user_id IS DISTINCT FROM ca.courier_user_id`
    )
  ).rowCount;

  // 3. Offers nobody ever answered.
  summary.closedExpiredOffers = (
    await client.query(
      `UPDATE courier_assignment
       SET ended_at = COALESCE(ended_at, NOW()),
           ended_reason = COALESCE(ended_reason, 'EXPIRED'),
           responded_at = COALESCE(responded_at, NOW()),
           status = 'expired'
       WHERE ended_at IS NULL
         AND status = 'pending'
         AND expires_at IS NOT NULL
         AND expires_at < NOW()`
    )
  ).rowCount;

  // 4. Grouped assignment on a delivery_job that already ended.
  summary.closedTerminalJobAssignments = (
    await client.query(
      `UPDATE courier_assignment ca
       SET ended_at = COALESCE(ca.ended_at, NOW()),
           ended_reason = COALESCE(
             ca.ended_reason,
             CASE WHEN j.lifecycle_status = 'DELIVERED' THEN 'COMPLETED' ELSE 'RELEASED' END
           ),
           status = CASE
             WHEN ca.status IN ('pending','assigned','accepted')
               AND j.lifecycle_status = 'DELIVERED' THEN 'completed'
             WHEN ca.status IN ('pending','assigned','accepted') THEN 'released'
             ELSE ca.status
           END
       FROM delivery_job j
       WHERE j.id = ca.delivery_job_id
         AND ca.ended_at IS NULL
         AND (
           j.lifecycle_status IN ('DELIVERED', 'CANCELLED', 'FAILED')
           OR j.assignment_status IN ('COMPLETED', 'CANCELLED', 'FAILED')
         )`
    )
  ).rowCount;

  // 5. Orders still flagged ASSIGNED although they are terminal.
  summary.clearedOrderFlags = (
    await client.query(
      `UPDATE customer_order o
       SET delivery_assignment_status = CASE
             WHEN o.status::text IN ('delivered','delivered_by_courier','received_by_customer','completed')
               THEN 'COMPLETED'
             ELSE 'CANCELLED'
           END,
           updated_at = NOW()
       WHERE o.delivery_assignment_status = 'ASSIGNED'
         AND o.status::text IN ${TERMINAL_ORDER_STATUS_SQL}`
    )
  ).rowCount;

  return summary;
}

export async function loadPendingAssignmentOrders(client, limit) {
  const safeLimit = Math.max(1, Math.min(100, Number(limit) || DEFAULT_BATCH_SIZE));
  const result = await client.query(
    `WITH picked AS (
       SELECT o.id
       FROM customer_order o
       WHERE o.delivery_assignment_status = 'PENDING_NO_DRIVER'
         AND o.status IN ('approved', 'preparing', 'ready_for_delivery')
         -- Multi-store group children are assigned as ONE grouped delivery_job,
         -- never individually. Excluding them here is the production cutover
         -- that stops the per-child worker from partially assigning a group.
         AND o.order_scope IS DISTINCT FROM 'group_child'
       ORDER BY COALESCE(o.courier_requested_at, o.prepared_at, o.updated_at, o.created_at) ASC,
                o.id ASC
       LIMIT $1
       FOR UPDATE SKIP LOCKED
     )
     SELECT
       o.id,
       o.merchant_id,
       o.customer_block,
       o.status,
       o.delivery_assignment_status,
       m.owner_user_id,
       m.name AS merchant_name
     FROM customer_order o
     JOIN picked p ON p.id = o.id
     JOIN merchant m ON m.id = o.merchant_id
     ORDER BY COALESCE(o.courier_requested_at, o.prepared_at, o.updated_at, o.created_at) ASC,
              o.id ASC`,
    [safeLimit]
  );
  return result.rows || [];
}

async function notifyAssignmentCommit({
  orderRow,
  assignmentResult,
}) {
  if (!assignmentResult?.assignmentCreated) return;
  const driver = assignmentResult.driver || null;
  const merchantOwnerUserId = Number(orderRow.owner_user_id || 0) || null;
  const payloadBase = {
    orderId: Number(orderRow.id),
    assignmentStatus: assignmentResult.assignmentStatus,
    assignmentId: assignmentResult.deliveryAssignment?.assignmentId || null,
    driver,
  };

  const notifications = [];
  if (driver?.id != null) {
    notifications.push({
      userId: Number(driver.id),
      type: "delivery_order_assigned",
      title: "تم إسناد طلب جديد إليك",
      body: `تم إسناد الطلب #${orderRow.id} من ${orderRow.merchant_name || "المتجر"} إليك.`,
      orderId: Number(orderRow.id),
      merchantId: Number(orderRow.merchant_id),
      payload: {
        ...payloadBase,
        target: "courier_orders_current",
        action: "open_assigned_order",
        roleScope: "courier",
      },
    });
  }

  if (merchantOwnerUserId) {
    notifications.push({
      userId: merchantOwnerUserId,
      type: "owner_delivery_assigned",
      title: "تم تعيين دلفري للطلب",
      body:
        driver?.name != null
          ? `تم تعيين ${driver.name} للطلب #${orderRow.id}.`
          : `تم تعيين دلفري للطلب #${orderRow.id}.`,
      orderId: Number(orderRow.id),
      merchantId: Number(orderRow.merchant_id),
      payload: {
        ...payloadBase,
        target: "merchant_order_details",
        action: "open_owner_order",
        roleScope: "owner",
      },
    });
  }

  notifications.push({
    userId: Number(orderRow.customer_user_id || 0),
    type: "customer_delivery_assigned",
    title: "تم تعيين التوصيل",
    body:
      driver?.name != null
        ? `تم تعيين ${driver.name} للطلب #${orderRow.id}.`
        : `تم تعيين دلفري للطلب #${orderRow.id}.`,
    orderId: Number(orderRow.id),
    merchantId: Number(orderRow.merchant_id),
    payload: {
      ...payloadBase,
      target: "order_tracking",
      action: "open_order_tracking",
      roleScope: "customer",
    },
  });

  await createManyNotifications(notifications.filter(Boolean));
}

async function loadGroupedAssignmentContext(client, orderGroupId) {
  const job = (
    await client.query(
      `SELECT j.id AS delivery_job_id, j.order_group_id, j.customer_user_id,
              j.delivery_user_id, j.assignment_status,
              u.full_name AS courier_name
         FROM delivery_job j
         LEFT JOIN app_user u ON u.id = j.delivery_user_id
        WHERE j.order_group_id = $1`,
      [Number(orderGroupId)]
    )
  ).rows[0];
  if (!job) return null;
  const stops = (
    await client.query(
      `SELECT s.child_order_id, s.store_id, m.name AS store_name, m.owner_user_id
         FROM delivery_pickup_stop s
         LEFT JOIN merchant m ON m.id = s.store_id
        WHERE s.delivery_job_id = $1 AND s.pickup_status <> 'CANCELLED'
        ORDER BY s.sequence_number`,
      [Number(job.delivery_job_id)]
    )
  ).rows;
  return { job, stops };
}

async function notifyGroupedAssignment({ context }) {
  if (!context) return;
  const { job, stops } = context;
  const courierId = Number(job.delivery_user_id) || null;
  if (!courierId) return;
  const storesCount = stops.length;
  const notifications = [];

  // NOTE: the courier assignment notification is delivered by the notification
  // outbox drain (durable, eventId-deduplicated) — see notification-outbox.worker
  // — so it is intentionally NOT pushed here to avoid a duplicate. The customer
  // and store owners get their immediate notifications below.

  if (job.customer_user_id) {
    notifications.push({
      userId: Number(job.customer_user_id),
      type: "customer_delivery_assigned",
      title: "تم تعيين التوصيل",
      body: job.courier_name
        ? `تم تعيين ${job.courier_name} لتوصيل طلبك.`
        : "تم تعيين دلفري لتوصيل طلبك.",
      orderId: Number(stops[0]?.child_order_id) || null,
      merchantId: Number(stops[0]?.store_id) || null,
      payload: {
        deliveryJobId: Number(job.delivery_job_id),
        orderGroupId: Number(job.order_group_id),
        target: "order_tracking",
        action: "open_order_tracking",
        roleScope: "customer",
      },
    });
  }

  const seenOwners = new Set();
  for (const stop of stops) {
    const ownerId = Number(stop.owner_user_id) || null;
    if (!ownerId || seenOwners.has(ownerId)) continue;
    seenOwners.add(ownerId);
    notifications.push({
      userId: ownerId,
      type: "owner_delivery_assigned",
      title: "تم تعيين دلفري للطلب",
      body: job.courier_name
        ? `تم تعيين ${job.courier_name} لاستلام طلب متجرك.`
        : "تم تعيين دلفري لاستلام طلب متجرك.",
      orderId: Number(stop.child_order_id) || null,
      merchantId: Number(stop.store_id) || null,
      payload: {
        deliveryJobId: Number(job.delivery_job_id),
        orderGroupId: Number(job.order_group_id),
        target: "merchant_order_details",
        action: "open_owner_order",
        roleScope: "owner",
      },
    });
  }

  await createManyNotifications(notifications.filter(Boolean));
}

/**
 * Grouped assignment pass (§4). Loads assignable grouped jobs and processes each
 * one in its own transaction through the authoritative grouped assignment
 * service. One job per order_group, one courier, outbox committed with the
 * assignment. Returns a summary.
 */
export async function processGroupedAssignmentBatch({
  limit = DEFAULT_BATCH_SIZE,
  orderGroupIds = null,
  restrictToCourierUserIds = null,
} = {}) {
  const loader = await pool.connect();
  let groupIds = [];
  try {
    await loader.query("BEGIN");
    groupIds = await loadAssignableGroupOrderIds(loader, limit, { orderGroupIds });
    await loader.query("COMMIT");
  } catch (error) {
    await loader.query("ROLLBACK").catch(() => {});
    console.error("[grouped-assignment-worker] load failed", error);
    return { processed: 0, assigned: 0, pending: 0 };
  } finally {
    loader.release();
  }

  const summary = { processed: groupIds.length, assigned: 0, pending: 0 };
  for (const orderGroupId of groupIds) {
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      const outcome = await runGroupedAssignmentForGroupTx(client, orderGroupId, {
        restrictToCourierUserIds,
      });
      let context = null;
      if (outcome.status === "ASSIGNED") {
        context = await loadGroupedAssignmentContext(client, orderGroupId);
      }
      await client.query("COMMIT");

      if (outcome.status === "ASSIGNED") {
        summary.assigned += 1;
        await notifyGroupedAssignment({ context });
      } else if (outcome.status === "PENDING_NO_DRIVER") {
        summary.pending += 1;
      }
    } catch (error) {
      await client.query("ROLLBACK").catch(() => {});
      console.error("[grouped-assignment-worker] group failed", {
        orderGroupId,
        error: error?.message || String(error),
      });
    } finally {
      client.release();
    }
  }

  // Drain the transactional outbox so grouped events reach the provider surface.
  try {
    await drainNotificationOutbox({ limit });
  } catch (error) {
    console.error("[grouped-assignment-worker] outbox drain failed", error);
  }

  return summary;
}

export async function processDeliveryAssignmentRecoveryBatch({ limit = DEFAULT_BATCH_SIZE } = {}) {
  const client = await pool.connect();
  let lockAcquired = false;
  try {
    const lock = await client.query(
      "SELECT pg_try_advisory_lock($1) AS locked",
      [DELIVERY_ASSIGNMENT_WORKER_LOCK_KEY]
    );
    lockAcquired = lock.rows[0]?.locked === true;
    if (!lockAcquired) {
      return { processed: 0, assigned: 0, pending: 0, locked: false };
    }

    // Release couriers stranded by a terminal order/job BEFORE selecting
    // candidates, so this same round can hand them the waiting work.
    let reconciled = null;
    try {
      await client.query("BEGIN");
      reconciled = await reconcileStaleCourierAssignments(client);
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK").catch(() => {});
      console.error("[delivery-assignment-worker] reconcile failed", error);
    }

    await client.query("BEGIN");
    const rows = await loadPendingAssignmentOrders(client, limit);
    await client.query("COMMIT");

    const summary = {
      processed: rows.length,
      assigned: 0,
      pending: 0,
      locked: true,
      reconciled,
    };

    for (const row of rows) {
      const txClient = await pool.connect();
      try {
        await txClient.query("BEGIN");
        const assignmentResult = await directAssignDeliveryOrderTx(txClient, {
          orderId: Number(row.id),
          merchantId: Number(row.merchant_id),
          requestedByUserId: null,
          customerBlock: row.customer_block || null,
          assignmentType: "recovery",
          allowPending: true,
          note: "recovery_assignment",
          forceMerchantCourier: null,
        });
        await txClient.query("COMMIT");

        if (assignmentResult.assignmentCreated) {
          summary.assigned += 1;
          await notifyAssignmentCommit({
            orderRow: row,
            assignmentResult,
          });
        } else if (assignmentResult.pendingNoDriver) {
          summary.pending += 1;
        }
      } catch (error) {
        await txClient.query("ROLLBACK").catch(() => {});
        console.error("[delivery-assignment-worker] recovery row failed", {
          orderId: row?.id || null,
          error: error?.message || String(error),
        });
      } finally {
        txClient.release();
      }
    }

    // Grouped multi-store pass: assign whole delivery_jobs as one unit.
    const grouped = await processGroupedAssignmentBatch({ limit });
    summary.grouped = grouped;
    summary.assigned += grouped.assigned;
    summary.pending += grouped.pending;

    return summary;
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {}
    console.error("[delivery-assignment-worker] batch failed", error);
    return { processed: 0, assigned: 0, pending: 0, locked: lockAcquired, error };
  } finally {
    if (lockAcquired) {
      await client.query("SELECT pg_advisory_unlock($1)", [
        DELIVERY_ASSIGNMENT_WORKER_LOCK_KEY,
      ]).catch(() => {});
    }
    client.release();
  }
}

export function startDeliveryAssignmentRecoveryWorker() {
  if (workerTimer) return true;
  const { intervalMs, batchSize } = workerConfig();
  workerTimer = setInterval(() => {
    if (workerRunPromise) return;
    workerRunPromise = processDeliveryAssignmentRecoveryBatch({ limit: batchSize })
      .catch((error) => {
        console.error("[delivery-assignment-worker] scheduled batch failed", error);
      })
      .finally(() => {
        workerRunPromise = null;
      });
  }, intervalMs);
  workerTimer.unref?.();
  void processDeliveryAssignmentRecoveryBatch({ limit: batchSize }).catch((error) => {
    console.error("[delivery-assignment-worker] startup batch failed", error);
  });
  return true;
}

export async function stopDeliveryAssignmentRecoveryWorker() {
  if (workerTimer) {
    clearInterval(workerTimer);
    workerTimer = null;
  }
  await workerRunPromise;
}

export async function requestDeliveryAssignmentRecovery({ limit = DEFAULT_BATCH_SIZE } = {}) {
  // Opt-out for deterministic tests: disable the fire-and-forget recovery so it
  // cannot race foreground assertions or mutate other tests' shared-DB state.
  if (process.env.DELIVERY_AUTO_RECOVERY_DISABLED === "1") {
    return { processed: 0, assigned: 0, pending: 0, disabled: true };
  }
  if (workerRunPromise) return workerRunPromise;
  workerRunPromise = processDeliveryAssignmentRecoveryBatch({ limit })
    .catch((error) => {
      console.error("[delivery-assignment-worker] manual batch failed", error);
    })
    .finally(() => {
      workerRunPromise = null;
    });
  return workerRunPromise;
}
