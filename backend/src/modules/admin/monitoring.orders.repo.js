import {
  q,
  ORDER_TERMINAL_STATUSES,
  ORDER_COMPLETED_STATUSES,
  ORDER_CANCELLED_STATUSES,
  ORDER_ACTIVE_STATUSES,
  ORDER_NEEDS_DELIVERY_STATUSES,
  DELIVERY_JOB_TERMINAL_STATUSES,
  SUPPORT_OPEN_STATUSES,
  SERVICE_ACTIVE_STATUSES,
  SERVICE_COMPLETED_STATUSES,
  SERVICE_CANCELLED_STATUSES,
  MARKETPLACE_ACTIVE_STATUSES,
  REAL_ESTATE_DONE_STATUSES,
  MARKETPLACE_CANCELLED_STATUSES,
  JOB_ACTIVE_STATUSES,
  JOB_CLOSED_STATUSES,
  JOB_ATTENTION_STATUSES,
  INTERNAL_COMMUNITY_ROLES,
  safeLimitOffset,
  addDateFilters,
} from "./monitoring.shared.js";

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

export async function getOrderMonitoringDetail(orderId, { includePhone = false } = {}) {
  const id = Number(orderId);
  if (!Number.isFinite(id) || id <= 0) return null;

  const orderRes = await q(
    `SELECT
       o.*,
       m.name AS merchant_name,
       m.phone AS merchant_phone,
       du.full_name AS delivery_name,
       du.phone AS delivery_phone
     FROM customer_order o
     LEFT JOIN merchant m ON m.id = o.merchant_id
     LEFT JOIN app_user du ON du.id = o.delivery_user_id
     WHERE o.id = $1
     LIMIT 1`,
    [id]
  );
  const order = orderRes.rows[0] || null;
  if (!order) return null;

  if (!includePhone) {
    order.customer_phone = null;
    order.merchant_phone = null;
    order.delivery_phone = null;
  }

  const items = await q(
    `SELECT
       oi.*,
       p.name AS product_name,
       p.image_url AS product_image_url
     FROM order_item oi
     LEFT JOIN product p ON p.id = oi.product_id
     WHERE oi.order_id = $1
     ORDER BY oi.id ASC`,
    [id]
  );

  const jobs = await q(
    `SELECT *
     FROM delivery_job
     WHERE primary_order_id = $1
     ORDER BY created_at DESC, id DESC
     LIMIT 20`,
    [id]
  ).catch(() => ({ rows: [] }));

  const assignments = await q(
    `SELECT ca.*
     FROM courier_assignment ca
     WHERE ca.order_id = $1
        OR ca.delivery_job_id IN (
          SELECT id FROM delivery_job WHERE primary_order_id = $1
        )
     ORDER BY ca.requested_at DESC, ca.id DESC
     LIMIT 50`,
    [id]
  ).catch(() => ({ rows: [] }));

  const tickets = await q(
    `SELECT id, status, priority, subject, created_at, updated_at
     FROM support_ticket
     WHERE entity_id::text = $1::text
       AND (entity_type IN ('order','customer_order') OR domain = 'ORDERS')
     ORDER BY created_at DESC, id DESC
     LIMIT 50`,
    [id]
  ).catch(() => ({ rows: [] }));

  return {
    order,
    items: items.rows,
    deliveryJobs: jobs.rows,
    courierAssignments: assignments.rows,
    tickets: tickets.rows,
  };
}
