import { q } from "../../config/db.js";

function toBigIntOrNull(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

export async function hasUserAnalyticsConsent(userId) {
  const r = await q(
    `SELECT analytics_consent_granted
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );

  return r.rows[0]?.analytics_consent_granted === true;
}

export async function insertActivityEvent(payload) {
  const metadata =
    payload.metadata && typeof payload.metadata === "object" ? payload.metadata : null;

  await q(
    `INSERT INTO user_activity_event
      (user_id, user_role, event_name, category, action, source, path, method,
       entity_type, entity_id, status_code, metadata, ip_address, user_agent)
     VALUES
      ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13::inet,$14)`,
    [
      toBigIntOrNull(payload.userId),
      payload.userRole || null,
      payload.eventName,
      payload.category || null,
      payload.action || null,
      payload.source || null,
      payload.path || null,
      payload.method || null,
      payload.entityType || null,
      toBigIntOrNull(payload.entityId),
      Number.isInteger(payload.statusCode) ? payload.statusCode : null,
      metadata ? JSON.stringify(metadata) : null,
      payload.ipAddress || null,
      payload.userAgent || null,
    ]
  );
}

export async function listUserActivityEvents(userId, { limit = 100 } = {}) {
  const r = await q(
    `SELECT
       id,
       event_name,
       category,
       action,
       source,
       path,
       method,
       entity_type,
       entity_id,
       status_code,
       metadata,
       created_at
     FROM user_activity_event
     WHERE user_id = $1
     ORDER BY id DESC
     LIMIT $2`,
    [Number(userId), Number(limit)]
  );
  return r.rows;
}

export async function listCustomerInsightSummary({ search = "", limit = 30, offset = 0 }) {
  const normalizedSearch = String(search || "").trim().toLowerCase();

  const params = [];
  let whereSql = `u.role = 'user'`;
  if (normalizedSearch) {
    params.push(`%${normalizedSearch}%`);
    whereSql +=
      ` AND (` +
      `LOWER(u.full_name) LIKE $${params.length} ` +
      `OR LOWER(u.phone) LIKE $${params.length} ` +
      `OR LOWER(COALESCE(u.block, '')) LIKE $${params.length}` +
      `)`;
  }

  params.push(Number(limit));
  const limitIndex = params.length;
  params.push(Number(offset));
  const offsetIndex = params.length;

  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.block,
       u.building_number,
       u.apartment,
       u.created_at,
       u.analytics_consent_granted,
       u.analytics_consent_version,
       u.analytics_consent_granted_at,
       COALESCE(COUNT(DISTINCT o.id), 0)::int AS orders_count,
       COALESCE(
         SUM(o.total_amount) FILTER (WHERE o.status <> 'cancelled'),
         0
       ) AS total_spent,
       MAX(o.created_at) AS last_order_at,
       MAX(e.created_at) AS last_activity_at,
       COALESCE(COUNT(e.id), 0)::int AS activity_events_count,
       (
         SELECT m.type
         FROM customer_order o2
         JOIN merchant m ON m.id = o2.merchant_id
         WHERE o2.customer_user_id = u.id
         ORDER BY o2.created_at DESC
         LIMIT 1
       ) AS last_merchant_type
     FROM app_user u
     LEFT JOIN customer_order o ON o.customer_user_id = u.id
     LEFT JOIN user_activity_event e ON e.user_id = u.id
     WHERE ${whereSql}
     GROUP BY u.id
     ORDER BY COALESCE(MAX(e.created_at), MAX(o.created_at), u.created_at) DESC
     LIMIT $${limitIndex}
     OFFSET $${offsetIndex}`,
    params
  );

  const countParams = [];
  let countWhereSql = `role = 'user'`;
  if (normalizedSearch) {
    countParams.push(`%${normalizedSearch}%`);
    countWhereSql +=
      ` AND (` +
      `LOWER(full_name) LIKE $${countParams.length} ` +
      `OR LOWER(phone) LIKE $${countParams.length} ` +
      `OR LOWER(COALESCE(block, '')) LIKE $${countParams.length}` +
      `)`;
  }
  const c = await q(
    `SELECT COUNT(*)::int AS total
     FROM app_user
     WHERE ${countWhereSql}`,
    countParams
  );

  return {
    items: r.rows,
    total: Number(c.rows[0]?.total || 0),
    limit: Number(limit),
    offset: Number(offset),
  };
}

export async function getCustomerBaseProfile(customerUserId) {
  const r = await q(
    `SELECT
       id,
       full_name,
       phone,
       role,
       block,
       building_number,
       apartment,
       analytics_consent_granted,
       analytics_consent_version,
       analytics_consent_granted_at,
       image_url,
       created_at
     FROM app_user
     WHERE id = $1
       AND role = 'user'`,
    [Number(customerUserId)]
  );
  return r.rows[0] || null;
}

export async function getCustomerOrderStats(customerUserId) {
  const r = await q(
    `SELECT
       COUNT(*)::int AS orders_count,
       COUNT(*) FILTER (WHERE status = 'delivered')::int AS delivered_orders_count,
       COUNT(*) FILTER (WHERE status = 'cancelled')::int AS cancelled_orders_count,
       COALESCE(SUM(total_amount) FILTER (WHERE status <> 'cancelled'), 0) AS total_spent,
       COALESCE(AVG(total_amount) FILTER (WHERE status <> 'cancelled'), 0) AS avg_basket,
       MAX(created_at) AS last_order_at,
       MAX(delivered_at) AS last_delivered_at
     FROM customer_order
     WHERE customer_user_id = $1`,
    [Number(customerUserId)]
  );
  return r.rows[0];
}

export async function getCustomerTopMerchantTypes(customerUserId, { limit = 5 } = {}) {
  const r = await q(
    `SELECT
       m.type,
       COUNT(*)::int AS orders_count,
       COALESCE(SUM(o.total_amount), 0) AS total_spent
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE o.customer_user_id = $1
       AND o.status <> 'cancelled'
     GROUP BY m.type
     ORDER BY orders_count DESC, total_spent DESC
     LIMIT $2`,
    [Number(customerUserId), Number(limit)]
  );
  return r.rows;
}

export async function getCustomerTopActivityCategories(
  customerUserId,
  { limit = 8 } = {}
) {
  const r = await q(
    `SELECT
       COALESCE(category, 'general') AS category,
       COUNT(*)::int AS events_count,
       MAX(created_at) AS last_at
     FROM user_activity_event
     WHERE user_id = $1
     GROUP BY COALESCE(category, 'general')
     ORDER BY events_count DESC, last_at DESC
     LIMIT $2`,
    [Number(customerUserId), Number(limit)]
  );
  return r.rows;
}

export async function getCustomerTopEventActions(customerUserId, { limit = 12 } = {}) {
  const r = await q(
    `SELECT
       event_name,
       COALESCE(category, 'general') AS category,
       COUNT(*)::int AS events_count,
       MAX(created_at) AS last_at
     FROM user_activity_event
     WHERE user_id = $1
     GROUP BY event_name, COALESCE(category, 'general')
     ORDER BY events_count DESC, last_at DESC
     LIMIT $2`,
    [Number(customerUserId), Number(limit)]
  );
  return r.rows;
}

export async function getCustomerLastCarSignals(customerUserId) {
  const r = await q(
    `SELECT
       metadata,
       created_at
     FROM user_activity_event
     WHERE user_id = $1
       AND category = 'cars'
       AND metadata IS NOT NULL
     ORDER BY created_at DESC
     LIMIT 8`,
    [Number(customerUserId)]
  );
  return r.rows;
}

export async function getCustomerLastEvents(customerUserId, { limit = 40 } = {}) {
  const r = await q(
    `SELECT
       id,
       event_name,
       category,
       action,
       source,
       path,
       method,
       entity_type,
       entity_id,
       status_code,
       metadata,
       created_at
     FROM user_activity_event
     WHERE user_id = $1
     ORDER BY id DESC
     LIMIT $2`,
    [Number(customerUserId), Number(limit)]
  );
  return r.rows;
}

export async function getCustomerTopMerchants(customerUserId, { limit = 8 } = {}) {
  const r = await q(
    `SELECT
       m.id AS merchant_id,
       m.name AS merchant_name,
       m.type,
       COUNT(*)::int AS orders_count,
       COALESCE(SUM(o.total_amount), 0) AS total_spent,
       MAX(o.created_at) AS last_order_at
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE o.customer_user_id = $1
       AND o.status <> 'cancelled'
     GROUP BY m.id, m.name, m.type
     ORDER BY orders_count DESC, total_spent DESC, last_order_at DESC
     LIMIT $2`,
    [Number(customerUserId), Number(limit)]
  );
  return r.rows;
}

export async function getCustomerTopProducts(customerUserId, { limit = 12 } = {}) {
  const r = await q(
    `SELECT
       COALESCE(oi.product_id, 0)::bigint AS product_id,
       oi.product_name,
       m.id AS merchant_id,
       m.name AS merchant_name,
       m.type AS merchant_type,
       SUM(oi.quantity)::int AS units_count,
       COALESCE(SUM(oi.line_total), 0) AS total_spent,
       MAX(o.created_at) AS last_order_at
     FROM customer_order o
     JOIN order_item oi ON oi.order_id = o.id
     JOIN merchant m ON m.id = o.merchant_id
     WHERE o.customer_user_id = $1
       AND o.status <> 'cancelled'
     GROUP BY COALESCE(oi.product_id, 0), oi.product_name, m.id, m.name, m.type
     ORDER BY units_count DESC, total_spent DESC, last_order_at DESC
     LIMIT $2`,
    [Number(customerUserId), Number(limit)]
  );
  return r.rows;
}

export async function getCustomerTopOrderCategories(
  customerUserId,
  { limit = 10 } = {}
) {
  const r = await q(
    `SELECT
       COALESCE(c.name, 'general') AS category_name,
       COUNT(DISTINCT o.id)::int AS orders_count,
       SUM(oi.quantity)::int AS items_count,
       COALESCE(SUM(oi.line_total), 0) AS total_spent,
       MAX(o.created_at) AS last_order_at
     FROM customer_order o
     JOIN order_item oi ON oi.order_id = o.id
     LEFT JOIN product p ON p.id = oi.product_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     WHERE o.customer_user_id = $1
       AND o.status <> 'cancelled'
     GROUP BY COALESCE(c.name, 'general')
     ORDER BY items_count DESC, total_spent DESC, last_order_at DESC
     LIMIT $2`,
    [Number(customerUserId), Number(limit)]
  );
  return r.rows;
}

export async function getCustomerFavoritesSummary(customerUserId, { limit = 20 } = {}) {
  const [summaryResult, itemsResult] = await Promise.all([
    q(
      `SELECT
         COUNT(*)::int AS favorites_count,
         COUNT(*) FILTER (WHERE m.type = 'restaurant')::int AS restaurant_favorites_count,
         COUNT(*) FILTER (WHERE m.type = 'market')::int AS market_favorites_count,
         MAX(f.created_at) AS last_favorite_at
       FROM customer_favorite_product f
       JOIN product p ON p.id = f.product_id
       JOIN merchant m ON m.id = p.merchant_id
       WHERE f.customer_user_id = $1`,
      [Number(customerUserId)]
    ),
    q(
      `SELECT
         p.id AS product_id,
         p.name AS product_name,
         m.id AS merchant_id,
         m.name AS merchant_name,
         m.type AS merchant_type,
         COALESCE(p.discounted_price, p.price, 0) AS effective_price,
         f.created_at
       FROM customer_favorite_product f
       JOIN product p ON p.id = f.product_id
       JOIN merchant m ON m.id = p.merchant_id
       WHERE f.customer_user_id = $1
       ORDER BY f.created_at DESC
       LIMIT $2`,
      [Number(customerUserId), Number(limit)]
    ),
  ]);

  return {
    summary: summaryResult.rows[0] || null,
    items: itemsResult.rows,
  };
}

export async function getCustomerActivitySummary(customerUserId) {
  const r = await q(
    `SELECT
       COUNT(*)::int AS events_count,
       COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days')::int AS events_30d,
       COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')::int AS events_7d,
       COUNT(DISTINCT DATE(created_at))::int AS active_days_count,
       COUNT(DISTINCT DATE(created_at))
         FILTER (WHERE created_at >= NOW() - INTERVAL '30 days')::int AS active_days_30d,
       MIN(created_at) AS first_event_at,
       MAX(created_at) AS last_event_at
     FROM user_activity_event
     WHERE user_id = $1`,
    [Number(customerUserId)]
  );
  return r.rows[0] || null;
}

export async function getCustomerHourlyActivity(customerUserId, { limit = 8 } = {}) {
  const r = await q(
    `SELECT
       EXTRACT(HOUR FROM created_at)::int AS hour,
       COUNT(*)::int AS events_count
     FROM user_activity_event
     WHERE user_id = $1
       AND created_at >= NOW() - INTERVAL '45 days'
     GROUP BY hour
     ORDER BY events_count DESC, hour ASC
     LIMIT $2`,
    [Number(customerUserId), Number(limit)]
  );
  return r.rows;
}

export async function getCustomerEventsForAnalysis(customerUserId, { limit = 260 } = {}) {
  const r = await q(
    `SELECT
       event_name,
       category,
       action,
       source,
       path,
       method,
       metadata,
       created_at
     FROM user_activity_event
     WHERE user_id = $1
     ORDER BY created_at DESC, id DESC
     LIMIT $2`,
    [Number(customerUserId), Number(limit)]
  );
  return r.rows;
}

export async function getCustomerAiPreferenceProfile(customerUserId) {
  const r = await q(
    `SELECT
       preference_json,
       last_summary,
       updated_at
     FROM ai_customer_profile
     WHERE customer_user_id = $1
     LIMIT 1`,
    [Number(customerUserId)]
  );
  return r.rows[0] || null;
}
