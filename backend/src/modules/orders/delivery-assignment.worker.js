import { pool, q } from "../../config/db.js";
import { env } from "../../config/env.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import { directAssignDeliveryOrderTx } from "../commerce/commerce.repo.js";
import {
  loadAssignableGroupOrderIds,
  runGroupedAssignmentForGroupTx,
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

    await client.query("BEGIN");
    const rows = await loadPendingAssignmentOrders(client, limit);
    await client.query("COMMIT");

    const summary = {
      processed: rows.length,
      assigned: 0,
      pending: 0,
      locked: true,
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
