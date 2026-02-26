import { pool, q } from "../../config/db.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";

function appError(message, status) {
  const err = new Error(message);
  err.status = status;
  return err;
}

export async function createMerchantWithOwnerLink({
  merchant,
  approvedByUserId,
  ownerUserId,
  ownerToCreate,
  ownerPinHash,
}) {
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    let owner = null;

    if (ownerUserId) {
      const ownerResult = await client.query(
        `SELECT id, full_name, phone, role, image_url
         FROM app_user
         WHERE id=$1
           AND role='owner'`,
        [ownerUserId]
      );

      owner = ownerResult.rows[0] || null;

      if (!owner) {
        throw appError("OWNER_NOT_FOUND", 404);
      }
    } else {
      const phoneExistsResult = await client.query(
        `SELECT id
         FROM app_user
         WHERE phone=$1
         LIMIT 1`,
        [ownerToCreate.phone]
      );

      if (phoneExistsResult.rows[0]) {
        throw appError("PHONE_EXISTS", 409);
      }

      const ownerInsertResult = await client.query(
        `INSERT INTO app_user
          (full_name, phone, pin_hash, block, building_number, apartment, image_url, role)
         VALUES ($1,$2,$3,$4,$5,$6,$7,'owner')
         RETURNING id, full_name, phone, role, image_url`,
        [
          ownerToCreate.fullName,
          ownerToCreate.phone,
          ownerPinHash,
          ownerToCreate.block,
          ownerToCreate.buildingNumber,
          ownerToCreate.apartment,
          ownerToCreate.imageUrl || null,
        ]
      );

      owner = ownerInsertResult.rows[0];
    }

    const merchantByOwnerResult = await client.query(
      `SELECT id
       FROM merchant
       WHERE owner_user_id=$1
       LIMIT 1`,
      [owner.id]
    );

    if (merchantByOwnerResult.rows[0]) {
      throw appError("OWNER_ALREADY_HAS_MERCHANT", 409);
    }

    const merchantResult = await client.query(
      `INSERT INTO merchant
        (name, type, description, phone, image_url, owner_user_id, is_approved, approved_by_user_id, approved_at)
       VALUES ($1,$2,$3,$4,$5,$6,TRUE,$7,NOW())
       RETURNING *`,
      [
        merchant.name,
        merchant.type,
        merchant.description,
        merchant.phone || owner.phone,
        merchant.imageUrl,
        owner.id,
        approvedByUserId || null,
      ]
    );
    const createdMerchant = merchantResult.rows[0];

    await client.query("COMMIT");

    await createManyNotifications([
      {
        userId: owner.id,
        type: "owner_merchant_linked",
        title: "تم ربط المتجر بحسابك",
        body: `تم إنشاء متجر ${createdMerchant.name} وربطه بحسابك`,
        merchantId: createdMerchant.id,
        payload: {
          merchantId: createdMerchant.id,
        },
      },
    ]);

    return createdMerchant;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function getAllMerchants(type) {
  if (type) {
    const r = await q(
      `SELECT
         m.*,
         EXISTS (
           SELECT 1
           FROM product p
           WHERE p.merchant_id = m.id
             AND p.is_available = TRUE
             AND p.discounted_price IS NOT NULL
             AND p.discounted_price < p.price
         ) AS has_discount_offer,
         EXISTS (
           SELECT 1
           FROM product p
           WHERE p.merchant_id = m.id
             AND p.is_available = TRUE
             AND p.free_delivery = TRUE
         ) AS has_free_delivery_offer
       FROM merchant m
       WHERE m.type=$1
         AND m.is_approved=TRUE
         AND m.is_disabled=FALSE`,
      [type]
    );
    return r.rows;
  }

  const r = await q(
    `SELECT
       m.*,
       EXISTS (
         SELECT 1
         FROM product p
         WHERE p.merchant_id = m.id
           AND p.is_available = TRUE
           AND p.discounted_price IS NOT NULL
           AND p.discounted_price < p.price
       ) AS has_discount_offer,
       EXISTS (
         SELECT 1
         FROM product p
         WHERE p.merchant_id = m.id
           AND p.is_available = TRUE
           AND p.free_delivery = TRUE
       ) AS has_free_delivery_offer
     FROM merchant m
     WHERE m.is_approved=TRUE
       AND m.is_disabled=FALSE`
  );
  return r.rows;
}

export async function getPublicMerchantProducts(merchantId) {
  const r = await q(
    `SELECT
       p.*,
       c.name AS category_name,
       c.sort_order AS category_sort_order
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     WHERE p.merchant_id=$1
       AND p.is_available=true
       AND m.is_approved=TRUE
       AND m.is_disabled=FALSE
     ORDER BY COALESCE(c.sort_order, 999999), COALESCE(c.id, 0), p.sort_order ASC, p.id DESC`,
    [merchantId]
  );
  return r.rows;
}

export async function getPublicMerchantCategories(merchantId) {
  const r = await q(
    `SELECT
       c.id,
       c.merchant_id,
       c.name,
       c.sort_order,
       c.created_at,
       c.updated_at,
       COUNT(p.id)::int AS available_products_count
     FROM merchant_category c
     JOIN merchant m ON m.id = c.merchant_id
     LEFT JOIN product p
       ON p.category_id = c.id
      AND p.is_available = TRUE
     WHERE c.merchant_id = $1
       AND m.is_approved = TRUE
       AND m.is_disabled = FALSE
     GROUP BY c.id
     ORDER BY c.sort_order ASC, c.id ASC`,
    [merchantId]
  );
  return r.rows;
}

export async function getMerchantsDiscoveryBase({ type, customerUserId }) {
  const r = await q(
    `WITH order_stats AS (
       SELECT
         o.merchant_id,
         COUNT(*) FILTER (WHERE o.status <> 'cancelled')::int AS total_orders,
         COUNT(*) FILTER (WHERE o.status = 'delivered')::int AS delivered_orders,
         COUNT(*) FILTER (WHERE o.status = 'cancelled')::int AS cancelled_orders,
         COALESCE(
           AVG(o.merchant_rating) FILTER (WHERE o.merchant_rating IS NOT NULL),
           0
         ) AS avg_merchant_rating,
         COUNT(o.merchant_rating) FILTER (WHERE o.merchant_rating IS NOT NULL)::int AS rating_count,
         COALESCE(
           AVG(EXTRACT(EPOCH FROM (o.delivered_at - o.created_at)) / 60)
             FILTER (WHERE o.status = 'delivered' AND o.delivered_at IS NOT NULL),
           0
         ) AS avg_delivery_minutes,
         COALESCE(
           AVG(
             CASE
               WHEN o.status = 'delivered'
                AND o.delivered_at IS NOT NULL
                AND (
                  COALESCE(o.estimated_prep_minutes, 0) +
                  COALESCE(o.estimated_delivery_minutes, 10)
                ) > 0
                AND (
                  EXTRACT(EPOCH FROM (o.delivered_at - o.created_at)) / 60
                ) <= (
                  COALESCE(o.estimated_prep_minutes, 0) +
                  COALESCE(o.estimated_delivery_minutes, 10)
                ) * 1.15
               THEN 1
               WHEN o.status = 'delivered' AND o.delivered_at IS NOT NULL
               THEN 0
               ELSE NULL
             END
           ),
           0
         ) AS on_time_rate,
         COALESCE(
           AVG(o.total_amount) FILTER (WHERE o.status <> 'cancelled'),
           0
         ) AS avg_order_amount,
         MAX(o.created_at) FILTER (WHERE o.status <> 'cancelled') AS last_ordered_at
       FROM customer_order o
       WHERE o.created_at >= NOW() - INTERVAL '120 days'
       GROUP BY o.merchant_id
     ),
     product_stats AS (
       SELECT
         p.merchant_id,
         COALESCE(
           AVG(
             CASE
               WHEN p.is_available
               THEN COALESCE(p.discounted_price, p.price)
               ELSE NULL
             END
           ),
           0
         ) AS avg_effective_price,
         COALESCE(
           MIN(
             CASE
               WHEN p.is_available
               THEN COALESCE(p.discounted_price, p.price)
               ELSE NULL
             END
           ),
           0
         ) AS min_effective_price,
         COALESCE(
           MAX(
             CASE
               WHEN p.is_available
                AND p.discounted_price IS NOT NULL
                AND p.price > 0
                AND p.discounted_price < p.price
               THEN ((p.price - p.discounted_price) / p.price) * 100
               ELSE 0
             END
           ),
           0
         ) AS max_discount_percent,
         COUNT(*) FILTER (
           WHERE p.is_available
             AND p.discounted_price IS NOT NULL
             AND p.discounted_price < p.price
         )::int AS discount_items_count,
         COUNT(*) FILTER (
           WHERE p.is_available
             AND p.free_delivery = TRUE
         )::int AS free_delivery_items_count
       FROM product p
       GROUP BY p.merchant_id
     ),
     user_counts AS (
       SELECT
         o.merchant_id,
         COUNT(*) FILTER (WHERE o.status <> 'cancelled')::int AS user_orders_count
       FROM customer_order o
       WHERE o.customer_user_id = $2
         AND o.created_at >= NOW() - INTERVAL '180 days'
       GROUP BY o.merchant_id
     ),
     user_recent AS (
       SELECT DISTINCT ON (o.merchant_id)
         o.merchant_id,
         o.id AS last_user_order_id,
         o.created_at AS last_user_ordered_at,
         o.total_amount AS last_user_total_amount,
         COALESCE(
           (SELECT SUM(oi.quantity)::int FROM order_item oi WHERE oi.order_id = o.id),
           0
         ) AS last_user_items_count
       FROM customer_order o
       WHERE o.customer_user_id = $2
         AND o.status <> 'cancelled'
       ORDER BY o.merchant_id, o.created_at DESC, o.id DESC
     )
     SELECT
       m.id AS merchant_id,
       m.name,
       m.type::text AS type,
       m.description,
       m.phone,
       m.image_url,
       m.is_open,
       EXISTS (
         SELECT 1
         FROM product p
         WHERE p.merchant_id = m.id
           AND p.is_available = TRUE
           AND p.discounted_price IS NOT NULL
           AND p.discounted_price < p.price
       ) AS has_discount_offer,
       EXISTS (
         SELECT 1
         FROM product p
         WHERE p.merchant_id = m.id
           AND p.is_available = TRUE
           AND p.free_delivery = TRUE
       ) AS has_free_delivery_offer,
       COALESCE(os.total_orders, 0)::int AS total_orders,
       COALESCE(os.delivered_orders, 0)::int AS delivered_orders,
       COALESCE(os.cancelled_orders, 0)::int AS cancelled_orders,
       COALESCE(os.avg_merchant_rating, 0) AS avg_merchant_rating,
       COALESCE(os.rating_count, 0)::int AS rating_count,
       COALESCE(os.avg_delivery_minutes, 0) AS avg_delivery_minutes,
       COALESCE(os.on_time_rate, 0) AS on_time_rate,
       COALESCE(os.avg_order_amount, 0) AS avg_order_amount,
       os.last_ordered_at,
       COALESCE(ps.avg_effective_price, 0) AS avg_effective_price,
       COALESCE(ps.min_effective_price, 0) AS min_effective_price,
       COALESCE(ps.max_discount_percent, 0) AS max_discount_percent,
       COALESCE(ps.discount_items_count, 0)::int AS discount_items_count,
       COALESCE(ps.free_delivery_items_count, 0)::int AS free_delivery_items_count,
       COALESCE(uc.user_orders_count, 0)::int AS user_orders_count,
       ur.last_user_order_id,
       ur.last_user_ordered_at,
       COALESCE(ur.last_user_total_amount, 0) AS last_user_total_amount,
       COALESCE(ur.last_user_items_count, 0)::int AS last_user_items_count
     FROM merchant m
     LEFT JOIN order_stats os ON os.merchant_id = m.id
     LEFT JOIN product_stats ps ON ps.merchant_id = m.id
     LEFT JOIN user_counts uc ON uc.merchant_id = m.id
     LEFT JOIN user_recent ur ON ur.merchant_id = m.id
     WHERE m.is_approved = TRUE
       AND m.is_disabled = FALSE
       AND ($1::text IS NULL OR m.type::text = $1::text)
     ORDER BY m.id ASC`,
    [type || null, Number(customerUserId)]
  );
  return r.rows;
}

export async function getCustomerProfileSignals({ customerUserId, type }) {
  const uid = Number(customerUserId);
  const merchantType = type || null;

  const [
    summaryAllResult,
    summaryTypeResult,
    topMerchantsResult,
    topHoursResult,
    typeMixResult,
    spendingBenchmarksResult,
  ] = await Promise.all([
    q(
      `SELECT
         COUNT(*) FILTER (WHERE o.status <> 'cancelled')::int AS orders_count,
         COUNT(*) FILTER (WHERE o.status = 'delivered')::int AS delivered_count,
         COALESCE(
           AVG(o.total_amount) FILTER (WHERE o.status <> 'cancelled'),
           0
         ) AS avg_order_value,
         COALESCE(
           SUM(o.total_amount) FILTER (WHERE o.status <> 'cancelled'),
           0
         ) AS total_spend
       FROM customer_order o
       WHERE o.customer_user_id = $1
         AND o.created_at >= NOW() - INTERVAL '120 days'`,
      [uid]
    ),
    q(
      `SELECT
         COUNT(*) FILTER (WHERE o.status <> 'cancelled')::int AS orders_count,
         COUNT(*) FILTER (WHERE o.status = 'delivered')::int AS delivered_count,
         COALESCE(
           AVG(o.total_amount) FILTER (WHERE o.status <> 'cancelled'),
           0
         ) AS avg_order_value
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE o.customer_user_id = $1
         AND o.created_at >= NOW() - INTERVAL '120 days'
         AND ($2::text IS NULL OR m.type::text = $2::text)`,
      [uid, merchantType]
    ),
    q(
      `SELECT
         o.merchant_id,
         m.name AS merchant_name,
         COUNT(*) FILTER (WHERE o.status <> 'cancelled')::int AS orders_count,
         MAX(o.created_at) FILTER (WHERE o.status <> 'cancelled') AS last_ordered_at
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE o.customer_user_id = $1
         AND o.created_at >= NOW() - INTERVAL '120 days'
         AND ($2::text IS NULL OR m.type::text = $2::text)
       GROUP BY o.merchant_id, m.name
       ORDER BY orders_count DESC, last_ordered_at DESC
       LIMIT 8`,
      [uid, merchantType]
    ),
    q(
      `SELECT
         EXTRACT(HOUR FROM o.created_at)::int AS hour,
         COUNT(*)::int AS orders_count
       FROM customer_order o
       WHERE o.customer_user_id = $1
         AND o.status <> 'cancelled'
         AND o.created_at >= NOW() - INTERVAL '120 days'
       GROUP BY hour
       ORDER BY orders_count DESC, hour DESC
       LIMIT 4`,
      [uid]
    ),
    q(
      `SELECT
         m.type::text AS type,
         COUNT(*) FILTER (WHERE o.status <> 'cancelled')::int AS orders_count
       FROM customer_order o
       JOIN merchant m ON m.id = o.merchant_id
       WHERE o.customer_user_id = $1
         AND o.created_at >= NOW() - INTERVAL '120 days'
       GROUP BY m.type
       ORDER BY orders_count DESC`,
      [uid]
    ),
    q(
      `WITH user_avg AS (
         SELECT
           customer_user_id,
           AVG(total_amount) FILTER (WHERE status <> 'cancelled') AS avg_ticket
         FROM customer_order
         WHERE created_at >= NOW() - INTERVAL '120 days'
         GROUP BY customer_user_id
       )
       SELECT
         COALESCE(PERCENTILE_CONT(0.35) WITHIN GROUP (ORDER BY avg_ticket), 0) AS p35,
         COALESCE(PERCENTILE_CONT(0.70) WITHIN GROUP (ORDER BY avg_ticket), 0) AS p70
       FROM user_avg
       WHERE avg_ticket IS NOT NULL`,
      []
    ),
  ]);

  return {
    summaryAll: summaryAllResult.rows[0] || null,
    summaryByType: summaryTypeResult.rows[0] || null,
    topMerchants: topMerchantsResult.rows,
    topOrderHours: topHoursResult.rows,
    typeMix: typeMixResult.rows,
    spendingBenchmarks: spendingBenchmarksResult.rows[0] || null,
  };
}
