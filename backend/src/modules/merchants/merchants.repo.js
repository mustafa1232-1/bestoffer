import { pool, q } from "../../config/db.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import { getRedisClient } from "../../config/redis.js";
import { getDefaultCatalogTypeForActivity } from "./catalog-taxonomy.js";

const MERCHANT_PRODUCTS_TTL = 120; // 2 minutes
const MERCHANT_CATEGORIES_TTL = 300; // 5 minutes
const MERCHANT_CATEGORIES_SCHEMA_VERSION = "2";
const MERCHANT_CATALOG_VERSION_TTL = 7 * 24 * 60 * 60; // 7 days
const MERCHANT_BROWSE_TTL = 120; // 2 minutes
const MERCHANT_BROWSE_VERSION_TTL = 7 * 24 * 60 * 60; // 7 days
const MERCHANT_BROWSE_VERSION_KEY = "merchant:browse:ver";
const MERCHANT_BROWSE_SCHEMA_VERSION = "3";

const FALLBACK_INTERNAL_CATEGORY_TEMPLATES = Object.freeze({
  smoking_supplies: Object.freeze([
    { name: "Cigarettes", order_index: 10, icon: "smoking_rooms", catalog_type: "smoking" },
    { name: "Hookahs & Accessories", order_index: 20, icon: "local_bar", catalog_type: "hookah" },
    { name: "Electronic Hookahs", order_index: 30, icon: "electrical_services", catalog_type: "hookah" },
    { name: "Vapes", order_index: 40, icon: "vape_free", catalog_type: "vapes" },
  ]),
  furnishings: Object.freeze([
    { name: "Sofas & Seating", order_index: 10, icon: "chair", catalog_type: "furniture" },
    { name: "Beds & Mattresses", order_index: 20, icon: "bed", catalog_type: "furniture" },
    { name: "Carpets & Curtains", order_index: 30, icon: "texture", catalog_type: "furniture" },
    { name: "Tables & Storage", order_index: 40, icon: "table_bar", catalog_type: "furniture" },
  ]),
  dietary_supplements: Object.freeze([
    { name: "Vitamins", order_index: 10, icon: "spa", catalog_type: "supplements" },
    { name: "Protein & Fitness", order_index: 20, icon: "fitness_center", catalog_type: "supplements" },
    { name: "Minerals", order_index: 30, icon: "medication", catalog_type: "supplements" },
    { name: "Wellness Supplements", order_index: 40, icon: "health_and_safety", catalog_type: "supplements" },
  ]),
  phone_maintenance: Object.freeze([
    { name: "Screen Repair", order_index: 10, icon: "phone_android", catalog_type: "electronics" },
    { name: "Battery Replacement", order_index: 20, icon: "battery_charging_full", catalog_type: "electronics" },
    { name: "Software Services", order_index: 30, icon: "settings_applications", catalog_type: "electronics" },
    { name: "Accessory Repair", order_index: 40, icon: "build", catalog_type: "electronics" },
  ]),
  phones_technology: Object.freeze([
    { name: "Smartphones", order_index: 10, icon: "phone_android", catalog_type: "electronics" },
    { name: "Phone Accessories", order_index: 20, icon: "headphones", catalog_type: "electronics" },
    { name: "Tablets", order_index: 30, icon: "tablet_mac", catalog_type: "electronics" },
    { name: "Gadgets", order_index: 40, icon: "devices_other", catalog_type: "electronics" },
  ]),
});

function merchantCatalogVersionKey(merchantId) {
  return `merchant:catalog:ver:${Number(merchantId)}`;
}

export const PUBLIC_MERCHANT_CATEGORY_SELECT_COLUMNS = [
  "c.id",
  "c.merchant_id",
  "c.catalog_type AS catalog_type",
  "c.name",
  "c.sort_order",
  "c.order_index",
  "c.icon",
  "c.is_active",
  "c.source",
  "c.created_at",
  "c.updated_at",
];

export function merchantBrowseCacheKey({
  version,
  type,
  search,
  activityType,
  discoverySubcategory,
  department,
}) {
  const normalizedType = String(type || "all").trim().toLowerCase() || "all";
  const normalizedSearch = String(search || "").trim().toLowerCase() || "none";
  const normalizedActivityType =
    String(activityType || "").trim().toLowerCase() || "none";
  const normalizedDiscovery =
    String(discoverySubcategory || "").trim().toLowerCase() || "none";
  const normalizedDepartment =
    String(department || "none").trim().toLowerCase() || "none";
  return [
    "merchant:browse:list",
    `schema:${MERCHANT_BROWSE_SCHEMA_VERSION}`,
    `v${String(version || "1")}`,
    `type:${encodeURIComponent(normalizedType)}`,
    `q:${encodeURIComponent(normalizedSearch)}`,
    `activity:${encodeURIComponent(normalizedActivityType)}`,
    `discovery:${encodeURIComponent(normalizedDiscovery)}`,
    `department:${encodeURIComponent(normalizedDepartment)}`,
  ].join(":");
}

async function getMerchantCatalogVersion(redis, merchantId) {
  if (!redis) return "1";
  const key = merchantCatalogVersionKey(merchantId);
  let version = "1";
  try {
    const hit = await redis.get(key);
    if (hit != null) {
      version = String(hit);
    } else {
      await redis.set(key, "1", "EX", MERCHANT_CATALOG_VERSION_TTL, "NX");
    }
  } catch (_) {
    return "1";
  }
  return version;
}

async function getMerchantBrowseVersion(redis) {
  if (!redis) return "1";
  let version = "1";
  try {
    const hit = await redis.get(MERCHANT_BROWSE_VERSION_KEY);
    if (hit != null) {
      version = String(hit);
    } else {
      await redis.set(
        MERCHANT_BROWSE_VERSION_KEY,
        "1",
        "EX",
        MERCHANT_BROWSE_VERSION_TTL,
        "NX"
      );
    }
  } catch (_) {
    return "1";
  }
  return version;
}

export async function invalidateMerchantBrowseCache() {
  const redis = await getRedisClient().catch(() => null);
  if (!redis) return;
  await Promise.all([
    redis.incr(MERCHANT_BROWSE_VERSION_KEY).catch(() => {}),
    redis.expire(MERCHANT_BROWSE_VERSION_KEY, MERCHANT_BROWSE_VERSION_TTL).catch(() => {}),
  ]);
}

export async function getCachedMerchantBrowseList({
  type,
  search,
  activityType,
  discoverySubcategory,
  department,
}) {
  const redis = await getRedisClient().catch(() => null);
  if (!redis) return null;
  const version = await getMerchantBrowseVersion(redis);
  const key = merchantBrowseCacheKey({
    version,
    type,
    search,
    activityType,
    discoverySubcategory,
    department,
  });
  try {
    const hit = await redis.get(key);
    if (hit == null) return null;
    return JSON.parse(hit);
  } catch (_) {
    return null;
  }
}

export async function setCachedMerchantBrowseList(
  { type, search, activityType, discoverySubcategory },
  payload
) {
  const redis = await getRedisClient().catch(() => null);
  if (!redis) return;
  const version = await getMerchantBrowseVersion(redis);
  const key = merchantBrowseCacheKey({
    version,
    type,
    search,
    activityType,
    discoverySubcategory,
  });
  redis
    .set(key, JSON.stringify(payload), "EX", MERCHANT_BROWSE_TTL)
    .catch(() => {});
}

export async function invalidateMerchantCatalogCache(merchantId) {
  const redis = await getRedisClient().catch(() => null);
  if (!redis) return;
  const merchantIdNum = Number(merchantId);
  if (!Number.isInteger(merchantIdNum) || merchantIdNum <= 0) return;
  const versionKey = merchantCatalogVersionKey(merchantIdNum);
  await Promise.all([
    // Legacy keys cleanup (pre-versioned caching)
    redis.del(`merchant:products:${merchantIdNum}`).catch(() => {}),
    redis.del(`merchant:categories:${merchantIdNum}`).catch(() => {}),
    // Version bump invalidates all paginated keys for this merchant atomically.
    redis.incr(versionKey).catch(() => {}),
    redis.expire(versionKey, MERCHANT_CATALOG_VERSION_TTL).catch(() => {}),
    redis.incr(MERCHANT_BROWSE_VERSION_KEY).catch(() => {}),
    redis.expire(MERCHANT_BROWSE_VERSION_KEY, MERCHANT_BROWSE_VERSION_TTL).catch(() => {}),
  ]);
}

function normalizeDiscoveryCodes(values) {
  if (!Array.isArray(values)) return [];
  const out = [];
  const seen = new Set();
  for (const value of values) {
    if (value == null) continue;
    const normalized = String(value).trim().toLowerCase();
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function appError(message, status) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function haversineDistanceSql(latExpr, lngExpr, latParam, lngParam) {
  return `(
    6371 * acos(
      LEAST(
        1,
        GREATEST(
          -1,
          cos(radians(${latParam})) * cos(radians(${latExpr})) *
            cos(radians(${lngExpr}) - radians(${lngParam})) +
          sin(radians(${latParam})) * sin(radians(${latExpr}))
        )
      )
    )
  )`;
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
          (full_name, username, phone, pin_hash, block, building_number, apartment, image_url, role)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'owner')
         RETURNING id, full_name, phone, role, image_url`,
        [
          ownerToCreate.fullName,
          ownerToCreate.username,
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

    const discoverySelectAll = merchant.discoverySelectAll === true;
    const discoveryCodes = normalizeDiscoveryCodes(
      merchant.discoverySubcategories
    );

    const merchantResult = await client.query(
      `INSERT INTO merchant
        (
          name,
          type,
          activity_type,
          store_department,
          discovery_subcategory,
          discovery_select_all,
          description,
          phone,
          image_url,
          owner_user_id,
          is_approved,
          approved_by_user_id,
          approved_at,
          service_flags_json,
          supports_chat,
          supports_attachments,
          supports_pharmacy_workflow,
          badges_json,
          logo_url,
          cover_image_url,
          delivery_eta_min_minutes,
          delivery_eta_max_minutes,
          delivery_fee,
          minimum_order,
          is_verified
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,TRUE,$11,NOW(),$12::jsonb,$13,$14,$15,$16::jsonb,$17,$18,$19,$20,$21,$22,$23)
       RETURNING id`,
      [
        merchant.name,
        merchant.type,
        merchant.activityType,
        merchant.storeDepartment || null,
        merchant.discoverySubcategory,
        discoverySelectAll,
        merchant.description,
        merchant.phone || owner.phone,
        merchant.imageUrl,
        owner.id,
        approvedByUserId || null,
        JSON.stringify(merchant.serviceFlags || {}),
        merchant.supportsChat === true,
        merchant.supportsAttachments === true,
        merchant.supportsPharmacyWorkflow === true,
        JSON.stringify(Array.isArray(merchant.badges) ? merchant.badges : []),
        merchant.logoUrl ?? null,
        merchant.coverImageUrl ?? null,
        merchant.deliveryEtaMinMinutes ?? null,
        merchant.deliveryEtaMaxMinutes ?? null,
        merchant.deliveryFee ?? null,
        merchant.minimumOrder ?? null,
        merchant.isVerified === true,
      ]
    );
    const merchantId = Number(merchantResult.rows[0]?.id);
    if (Number.isInteger(merchantId) && merchantId > 0 && discoveryCodes.length) {
      await client.query(
        `INSERT INTO merchant_discovery_subcategory (merchant_id, discovery_code)
         SELECT $1::bigint, code
         FROM UNNEST($2::text[]) AS t(code)
         ON CONFLICT (merchant_id, discovery_code) DO NOTHING`,
        [merchantId, discoveryCodes]
      );
    }

    const hydratedResult = await client.query(
      `SELECT m.*,
              COALESCE(
                (
                  SELECT ARRAY_AGG(mds.discovery_code ORDER BY mds.discovery_code)
                  FROM merchant_discovery_subcategory mds
                  WHERE mds.merchant_id = m.id
                ),
                ARRAY[]::text[]
              ) AS discovery_subcategories
       FROM merchant m
       WHERE m.id = $1
       LIMIT 1`,
      [merchantId]
    );
    const createdMerchant = hydratedResult.rows[0];

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

    await invalidateMerchantBrowseCache();

    return createdMerchant;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function getAllMerchants(type, search, options = {}) {
  const values = [];
  const where = ["m.is_approved=TRUE", "m.is_disabled=FALSE"];
  const activityType =
    typeof options.activityType === "string" ? options.activityType.trim() : "";
  const discoverySubcategory =
    typeof options.discoverySubcategory === "string"
      ? options.discoverySubcategory.trim()
      : "";

  if (type) {
    values.push(type);
    where.push(`m.type=$${values.length}`);
  }

  if (activityType) {
    values.push(activityType);
    where.push(`m.activity_type = $${values.length}`);
  }

  const department =
    typeof options.department === "string"
      ? options.department.trim().toLowerCase()
      : "";
  if (department === "men" || department === "women") {
    values.push(department);
    // A store is in the customer section if its department matches OR it is
    // unisex (sells both). needs_review / NULL never appear in a section.
    where.push(`m.store_department IN ($${values.length}, 'unisex')`);
  }

  if (discoverySubcategory) {
    values.push(discoverySubcategory);
    where.push(
      `(
        (
          m.discovery_select_all = TRUE
          AND EXISTS (
            SELECT 1
            FROM store_activity_discovery_option sado
            WHERE sado.activity_type = m.activity_type
              AND sado.code = $${values.length}
              AND sado.is_active = TRUE
          )
        )
        OR m.discovery_subcategory = $${values.length}
        OR EXISTS (
          SELECT 1
          FROM merchant_discovery_subcategory mds
          WHERE mds.merchant_id = m.id
            AND mds.discovery_code = $${values.length}
        )
      )`
    );
  }

  const normalizedSearch = typeof search === "string" ? search.trim() : "";
  if (normalizedSearch) {
    values.push(`%${normalizedSearch}%`);
    const idx = values.length;
    where.push(
      `(
        m.name ILIKE $${idx}
        OR COALESCE(m.description, '') ILIKE $${idx}
        OR COALESCE(m.tagline, '') ILIKE $${idx}
        OR COALESCE(m.phone, '') ILIKE $${idx}
        OR EXISTS (
          SELECT 1
          FROM product p
          LEFT JOIN merchant_category c ON c.id = p.category_id
          WHERE p.merchant_id = m.id
            AND (
              p.name ILIKE $${idx}
              OR COALESCE(p.description, '') ILIKE $${idx}
              OR COALESCE(c.name, '') ILIKE $${idx}
            )
        )
      )`
    );
  }

  const r = await q(
    `SELECT
       m.*,
       COALESCE(
         (
           SELECT ARRAY_AGG(mds.discovery_code ORDER BY mds.discovery_code)
           FROM merchant_discovery_subcategory mds
           WHERE mds.merchant_id = m.id
         ),
         ARRAY[]::text[]
       ) AS discovery_subcategories,
       EXISTS (
         SELECT 1
         FROM product p
         WHERE p.merchant_id = m.id
           AND p.is_available = TRUE
           AND (
             (p.discounted_price IS NOT NULL AND p.discounted_price < p.price)
             OR EXISTS (
               SELECT 1
               FROM merchant_offer_product mop
               JOIN merchant_offer mo ON mo.id = mop.offer_id
               WHERE mop.product_id = p.id
                 AND mo.merchant_id = m.id
                 AND mo.status NOT IN ('draft', 'disabled', 'expired')
                 AND (mo.starts_at IS NULL OR mo.starts_at <= NOW())
                 AND (mo.ends_at IS NULL OR mo.ends_at >= NOW())
             )
           )
       ) AS has_discount_offer,
       EXISTS (
         SELECT 1
         FROM product p
         WHERE p.merchant_id = m.id
           AND p.is_available = TRUE
           AND p.free_delivery = TRUE
       ) AS has_free_delivery_offer,
       COALESCE(
         (
           SELECT AVG(o.merchant_rating)
           FROM customer_order o
           WHERE o.merchant_id = m.id
             AND o.merchant_rating IS NOT NULL
             AND o.status IN ('completed', 'delivered', 'received_by_customer')
         ),
         0
       )::numeric(6,3) AS avg_merchant_rating,
       COALESCE(
         (
           SELECT COUNT(o.merchant_rating)
           FROM customer_order o
           WHERE o.merchant_id = m.id
             AND o.merchant_rating IS NOT NULL
             AND o.status IN ('completed', 'delivered', 'received_by_customer')
         ),
         0
       )::int AS rating_count,
       COALESCE(
         (
           SELECT AVG(
             CASE
               WHEN p.discounted_price IS NOT NULL AND p.discounted_price > 0
                 THEN p.discounted_price
               ELSE p.price
             END
           )
           FROM product p
           WHERE p.merchant_id = m.id
             AND p.is_available = TRUE
         ),
         0
       )::numeric(12,2) AS avg_menu_price,
       COALESCE(
         (
           SELECT COUNT(*)
           FROM customer_order o
           WHERE o.merchant_id = m.id
             AND o.status IN ('completed', 'delivered', 'received_by_customer')
         ),
         0
       )::int AS completed_orders_count
     FROM merchant m
     WHERE ${where.join(" AND ")}`,
    values
  );
  return r.rows;
}

export async function getPublicMerchantProducts(merchantId, { limit = 200, offset = 0 } = {}) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 200));
  const safeOffset = Math.max(0, Number(offset) || 0);

  const redis = await getRedisClient().catch(() => null);
  const cacheVersion = await getMerchantCatalogVersion(redis, merchantId);
  const cacheKey = `merchant:products:${Number(merchantId)}:v${cacheVersion}:${safeOffset}:${safeLimit}`;
  if (redis) {
    try {
      const hit = await redis.get(cacheKey);
      if (hit !== null) return JSON.parse(hit);
    } catch (_) { /* fall through */ }
  }
  const r = await q(
    `SELECT
       p.*,
       COALESCE(s.inventory_enabled, FALSE) AS track_stock,
       CASE
         WHEN COALESCE(s.inventory_enabled, FALSE) = TRUE THEN 'tracked'
         ELSE 'untracked'
       END AS stock_mode,
       CASE
         WHEN s.inventory_enabled = TRUE
           AND s.daily_update_mode <> 'manual_override'
           AND s.show_all_without_auto_disable = FALSE
         THEN CASE
           WHEN COALESCE(si.manual_disabled, FALSE) = TRUE THEN FALSE
           WHEN COALESCE(si.auto_disabled, FALSE) = TRUE THEN FALSE
           WHEN COALESCE(si.stock_status, 'in_stock') = 'manual_disabled' THEN FALSE
           WHEN COALESCE(si.stock_status, 'in_stock') = 'out_of_stock'
             AND s.auto_disable_out_of_stock = TRUE THEN FALSE
           ELSE p.is_available
         END
         ELSE p.is_available
       END AS is_available,
       COALESCE(si.quantity, NULL) AS inventory_quantity,
       COALESCE(si.stock_status, NULL) AS inventory_stock_status,
       c.name AS category_name,
       c.sort_order AS category_sort_order,
       c.order_index AS category_order_index
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     LEFT JOIN inventory_settings s ON s.merchant_id = p.merchant_id
     LEFT JOIN store_inventory_item si
       ON si.merchant_id = p.merchant_id
      AND si.product_id = p.id
     WHERE p.merchant_id=$1
       AND m.is_approved=TRUE
       AND m.is_disabled=FALSE
     ORDER BY
       COALESCE(c.order_index, c.sort_order, 999999),
       COALESCE(c.sort_order, 999999),
       COALESCE(c.id, 0),
       p.sort_order ASC,
       p.id DESC
     LIMIT $2 OFFSET $3`,
    [merchantId, safeLimit, safeOffset]
  );
  if (redis) redis.set(cacheKey, JSON.stringify(r.rows), "EX", MERCHANT_PRODUCTS_TTL).catch(() => {});
  return r.rows;
}

export async function getPublicMerchantCategories(merchantId) {
  const redis = await getRedisClient().catch(() => null);
  const cacheVersion = await getMerchantCatalogVersion(redis, merchantId);
  const cacheKey = `merchant:categories:schema:${MERCHANT_CATEGORIES_SCHEMA_VERSION}:${Number(merchantId)}:v${cacheVersion}`;
  if (redis) {
    try {
      const hit = await redis.get(cacheKey);
      if (hit !== null) return JSON.parse(hit);
    } catch (_) { /* fall through */ }
  }
  const r = await q(
    `SELECT
       ${PUBLIC_MERCHANT_CATEGORY_SELECT_COLUMNS.join(",\n       ")},
       COUNT(p.id) FILTER (
         WHERE CASE
           WHEN s.inventory_enabled = TRUE
             AND s.daily_update_mode <> 'manual_override'
             AND s.show_all_without_auto_disable = FALSE
           THEN CASE
             WHEN COALESCE(si.manual_disabled, FALSE) = TRUE THEN FALSE
             WHEN COALESCE(si.auto_disabled, FALSE) = TRUE THEN FALSE
             WHEN COALESCE(si.stock_status, 'in_stock') = 'manual_disabled' THEN FALSE
             WHEN COALESCE(si.stock_status, 'in_stock') = 'out_of_stock'
               AND s.auto_disable_out_of_stock = TRUE THEN FALSE
             ELSE p.is_available
           END
           ELSE p.is_available
         END
       )::int AS available_products_count
     FROM merchant_category c
     JOIN merchant m ON m.id = c.merchant_id
     LEFT JOIN inventory_settings s ON s.merchant_id = c.merchant_id
     LEFT JOIN product p
       ON p.category_id = c.id
     LEFT JOIN store_inventory_item si
       ON si.merchant_id = p.merchant_id
      AND si.product_id = p.id
     WHERE c.merchant_id = $1
       AND m.is_approved = TRUE
       AND m.is_disabled = FALSE
       AND c.is_active = TRUE
     GROUP BY c.id
     ORDER BY COALESCE(c.order_index, c.sort_order, 999999) ASC, c.id ASC`,
    [merchantId]
  );
  if (redis) {
    redis
      .set(cacheKey, JSON.stringify(r.rows), "EX", MERCHANT_CATEGORIES_TTL)
      .catch(() => {});
  }
  return r.rows;
}

export async function getPublicMerchantById(merchantId) {
  const id = Number(merchantId);
  if (!Number.isInteger(id) || id <= 0) {
    throw appError("MERCHANT_ID_INVALID", 400);
  }

  const r = await q(
    `SELECT
       m.*,
       COALESCE(
         (
           SELECT ARRAY_AGG(mds.discovery_code ORDER BY mds.discovery_code)
           FROM merchant_discovery_subcategory mds
           WHERE mds.merchant_id = m.id
         ),
         ARRAY[]::text[]
       ) AS discovery_subcategories,
       EXISTS (
         SELECT 1
         FROM product p
         WHERE p.merchant_id = m.id
           AND p.is_available = TRUE
           AND (
             (p.discounted_price IS NOT NULL AND p.discounted_price < p.price)
             OR EXISTS (
               SELECT 1
               FROM merchant_offer_product mop
               JOIN merchant_offer mo ON mo.id = mop.offer_id
               WHERE mop.product_id = p.id
                 AND mo.merchant_id = m.id
                 AND mo.status NOT IN ('draft', 'disabled', 'expired')
                 AND (mo.starts_at IS NULL OR mo.starts_at <= NOW())
                 AND (mo.ends_at IS NULL OR mo.ends_at >= NOW())
             )
           )
       ) AS has_discount_offer,
       EXISTS (
         SELECT 1
         FROM product p
         WHERE p.merchant_id = m.id
           AND p.is_available = TRUE
           AND p.free_delivery = TRUE
       ) AS has_free_delivery_offer,
       COALESCE(
         (
           SELECT AVG(o.merchant_rating)
           FROM customer_order o
           WHERE o.merchant_id = m.id
             AND o.merchant_rating IS NOT NULL
             AND o.status IN ('completed', 'delivered', 'received_by_customer')
         ),
         0
       )::numeric(6,3) AS avg_merchant_rating,
       COALESCE(
         (
           SELECT COUNT(o.merchant_rating)
           FROM customer_order o
           WHERE o.merchant_id = m.id
             AND o.merchant_rating IS NOT NULL
             AND o.status IN ('completed', 'delivered', 'received_by_customer')
         ),
         0
       )::int AS rating_count
     FROM merchant m
     WHERE m.id = $1
       AND m.is_approved = TRUE
       AND COALESCE(m.is_disabled, FALSE) = FALSE
     LIMIT 1`,
    [id]
  );

  return r.rows[0] || null;
}

export async function getNearbyPublicMerchants({
  latitude,
  longitude,
  radiusKm = 10,
  limit = 40,
  type = null,
}) {
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
    throw appError("LATITUDE_INVALID", 400);
  }
  if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
    throw appError("LONGITUDE_INVALID", 400);
  }

  const safeRadius = Math.max(0.5, Math.min(50, Number(radiusKm) || 10));
  const safeLimit = Math.max(
    1,
    Math.min(120, Math.trunc(Number(limit) || 40))
  );
  const normalizedType =
    typeof type === "string" && type.trim().length ? type.trim() : null;

  const latDelta = safeRadius / 111.32;
  const cosLat = Math.cos((lat * Math.PI) / 180);
  const lngDelta =
    Math.abs(cosLat) < 0.000001
      ? 180
      : safeRadius / (111.32 * Math.abs(cosLat));

  const minLat = Math.max(-90, lat - latDelta);
  const maxLat = Math.min(90, lat + latDelta);
  const minLng = Math.max(-180, lng - lngDelta);
  const maxLng = Math.min(180, lng + lngDelta);

  const distanceExpr = haversineDistanceSql("m.latitude", "m.longitude", "$1", "$2");
  const r = await q(
    `WITH candidates AS (
       SELECT
         m.*,
         COALESCE(
           (
             SELECT ARRAY_AGG(mds.discovery_code ORDER BY mds.discovery_code)
             FROM merchant_discovery_subcategory mds
             WHERE mds.merchant_id = m.id
           ),
           ARRAY[]::text[]
         ) AS discovery_subcategories,
         EXISTS (
           SELECT 1
           FROM product p
           WHERE p.merchant_id = m.id
             AND p.is_available = TRUE
             AND (
               (p.discounted_price IS NOT NULL AND p.discounted_price < p.price)
               OR EXISTS (
                 SELECT 1
                 FROM merchant_offer_product mop
                 JOIN merchant_offer mo ON mo.id = mop.offer_id
                 WHERE mop.product_id = p.id
                   AND mo.merchant_id = m.id
                   AND mo.status NOT IN ('draft', 'disabled', 'expired')
                   AND (mo.starts_at IS NULL OR mo.starts_at <= NOW())
                   AND (mo.ends_at IS NULL OR mo.ends_at >= NOW())
               )
             )
         ) AS has_discount_offer,
         EXISTS (
           SELECT 1
           FROM product p
           WHERE p.merchant_id = m.id
             AND p.is_available = TRUE
             AND p.free_delivery = TRUE
         ) AS has_free_delivery_offer,
         COALESCE(
           (
             SELECT AVG(o.merchant_rating)
             FROM customer_order o
             WHERE o.merchant_id = m.id
               AND o.merchant_rating IS NOT NULL
               AND o.status IN ('completed', 'delivered', 'received_by_customer')
           ),
           0
         )::numeric(6,3) AS avg_merchant_rating,
         COALESCE(
           (
             SELECT COUNT(o.merchant_rating)
             FROM customer_order o
             WHERE o.merchant_id = m.id
               AND o.merchant_rating IS NOT NULL
               AND o.status IN ('completed', 'delivered', 'received_by_customer')
           ),
           0
         )::int AS rating_count,
         ${distanceExpr} AS distance_km
       FROM merchant m
       WHERE m.is_approved = TRUE
         AND COALESCE(m.is_disabled, FALSE) = FALSE
         AND m.latitude IS NOT NULL
         AND m.longitude IS NOT NULL
         AND m.latitude BETWEEN $3 AND $4
         AND m.longitude BETWEEN $5 AND $6
         AND ($9::text IS NULL OR m.type::text = $9::text)
     )
     SELECT *
     FROM candidates
     WHERE distance_km <= $7
     ORDER BY distance_km ASC, id DESC
     LIMIT $8`,
    [lat, lng, minLat, maxLat, minLng, maxLng, safeRadius, safeLimit, normalizedType]
  );
  return r.rows;
}

export async function getPublicAdBoardItems({
  type,
  placement = null,
  categoryKey = null,
  activityType = null,
}) {
  const r = await q(
    `SELECT
       a.id,
       a.placement,
       a.title,
       a.title_ar,
       a.title_en,
       a.subtitle,
       a.subtitle_ar,
       a.subtitle_en,
       a.image_url,
       a.mobile_image_url,
       a.badge_label,
       a.cta_label,
       a.cta_label_ar,
       a.cta_label_en,
       a.cta_target_type,
       a.cta_target_value,
       a.target_id,
       a.target_route,
       a.promo_code,
       a.category,
       a.activity_type,
       a.external_link,
       a.merchant_id,
       a.priority,
       a.starts_at,
       a.ends_at,
       a.created_at,
       m.name AS merchant_name,
       m.type::text AS merchant_type,
       m.image_url AS merchant_image_url,
       m.is_open AS merchant_is_open
     FROM app_ad_board_item a
     LEFT JOIN merchant m ON m.id = a.merchant_id
     WHERE a.is_active = TRUE
       AND (a.starts_at IS NULL OR a.starts_at <= NOW())
       AND (a.ends_at IS NULL OR a.ends_at >= NOW())
       AND (
         a.merchant_id IS NULL
         OR (
           m.is_approved = TRUE
           AND COALESCE(m.is_disabled, FALSE) = FALSE
         )
       )
       AND ($2::text IS NULL OR a.placement = $2::text)
       AND (
         $1::text IS NULL
         OR a.merchant_id IS NULL
         OR m.type::text = $1::text
       )
       -- Category targeting: a category-scoped ad matches only its category /
       -- activity; an ad with neither is a general fallback for every category.
       AND (
         $2::text IS DISTINCT FROM 'MARKETPLACE_CATEGORY'
         OR (a.category IS NULL AND a.activity_type IS NULL)
         OR ($3::text IS NOT NULL AND a.category = $3::text)
         OR ($4::text IS NOT NULL AND a.activity_type = $4::text)
       )
     ORDER BY
       -- Exact category/subcategory/department ads outrank activity-wide ads,
       -- and both outrank the general fallback.
       ($3::text IS NOT NULL AND a.category = $3::text) DESC,
       ($4::text IS NOT NULL AND a.activity_type = $4::text) DESC,
       (a.category IS NOT NULL OR a.activity_type IS NOT NULL) DESC,
       a.priority ASC, a.created_at DESC, a.id DESC
     LIMIT 60`,
    [type || null, placement || null, categoryKey || null, activityType || null]
  );
  return r.rows;
}

/// Records one impression for an ad (called from the client only when the ad is
/// actually visible — not on every rebuild).
export async function incrementAdBoardImpression(itemId) {
  const r = await q(
    `UPDATE app_ad_board_item
        SET impression_count = impression_count + 1, last_impression_at = NOW()
      WHERE id = $1
      RETURNING id, impression_count`,
    [Number(itemId)]
  );
  return r.rows[0] || null;
}

/// Records one click/CTA tap for an ad.
export async function incrementAdBoardClick(itemId) {
  const r = await q(
    `UPDATE app_ad_board_item
        SET click_count = click_count + 1, last_click_at = NOW()
      WHERE id = $1
      RETURNING id, click_count`,
    [Number(itemId)]
  );
  return r.rows[0] || null;
}

export async function getMerchantsDiscoveryBase({
  type,
  customerUserId,
  activityType = null,
  discoverySubcategory = null,
}) {
  const normalizedActivityType =
    typeof activityType === "string" && activityType.trim().length
      ? activityType.trim()
      : null;
  const normalizedDiscoverySubcategory =
    typeof discoverySubcategory === "string" && discoverySubcategory.trim().length
      ? discoverySubcategory.trim()
      : null;
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
       m.activity_type,
       m.discovery_subcategory,
       m.discovery_select_all,
       COALESCE(
         (
           SELECT ARRAY_AGG(mds.discovery_code ORDER BY mds.discovery_code)
           FROM merchant_discovery_subcategory mds
           WHERE mds.merchant_id = m.id
         ),
         ARRAY[]::text[]
       ) AS discovery_subcategories,
       m.description,
       m.phone,
       m.image_url,
       m.tagline,
       m.working_hours,
       m.service_area_note,
       m.supports_chat,
       m.supports_attachments,
       m.supports_pharmacy_workflow,
       m.service_flags_json,
       m.badges_json,
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
       AND ($3::text IS NULL OR m.activity_type = $3::text)
        AND (
          $4::text IS NULL
          OR (
            m.discovery_select_all = TRUE
            AND EXISTS (
              SELECT 1
              FROM store_activity_discovery_option sado
              WHERE sado.activity_type = m.activity_type
                AND sado.code = $4::text
                AND sado.is_active = TRUE
            )
          )
          OR m.discovery_subcategory = $4::text
          OR EXISTS (
            SELECT 1
            FROM merchant_discovery_subcategory mds
            WHERE mds.merchant_id = m.id
              AND mds.discovery_code = $4::text
         )
       )
     ORDER BY m.id ASC`,
    [
      type || null,
      Number(customerUserId),
      normalizedActivityType,
      normalizedDiscoverySubcategory,
    ]
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

export async function listStoreActivities({ includeInactive = false } = {}) {
  const r = await q(
    `SELECT
       activity_type,
       base_type::text AS base_type,
       display_name_en,
       display_name_ar,
       has_discovery_subcategories,
       supports_chat,
       supports_attachments,
       supports_pharmacy_workflow,
       internal_category_mode,
       default_service_flags_json,
       default_badges_json,
       is_active
     FROM store_activity_definition
     WHERE ($1::boolean = TRUE OR is_active = TRUE)
     ORDER BY display_name_en ASC`,
    [includeInactive === true]
  );
  return r.rows;
}

export async function getStoreActivityByCode(activityType) {
  const r = await q(
    `SELECT
       activity_type,
       base_type::text AS base_type,
       display_name_en,
       display_name_ar,
       has_discovery_subcategories,
       supports_chat,
       supports_attachments,
       supports_pharmacy_workflow,
       internal_category_mode,
       default_service_flags_json,
       default_badges_json,
       is_active
     FROM store_activity_definition
     WHERE activity_type = $1
     LIMIT 1`,
    [String(activityType || "").trim()]
  );
  return r.rows[0] || null;
}

export async function listStoreActivityDiscoveryOptions(activityType) {
  const r = await q(
    `SELECT
       id,
       activity_type,
       code,
       label_en,
       label_ar,
       order_index,
       is_active,
       metadata_json
     FROM store_activity_discovery_option
     WHERE activity_type = $1
       AND is_active = TRUE
     ORDER BY order_index ASC, id ASC`,
    [String(activityType || "").trim()]
  );
  return r.rows;
}

export async function listStoreActivityInternalTemplates(
  activityType,
  { includeInactive = false } = {}
) {
  const r = await q(
    `SELECT
       id,
       activity_type,
       code,
       name_en,
       name_ar,
       icon,
       order_index,
       catalog_type,
       is_active,
       metadata_json
     FROM store_activity_internal_category_template
     WHERE activity_type = $1
       AND ($2::boolean = TRUE OR is_active = TRUE)
     ORDER BY order_index ASC, id ASC`,
    [String(activityType || "").trim(), includeInactive === true]
  );
  return r.rows;
}

export async function upsertStoreActivityInternalTemplate({
  activityType,
  code,
  nameEn,
  nameAr,
  icon = null,
  orderIndex = 0,
  catalogType = "generic",
  isActive = true,
} = {}) {
  const r = await q(
    `INSERT INTO store_activity_internal_category_template (
       activity_type,
       code,
       name_en,
       name_ar,
       icon,
       order_index,
       catalog_type,
       is_active,
       metadata_json
     )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'{}'::jsonb)
     ON CONFLICT (activity_type, code) DO UPDATE
       SET name_en = EXCLUDED.name_en,
           name_ar = EXCLUDED.name_ar,
           icon = EXCLUDED.icon,
           order_index = EXCLUDED.order_index,
           catalog_type = EXCLUDED.catalog_type,
           is_active = EXCLUDED.is_active,
           updated_at = NOW()
     RETURNING *`,
    [
      String(activityType || "").trim(),
      String(code || "").trim(),
      String(nameEn || "").trim(),
      String(nameAr || "").trim(),
      icon ? String(icon).trim() : null,
      Number(orderIndex) || 0,
      String(catalogType || "generic").trim(),
      isActive !== false,
    ]
  );
  return r.rows[0] || null;
}

export async function updateStoreActivityInternalTemplate(templateId, patch = {}) {
  const map = {
    code: "code",
    nameEn: "name_en",
    nameAr: "name_ar",
    icon: "icon",
    orderIndex: "order_index",
    catalogType: "catalog_type",
    isActive: "is_active",
  };
  const values = [];
  const sets = [];
  let idx = 1;
  for (const [key, column] of Object.entries(map)) {
    if (patch[key] !== undefined) {
      values.push(patch[key]);
      sets.push(`${column}=$${idx++}`);
    }
  }
  if (sets.length === 0) {
    const current = await q(
      `SELECT *
       FROM store_activity_internal_category_template
       WHERE id = $1
       LIMIT 1`,
      [Number(templateId)]
    );
    return current.rows[0] || null;
  }
  values.push(Number(templateId));
  const r = await q(
    `UPDATE store_activity_internal_category_template
     SET ${sets.join(", ")},
         updated_at = NOW()
     WHERE id = $${idx}
     RETURNING *`,
    values
  );
  return r.rows[0] || null;
}

export async function deactivateStoreActivityInternalTemplate(templateId) {
  const r = await q(
    `UPDATE store_activity_internal_category_template
     SET is_active = FALSE,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(templateId)]
  );
  return r.rows[0] || null;
}

export async function applyStoreActivityInternalTemplateToMerchants(templateId) {
  const r = await q(
    `WITH tpl AS (
       SELECT *
       FROM store_activity_internal_category_template
       WHERE id = $1
         AND is_active = TRUE
       LIMIT 1
     ),
     target_merchants AS (
       SELECT m.id AS merchant_id
       FROM merchant m
       JOIN tpl ON tpl.activity_type = m.activity_type
     )
     INSERT INTO merchant_category
       (
         merchant_id,
         name,
         sort_order,
         order_index,
         icon,
         is_active,
         source,
         catalog_type
       )
     SELECT
       tm.merchant_id,
       tpl.name_ar,
       tpl.order_index,
       tpl.order_index,
       tpl.icon,
       TRUE,
       'template',
       COALESCE(NULLIF(tpl.catalog_type, ''), 'generic')
     FROM target_merchants tm
     CROSS JOIN tpl
     WHERE NOT EXISTS (
       SELECT 1
       FROM merchant_category c
       WHERE c.merchant_id = tm.merchant_id
         AND LOWER(TRIM(c.name)) = LOWER(TRIM(tpl.name_ar))
     )
     ON CONFLICT (merchant_id, name) DO NOTHING
     RETURNING merchant_id`,
    [Number(templateId)]
  );
  return r.rows.map((row) => Number(row.merchant_id)).filter(Boolean);
}

export async function ensureMerchantDefaultInternalCategories(merchantId) {
  const merchantResult = await q(
    `SELECT activity_type
     FROM merchant
     WHERE id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  const activityType = String(merchantResult.rows[0]?.activity_type || "")
    .trim()
    .toLowerCase();
  const defaultCatalogType = getDefaultCatalogTypeForActivity(
    activityType
  );
  await q(
    `WITH target AS (
       SELECT m.id AS merchant_id, m.activity_type
       FROM merchant m
       WHERE m.id = $1
     ),
     has_categories AS (
       SELECT EXISTS (
         SELECT 1
         FROM merchant_category c
         WHERE c.merchant_id = $1
       ) AS has_any
     )
     INSERT INTO merchant_category
       (
         merchant_id,
         name,
         sort_order,
         order_index,
         icon,
         is_active,
         source,
         catalog_type
       )
     SELECT
       t.merchant_id,
       tpl.name_ar,
       tpl.order_index,
       tpl.order_index,
       tpl.icon,
       TRUE,
       'template',
       COALESCE(NULLIF(tpl.catalog_type, ''), $2)
     FROM target t
     JOIN has_categories hc ON hc.has_any = FALSE
     JOIN store_activity_internal_category_template tpl
       ON tpl.activity_type = t.activity_type
      AND tpl.is_active = TRUE
     ON CONFLICT (merchant_id, name) DO NOTHING`,
    [Number(merchantId), defaultCatalogType]
  );

  const fallbackTemplates = FALLBACK_INTERNAL_CATEGORY_TEMPLATES[activityType] || [];
  if (fallbackTemplates.length === 0) return;

  await q(
    `WITH has_categories AS (
       SELECT EXISTS (
         SELECT 1
         FROM merchant_category c
         WHERE c.merchant_id = $1
       ) AS has_any
     ),
     fallback_template AS (
       SELECT
         name,
         order_index,
         icon,
         catalog_type
       FROM jsonb_to_recordset($2::jsonb) AS tpl(
         name text,
         order_index integer,
         icon text,
         catalog_type text
       )
     )
     INSERT INTO merchant_category
       (
         merchant_id,
         name,
         sort_order,
         order_index,
         icon,
         is_active,
         source,
         catalog_type
       )
     SELECT
       $1,
       tpl.name,
       tpl.order_index,
       tpl.order_index,
       tpl.icon,
       TRUE,
       'template',
       COALESCE(NULLIF(tpl.catalog_type, ''), $3)
     FROM fallback_template tpl
     JOIN has_categories hc ON hc.has_any = FALSE
     ON CONFLICT (merchant_id, name) DO NOTHING`,
    [Number(merchantId), JSON.stringify(fallbackTemplates), defaultCatalogType]
  );
}
