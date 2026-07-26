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

export async function getRealEstateListingMonitoringDetail(
  listingId,
  { includeContact = false } = {}
) {
  const id = Number(listingId);
  if (!Number.isFinite(id) || id <= 0) return null;
  const listingRes = await q(
    `SELECT l.*, u.full_name AS owner_name, u.phone AS owner_phone
     FROM real_estate_listing l
     JOIN app_user u ON u.id = l.owner_user_id
     WHERE l.id = $1
     LIMIT 1`,
    [id]
  );
  const listing = listingRes.rows[0] || null;
  if (!listing) return null;
  if (!includeContact) listing.owner_phone = null;

  const media = await q(
    `SELECT id, image_url, sort_order, created_at
     FROM real_estate_listing_media
     WHERE listing_id = $1
     ORDER BY sort_order ASC, id ASC`,
    [id]
  ).catch(() => ({ rows: [] }));
  const history = await q(
    `SELECT status, note, actor_user_id, created_at
     FROM real_estate_listing_status_history
     WHERE listing_id = $1
     ORDER BY created_at ASC, id ASC`,
    [id]
  ).catch(() => ({ rows: [] }));
  return { listing, media: media.rows, history: history.rows };
}

export async function getCarListingMonitoringDetail(
  listingId,
  { includeContact = false } = {}
) {
  const id = Number(listingId);
  if (!Number.isFinite(id) || id <= 0) return null;
  const listingRes = await q(
    `SELECT l.*, u.full_name AS owner_name, u.phone AS owner_phone
     FROM car_listing l
     JOIN app_user u ON u.id = l.owner_user_id
     WHERE l.id = $1
     LIMIT 1`,
    [id]
  );
  const listing = listingRes.rows[0] || null;
  if (!listing) return null;
  if (!includeContact) listing.owner_phone = null;

  const media = await q(
    `SELECT id, image_url, sort_order, created_at
     FROM car_listing_media
     WHERE listing_id = $1
     ORDER BY sort_order ASC, id ASC`,
    [id]
  ).catch(() => ({ rows: [] }));
  return { listing, media: media.rows };
}
