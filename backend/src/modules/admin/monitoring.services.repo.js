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
