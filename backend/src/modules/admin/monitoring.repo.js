/**
 * Purpose:
 * تجميعات لوحة المتابعة الموحدة (المرحلة 3) التي لا تخص وحدة التاكسي.
 * عدّادات الطلبات تُقرأ مباشرة من customer_order (قراءة تجميعية للـbackoffice).
 * التوقيت المحلي: Asia/Baghdad.
 */

import { q } from "../../config/db.js";

const ORDER_TERMINAL_STATUSES = [
  "delivered",
  "completed",
  "received_by_customer",
  "cancelled",
  "cancelled_by_admin",
  "cancelled_by_customer",
  "cancelled_by_store",
  "expired",
  "failed_delivery",
];

const ORDER_COMPLETED_STATUSES = ["completed", "delivered", "received_by_customer"];
const ORDER_CANCELLED_STATUSES = [
  "cancelled",
  "cancelled_by_admin",
  "cancelled_by_customer",
  "cancelled_by_store",
  "expired",
  "failed_delivery",
];

const ORDER_ACTIVE_STATUSES = [
  "pending",
  "approved",
  "accepted_by_store",
  "preparing",
  "ready_for_delivery",
  "courier_requested",
  "courier_assigned",
  "on_the_way",
  "picked_up",
  "arrived",
];

const ORDER_NEEDS_DELIVERY_STATUSES = [
  "ready_for_delivery",
  "courier_requested",
];

const DELIVERY_JOB_TERMINAL_STATUSES = ["COMPLETED", "CANCELLED", "FAILED"];
const SUPPORT_OPEN_STATUSES = [
  "new",
  "assigned",
  "in_progress",
  "waiting_customer",
  "waiting_internal",
  "escalated",
  "reopened",
];

function safeLimitOffset({ limit = 25, offset = 0 } = {}) {
  return {
    limit: Math.max(1, Math.min(100, Number(limit) || 25)),
    offset: Math.max(0, Number(offset) || 0),
  };
}

function addDateFilters({ conds, params, from, to, column = "created_at" }) {
  if (from) {
    params.push(from);
    conds.push(`${column} >= $${params.length}`);
  }
  if (to) {
    params.push(to);
    conds.push(`${column} <= $${params.length}`);
  }
}

export async function getOrderMonitoringCounters() {
  const r = await q(
    `SELECT
       COUNT(*) FILTER (WHERE status::text <> ALL($1))::int AS active,
       COUNT(*) FILTER (
         WHERE status::text = ANY($2)
           AND (updated_at AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS completed_today,
       COUNT(*) FILTER (
         WHERE status::text = ANY($3)
           AND (updated_at AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS cancelled_today
     FROM customer_order`,
    [ORDER_TERMINAL_STATUSES, ORDER_COMPLETED_STATUSES, ORDER_CANCELLED_STATUSES]
  );
  const attention = await q(
    `SELECT
       COUNT(*) FILTER (
         WHERE status::text = ANY($1)
            OR delivery_assignment_status = 'PENDING_NO_DRIVER'
            OR (
              status::text = ANY($2)
              AND updated_at < NOW() - INTERVAL '45 minutes'
            )
       )::int AS needs_attention,
       COUNT(*) FILTER (
         WHERE status::text = ANY($2)
           AND updated_at < NOW() - INTERVAL '45 minutes'
       )::int AS delayed,
       COUNT(*) FILTER (
         WHERE EXISTS (
           SELECT 1 FROM support_ticket st
           WHERE st.entity_type IN ('order','customer_order')
             AND st.entity_id::text = customer_order.id::text
             AND st.status = ANY($3)
         )
       )::int AS open_tickets
     FROM customer_order`,
    [ORDER_NEEDS_DELIVERY_STATUSES, ORDER_ACTIVE_STATUSES, SUPPORT_OPEN_STATUSES]
  );
  const row = r.rows[0] || {};
  const attentionRow = attention.rows[0] || {};
  return {
    active: Number(row.active || 0),
    completedToday: Number(row.completed_today || 0),
    cancelledToday: Number(row.cancelled_today || 0),
    delayed: Number(attentionRow.delayed || 0),
    needsAttention: Number(attentionRow.needs_attention || 0),
    openTickets: Number(attentionRow.open_tickets || 0),
  };
}

export async function getDeliveryMonitoringCounters() {
  const r = await q(
    `SELECT
       COUNT(*) FILTER (
         WHERE cp.active_status = TRUE
           AND cp.availability_status = 'online'
       )::int AS available,
       COUNT(*) FILTER (
         WHERE cp.active_status = TRUE
           AND cp.availability_status = 'online'
           AND p.is_online = TRUE
           AND p.updated_at >= NOW() - INTERVAL '90 seconds'
       )::int AS online_fresh,
       COUNT(*) FILTER (
         WHERE EXISTS (
           SELECT 1
           FROM courier_assignment ca
           WHERE ca.courier_user_id = cp.user_id
             AND ca.ended_at IS NULL
             AND ca.status IN ('assigned','accepted')
         )
         OR EXISTS (
           SELECT 1
           FROM delivery_job dj
           WHERE dj.delivery_user_id = cp.user_id
             AND dj.assignment_status = 'ASSIGNED'
         )
       )::int AS active_delivery
     FROM courier_profile cp
     LEFT JOIN courier_presence p ON p.courier_user_id = cp.user_id`
  );
  const orders = await q(
    `SELECT
       COUNT(*) FILTER (
         WHERE delivery_assignment_status = 'PENDING_NO_DRIVER'
            OR status::text = ANY($1)
       )::int AS pending_no_driver,
       COUNT(*) FILTER (
         WHERE delivery_user_id IS NOT NULL
           AND status::text = ANY($2)
       )::int AS active_orders,
       COUNT(*) FILTER (
         WHERE status::text = ANY($3)
           AND (COALESCE(delivered_at, completed_at, customer_confirmed_at, updated_at)
                AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS deliveries_today,
       COUNT(*) FILTER (
         WHERE status::text = ANY($2)
           AND updated_at < NOW() - INTERVAL '45 minutes'
       )::int AS delayed
     FROM customer_order`,
    [
      ORDER_NEEDS_DELIVERY_STATUSES,
      ORDER_ACTIVE_STATUSES,
      ORDER_COMPLETED_STATUSES,
    ]
  );
  const row = r.rows[0] || {};
  const orderRow = orders.rows[0] || {};
  return {
    active: Number(row.active_delivery || orderRow.active_orders || 0),
    available: Number(row.available || 0),
    onlineFresh: Number(row.online_fresh || 0),
    pendingNoDriver: Number(orderRow.pending_no_driver || 0),
    deliveriesToday: Number(orderRow.deliveries_today || 0),
    delayed: Number(orderRow.delayed || 0),
  };
}

export async function listOrdersForMonitoring({
  status = null,
  search = "",
  from = null,
  to = null,
  merchantId = null,
  userId = null,
  deliveryUserId = null,
  sort = "updated_desc",
  limit = 25,
  offset = 0,
} = {}) {
  const page = safeLimitOffset({ limit, offset });
  const conds = [];
  const params = [];

  if (status) {
    params.push(String(status));
    conds.push(`o.status::text = $${params.length}`);
  }
  if (merchantId) {
    params.push(Number(merchantId));
    conds.push(`o.merchant_id = $${params.length}`);
  }
  if (userId) {
    params.push(Number(userId));
    conds.push(`o.customer_user_id = $${params.length}`);
  }
  if (deliveryUserId) {
    params.push(Number(deliveryUserId));
    conds.push(`o.delivery_user_id = $${params.length}`);
  }
  const term = String(search || "").trim();
  if (term) {
    params.push(`%${term}%`);
    conds.push(
      `(o.id::text ILIKE $${params.length}
        OR o.customer_full_name ILIKE $${params.length}
        OR COALESCE(o.customer_phone, '') ILIKE $${params.length}
        OR COALESCE(m.name, '') ILIKE $${params.length}
        OR COALESCE(du.full_name, '') ILIKE $${params.length})`
    );
  }
  addDateFilters({ conds, params, from, to, column: "o.created_at" });
  const where = conds.length ? `WHERE ${conds.join(" AND ")}` : "";
  const orderBy =
    sort === "created_asc"
      ? "o.created_at ASC, o.id ASC"
      : sort === "created_desc"
        ? "o.created_at DESC, o.id DESC"
        : "o.updated_at DESC, o.id DESC";

  const countRes = await q(
    `SELECT COUNT(*)::int AS total
     FROM customer_order o
     LEFT JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN app_user du ON du.id = o.delivery_user_id
     ${where}`,
    params
  );

  params.push(page.limit);
  params.push(page.offset);
  const rows = await q(
    `SELECT
       o.id,
       o.status::text AS status,
       o.delivery_assignment_status,
       o.customer_user_id,
       o.customer_full_name,
       o.merchant_id,
       m.name AS merchant_name,
       o.delivery_user_id,
       du.full_name AS delivery_name,
       o.subtotal,
       o.delivery_fee,
       o.service_fee,
       o.total_amount,
       o.courier_source,
       o.courier_requested_at,
       o.courier_assigned_at,
       o.prepared_at,
       o.ready_for_pickup_at,
       o.picked_up_at,
       o.delivered_at,
       o.completed_at,
       o.cancelled_at,
       o.cancellation_reason,
       o.created_at,
       o.updated_at,
       COUNT(oi.id)::int AS item_count,
       EXISTS (
         SELECT 1 FROM support_ticket st
         WHERE st.entity_type IN ('order','customer_order')
           AND st.entity_id::text = o.id::text
           AND st.status = ANY($${params.length + 1})
       ) AS has_open_ticket,
       EXISTS (
         SELECT 1 FROM order_revision rev
         WHERE rev.order_id = o.id
           AND rev.status NOT IN ('applied','cancelled','rejected')
       ) AS has_open_revision
     FROM customer_order o
     LEFT JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN app_user du ON du.id = o.delivery_user_id
     LEFT JOIN order_item oi ON oi.order_id = o.id
     ${where}
     GROUP BY o.id, m.name, du.full_name
     ORDER BY ${orderBy}
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    [...params, SUPPORT_OPEN_STATUSES]
  );

  return {
    total: Number(countRes.rows[0]?.total || 0),
    limit: page.limit,
    offset: page.offset,
    items: rows.rows,
  };
}

export async function listCouriersForMonitoring({
  status = null,
  search = "",
  region = null,
  from = null,
  to = null,
  sort = "presence_desc",
  limit = 25,
  offset = 0,
} = {}) {
  const page = safeLimitOffset({ limit, offset });
  const conds = [];
  const params = [];

  if (status) {
    if (status === "fresh_online") {
      conds.push(`p.is_online = TRUE AND p.updated_at >= NOW() - INTERVAL '90 seconds'`);
    } else if (status === "busy") {
      conds.push(
        `(EXISTS (
           SELECT 1
           FROM courier_assignment ca_status
           WHERE ca_status.courier_user_id = cp.user_id
             AND ca_status.ended_at IS NULL
             AND ca_status.status IN ('assigned','accepted')
         ) OR EXISTS (
           SELECT 1
           FROM delivery_job dj_status
           WHERE dj_status.delivery_user_id = cp.user_id
             AND dj_status.assignment_status = 'ASSIGNED'
         ))`
      );
    } else {
      params.push(String(status));
      conds.push(`cp.availability_status = $${params.length}`);
    }
  }
  if (region) {
    params.push(String(region));
    conds.push(`cp.coverage_block = $${params.length}`);
  }
  const term = String(search || "").trim();
  if (term) {
    params.push(`%${term}%`);
    conds.push(
      `(u.full_name ILIKE $${params.length}
        OR u.phone ILIKE $${params.length}
        OR COALESCE(cp.vehicle_type, '') ILIKE $${params.length}
        OR cp.user_id::text ILIKE $${params.length})`
    );
  }
  addDateFilters({ conds, params, from, to, column: "cp.updated_at" });
  const where = conds.length ? `WHERE ${conds.join(" AND ")}` : "";
  const orderBy =
    sort === "rating_desc"
      ? "cp.rating DESC NULLS LAST, cp.updated_at DESC"
      : "p.updated_at DESC NULLS LAST, cp.updated_at DESC";

  const countRes = await q(
    `SELECT COUNT(*)::int AS total
     FROM courier_profile cp
     JOIN app_user u ON u.id = cp.user_id
     LEFT JOIN courier_presence p ON p.courier_user_id = cp.user_id
     ${where}`,
    params
  );

  params.push(page.limit);
  params.push(page.offset);
  const rows = await q(
    `SELECT
       cp.user_id,
       u.full_name,
       cp.vehicle_type,
       cp.driver_type,
       cp.availability_status,
       cp.coverage_block,
       cp.rating,
       cp.total_completed_orders,
       p.is_online,
       p.updated_at AS presence_updated_at,
       p.current_order_id,
       EXISTS (
         SELECT 1
         FROM courier_assignment ca
         WHERE ca.courier_user_id = cp.user_id
           AND ca.ended_at IS NULL
           AND ca.status IN ('assigned','accepted')
       ) OR EXISTS (
         SELECT 1
         FROM delivery_job dj
         WHERE dj.delivery_user_id = cp.user_id
           AND dj.assignment_status = 'ASSIGNED'
       ) AS busy,
       (
         SELECT COUNT(*)::int
         FROM customer_order o
         WHERE o.delivery_user_id = cp.user_id
           AND o.status::text = ANY($${params.length + 1})
           AND (COALESCE(o.delivered_at, o.completed_at, o.customer_confirmed_at, o.updated_at)
                AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       ) AS deliveries_today
     FROM courier_profile cp
     JOIN app_user u ON u.id = cp.user_id
     LEFT JOIN courier_presence p ON p.courier_user_id = cp.user_id
     ${where}
     ORDER BY ${orderBy}
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    [...params, ORDER_COMPLETED_STATUSES]
  );

  return {
    total: Number(countRes.rows[0]?.total || 0),
    limit: page.limit,
    offset: page.offset,
    items: rows.rows,
  };
}
