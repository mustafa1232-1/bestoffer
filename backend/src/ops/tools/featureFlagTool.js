import { q } from "../../config/db.js";

export async function disableFeatureFlag({ flagKey, actorUserId }) {
  const key = String(flagKey || "").trim().toLowerCase();
  if (!key) {
    return {
      ok: false,
      reason: "missing_flag_key",
    };
  }

  const result = await q(
    `UPDATE feature_flag
     SET is_enabled = FALSE,
         updated_by_user_id = $2,
         updated_at = NOW()
     WHERE flag_key = $1
     RETURNING *`,
    [key, actorUserId || null]
  );

  if (!result.rows[0]) {
    return {
      ok: false,
      reason: "flag_not_found",
    };
  }

  return {
    ok: true,
    item: result.rows[0],
  };
}
