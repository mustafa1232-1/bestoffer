import { pool, q } from "../../config/db.js";
import { getRedisClient } from "../../config/redis.js";

const SUPER_ADMIN_TTL = 300; // 5 minutes

function toPositiveInteger(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

function normalizeMetadata(value) {
  if (!value || typeof value !== "object") return null;
  try {
    const compact = {};
    for (const [key, raw] of Object.entries(value).slice(0, 40)) {
      const safeKey = String(key || "").trim().slice(0, 80);
      if (!safeKey) continue;
      if (raw === null || raw === undefined) {
        compact[safeKey] = null;
        continue;
      }
      if (
        typeof raw === "string" ||
        typeof raw === "number" ||
        typeof raw === "boolean"
      ) {
        compact[safeKey] = raw;
        continue;
      }
      compact[safeKey] = String(raw).slice(0, 400);
    }
    return Object.keys(compact).length ? compact : null;
  } catch (_) {
    return null;
  }
}

export async function listAvailableOwnerAccounts() {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.block,
       u.building_number,
       u.apartment
     FROM app_user u
     LEFT JOIN merchant m
       ON m.owner_user_id = u.id
     WHERE u.role = 'owner'
       AND m.id IS NULL
     ORDER BY u.full_name ASC, u.id DESC`
  );

  return r.rows;
}

export async function listManagedMerchants() {
  const r = await q(
    `SELECT
       m.id,
       m.name,
       m.type,
       m.phone,
       m.is_open,
       m.is_approved,
       m.is_disabled,
       m.created_at,
       u.id AS owner_user_id,
       u.full_name AS owner_full_name,
       u.phone AS owner_phone,
       COALESCE(
         COUNT(o.id) FILTER (
           WHERE o.created_at >= DATE_TRUNC('day', NOW())
         ),
         0
       )::int AS today_orders_count
     FROM merchant m
     LEFT JOIN app_user u ON u.id = m.owner_user_id
     LEFT JOIN customer_order o ON o.merchant_id = m.id
     GROUP BY m.id, u.id
     ORDER BY m.id DESC`
  );
  return r.rows;
}

export async function insertAdminAuditEvent(payload) {
  const metadata = normalizeMetadata(payload.metadata);
  const r = await q(
    `INSERT INTO admin_audit_event
      (
        actor_user_id,
        actor_role,
        action_key,
        summary,
        target_type,
        target_id,
        target_label,
        metadata
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
     RETURNING id, created_at`,
    [
      toPositiveInteger(payload.actorUserId),
      payload.actorRole || null,
      String(payload.actionKey || "").slice(0, 120),
      String(payload.summary || "").slice(0, 1000),
      payload.targetType || null,
      toPositiveInteger(payload.targetId),
      payload.targetLabel ? String(payload.targetLabel).slice(0, 200) : null,
      metadata ? JSON.stringify(metadata) : null,
    ]
  );

  return r.rows[0] || null;
}

export async function listAdminAuditFeed({ limit = 40, beforeId = null } = {}) {
  const r = await q(
    `SELECT
       e.id,
       e.actor_user_id,
       e.actor_role,
       e.action_key,
       e.summary,
       e.target_type,
       e.target_id,
       e.target_label,
       e.metadata,
       e.created_at,
       u.full_name AS actor_full_name,
       u.phone AS actor_phone
     FROM admin_audit_event e
     LEFT JOIN app_user u ON u.id = e.actor_user_id
     WHERE ($1::bigint IS NULL OR e.id < $1)
     ORDER BY e.id DESC
     LIMIT $2`,
    [toPositiveInteger(beforeId), Math.max(1, Math.min(200, Number(limit) || 40))]
  );

  return r.rows;
}

export async function setMerchantDisabled(merchantId, isDisabled) {
  const r = await q(
    `UPDATE merchant
     SET is_disabled = $2
     WHERE id = $1
     RETURNING
       id,
       name,
       owner_user_id,
       is_disabled`,
    [Number(merchantId), isDisabled === true]
  );
  return r.rows[0] || null;
}

export async function isUserSuperAdmin(userId) {
  const id = Number(userId);
  if (!Number.isFinite(id) || id <= 0) return false;

  const redis = await getRedisClient().catch(() => null);
  if (redis) {
    try {
      const hit = await redis.get(`admin:superadmin:${id}`);
      if (hit !== null) return hit === "1";
    } catch (_) { /* fall through */ }
  }

  const r = await q(
    `SELECT is_super_admin
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [id]
  );

  const result = r.rows[0]?.is_super_admin === true;
  if (redis) {
    redis.set(`admin:superadmin:${id}`, result ? "1" : "0", "EX", SUPER_ADMIN_TTL).catch(() => {});
  }
  return result;
}

export async function findUserForSocialModeration(userId) {
  const r = await q(
    `SELECT
       id,
       username,
       full_name,
       phone,
       role,
       image_url,
       block,
       building_number,
       apartment,
       is_super_admin,
       is_account_disabled,
       account_disabled_note,
       account_disabled_at,
       account_disabled_by_user_id,
       account_enabled_at,
       account_enabled_by_user_id,
       created_at,
       updated_at
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function listSocialUsersForModeration({
  search = "",
  limit = 60,
  beforeId = null,
}) {
  const safeSearch = String(search || "").trim();
  const normalizedSearch = safeSearch.replace(/^@+/, "").trim();
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 60));
  const normalizedDigits = normalizedSearch
    .replace(/[\u0660-\u0669]/g, (digit) =>
      String(digit.charCodeAt(0) - 0x0660)
    )
    .replace(/[\u06F0-\u06F9]/g, (digit) =>
      String(digit.charCodeAt(0) - 0x06f0)
    )
    .replace(/[^\d]/g, "");
  const like = `%${normalizedSearch.toLowerCase()}%`;
  const phoneLike = normalizedDigits.length > 0 ? `%${normalizedDigits}%` : null;
  const searchId =
    normalizedDigits.length > 0 && normalizedDigits.length <= 15
      ? Number(normalizedDigits)
      : null;

  const r = await q(
    `SELECT
       u.id,
       u.username,
       u.full_name,
       u.phone,
       u.role,
       u.image_url,
       u.block,
       u.building_number,
       u.apartment,
       u.is_super_admin,
       u.is_account_disabled,
       u.account_disabled_note,
       u.account_disabled_at,
       u.account_disabled_by_user_id,
       u.account_enabled_at,
       u.account_enabled_by_user_id,
       u.created_at,
       u.updated_at
     FROM app_user u
     WHERE ($1::bigint IS NULL OR u.id < $1::bigint)
       AND (
         $2::text = ''
         OR LOWER(COALESCE(u.username, '')) LIKE $3::text
         OR LOWER(COALESCE(u.full_name, '')) LIKE $3::text
         OR (
           $4::text IS NOT NULL
           AND regexp_replace(
              translate(
                COALESCE(u.phone, ''),
                'Ù Ù¡Ù¢Ù£Ù¤Ù¥Ù¦Ù§Ù¨Ù©Û°Û±Û²Û³Û´ÛµÛ¶Û·Û¸Û¹',
                '01234567890123456789'
              ),
              '[^0-9]',
              '',
              'g'
            ) LIKE $4::text
         )
         OR (
           $4::text IS NOT NULL
           AND regexp_replace(
             COALESCE(u.phone, ''),
             '[^0-9]',
             '',
             'g'
           ) LIKE $4::text
         )
         OR ($5::bigint IS NOT NULL AND u.id = $5::bigint)
       )
     ORDER BY u.id DESC
     LIMIT $6`,
    [
      beforeId == null ? null : Number(beforeId),
      normalizedSearch,
      like,
      phoneLike,
      Number.isInteger(searchId) && searchId > 0 ? searchId : null,
      safeLimit,
    ]
  );
  return r.rows;
}

export async function setSocialUserAccountStatus({
  userId,
  isDisabled,
  note = null,
  actedByUserId = null,
}) {
  const normalizedNote = String(note || "").trim();
  const actor = Number(actedByUserId) || null;
  const r = await q(
    `UPDATE app_user
     SET is_account_disabled = $2,
         account_disabled_note = CASE
           WHEN $2 = TRUE THEN $3
           ELSE NULL
         END,
         account_disabled_by_user_id = CASE
           WHEN $2 = TRUE THEN $4
           ELSE account_disabled_by_user_id
         END,
         account_disabled_at = CASE
           WHEN $2 = TRUE THEN NOW()
           ELSE account_disabled_at
         END,
         account_enabled_by_user_id = CASE
           WHEN $2 = FALSE THEN $4
           ELSE account_enabled_by_user_id
         END,
         account_enabled_at = CASE
           WHEN $2 = FALSE THEN NOW()
           ELSE account_enabled_at
         END,
         updated_at = NOW()
     WHERE id = $1
     RETURNING
       id,
       username,
       full_name,
       phone,
       role,
       image_url,
       block,
       building_number,
       apartment,
       is_super_admin,
       is_account_disabled,
       account_disabled_note,
       account_disabled_at,
       account_disabled_by_user_id,
       account_enabled_at,
       account_enabled_by_user_id,
       created_at,
       updated_at`,
    [Number(userId), isDisabled === true, normalizedNote || null, actor]
  );
  return r.rows[0] || null;
}

export async function listPendingDeliveryAccounts() {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.block,
       u.building_number,
       u.apartment,
       u.created_at,
       p.vehicle_type,
       p.car_make,
       p.car_model,
       p.car_year,
       p.car_color,
       p.plate_number,
       p.profile_image_url,
       p.car_image_url
     FROM app_user u
     LEFT JOIN taxi_captain_profile p
       ON p.user_id = u.id
     WHERE u.role = 'delivery'
       AND NOT EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       )
       AND u.delivery_account_approved = FALSE
     ORDER BY u.created_at DESC, u.id DESC`
  );

  return r.rows;
}

export async function listPendingTaxiCaptainAccounts() {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.block,
       u.building_number,
       u.apartment,
       u.created_at,
       p.vehicle_type,
       p.car_make,
       p.car_model,
       p.car_year,
       p.car_color,
       p.plate_number,
       p.profile_image_url,
       p.car_image_url
     FROM app_user u
     JOIN taxi_captain_profile p
       ON p.user_id = u.id
     WHERE u.role IN ('taxi_captain', 'delivery')
       AND u.delivery_account_approved = FALSE
     ORDER BY u.created_at DESC, u.id DESC`
  );

  return r.rows;
}

export async function approveDeliveryAccount(deliveryUserId, approvedByUserId) {
  const r = await q(
    `UPDATE app_user
     SET delivery_account_approved = TRUE,
         delivery_approved_by_user_id = $2,
         delivery_approved_at = NOW()
     WHERE id = $1
       AND role = 'delivery'
       AND delivery_account_approved = FALSE
     RETURNING id, full_name, phone`,
    [Number(deliveryUserId), Number(approvedByUserId)]
  );

  return r.rows[0] || null;
}

export async function approveTaxiCaptainAccount(captainUserId, approvedByUserId) {
  const r = await q(
    `UPDATE app_user u
     SET role = 'taxi_captain',
         delivery_account_approved = TRUE,
         delivery_approved_by_user_id = $2,
         delivery_approved_at = NOW()
     WHERE u.id = $1
       AND u.role IN ('taxi_captain', 'delivery')
       AND u.delivery_account_approved = FALSE
       AND EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       )
     RETURNING u.id, u.full_name, u.phone`,
    [Number(captainUserId), Number(approvedByUserId)]
  );

  return r.rows[0] || null;
}

export async function getDeliveryUserProfileById(deliveryUserId) {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.is_account_disabled,
       u.delivery_account_approved,
       cp.driver_type,
       cp.merchant_id,
       m.name AS merchant_name
     FROM app_user u
     LEFT JOIN courier_profile cp ON cp.user_id = u.id
     LEFT JOIN merchant m ON m.id = cp.merchant_id
     WHERE u.id = $1
       AND u.role = 'delivery'
     LIMIT 1`,
    [Number(deliveryUserId)]
  );
  return r.rows[0] || null;
}

export async function getMerchantById(merchantId) {
  const r = await q(
    `SELECT id, name, type, is_approved, is_disabled
     FROM merchant
     WHERE id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function listMerchantProductsForAdBoard(merchantId, limit = 300) {
  const safeLimit = Math.max(1, Math.min(500, Number(limit) || 300));
  const r = await q(
    `SELECT
       p.id,
       p.merchant_id,
       p.name,
       p.image_url,
       p.price,
       p.discounted_price,
       p.is_available
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     WHERE p.merchant_id = $1
       AND m.is_approved = TRUE
       AND COALESCE(m.is_disabled, FALSE) = FALSE
     ORDER BY p.is_available DESC, p.sort_order ASC, p.id DESC
     LIMIT $2`,
    [Number(merchantId), safeLimit]
  );
  return r.rows;
}

export async function getMerchantProductById(merchantId, productId) {
  const r = await q(
    `SELECT
       p.id,
       p.merchant_id,
       p.name,
       p.image_url,
       p.price,
       p.discounted_price,
       p.is_available
     FROM product p
     WHERE p.id = $1
       AND p.merchant_id = $2
     LIMIT 1`,
    [Number(productId), Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function linkDeliveryAgentToMerchant({
  merchantId,
  deliveryUserId,
  createdByUserId,
  source = "admin",
}) {
  const r = await q(
    `INSERT INTO merchant_delivery_agent
      (
        merchant_id,
        delivery_user_id,
        created_by_user_id,
        source,
        is_active,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,TRUE,NOW(),NOW())
     ON CONFLICT (merchant_id, delivery_user_id)
     DO UPDATE SET
       is_active = TRUE,
       source = EXCLUDED.source,
       created_by_user_id = COALESCE(EXCLUDED.created_by_user_id, merchant_delivery_agent.created_by_user_id),
       updated_at = NOW()
     RETURNING merchant_id, delivery_user_id`,
    [
      Number(merchantId),
      Number(deliveryUserId),
      Number(createdByUserId) || null,
      String(source || "admin").slice(0, 20),
    ]
  );
  return r.rows[0] || null;
}

export async function linkAccountantToMerchant({
  merchantId,
  accountantUserId,
  createdByUserId,
  source = "admin",
}) {
  const r = await q(
    `INSERT INTO merchant_accountant
      (
        merchant_id,
        accountant_user_id,
        created_by_user_id,
        source,
        is_active,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,TRUE,NOW(),NOW())
     ON CONFLICT (merchant_id, accountant_user_id)
     DO UPDATE SET
       is_active = TRUE,
       source = EXCLUDED.source,
       created_by_user_id = COALESCE(EXCLUDED.created_by_user_id, merchant_accountant.created_by_user_id),
       updated_at = NOW()
     RETURNING merchant_id, accountant_user_id`,
    [
      Number(merchantId),
      Number(accountantUserId),
      Number(createdByUserId) || null,
      String(source || "admin").slice(0, 20),
    ]
  );
  return r.rows[0] || null;
}

export async function linkHrToMerchant({
  merchantId,
  hrUserId,
  createdByUserId,
  source = "admin",
}) {
  const r = await q(
    `INSERT INTO merchant_hr_staff
      (
        merchant_id,
        hr_user_id,
        created_by_user_id,
        source,
        is_active,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,TRUE,NOW(),NOW())
     ON CONFLICT (merchant_id, hr_user_id)
     DO UPDATE SET
       is_active = TRUE,
       source = EXCLUDED.source,
       created_by_user_id = COALESCE(EXCLUDED.created_by_user_id, merchant_hr_staff.created_by_user_id),
       updated_at = NOW()
     RETURNING merchant_id, hr_user_id`,
    [
      Number(merchantId),
      Number(hrUserId),
      Number(createdByUserId) || null,
      String(source || "admin").slice(0, 20),
    ]
  );
  return r.rows[0] || null;
}

export async function getSettlementById(settlementId) {
  const r = await q(
    `SELECT
       s.id,
       s.merchant_id,
       s.owner_user_id,
       s.amount,
       s.status,
       s.requested_at,
       s.approved_at,
       m.name AS merchant_name,
       u.full_name AS owner_full_name,
       u.phone AS owner_phone
     FROM merchant_settlement s
     JOIN merchant m ON m.id = s.merchant_id
     JOIN app_user u ON u.id = s.owner_user_id
     WHERE s.id = $1
     LIMIT 1`,
    [Number(settlementId)]
  );

  return r.rows[0] || null;
}

export async function listAdBoardItems() {
  const r = await q(
    `SELECT
       a.*,
       m.name AS merchant_name,
       m.type::text AS merchant_type,
       m.is_approved AS merchant_is_approved,
       m.is_disabled AS merchant_is_disabled
     FROM app_ad_board_item a
     LEFT JOIN merchant m ON m.id = a.merchant_id
     ORDER BY a.priority ASC, a.created_at DESC, a.id DESC`
  );
  return r.rows;
}

export async function getAdBoardItemById(itemId) {
  const r = await q(
    `SELECT *
     FROM app_ad_board_item
     WHERE id = $1
     LIMIT 1`,
    [Number(itemId)]
  );
  return r.rows[0] || null;
}

export async function createAdBoardItem(item) {
  const r = await q(
    `INSERT INTO app_ad_board_item
      (
        title,
        subtitle,
        image_url,
        badge_label,
        cta_label,
        cta_target_type,
        cta_target_value,
        target_id,
        target_route,
        promo_code,
        category,
        external_link,
        merchant_id,
        priority,
        is_active,
        starts_at,
        ends_at,
        placement,
        activity_type,
        mobile_image_url,
        title_ar,
        title_en,
        subtitle_ar,
        subtitle_en,
        cta_label_ar,
        cta_label_en,
        created_by_user_id,
        updated_by_user_id
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$27)
     RETURNING *`,
    [
      item.title,
      item.subtitle,
      item.imageUrl || null,
      item.badgeLabel || null,
      item.ctaLabel || null,
      item.ctaTargetType || "none",
      item.ctaTargetValue || null,
      item.targetId || null,
      item.targetRoute || null,
      item.promoCode || null,
      item.category || null,
      item.externalLink || null,
      item.merchantId || null,
      Number(item.priority ?? 100),
      item.isActive !== false,
      item.startsAt || null,
      item.endsAt || null,
      item.placement || "HOME_MAIN",
      item.activityType || null,
      item.mobileImageUrl || null,
      item.titleAr || null,
      item.titleEn || null,
      item.subtitleAr || null,
      item.subtitleEn || null,
      item.ctaLabelAr || null,
      item.ctaLabelEn || null,
      Number(item.actorUserId) || null,
    ]
  );
  return r.rows[0] || null;
}

export async function updateAdBoardItem(itemId, patch, actorUserId) {
  const allowed = new Map([
    ["title", "title"],
    ["subtitle", "subtitle"],
    ["imageUrl", "image_url"],
    ["badgeLabel", "badge_label"],
    ["ctaLabel", "cta_label"],
    ["ctaTargetType", "cta_target_type"],
    ["ctaTargetValue", "cta_target_value"],
    ["targetId", "target_id"],
    ["targetRoute", "target_route"],
    ["promoCode", "promo_code"],
    ["category", "category"],
    ["externalLink", "external_link"],
    ["merchantId", "merchant_id"],
    ["priority", "priority"],
    ["isActive", "is_active"],
    ["startsAt", "starts_at"],
    ["endsAt", "ends_at"],
    ["placement", "placement"],
    ["activityType", "activity_type"],
    ["mobileImageUrl", "mobile_image_url"],
    ["titleAr", "title_ar"],
    ["titleEn", "title_en"],
    ["subtitleAr", "subtitle_ar"],
    ["subtitleEn", "subtitle_en"],
    ["ctaLabelAr", "cta_label_ar"],
    ["ctaLabelEn", "cta_label_en"],
  ]);

  const keys = Object.keys(patch || {}).filter((key) => allowed.has(key));
  if (!keys.length) return null;

  const params = [];
  const assignments = keys.map((key, index) => {
    params.push(patch[key]);
    return `${allowed.get(key)} = $${index + 2}`;
  });

  params.unshift(Number(itemId));
  params.push(Number(actorUserId) || null);

  const updatedByPosition = params.length;

  const sql = `
    UPDATE app_ad_board_item
    SET ${assignments.join(", ")},
        updated_by_user_id = $${updatedByPosition}
    WHERE id = $1
    RETURNING *`;

  const r = await q(sql, params);
  return r.rows[0] || null;
}

export async function deleteAdBoardItem(itemId) {
  const r = await q(
    `DELETE FROM app_ad_board_item
     WHERE id = $1
     RETURNING id`,
    [Number(itemId)]
  );
  return r.rows[0] || null;
}

export async function listPostReports({ status = "open", limit = 80, beforePostId = null }) {
  const normalizedStatus = String(status || "open").trim().toLowerCase();
  const safeStatus = ["open", "pending_edit", "all"].includes(normalizedStatus)
    ? normalizedStatus
    : "open";
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 80));
  const r = await q(
    `SELECT
       p.id AS post_id,
       p.user_id AS author_user_id,
       p.caption,
       p.media_url,
       p.media_kind,
       p.post_kind,
       p.audience_scope_type,
       p.audience_scope_code,
       p.moderation_status,
       p.moderation_note,
       p.moderation_requested_at,
       p.created_at AS post_created_at,
       p.updated_at AS post_updated_at,
       u.full_name AS author_full_name,
       u.phone AS author_phone,
       COALESCE(COUNT(rp.id), 0)::int AS reports_count,
       MAX(rp.created_at) AS last_reported_at,
       COALESCE(
         (
           SELECT JSON_AGG(
             JSON_BUILD_OBJECT(
               'id', x.id,
               'reason', x.reason,
               'details', x.details,
               'createdAt', x.created_at,
               'reporterUserId', x.reporter_user_id,
               'reporterFullName', x.reporter_full_name,
               'reporterPhone', x.reporter_phone,
               'source', 'user'
             )
             ORDER BY x.created_at DESC, x.id DESC
           )
           FROM (
             SELECT
               rp2.id,
               rp2.reason,
               rp2.details,
               rp2.created_at,
               rp2.reporter_user_id,
               ru.full_name AS reporter_full_name,
               ru.phone AS reporter_phone
             FROM social_post_report rp2
             LEFT JOIN app_user ru ON ru.id = rp2.reporter_user_id
             WHERE rp2.post_id = p.id
             ORDER BY rp2.created_at DESC, rp2.id DESC
             LIMIT 20
           ) x
         ),
         '[]'::json
       ) AS reports
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
      LEFT JOIN social_post_report rp ON rp.post_id = p.id
      WHERE (
        (
          $1::text = 'all'
          AND p.is_deleted = FALSE
          AND (
            (p.moderation_status = 'approved' AND rp.id IS NOT NULL)
            OR p.moderation_status = 'pending'
          )
        )
        OR (
          $1::text = 'open'
          AND p.is_deleted = FALSE
         AND p.moderation_status = 'approved'
         AND rp.id IS NOT NULL
       )
       OR (
         $1::text = 'pending_edit'
         AND p.is_deleted = FALSE
         AND p.moderation_status = 'pending'
       )
     )
       AND ($2::bigint IS NULL OR p.id < $2::bigint)
     GROUP BY p.id, u.id
     ORDER BY
       COALESCE(MAX(rp.created_at), p.moderation_requested_at, p.updated_at, p.created_at) DESC,
       p.id DESC
     LIMIT $3`,
    [safeStatus, beforePostId == null ? null : Number(beforePostId), safeLimit]
  );
  return r.rows;
}

export async function listUserReports({ limit = 80, beforeId = null }) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 80));
  const r = await q(
    `SELECT
       ur.id,
       ur.reported_user_id,
       ur.reporter_user_id,
       ur.reason,
       ur.details,
       ur.created_at,
       target.full_name AS reported_user_full_name,
       target.phone AS reported_user_phone,
       reporter.full_name AS reporter_full_name,
       reporter.phone AS reporter_phone
     FROM social_user_report ur
     JOIN app_user target ON target.id = ur.reported_user_id
     JOIN app_user reporter ON reporter.id = ur.reporter_user_id
     WHERE ($1::bigint IS NULL OR ur.id < $1::bigint)
     ORDER BY ur.id DESC
     LIMIT $2`,
    [beforeId == null ? null : Number(beforeId), safeLimit]
  );
  return r.rows;
}

export async function findPostForModeration(postId) {
  const r = await q(
    `SELECT
       p.*,
       u.full_name AS author_full_name,
       u.phone AS author_phone
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     WHERE p.id = $1
     LIMIT 1`,
    [Number(postId)]
  );
  return r.rows[0] || null;
}

export async function listPostReporterIds(postId) {
  const r = await q(
    `SELECT DISTINCT reporter_user_id
     FROM social_post_report
     WHERE post_id = $1`,
    [Number(postId)]
  );
  return r.rows.map((row) => Number(row.reporter_user_id)).filter((id) => id > 0);
}

export async function clearPostReports(postId) {
  await q(`DELETE FROM social_post_report WHERE post_id = $1`, [Number(postId)]);
}

export async function markPostPendingEdit({
  postId,
  note = null,
  adminUserId = null,
}) {
  const r = await q(
    `UPDATE social_post
     SET moderation_status = 'pending',
         moderation_note = $2,
         moderation_requested_at = NOW(),
         moderation_requested_by_user_id = $3
     WHERE id = $1
       AND is_deleted = FALSE
     RETURNING *`,
    [Number(postId), note, adminUserId == null ? null : Number(adminUserId)]
  );
  return r.rows[0] || null;
}

export async function approveModeratedPost(postId) {
  const r = await q(
    `UPDATE social_post
     SET moderation_status = 'approved',
         moderation_note = NULL,
         moderation_requested_at = NULL,
         moderation_requested_by_user_id = NULL
     WHERE id = $1
       AND is_deleted = FALSE
     RETURNING *`,
    [Number(postId)]
  );
  return r.rows[0] || null;
}

export async function softDeletePostByModeration(postId) {
  const r = await q(
    `UPDATE social_post
     SET is_deleted = TRUE,
         moderation_status = 'rejected',
         moderation_requested_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(postId)]
  );
  return r.rows[0] || null;
}

export async function incrementFalseReportCounts(userIds = []) {
  if (!Array.isArray(userIds) || userIds.length <= 0) return [];
  const ids = [...new Set(userIds.map((value) => Number(value)).filter((id) => id > 0))];
  if (ids.length <= 0) return [];
  const r = await q(
    `UPDATE app_user
     SET social_false_reports_count = COALESCE(social_false_reports_count, 0) + 1,
         social_reports_blocked = (
           COALESCE(social_false_reports_count, 0) + 1
         ) >= 5
     WHERE id = ANY($1::bigint[])
     RETURNING id, social_false_reports_count, social_reports_blocked`,
    [ids]
  );
  return r.rows;
}

export async function applySocialViolationStrike(userId) {
  const r = await q(
    `WITH bumped AS (
       UPDATE app_user
       SET social_violation_strikes = COALESCE(social_violation_strikes, 0) + 1
       WHERE id = $1
       RETURNING
         id,
         social_violation_strikes,
         social_visibility_tier
     )
     UPDATE app_user u
     SET social_write_block_until = CASE
           WHEN bumped.social_violation_strikes = 1 THEN NOW() + INTERVAL '1 day'
           WHEN bumped.social_violation_strikes = 2 THEN NOW() + INTERVAL '7 days'
           ELSE NULL
         END,
         social_visibility_tier = CASE
           WHEN bumped.social_violation_strikes >= 3 THEN 'gray_zone'
           ELSE COALESCE(u.social_visibility_tier, 'normal')
         END
     FROM bumped
     WHERE u.id = bumped.id
     RETURNING
       u.id,
       bumped.social_violation_strikes AS strikes,
       u.social_write_block_until,
       u.social_visibility_tier`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function insertPostReportReviewLog({
  postId,
  adminUserId,
  action,
  note = null,
}) {
  const r = await q(
    `INSERT INTO social_post_report_review_log
      (post_id, admin_user_id, action, note)
     VALUES ($1, $2, $3, $4)
     RETURNING id, created_at`,
    [
      Number(postId),
      Number(adminUserId),
      String(action || "").trim().slice(0, 32),
      note == null ? null : String(note).trim() || null,
    ]
  );
  return r.rows[0] || null;
}

export async function listStoryReports({ status = "open", limit = 80, beforeStoryId = null }) {
  const normalizedStatus = String(status || "open").trim().toLowerCase();
  const safeStatus = ["open", "pending_edit", "all"].includes(normalizedStatus)
    ? normalizedStatus
    : "open";
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 80));
  const r = await q(
    `SELECT
       s.id AS story_id,
       s.user_id AS author_user_id,
       s.caption,
       s.media_url,
       s.media_kind,
       s.moderation_status,
       s.moderation_note,
       s.moderation_requested_at,
       s.created_at AS story_created_at,
       s.updated_at AS story_updated_at,
       s.expires_at,
       u.full_name AS author_full_name,
       u.phone AS author_phone,
       COALESCE(COUNT(sr.id), 0)::int AS reports_count,
       MAX(sr.created_at) AS last_reported_at,
       COALESCE(
         (
           SELECT JSON_AGG(
             JSON_BUILD_OBJECT(
               'id', x.id,
               'reason', x.reason,
               'details', x.details,
               'createdAt', x.created_at,
               'reporterUserId', x.reporter_user_id,
               'reporterFullName', x.reporter_full_name,
               'reporterPhone', x.reporter_phone
             )
             ORDER BY x.created_at DESC, x.id DESC
           )
           FROM (
             SELECT
               sr2.id,
               sr2.reason,
               sr2.details,
               sr2.created_at,
               sr2.reporter_user_id,
               ru.full_name AS reporter_full_name,
               ru.phone AS reporter_phone
             FROM social_story_report sr2
             LEFT JOIN app_user ru ON ru.id = sr2.reporter_user_id
             WHERE sr2.story_id = s.id
             ORDER BY sr2.created_at DESC, sr2.id DESC
             LIMIT 20
           ) x
         ),
         '[]'::json
       ) AS reports
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_story_report sr ON sr.story_id = s.id
     WHERE (
       (
         $1::text = 'all'
         AND s.is_deleted = FALSE
         AND (
           (s.moderation_status = 'approved' AND sr.id IS NOT NULL)
           OR s.moderation_status = 'pending'
         )
       )
       OR (
         $1::text = 'open'
         AND s.is_deleted = FALSE
         AND s.moderation_status = 'approved'
         AND sr.id IS NOT NULL
       )
       OR (
         $1::text = 'pending_edit'
         AND s.is_deleted = FALSE
         AND s.moderation_status = 'pending'
       )
     )
       AND ($2::bigint IS NULL OR s.id < $2::bigint)
     GROUP BY s.id, u.id
     ORDER BY
       COALESCE(MAX(sr.created_at), s.moderation_requested_at, s.updated_at, s.created_at) DESC,
       s.id DESC
     LIMIT $3`,
    [safeStatus, beforeStoryId == null ? null : Number(beforeStoryId), safeLimit]
  );
  return r.rows;
}

export async function findStoryForModeration(storyId) {
  const r = await q(
    `SELECT
       s.*,
       u.full_name AS author_full_name,
       u.phone AS author_phone
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     WHERE s.id = $1
     LIMIT 1`,
    [Number(storyId)]
  );
  return r.rows[0] || null;
}

export async function listStoryReporterIds(storyId) {
  const r = await q(
    `SELECT DISTINCT reporter_user_id
     FROM social_story_report
     WHERE story_id = $1`,
    [Number(storyId)]
  );
  return r.rows.map((row) => Number(row.reporter_user_id)).filter((id) => id > 0);
}

export async function clearStoryReports(storyId) {
  await q(`DELETE FROM social_story_report WHERE story_id = $1`, [Number(storyId)]);
}

export async function markStoryPendingEdit({
  storyId,
  note = null,
  adminUserId = null,
}) {
  const r = await q(
    `UPDATE social_story
     SET moderation_status = 'pending',
         moderation_note = $2,
         moderation_requested_at = NOW(),
         moderation_requested_by_user_id = $3
     WHERE id = $1
       AND is_deleted = FALSE
     RETURNING *`,
    [Number(storyId), note, adminUserId == null ? null : Number(adminUserId)]
  );
  return r.rows[0] || null;
}

export async function approveModeratedStory(storyId) {
  const r = await q(
    `UPDATE social_story
     SET moderation_status = 'approved',
         moderation_note = NULL,
         moderation_requested_at = NULL,
         moderation_requested_by_user_id = NULL
     WHERE id = $1
       AND is_deleted = FALSE
     RETURNING *`,
    [Number(storyId)]
  );
  return r.rows[0] || null;
}

export async function softDeleteStoryByModeration(storyId) {
  const r = await q(
    `UPDATE social_story
     SET is_deleted = TRUE,
         moderation_status = 'rejected',
         moderation_requested_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(storyId)]
  );
  return r.rows[0] || null;
}

export async function insertStoryReportReviewLog({
  storyId,
  adminUserId,
  action,
  note = null,
}) {
  const r = await q(
    `INSERT INTO social_story_report_review_log
      (story_id, admin_user_id, action, note)
     VALUES ($1, $2, $3, $4)
     RETURNING id, created_at`,
    [
      Number(storyId),
      Number(adminUserId),
      String(action || "").trim().slice(0, 32),
      note == null ? null : String(note).trim() || null,
    ]
  );
  return r.rows[0] || null;
}

export async function listResidenceChangeRequests({
  status = "pending",
  limit = 80,
  beforeId = null,
}) {
  const safeStatus = ["pending", "approved", "rejected", "cancelled", "all"].includes(
    String(status || "pending").trim().toLowerCase()
  )
    ? String(status || "pending").trim().toLowerCase()
    : "pending";
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 80));
  const r = await q(
    `SELECT
       r.*,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       reviewer.full_name AS reviewed_by_full_name
     FROM residence_change_request r
     JOIN app_user u ON u.id = r.user_id
     LEFT JOIN app_user reviewer ON reviewer.id = r.reviewed_by_user_id
     WHERE ($1::text = 'all' OR r.status = $1::text)
       AND ($2::bigint IS NULL OR r.id < $2::bigint)
     ORDER BY r.id DESC
     LIMIT $3`,
    [safeStatus, beforeId == null ? null : Number(beforeId), safeLimit]
  );
  return r.rows;
}

export async function listProfileCoreChangeRequests({
  status = "pending",
  limit = 80,
  beforeId = null,
}) {
  const safeStatus = ["pending", "approved", "rejected", "cancelled", "all"].includes(
    String(status || "pending").trim().toLowerCase()
  )
    ? String(status || "pending").trim().toLowerCase()
    : "pending";
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 80));
  const r = await q(
    `SELECT
       r.*,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       reviewer.full_name AS reviewed_by_full_name
     FROM social_profile_change_request r
     JOIN app_user u ON u.id = r.user_id
     LEFT JOIN app_user reviewer ON reviewer.id = r.reviewed_by_user_id
     WHERE r.change_kind = 'core_identity'
       AND ($1::text = 'all' OR r.status = $1::text)
       AND ($2::bigint IS NULL OR r.id < $2::bigint)
     ORDER BY r.id DESC
     LIMIT $3`,
    [safeStatus, beforeId == null ? null : Number(beforeId), safeLimit]
  );
  return r.rows;
}

export async function listSocialCapabilityRestrictionsForUser(userId) {
  const r = await q(
    `SELECT
       scr.*,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       creator.full_name AS created_by_full_name,
       revoker.full_name AS revoked_by_full_name
     FROM social_capability_restriction scr
     JOIN app_user u ON u.id = scr.user_id
     LEFT JOIN app_user creator ON creator.id = scr.created_by_user_id
     LEFT JOIN app_user revoker ON revoker.id = scr.revoked_by_user_id
     WHERE scr.user_id = $1
     ORDER BY scr.created_at DESC, scr.id DESC`,
    [Number(userId)]
  );
  return r.rows;
}

export async function createSocialCapabilityRestriction({
  userId,
  capabilityKey,
  reason = null,
  startsAt = null,
  endsAt = null,
  createdByUserId = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `UPDATE social_capability_restriction
       SET revoked_at = NOW(),
           revoked_by_user_id = $3,
           updated_at = NOW()
       WHERE user_id = $1
         AND capability_key = $2
         AND revoked_at IS NULL
         AND starts_at <= NOW()
         AND (ends_at IS NULL OR ends_at > NOW())`,
      [
        Number(userId),
        String(capabilityKey || "").trim().toLowerCase(),
        createdByUserId == null ? null : Number(createdByUserId),
      ]
    );

    const inserted = await client.query(
      `INSERT INTO social_capability_restriction
        (user_id, capability_key, reason, starts_at, ends_at, created_by_user_id)
       VALUES ($1, $2, $3, COALESCE($4::timestamptz, NOW()), $5::timestamptz, $6)
       RETURNING *`,
      [
        Number(userId),
        String(capabilityKey || "").trim().toLowerCase(),
        reason == null ? null : String(reason).trim() || null,
        startsAt,
        endsAt,
        createdByUserId == null ? null : Number(createdByUserId),
      ]
    );

    await client.query("COMMIT");
    return inserted.rows[0] || null;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function revokeSocialCapabilityRestriction({
  restrictionId,
  revokedByUserId,
}) {
  const r = await q(
    `UPDATE social_capability_restriction
     SET revoked_at = NOW(),
         revoked_by_user_id = $2,
         updated_at = NOW()
     WHERE id = $1
       AND revoked_at IS NULL
     RETURNING *`,
    [Number(restrictionId), Number(revokedByUserId)]
  );
  return r.rows[0] || null;
}

export async function approveResidenceChangeRequest({
  requestId,
  reviewedByUserId,
  reviewNote = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const requestResult = await client.query(
      `SELECT *
       FROM residence_change_request
       WHERE id = $1
       FOR UPDATE`,
      [Number(requestId)]
    );
    const request = requestResult.rows[0] || null;
    if (!request) {
      await client.query("ROLLBACK");
      return null;
    }
    if (String(request.status || "").trim().toLowerCase() !== "pending") {
      await client.query("ROLLBACK");
      return { request, alreadyReviewed: true };
    }

    const requested = request.requested_snapshot_json || {};
    const block = String(requested.block || requested.town || "").trim().toUpperCase();
    const buildingNumber = String(
      requested.buildingNumber || requested.building_number || ""
    )
      .trim()
      .toUpperCase();
    const apartment = String(
      requested.apartment || requested.apartmentNumber || requested.apartment_number || ""
    )
      .trim()
      .toUpperCase();

    await client.query(
      `UPDATE app_user
       SET block = $2,
           building_number = $3,
           apartment = $4,
           updated_at = NOW()
       WHERE id = $1`,
      [Number(request.user_id), block, buildingNumber, apartment]
    );

    await client.query(
      `INSERT INTO user_residence_info
        (user_id, document_type, town, building_number, apartment_number, image_url, created_at, updated_at)
       VALUES ($1, 'residence_change_request', $2, $3, $4, $5, NOW(), NOW())
       ON CONFLICT (user_id)
       DO UPDATE SET
         town = EXCLUDED.town,
         building_number = EXCLUDED.building_number,
         apartment_number = EXCLUDED.apartment_number,
         image_url = COALESCE(EXCLUDED.image_url, user_residence_info.image_url),
         updated_at = NOW()`,
      [
        Number(request.user_id),
        block || null,
        buildingNumber || null,
        apartment || null,
        request.document_image_url || null,
      ]
    );

    const updated = await client.query(
      `UPDATE residence_change_request
       SET status = 'approved',
           review_note = $2,
           reviewed_by_user_id = $3,
           reviewed_at = NOW(),
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(requestId),
        reviewNote == null ? null : String(reviewNote).trim() || null,
        Number(reviewedByUserId),
      ]
    );

    await client.query("COMMIT");
    return updated.rows[0] || null;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function approveProfileCoreChangeRequest({
  requestId,
  reviewedByUserId,
  reviewNote = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const requestResult = await client.query(
      `SELECT *
       FROM social_profile_change_request
       WHERE id = $1
         AND change_kind = 'core_identity'
       FOR UPDATE`,
      [Number(requestId)]
    );
    const request = requestResult.rows[0] || null;
    if (!request) {
      await client.query("ROLLBACK");
      return null;
    }
    if (String(request.status || "").trim().toLowerCase() !== "pending") {
      await client.query("ROLLBACK");
      return { request, alreadyReviewed: true };
    }

    const requested = request.requested_snapshot_json || {};
    const nextFullName =
      requested.fullName == null
        ? null
        : String(requested.fullName || "").trim() || null;
    const nextUsername =
      requested.username == null
        ? null
        : String(requested.username || "").trim().toLowerCase() || null;

    if (nextUsername != null) {
      const taken = await client.query(
        `SELECT 1
         FROM app_user
         WHERE LOWER(username) = $1
           AND id <> $2
         LIMIT 1`,
        [nextUsername, Number(request.user_id)]
      );
      if (taken.rowCount > 0) {
        const err = new Error("USERNAME_TAKEN");
        err.code = "USERNAME_TAKEN";
        err.status = 409;
        throw err;
      }
    }

    const sets = [];
    const params = [Number(request.user_id)];
    if (nextFullName != null) {
      params.push(nextFullName);
      sets.push(`full_name = $${params.length}`);
    }
    if (nextUsername != null) {
      params.push(nextUsername);
      sets.push(`username = $${params.length}`);
    }
    if (sets.length > 0) {
      await client.query(
        `UPDATE app_user
         SET ${sets.join(", ")},
             updated_at = NOW()
         WHERE id = $1`,
        params
      );
    }

    const updated = await client.query(
      `UPDATE social_profile_change_request
       SET status = 'approved',
           review_note = $2,
           reviewed_by_user_id = $3,
           reviewed_at = NOW(),
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(requestId),
        reviewNote == null ? null : String(reviewNote).trim() || null,
        Number(reviewedByUserId),
      ]
    );
    await client.query("COMMIT");
    return updated.rows[0] || null;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function rejectProfileCoreChangeRequest({
  requestId,
  reviewedByUserId,
  reviewNote = null,
}) {
  const r = await q(
    `UPDATE social_profile_change_request
     SET status = 'rejected',
         review_note = $2,
         reviewed_by_user_id = $3,
         reviewed_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND change_kind = 'core_identity'
       AND status = 'pending'
     RETURNING *`,
    [
      Number(requestId),
      reviewNote == null ? null : String(reviewNote).trim() || null,
      Number(reviewedByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function rejectResidenceChangeRequest({
  requestId,
  reviewedByUserId,
  reviewNote = null,
}) {
  const r = await q(
    `UPDATE residence_change_request
     SET status = 'rejected',
         review_note = $2,
         reviewed_by_user_id = $3,
         reviewed_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND status = 'pending'
     RETURNING *`,
    [
      Number(requestId),
      reviewNote == null ? null : String(reviewNote).trim() || null,
      Number(reviewedByUserId),
    ]
  );
  return r.rows[0] || null;
}
