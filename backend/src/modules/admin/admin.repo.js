import { q } from "../../config/db.js";

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

  const r = await q(
    `SELECT is_super_admin
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [id]
  );

  return r.rows[0]?.is_super_admin === true;
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
     ORDER BY a.priority ASC, a.id DESC`
  );
  return r.rows;
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
        merchant_id,
        priority,
        is_active,
        starts_at,
        ends_at,
        created_by_user_id,
        updated_by_user_id
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13)
     RETURNING *`,
    [
      item.title,
      item.subtitle,
      item.imageUrl || null,
      item.badgeLabel || null,
      item.ctaLabel || null,
      item.ctaTargetType || "none",
      item.ctaTargetValue || null,
      item.merchantId || null,
      Number(item.priority ?? 100),
      item.isActive !== false,
      item.startsAt || null,
      item.endsAt || null,
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
    ["merchantId", "merchant_id"],
    ["priority", "priority"],
    ["isActive", "is_active"],
    ["startsAt", "starts_at"],
    ["endsAt", "ends_at"],
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
