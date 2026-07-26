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
