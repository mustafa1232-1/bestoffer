/**
 * Purpose:
 * تخزين إعدادات المنصّة المركزية (key/value) — المرحلة 8.
 */

import { q } from "../../config/db.js";

export async function getSetting(key) {
  const r = await q(
    `SELECT key, value_json, updated_by_user_id, updated_at
     FROM platform_setting
     WHERE key = $1
     LIMIT 1`,
    [String(key)]
  );
  return r.rows[0] || null;
}

export async function upsertSetting({ key, value, actorUserId = null }) {
  const r = await q(
    `INSERT INTO platform_setting (key, value_json, updated_by_user_id, updated_at)
     VALUES ($1, $2::jsonb, $3, NOW())
     ON CONFLICT (key)
     DO UPDATE SET
       value_json = EXCLUDED.value_json,
       updated_by_user_id = EXCLUDED.updated_by_user_id,
       updated_at = NOW()
     RETURNING key, value_json, updated_by_user_id, updated_at`,
    [String(key), JSON.stringify(value || {}), actorUserId ? Number(actorUserId) : null]
  );
  return r.rows[0];
}
