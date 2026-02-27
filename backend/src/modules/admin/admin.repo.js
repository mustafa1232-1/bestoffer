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
