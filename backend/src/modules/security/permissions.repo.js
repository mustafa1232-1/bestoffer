/**
 * Purpose:
 * طبقة الوصول لبيانات صلاحيات الإدارة الدقيقة (المرحلة 2).
 * تقرأ/تكتب: app_user (role/is_super_admin/admin_role_key/permission_version)،
 * role_permission_override (توجيهات على مستوى الدور)، admin_user_permission
 * (منح فردية)، و admin_permission_change_log (تدقيق).
 */

import { pool, q } from "../../config/db.js";

export async function getUserAuthzRow(userId) {
  const r = await q(
    `SELECT id, role, is_super_admin, admin_role_key, permission_version,
            COALESCE(is_account_disabled, FALSE) AS is_account_disabled
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function listRoleOverrides(roleKey) {
  if (!roleKey) return [];
  const r = await q(
    `SELECT capability_key, is_enabled
     FROM role_permission_override
     WHERE role_key = $1`,
    [String(roleKey)]
  );
  return r.rows;
}

export async function listUserPermissionGrants(userId) {
  const r = await q(
    `SELECT permission_key, effect, scope, expires_at
     FROM admin_user_permission
     WHERE user_id = $1
       AND (expires_at IS NULL OR expires_at > NOW())`,
    [Number(userId)]
  );
  return r.rows;
}

export async function listAllUserPermissionGrants(userId) {
  const r = await q(
    `SELECT id, permission_key, effect, scope, expires_at, reason,
            granted_by_user_id, created_at, updated_at
     FROM admin_user_permission
     WHERE user_id = $1
     ORDER BY permission_key ASC`,
    [Number(userId)]
  );
  return r.rows;
}

/**
 * منح/سحب صلاحية فردية + رفع permission_version + تسجيل التدقيق، ذرياً.
 */
export async function upsertUserPermission({
  targetUserId,
  actorUserId,
  permissionKey,
  effect,
  scope,
  expiresAt = null,
  reason = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const before = await client.query(
      `SELECT permission_key, effect, scope, expires_at
       FROM admin_user_permission
       WHERE user_id = $1 AND permission_key = $2`,
      [Number(targetUserId), String(permissionKey)]
    );

    const upserted = await client.query(
      `INSERT INTO admin_user_permission
         (user_id, permission_key, effect, scope, expires_at, reason, granted_by_user_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       ON CONFLICT (user_id, permission_key)
       DO UPDATE SET
         effect = EXCLUDED.effect,
         scope = EXCLUDED.scope,
         expires_at = EXCLUDED.expires_at,
         reason = EXCLUDED.reason,
         granted_by_user_id = EXCLUDED.granted_by_user_id,
         updated_at = NOW()
       RETURNING permission_key, effect, scope, expires_at`,
      [
        Number(targetUserId),
        String(permissionKey),
        String(effect),
        String(scope),
        expiresAt,
        reason,
        actorUserId ? Number(actorUserId) : null,
      ]
    );

    const newVersion = await client.query(
      `UPDATE app_user
       SET permission_version = permission_version + 1,
           updated_at = NOW()
       WHERE id = $1
       RETURNING permission_version`,
      [Number(targetUserId)]
    );

    await client.query(
      `INSERT INTO admin_permission_change_log
         (target_user_id, actor_user_id, action, permission_key, scope,
          before_value, after_value, reason)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        Number(targetUserId),
        actorUserId ? Number(actorUserId) : null,
        effect === "revoke" ? "revoke" : "grant",
        String(permissionKey),
        String(scope),
        before.rows[0] ? JSON.stringify(before.rows[0]) : null,
        JSON.stringify(upserted.rows[0]),
        reason,
      ]
    );

    await client.query("COMMIT");
    return {
      permission: upserted.rows[0],
      permissionVersion: Number(newVersion.rows[0]?.permission_version || 1),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function deleteUserPermission({
  targetUserId,
  actorUserId,
  permissionKey,
  reason = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const before = await client.query(
      `DELETE FROM admin_user_permission
       WHERE user_id = $1 AND permission_key = $2
       RETURNING permission_key, effect, scope, expires_at`,
      [Number(targetUserId), String(permissionKey)]
    );

    if (!before.rows[0]) {
      await client.query("ROLLBACK");
      return { removed: false };
    }

    const newVersion = await client.query(
      `UPDATE app_user
       SET permission_version = permission_version + 1,
           updated_at = NOW()
       WHERE id = $1
       RETURNING permission_version`,
      [Number(targetUserId)]
    );

    await client.query(
      `INSERT INTO admin_permission_change_log
         (target_user_id, actor_user_id, action, permission_key,
          before_value, after_value, reason)
       VALUES ($1, $2, 'clear', $3, $4, NULL, $5)`,
      [
        Number(targetUserId),
        actorUserId ? Number(actorUserId) : null,
        String(permissionKey),
        JSON.stringify(before.rows[0]),
        reason,
      ]
    );

    await client.query("COMMIT");
    return {
      removed: true,
      permissionVersion: Number(newVersion.rows[0]?.permission_version || 1),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function setUserAdminRole({
  targetUserId,
  actorUserId,
  roleKey,
  reason = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const before = await client.query(
      `SELECT admin_role_key FROM app_user WHERE id = $1`,
      [Number(targetUserId)]
    );

    const updated = await client.query(
      `UPDATE app_user
       SET admin_role_key = $2,
           permission_version = permission_version + 1,
           updated_at = NOW()
       WHERE id = $1
       RETURNING admin_role_key, permission_version`,
      [Number(targetUserId), roleKey ? String(roleKey) : null]
    );

    await client.query(
      `INSERT INTO admin_permission_change_log
         (target_user_id, actor_user_id, action, role_key, before_value, after_value, reason)
       VALUES ($1, $2, 'role_assign', $3, $4, $5, $6)`,
      [
        Number(targetUserId),
        actorUserId ? Number(actorUserId) : null,
        roleKey ? String(roleKey) : null,
        JSON.stringify({ admin_role_key: before.rows[0]?.admin_role_key || null }),
        JSON.stringify({ admin_role_key: updated.rows[0]?.admin_role_key || null }),
        reason,
      ]
    );

    await client.query("COMMIT");
    return {
      adminRoleKey: updated.rows[0]?.admin_role_key || null,
      permissionVersion: Number(updated.rows[0]?.permission_version || 1),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listPermissionChangeLog({ targetUserId = null, limit = 100 } = {}) {
  const safeLimit = Math.max(1, Math.min(500, Number(limit) || 100));
  const params = [];
  let where = "";
  if (targetUserId) {
    params.push(Number(targetUserId));
    where = `WHERE target_user_id = $${params.length}`;
  }
  params.push(safeLimit);
  const r = await q(
    `SELECT id, target_user_id, actor_user_id, action, permission_key, scope,
            role_key, before_value, after_value, reason, created_at
     FROM admin_permission_change_log
     ${where}
     ORDER BY created_at DESC
     LIMIT $${params.length}`,
    params
  );
  return r.rows;
}
