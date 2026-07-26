/**
 * Purpose:
 * أدلة الاستخدام لكل تطبيق (المرحلة 10). versioned + scope-aware.
 */

import { q } from "../../config/db.js";

export async function listSections({ appScope, publishedOnly = true }) {
  const conds = ["app_scope = $1"];
  const params = [String(appScope)];
  if (publishedOnly) conds.push("is_published = TRUE");
  const r = await q(
    `SELECT id, app_scope, section_key, title, body, order_index,
            required_permission, deep_link, version, is_published, updated_at
     FROM app_guide_section
     WHERE ${conds.join(" AND ")}
     ORDER BY order_index ASC, id ASC`,
    params
  );
  return r.rows;
}

export async function guideVersion(appScope) {
  const r = await q(
    `SELECT COALESCE(MAX(EXTRACT(EPOCH FROM updated_at))::bigint, 0) AS v,
            COUNT(*)::int AS sections
     FROM app_guide_section
     WHERE app_scope = $1 AND is_published = TRUE`,
    [String(appScope)]
  );
  return { version: Number(r.rows[0]?.v || 0), sections: Number(r.rows[0]?.sections || 0) };
}

export async function upsertSection({
  appScope, sectionKey, title, body, orderIndex = 0,
  requiredPermission = null, deepLink = null, isPublished = true, actorUserId = null,
}) {
  const r = await q(
    `INSERT INTO app_guide_section
       (app_scope, section_key, title, body, order_index, required_permission,
        deep_link, is_published, updated_by_user_id)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
     ON CONFLICT (app_scope, section_key) DO UPDATE SET
       title = EXCLUDED.title,
       body = EXCLUDED.body,
       order_index = EXCLUDED.order_index,
       required_permission = EXCLUDED.required_permission,
       deep_link = EXCLUDED.deep_link,
       is_published = EXCLUDED.is_published,
       version = app_guide_section.version + 1,
       updated_by_user_id = EXCLUDED.updated_by_user_id,
       updated_at = NOW()
     RETURNING *`,
    [
      String(appScope), String(sectionKey), title, body, Number(orderIndex) || 0,
      requiredPermission, deepLink, isPublished !== false,
      actorUserId ? Number(actorUserId) : null,
    ]
  );
  return r.rows[0];
}
