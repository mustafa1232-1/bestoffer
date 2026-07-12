import { pool, q } from "../../config/db.js";
import { env } from "../../config/env.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import { directAssignDeliveryOrderTx } from "../commerce/commerce.repo.js";

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

async function loadPendingAssignmentOrders(client, limit) {
  const safeLimit = Math.max(1, Math.min(100, Number(limit) || DEFAULT_BATCH_SIZE));
  const result = await client.query(
    `WITH picked AS (
       SELECT o.id
       FROM customer_order o
       WHERE o.delivery_assignment_status = 'PENDING_NO_DRIVER'
         AND o.status IN ('approved', 'preparing', 'ready_for_delivery')
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
