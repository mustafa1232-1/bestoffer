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
