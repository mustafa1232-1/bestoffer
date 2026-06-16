import { q } from "../../config/db.js";

export async function setDeliveryAccountPendingApproval(userId) {
  await q(
    `UPDATE app_user
     SET delivery_account_approved = FALSE,
         delivery_approved_by_user_id = NULL,
         delivery_approved_at = NULL
     WHERE id = $1`,
    [Number(userId)]
  );
}

export async function createDeliveryCaptainProfile({
  userId,
  profileImageUrl = null,
  carImageUrl = null,
  vehicleType = "sedan",
  carMake,
  carModel,
  carYear,
  carColor = null,
  plateNumber,
}) {
  await q(
    `INSERT INTO taxi_captain_profile
      (
        user_id,
        profile_image_url,
        car_image_url,
        vehicle_type,
        car_make,
        car_model,
        car_year,
        car_color,
        plate_number,
        is_active
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,TRUE)`,
    [
      Number(userId),
      profileImageUrl || null,
      carImageUrl || null,
      String(vehicleType || "sedan").trim().slice(0, 60),
      String(carMake || "").trim(),
      String(carModel || "").trim(),
      Number(carYear),
      carColor == null ? null : String(carColor).trim() || null,
      String(plateNumber || "").trim(),
    ]
  );
}

export async function deleteUserById(userId) {
  await q(`DELETE FROM app_user WHERE id = $1`, [Number(userId)]);
}

export async function listDeliveryApproverUserIds() {
  const result = await q(
    `SELECT DISTINCT id
     FROM app_user
     WHERE role IN ('admin', 'deputy_admin')
        OR is_super_admin = TRUE`
  );
  return result.rows.map((row) => Number(row.id));
}
