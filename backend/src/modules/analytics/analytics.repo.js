import { q } from "../../config/db.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";

function periodStart(range) {
  if (range === "day") return "DATE_TRUNC('day', NOW())";
  if (range === "month") return "DATE_TRUNC('month', NOW())";
  return "DATE_TRUNC('year', NOW())";
}

async function queryTotals(whereSql, whereParams, timeColumn = "created_at") {
  const ranges = ["day", "month", "year"];
  const out = {};

  for (const range of ranges) {
    const r = await q(
      `SELECT
         COUNT(*)::int AS orders_count,
         COUNT(*) FILTER (WHERE status = 'delivered')::int AS delivered_orders_count,
         COUNT(*) FILTER (WHERE status = 'cancelled')::int AS cancelled_orders_count,
         COALESCE(SUM(delivery_fee) FILTER (WHERE status <> 'cancelled'), 0) AS delivery_fees,
         COALESCE(SUM(total_amount) FILTER (WHERE status <> 'cancelled'), 0) AS total_amount,
         COALESCE(SUM(total_amount - subtotal) FILTER (WHERE status <> 'cancelled'), 0) AS app_fees,
         COALESCE(AVG(delivery_rating) FILTER (WHERE status = 'delivered'), 0) AS avg_delivery_rating,
         COALESCE(AVG(merchant_rating) FILTER (WHERE status = 'delivered'), 0) AS avg_merchant_rating,
         COALESCE(
           AVG(EXTRACT(EPOCH FROM (delivered_at - picked_up_at)) / 60)
             FILTER (WHERE delivered_at IS NOT NULL AND picked_up_at IS NOT NULL),
           0
         ) AS avg_delivery_minutes
       FROM customer_order
       WHERE ${whereSql}
         AND ${timeColumn} >= ${periodStart(range)}`,
      whereParams
    );

    out[range] = r.rows[0];
  }

  return out;
}

export async function getAdminAnalytics() {
  return queryTotals("1=1", []);
}

export async function getOwnerAnalytics(ownerUserId) {
  const out = {};
  for (const range of ["day", "month", "year"]) {
    const r = await q(
      `SELECT
         COUNT(*)::int AS orders_count,
         COUNT(*) FILTER (WHERE o.status = 'delivered')::int AS delivered_orders_count,
         COUNT(*) FILTER (WHERE o.status = 'cancelled')::int AS cancelled_orders_count,
         COALESCE(SUM(o.delivery_fee) FILTER (WHERE o.status <> 'cancelled'), 0) AS delivery_fees,
         COALESCE(SUM(o.total_amount) FILTER (WHERE o.status <> 'cancelled'), 0) AS total_amount,
         COALESCE(SUM(o.total_amount - o.subtotal) FILTER (WHERE o.status <> 'cancelled'), 0) AS app_fees,
         COALESCE(AVG(o.merchant_rating) FILTER (WHERE o.status = 'delivered'), 0) AS avg_merchant_rating,
         COALESCE(AVG(o.delivery_rating) FILTER (WHERE o.status = 'delivered'), 0) AS avg_delivery_rating
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE m.owner_user_id = $1
         AND o.created_at >= ${periodStart(range)}`,
      [ownerUserId]
    );
    out[range] = r.rows[0];
  }

  const blockR = await q(
    `SELECT
       o.customer_block,
       COUNT(*)::int AS orders_count
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE m.owner_user_id = $1
       AND o.status <> 'cancelled'
       AND o.created_at >= DATE_TRUNC('day', NOW())
     GROUP BY o.customer_block
     ORDER BY orders_count DESC`,
    [ownerUserId]
  );

  const topProductsR = await q(
    `SELECT
       oi.product_id,
       oi.product_name,
       SUM(oi.quantity)::int AS total_qty
     FROM order_item oi
     JOIN customer_order o ON o.id = oi.order_id
     JOIN merchant m ON m.id = o.merchant_id
     WHERE m.owner_user_id = $1
       AND o.status <> 'cancelled'
       AND o.created_at >= DATE_TRUNC('day', NOW())
     GROUP BY oi.product_id, oi.product_name
     ORDER BY total_qty DESC, oi.product_name ASC
     LIMIT 5`,
    [ownerUserId]
  );

  const statusTodayR = await q(
    `SELECT
       o.status,
       COUNT(*)::int AS orders_count
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE m.owner_user_id = $1
       AND o.created_at >= DATE_TRUNC('day', NOW())
     GROUP BY o.status
     ORDER BY orders_count DESC`,
    [ownerUserId]
  );

  return {
    ...out,
    blocksToday: blockR.rows,
    topProductsToday: topProductsR.rows,
    statusToday: statusTodayR.rows,
  };
}

export async function getDeliveryAnalytics(deliveryUserId) {
  const out = {};
  for (const range of ["day", "month", "year"]) {
    const r = await q(
      `SELECT
         COUNT(*)::int AS delivered_orders_count,
         COALESCE(SUM(total_amount), 0) AS delivered_total_amount,
         COALESCE(SUM(delivery_fee), 0) AS delivery_fees,
         COALESCE(AVG(delivery_rating), 0) AS avg_rating,
         COALESCE(
           SUM(
             CASE
               WHEN estimated_delivery_minutes IS NOT NULL
                AND picked_up_at IS NOT NULL
                AND delivered_at IS NOT NULL
                AND (EXTRACT(EPOCH FROM (delivered_at - picked_up_at)) / 60) <= estimated_delivery_minutes
               THEN 1
               ELSE 0
             END
           ),
           0
         )::int AS on_time_deliveries
       FROM customer_order
       WHERE delivery_user_id = $1
         AND status = 'delivered'
         AND delivered_at >= ${periodStart(range)}`,
      [deliveryUserId]
    );
    const row = r.rows[0];
    const delivered = Number(row.delivered_orders_count || 0);
    const onTime = Number(row.on_time_deliveries || 0);

    out[range] = {
      ...row,
      on_time_rate: delivered > 0 ? (onTime / delivered) * 100 : 0,
    };
  }
  return out;
}

export async function listPendingMerchants() {
  const r = await q(
    `SELECT
       m.id,
       m.name,
       m.type,
       m.phone,
       m.description,
       m.created_at,
       u.id AS owner_user_id,
       u.full_name AS owner_full_name,
       u.phone AS owner_phone
     FROM merchant m
     LEFT JOIN app_user u ON u.id = m.owner_user_id
     WHERE m.is_approved = FALSE
     ORDER BY m.id DESC`
  );
  return r.rows;
}

export async function approveMerchant(merchantId, approvedByUserId) {
  const r = await q(
    `UPDATE merchant
     SET is_approved = TRUE,
         approved_by_user_id = $2,
         approved_at = NOW()
     WHERE id = $1
       AND is_approved = FALSE
     RETURNING id, owner_user_id, name`,
    [merchantId, approvedByUserId]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications(
    [
      row.owner_user_id
        ? {
            userId: row.owner_user_id,
            type: "owner_merchant_approved",
            title: "تمت الموافقة على المتجر",
            body: `تمت الموافقة على متجر ${row.name}`,
            merchantId: row.id,
            payload: {
              merchantId: row.id,
            },
          }
        : null,
    ].filter(Boolean)
  );

  return true;
}

export async function getOwnerOutstanding(ownerUserId) {
  const approvedR = await q(
    `SELECT cutoff_delivered_at
     FROM merchant_settlement
     WHERE owner_user_id = $1
       AND status = 'approved'
     ORDER BY approved_at DESC
     LIMIT 1`,
    [ownerUserId]
  );
  const cutoff = approvedR.rows[0]?.cutoff_delivered_at || null;

  const pendingR = await q(
    `SELECT id, amount, requested_at
     FROM merchant_settlement
     WHERE owner_user_id = $1
       AND status = 'pending'
     ORDER BY requested_at DESC
     LIMIT 1`,
    [ownerUserId]
  );

  const dueR = await q(
    `SELECT
       m.id AS merchant_id,
       COALESCE(SUM(o.total_amount - o.subtotal), 0) AS outstanding_amount,
       COUNT(*)::int AS orders_count,
       MAX(o.delivered_at) AS cutoff_delivered_at
     FROM merchant m
     LEFT JOIN customer_order o
       ON o.merchant_id = m.id
      AND o.status = 'delivered'
      AND o.delivered_at IS NOT NULL
      AND ($2::timestamptz IS NULL OR o.delivered_at > $2::timestamptz)
     WHERE m.owner_user_id = $1
     GROUP BY m.id`,
    [ownerUserId, cutoff]
  );

  const row = dueR.rows[0];
  if (!row) {
    return {
      merchantId: null,
      outstandingAmount: 0,
      ordersCount: 0,
      cutoffDeliveredAt: null,
      pendingSettlement: pendingR.rows[0] || null,
    };
  }

  return {
    merchantId: row.merchant_id,
    outstandingAmount: Number(row.outstanding_amount || 0),
    ordersCount: Number(row.orders_count || 0),
    cutoffDeliveredAt: row.cutoff_delivered_at,
    pendingSettlement: pendingR.rows[0] || null,
  };
}

export async function createOwnerSettlementRequest(ownerUserId, requestedNote) {
  const due = await getOwnerOutstanding(ownerUserId);
  if (!due.merchantId) return null;

  if (due.pendingSettlement) {
    const err = new Error("SETTLEMENT_ALREADY_PENDING");
    err.status = 409;
    throw err;
  }

  if (Number(due.outstandingAmount || 0) <= 0) {
    const err = new Error("NO_OUTSTANDING_FEES");
    err.status = 400;
    throw err;
  }

  const r = await q(
    `INSERT INTO merchant_settlement
      (merchant_id, owner_user_id, amount, cutoff_delivered_at, requested_note, status)
     VALUES ($1,$2,$3,$4,$5,'pending')
     RETURNING *`,
    [
      due.merchantId,
      ownerUserId,
      due.outstandingAmount,
      due.cutoffDeliveredAt,
      requestedNote || null,
    ]
  );

  const settlement = r.rows[0];

  const backofficeUsersResult = await q(
    `SELECT id
     FROM app_user
     WHERE role IN ('admin', 'deputy_admin')`
  );

  await createManyNotifications(
    backofficeUsersResult.rows.map((user) => ({
      userId: user.id,
      type: "admin_settlement_requested",
      title: "طلب تسديد جديد",
      body: `صاحب متجر طلب تسديد مستحقات بقيمة ${Number(settlement.amount || 0).toFixed(0)} د.ع`,
      merchantId: settlement.merchant_id,
      payload: {
        settlementId: settlement.id,
        merchantId: settlement.merchant_id,
      },
    }))
  );

  return settlement;
}

export async function listPendingSettlements() {
  const r = await q(
    `SELECT
       s.*,
       m.name AS merchant_name,
       u.full_name AS owner_full_name,
       u.phone AS owner_phone
     FROM merchant_settlement s
     JOIN merchant m ON m.id = s.merchant_id
     JOIN app_user u ON u.id = s.owner_user_id
     WHERE s.status = 'pending'
     ORDER BY s.requested_at DESC`
  );
  return r.rows;
}

export async function approveSettlement(settlementId, approvedByUserId, adminNote) {
  const r = await q(
    `UPDATE merchant_settlement
     SET status = 'approved',
         approved_by_user_id = $2,
         approved_at = NOW(),
         admin_note = $3
     WHERE id = $1
       AND status = 'pending'
     RETURNING id, owner_user_id, merchant_id, amount`,
    [settlementId, approvedByUserId, adminNote || null]
  );
  const row = r.rows[0];
  if (!row) return false;

  await createManyNotifications([
    {
      userId: row.owner_user_id,
      type: "owner_settlement_approved",
      title: "تمت المصادقة على التسديد",
      body: `تمت المصادقة على طلب التسديد #${row.id} بقيمة ${Number(row.amount || 0).toFixed(0)} د.ع`,
      merchantId: row.merchant_id,
      payload: {
        settlementId: row.id,
      },
    },
  ]);

  return true;
}
