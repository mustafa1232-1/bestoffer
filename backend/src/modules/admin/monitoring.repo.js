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
  "NEW",
  "TRIAGED",
  "ASSIGNED",
  "assigned",
  "IN_PROGRESS",
  "in_progress",
  "WAITING_FOR_CUSTOMER",
  "WAITING_FOR_MERCHANT",
  "WAITING_FOR_CAPTAIN",
  "WAITING_FOR_DELIVERY",
  "waiting_customer",
  "waiting_internal",
  "ESCALATED",
  "escalated",
  "REOPENED",
  "reopened",
];

const SERVICE_ACTIVE_STATUSES = [
  "pending",
  "awaiting_provider",
  "accepted",
  "scheduled",
  "in_progress",
  "PENDING_PROVIDER_CONFIRMATION",
  "CONFIRMED",
  "IN_PROGRESS",
  "PROVIDER_COMPLETED",
  "DISPUTED",
];
const SERVICE_COMPLETED_STATUSES = ["completed", "COMPLETED"];
const SERVICE_CANCELLED_STATUSES = [
  "cancelled",
  "rejected",
  "REJECTED_BY_PROVIDER",
  "CANCELLED_BY_CUSTOMER",
  "CANCELLED_BY_PROVIDER",
  "CANCELLED_BY_ADMIN",
  "EXPIRED",
];
const MARKETPLACE_ACTIVE_STATUSES = ["active"];
const REAL_ESTATE_DONE_STATUSES = ["sold", "rented"];
const MARKETPLACE_CANCELLED_STATUSES = [
  "archived",
  "hidden_due_subscription_expiry",
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

export async function getServiceMonitoringCounters() {
  const r = await q(
    `SELECT
       COUNT(*) FILTER (WHERE sr.status = ANY($1))::int AS active,
       COUNT(*) FILTER (
         WHERE sr.status = ANY($2)
           AND (COALESCE(sr.completed_at, sr.booking_finalized_at, sr.updated_at)
                AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS completed_today,
       COUNT(*) FILTER (
         WHERE sr.status = ANY($3)
           AND (sr.updated_at AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS cancelled_today,
       COUNT(*) FILTER (
         WHERE sr.status = ANY($1)
           AND (
             (sr.scheduled_start_at IS NOT NULL AND sr.scheduled_start_at < NOW() - INTERVAL '15 minutes')
             OR (sr.scheduled_start_at IS NULL AND sr.updated_at < NOW() - INTERVAL '24 hours')
           )
       )::int AS delayed,
       COUNT(*) FILTER (
         WHERE sr.status IN ('pending','awaiting_provider','PENDING_PROVIDER_CONFIRMATION','DISPUTED')
            OR EXISTS (
              SELECT 1 FROM service_reports rep
              WHERE rep.target_type = 'request'
                AND rep.target_id = sr.id
                AND rep.status = 'pending'
            )
       )::int AS needs_attention,
       COUNT(*) FILTER (
         WHERE EXISTS (
           SELECT 1 FROM support_ticket st
           WHERE st.entity_id = sr.id
             AND (
               st.domain = 'SERVICES'
               OR st.entity_type IN ('service_request','services_request','service')
             )
             AND st.status = ANY($4)
         )
       )::int AS open_tickets
     FROM service_requests sr`,
    [
      SERVICE_ACTIVE_STATUSES,
      SERVICE_COMPLETED_STATUSES,
      SERVICE_CANCELLED_STATUSES,
      SUPPORT_OPEN_STATUSES,
    ]
  );
  const row = r.rows[0] || {};
  return {
    active: Number(row.active || 0),
    completedToday: Number(row.completed_today || 0),
    cancelledToday: Number(row.cancelled_today || 0),
    delayed: Number(row.delayed || 0),
    needsAttention: Number(row.needs_attention || 0),
    openTickets: Number(row.open_tickets || 0),
  };
}

export async function getRealEstateMonitoringCounters() {
  const r = await q(
    `SELECT
       COUNT(*) FILTER (WHERE status = ANY($1))::int AS active,
       COUNT(*) FILTER (
         WHERE status = ANY($2)
           AND (COALESCE(sold_at, rented_at, updated_at)
                AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS completed_today,
       COUNT(*) FILTER (
         WHERE status = ANY($3)
           AND (COALESCE(archived_at, hidden_due_subscription_expiry_at, updated_at)
                AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS cancelled_today,
       COUNT(*) FILTER (
         WHERE status = 'pending_admin_review'
           AND created_at < NOW() - INTERVAL '24 hours'
       )::int AS delayed,
       COUNT(*) FILTER (
         WHERE status = 'pending_admin_review'
            OR EXISTS (
              SELECT 1 FROM support_ticket st
              WHERE st.entity_id = real_estate_listing.id
                AND (
                  st.domain = 'REAL_ESTATE'
                  OR st.entity_type IN ('real_estate_listing','real_estate')
                )
                AND st.status = ANY($4)
            )
       )::int AS needs_attention,
       COUNT(*) FILTER (
         WHERE EXISTS (
           SELECT 1 FROM support_ticket st
           WHERE st.entity_id = real_estate_listing.id
             AND (
               st.domain = 'REAL_ESTATE'
               OR st.entity_type IN ('real_estate_listing','real_estate')
             )
             AND st.status = ANY($4)
         )
       )::int AS open_tickets
     FROM real_estate_listing`,
    [
      MARKETPLACE_ACTIVE_STATUSES,
      REAL_ESTATE_DONE_STATUSES,
      MARKETPLACE_CANCELLED_STATUSES,
      SUPPORT_OPEN_STATUSES,
    ]
  );
  const row = r.rows[0] || {};
  return {
    active: Number(row.active || 0),
    completedToday: Number(row.completed_today || 0),
    cancelledToday: Number(row.cancelled_today || 0),
    delayed: Number(row.delayed || 0),
    needsAttention: Number(row.needs_attention || 0),
    openTickets: Number(row.open_tickets || 0),
  };
}

export async function getCarMonitoringCounters() {
  const r = await q(
    `SELECT
       COUNT(*) FILTER (WHERE status = ANY($1))::int AS active,
       COUNT(*) FILTER (
         WHERE status = 'sold'
           AND (COALESCE(sold_at, updated_at) AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS completed_today,
       COUNT(*) FILTER (
         WHERE status = ANY($2)
           AND (COALESCE(archived_at, hidden_due_subscription_expiry_at, updated_at)
                AT TIME ZONE 'Asia/Baghdad')::date
             = (NOW() AT TIME ZONE 'Asia/Baghdad')::date
       )::int AS cancelled_today,
       0::int AS delayed,
       COUNT(*) FILTER (
         WHERE EXISTS (
           SELECT 1 FROM support_ticket st
           WHERE st.entity_id = car_listing.id
             AND (
               st.domain = 'CARS'
               OR st.entity_type IN ('car_listing','car')
             )
             AND st.status = ANY($3)
         )
       )::int AS needs_attention,
       COUNT(*) FILTER (
         WHERE EXISTS (
           SELECT 1 FROM support_ticket st
           WHERE st.entity_id = car_listing.id
             AND (
               st.domain = 'CARS'
               OR st.entity_type IN ('car_listing','car')
             )
             AND st.status = ANY($3)
         )
       )::int AS open_tickets
     FROM car_listing`,
    [
      MARKETPLACE_ACTIVE_STATUSES,
      MARKETPLACE_CANCELLED_STATUSES,
      SUPPORT_OPEN_STATUSES,
    ]
  );
  const row = r.rows[0] || {};
  return {
    active: Number(row.active || 0),
    completedToday: Number(row.completed_today || 0),
    cancelledToday: Number(row.cancelled_today || 0),
    delayed: Number(row.delayed || 0),
    needsAttention: Number(row.needs_attention || 0),
    openTickets: Number(row.open_tickets || 0),
  };
}

export async function listServiceRequestsForMonitoring({
  status = null,
  search = "",
  region = null,
  from = null,
  to = null,
  userId = null,
  providerUserId = null,
  sort = "updated_desc",
  limit = 25,
  offset = 0,
} = {}) {
  const page = safeLimitOffset({ limit, offset });
  const conds = [];
  const params = [];

  if (status) {
    params.push(String(status));
    conds.push(`sr.status = $${params.length}`);
  }
  if (region) {
    params.push(String(region));
    conds.push(`(sr.city = $${params.length} OR sr.area = $${params.length} OR spp.city = $${params.length} OR spp.area = $${params.length})`);
  }
  if (userId) {
    params.push(Number(userId));
    conds.push(`sr.customer_user_id = $${params.length}`);
  }
  if (providerUserId) {
    params.push(Number(providerUserId));
    conds.push(`spp.user_id = $${params.length}`);
  }
  const term = String(search || "").trim();
  if (term) {
    params.push(`%${term}%`);
    conds.push(
      `(sr.id::text ILIKE $${params.length}
        OR COALESCE(sr.request_code, '') ILIKE $${params.length}
        OR cu.full_name ILIKE $${params.length}
        OR spp.business_name ILIKE $${params.length}
        OR so.name ILIKE $${params.length}
        OR COALESCE(sr.city, '') ILIKE $${params.length}
        OR COALESCE(sr.area, '') ILIKE $${params.length})`
    );
  }
  addDateFilters({ conds, params, from, to, column: "sr.created_at" });
  const where = conds.length ? `WHERE ${conds.join(" AND ")}` : "";
  const orderBy =
    sort === "created_asc"
      ? "sr.created_at ASC, sr.id ASC"
      : sort === "scheduled_asc"
        ? "sr.scheduled_start_at ASC NULLS LAST, sr.created_at DESC"
        : sort === "price_desc"
          ? "COALESCE(sr.booking_total_iqd, sr.final_price, 0) DESC, sr.updated_at DESC"
          : "sr.updated_at DESC, sr.id DESC";

  const countRes = await q(
    `SELECT COUNT(*)::int AS total
     FROM service_requests sr
     JOIN service_provider_profiles spp ON spp.id = sr.provider_id
     JOIN service_offerings so ON so.id = sr.offering_id
     JOIN app_user cu ON cu.id = sr.customer_user_id
     ${where}`,
    params
  );

  params.push(page.limit);
  params.push(page.offset);
  const rows = await q(
    `SELECT
       sr.id,
       sr.request_code,
       sr.status,
       sr.customer_user_id,
       cu.full_name AS customer_name,
       spp.id AS provider_id,
       spp.user_id AS provider_user_id,
       spp.business_name AS provider_name,
       so.id AS offering_id,
       so.name AS offering_name,
       sc.name AS main_category_name,
       sr.requested_date,
       sr.requested_time,
       sr.scheduled_start_at,
       sr.scheduled_end_at,
       sr.city,
       sr.area,
       sr.final_price,
       sr.booking_total_iqd,
       sr.booking_flow_kind,
       sr.cancel_reason,
       sr.created_at,
       sr.updated_at,
       COUNT(sa.id)::int AS attachment_count,
       EXISTS (
         SELECT 1 FROM service_reports rep
         WHERE rep.target_type = 'request'
           AND rep.target_id = sr.id
           AND rep.status = 'pending'
       ) AS has_open_report,
       EXISTS (
         SELECT 1 FROM support_ticket st
         WHERE st.entity_id = sr.id
           AND (
             st.domain = 'SERVICES'
             OR st.entity_type IN ('service_request','services_request','service')
           )
           AND st.status = ANY($${params.length + 1})
       ) AS has_open_ticket
     FROM service_requests sr
     JOIN service_provider_profiles spp ON spp.id = sr.provider_id
     JOIN service_offerings so ON so.id = sr.offering_id
     JOIN app_user cu ON cu.id = sr.customer_user_id
     LEFT JOIN service_categories sc ON sc.id = so.main_category_id
     LEFT JOIN service_request_attachments sa ON sa.request_id = sr.id
     ${where}
     GROUP BY sr.id, cu.full_name, spp.id, so.id, sc.name
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

export async function listRealEstateListingsForMonitoring({
  status = null,
  search = "",
  region = null,
  from = null,
  to = null,
  userId = null,
  sort = "updated_desc",
  limit = 25,
  offset = 0,
} = {}) {
  const page = safeLimitOffset({ limit, offset });
  const conds = [];
  const params = [];

  if (status) {
    params.push(String(status));
    conds.push(`l.status = $${params.length}`);
  }
  if (region) {
    params.push(String(region));
    conds.push(`(l.city = $${params.length} OR l.block = $${params.length})`);
  }
  if (userId) {
    params.push(Number(userId));
    conds.push(`l.owner_user_id = $${params.length}`);
  }
  const term = String(search || "").trim();
  if (term) {
    params.push(`%${term}%`);
    conds.push(
      `(l.id::text ILIKE $${params.length}
        OR l.title ILIKE $${params.length}
        OR COALESCE(l.description, '') ILIKE $${params.length}
        OR COALESCE(l.city, '') ILIKE $${params.length}
        OR COALESCE(l.block, '') ILIKE $${params.length}
        OR u.full_name ILIKE $${params.length})`
    );
  }
  addDateFilters({ conds, params, from, to, column: "l.created_at" });
  const where = conds.length ? `WHERE ${conds.join(" AND ")}` : "";
  const orderBy =
    sort === "created_asc"
      ? "l.created_at ASC, l.id ASC"
      : sort === "price_desc"
        ? "l.price DESC, l.updated_at DESC"
        : sort === "views_desc"
          ? "l.view_count DESC, l.updated_at DESC"
          : "l.updated_at DESC, l.id DESC";

  const countRes = await q(
    `SELECT COUNT(*)::int AS total
     FROM real_estate_listing l
     JOIN app_user u ON u.id = l.owner_user_id
     ${where}`,
    params
  );

  params.push(page.limit);
  params.push(page.offset);
  const rows = await q(
    `SELECT
       l.id,
       l.status,
       l.purpose,
       l.title,
       l.owner_user_id,
       u.full_name AS owner_name,
       l.city,
       l.block,
       l.area_sqm,
       l.rooms_count,
       l.bathrooms_count,
       l.price,
       l.payment_method,
       l.furnished,
       l.is_featured,
       l.view_count,
       l.review_note,
       l.created_at,
       l.updated_at,
       COUNT(DISTINCT lm.id)::int AS media_count,
       COUNT(DISTINCT sl.user_id)::int AS saved_count,
       EXISTS (
         SELECT 1 FROM support_ticket st
         WHERE st.entity_id = l.id
           AND (
             st.domain = 'REAL_ESTATE'
             OR st.entity_type IN ('real_estate_listing','real_estate')
           )
           AND st.status = ANY($${params.length + 1})
       ) AS has_open_ticket
     FROM real_estate_listing l
     JOIN app_user u ON u.id = l.owner_user_id
     LEFT JOIN real_estate_listing_media lm ON lm.listing_id = l.id
     LEFT JOIN real_estate_saved_listing sl ON sl.listing_id = l.id
     ${where}
     GROUP BY l.id, u.full_name
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

export async function listCarListingsForMonitoring({
  status = null,
  search = "",
  region = null,
  from = null,
  to = null,
  userId = null,
  sort = "updated_desc",
  limit = 25,
  offset = 0,
} = {}) {
  const page = safeLimitOffset({ limit, offset });
  const conds = [];
  const params = [];

  if (status) {
    params.push(String(status));
    conds.push(`l.status = $${params.length}`);
  }
  if (region) {
    params.push(String(region));
    conds.push(`l.city = $${params.length}`);
  }
  if (userId) {
    params.push(Number(userId));
    conds.push(`l.owner_user_id = $${params.length}`);
  }
  const term = String(search || "").trim();
  if (term) {
    params.push(`%${term}%`);
    conds.push(
      `(l.id::text ILIKE $${params.length}
        OR l.title ILIKE $${params.length}
        OR l.brand ILIKE $${params.length}
        OR l.model ILIKE $${params.length}
        OR COALESCE(l.city, '') ILIKE $${params.length}
        OR u.full_name ILIKE $${params.length})`
    );
  }
  addDateFilters({ conds, params, from, to, column: "l.created_at" });
  const where = conds.length ? `WHERE ${conds.join(" AND ")}` : "";
  const orderBy =
    sort === "created_asc"
      ? "l.created_at ASC, l.id ASC"
      : sort === "price_desc"
        ? "l.price DESC, l.updated_at DESC"
        : sort === "year_desc"
          ? "l.model_year DESC, l.updated_at DESC"
          : "l.updated_at DESC, l.id DESC";

  const countRes = await q(
    `SELECT COUNT(*)::int AS total
     FROM car_listing l
     JOIN app_user u ON u.id = l.owner_user_id
     ${where}`,
    params
  );

  params.push(page.limit);
  params.push(page.offset);
  const rows = await q(
    `SELECT
       l.id,
       l.status,
       l.title,
       l.owner_user_id,
       u.full_name AS owner_name,
       l.brand,
       l.model,
       l.model_year,
       l.condition,
       l.price,
       l.mileage_km,
       l.city,
       l.transmission,
       l.fuel_type,
       l.body_type,
       l.color,
       l.created_at,
       l.updated_at,
       COUNT(cm.id)::int AS media_count,
       EXISTS (
         SELECT 1 FROM support_ticket st
         WHERE st.entity_id = l.id
           AND (
             st.domain = 'CARS'
             OR st.entity_type IN ('car_listing','car')
           )
           AND st.status = ANY($${params.length + 1})
       ) AS has_open_ticket
     FROM car_listing l
     JOIN app_user u ON u.id = l.owner_user_id
     LEFT JOIN car_listing_media cm ON cm.listing_id = l.id
     ${where}
     GROUP BY l.id, u.full_name
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
