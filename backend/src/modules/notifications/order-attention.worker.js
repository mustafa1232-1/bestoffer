import { pool, q } from "../../config/db.js";
import { createManyNotifications } from "./notifications.repo.js";

const REMINDER_SWEEP_INTERVAL_MS = 10_000;
const REMINDER_REPEAT_SECONDS = 20;
const REMINDER_MAX_AGE_SECONDS = 120;
const REMINDER_LOCK_KEY = 842117;

let reminderTimer = null;
let reminderSweepInFlight = false;

async function listOwnerApprovalReminders() {
  const r = await q(
    `SELECT
       o.id,
       o.merchant_id,
       m.owner_user_id AS user_id,
       m.name AS merchant_name
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN LATERAL (
       SELECT n.created_at
       FROM app_notification n
       WHERE n.user_id = m.owner_user_id
         AND n.order_id = o.id
         AND n.type = 'owner_order_pending_reminder'
       ORDER BY n.created_at DESC
       LIMIT 1
     ) last_notice ON TRUE
     WHERE o.status = 'pending'
       AND m.owner_user_id IS NOT NULL
       AND o.created_at >= NOW() - (INTERVAL '1 second' * $1)
       AND (
         last_notice.created_at IS NULL
         OR last_notice.created_at <= NOW() - (INTERVAL '1 second' * $2)
       )
     ORDER BY o.id ASC
     LIMIT 40`,
    [REMINDER_MAX_AGE_SECONDS, REMINDER_REPEAT_SECONDS]
  );

  return r.rows.map((row) => ({
    userId: Number(row.user_id),
    type: "owner_order_pending_reminder",
    title: "طلب بانتظار موافقتك",
    body: `الطلب #${row.id} لدى ${row.merchant_name} ما زال بانتظار الموافقة.`,
    orderId: Number(row.id),
    merchantId: Number(row.merchant_id),
    payload: {
      orderId: Number(row.id),
      status: "pending",
      requiresAction: true,
      reminderKind: "owner_approval",
    },
  }));
}

async function listDeliveryPickupReminders() {
  const r = await q(
    `SELECT
       o.id,
       o.merchant_id,
       o.delivery_user_id AS user_id,
       m.name AS merchant_name
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN LATERAL (
       SELECT n.created_at
       FROM app_notification n
       WHERE n.user_id = o.delivery_user_id
         AND n.order_id = o.id
         AND n.type = 'delivery_order_ready_reminder'
       ORDER BY n.created_at DESC
       LIMIT 1
     ) last_notice ON TRUE
     WHERE o.status = 'ready_for_delivery'
       AND o.delivery_user_id IS NOT NULL
       AND o.updated_at >= NOW() - (INTERVAL '1 second' * $1)
       AND (
         last_notice.created_at IS NULL
         OR last_notice.created_at <= NOW() - (INTERVAL '1 second' * $2)
       )
     ORDER BY o.id ASC
     LIMIT 40`,
    [REMINDER_MAX_AGE_SECONDS, REMINDER_REPEAT_SECONDS]
  );

  return r.rows.map((row) => ({
    userId: Number(row.user_id),
    type: "delivery_order_ready_reminder",
    title: "الطلب بانتظار استلامك",
    body: `الطلب #${row.id} من ${row.merchant_name} جاهز الآن للاستلام.`,
    orderId: Number(row.id),
    merchantId: Number(row.merchant_id),
    payload: {
      orderId: Number(row.id),
      status: "ready_for_delivery",
      requiresAction: true,
      reminderKind: "delivery_pickup",
    },
  }));
}

async function listCustomerConfirmationReminders() {
  const r = await q(
    `SELECT
       o.id,
       o.merchant_id,
       o.customer_user_id AS user_id,
       m.name AS merchant_name
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN LATERAL (
       SELECT n.created_at
       FROM app_notification n
       WHERE n.user_id = o.customer_user_id
         AND n.order_id = o.id
         AND n.type = 'customer_order_delivered_reminder'
       ORDER BY n.created_at DESC
       LIMIT 1
     ) last_notice ON TRUE
     WHERE o.status = 'delivered'
       AND o.customer_confirmed_at IS NULL
       AND o.updated_at >= NOW() - (INTERVAL '1 second' * $1)
       AND (
         last_notice.created_at IS NULL
         OR last_notice.created_at <= NOW() - (INTERVAL '1 second' * $2)
       )
     ORDER BY o.id ASC
     LIMIT 40`,
    [REMINDER_MAX_AGE_SECONDS, REMINDER_REPEAT_SECONDS]
  );

  return r.rows.map((row) => ({
    userId: Number(row.user_id),
    type: "customer_order_delivered_reminder",
    title: "أكد استلام الطلب",
    body: `تم تسليم الطلب #${row.id} من ${row.merchant_name}. اضغط استلمت الطلب لإيقاف التنبيه.`,
    orderId: Number(row.id),
    merchantId: Number(row.merchant_id),
    payload: {
      orderId: Number(row.id),
      status: "delivered",
      requiresAction: true,
      reminderKind: "customer_confirmation",
    },
  }));
}

async function sweepOrderAttentionReminders() {
  const client = await pool.connect();
  let locked = false;
  try {
    const lockResult = await client.query(
      `SELECT pg_try_advisory_lock($1) AS locked`,
      [REMINDER_LOCK_KEY]
    );
    locked = lockResult.rows[0]?.locked === true;
    if (!locked) return;

    const [ownerRows, deliveryRows, customerRows] = await Promise.all([
      listOwnerApprovalReminders(),
      listDeliveryPickupReminders(),
      listCustomerConfirmationReminders(),
    ]);

    const rows = [...ownerRows, ...deliveryRows, ...customerRows];
    if (!rows.length) return;
    await createManyNotifications(rows);
  } finally {
    try {
      if (locked) {
        await client.query(`SELECT pg_advisory_unlock($1)`, [REMINDER_LOCK_KEY]);
      }
    } catch (error) {
      console.error("[notifications] failed to unlock reminder worker", error);
    } finally {
      client.release();
    }
  }
}

export function startOrderAttentionReminderWorker() {
  if (reminderTimer) return;

  const tick = async () => {
    if (reminderSweepInFlight) return;
    reminderSweepInFlight = true;
    try {
      await sweepOrderAttentionReminders();
    } catch (error) {
      console.error("[notifications] order attention reminder sweep failed", error);
    } finally {
      reminderSweepInFlight = false;
    }
  };

  void tick();
  reminderTimer = setInterval(() => {
    void tick();
  }, REMINDER_SWEEP_INTERVAL_MS);
  reminderTimer.unref?.();
}

export function stopOrderAttentionReminderWorker() {
  if (reminderTimer) {
    clearInterval(reminderTimer);
    reminderTimer = null;
  }
}
