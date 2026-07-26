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

export async function getAdminRole(roleKey) {
  const key = String(roleKey || "").trim();
  if (!key) return null;
  const r = await q(
    `SELECT role_key, display_name, description, category, is_system, is_archived
     FROM admin_role
     WHERE role_key = $1
     LIMIT 1`,
    [key]
  );
  return r.rows[0] || null;
}

export async function listAdminRolePermissions(roleKey) {
  const key = String(roleKey || "").trim();
  if (!key) return [];
  const r = await q(
    `SELECT permission_key, scope
     FROM admin_role_permission
     WHERE role_key = $1
     ORDER BY permission_key ASC`,
    [key]
  );
  return r.rows;
}

export async function listAdminRoles({ includeArchived = false, search = "" } = {}) {
  const params = [];
  const clauses = [];
  if (!includeArchived) clauses.push(`is_archived = FALSE`);
  const term = String(search || "").trim();
  if (term) {
    params.push(`%${term}%`);
    clauses.push(
      `(role_key ILIKE $${params.length} OR display_name ILIKE $${params.length} OR COALESCE(description, '') ILIKE $${params.length})`
    );
  }
  const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
  const r = await q(
    `SELECT r.role_key, r.display_name, r.description, r.category,
            r.is_system, r.is_archived, r.copied_from_role_key,
            r.created_at, r.updated_at,
            COUNT(DISTINCT u.id)::int AS employee_count,
            COUNT(DISTINCT p.permission_key)::int AS permission_count
     FROM admin_role r
     LEFT JOIN app_user u ON u.admin_role_key = r.role_key
     LEFT JOIN admin_role_permission p ON p.role_key = r.role_key
     ${where}
     GROUP BY r.role_key
     ORDER BY r.is_archived ASC, r.is_system DESC, r.role_key ASC`,
    params
  );
  return r.rows;
}

async function bumpUsersForRoleTx(client, roleKey) {
  const updated = await client.query(
    `UPDATE app_user
     SET permission_version = permission_version + 1,
         updated_at = NOW()
     WHERE admin_role_key = $1
     RETURNING id`,
    [String(roleKey)]
  );
  return updated.rows.map((row) => Number(row.id)).filter(Boolean);
}

export async function createAdminRole({
  roleKey,
  displayName,
  description = null,
  category = "custom",
  actorUserId = null,
  permissions = [],
  reason = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const created = await client.query(
      `INSERT INTO admin_role
         (role_key, display_name, description, category, created_by_user_id, updated_by_user_id)
       VALUES ($1,$2,$3,$4,$5,$5)
       RETURNING *`,
      [
        String(roleKey),
        String(displayName),
        description,
        String(category || "custom"),
        actorUserId ? Number(actorUserId) : null,
      ]
    );
    for (const permission of permissions) {
      await client.query(
        `INSERT INTO admin_role_permission
           (role_key, permission_key, scope, granted_by_user_id)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (role_key, permission_key)
         DO UPDATE SET scope = EXCLUDED.scope, updated_at = NOW()`,
        [
          String(roleKey),
          String(permission.permissionKey),
          String(permission.scope || "all"),
          actorUserId ? Number(actorUserId) : null,
        ]
      );
    }
    await client.query(
      `INSERT INTO admin_permission_change_log
         (actor_user_id, action, role_key, target_role_key, after_value, reason)
       VALUES ($1, 'role_create', $2, $2, $3, $4)`,
      [
        actorUserId ? Number(actorUserId) : null,
        String(roleKey),
        JSON.stringify({ ...created.rows[0], permissions }),
        reason,
      ]
    );
    await client.query("COMMIT");
    return created.rows[0];
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function updateAdminRole({
  roleKey,
  displayName,
  description = null,
  category = "custom",
  actorUserId = null,
  permissions = null,
  reason = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const beforeRole = await client.query(
      `SELECT * FROM admin_role WHERE role_key=$1 FOR UPDATE`,
      [String(roleKey)]
    );
    if (!beforeRole.rows[0]) {
      const error = new Error("ADMIN_ROLE_NOT_FOUND");
      error.status = 404;
      throw error;
    }
    const updated = await client.query(
      `UPDATE admin_role
       SET display_name = $2,
           description = $3,
           category = $4,
           updated_by_user_id = $5,
           updated_at = NOW()
       WHERE role_key = $1
       RETURNING *`,
      [
        String(roleKey),
        String(displayName),
        description,
        String(category || "custom"),
        actorUserId ? Number(actorUserId) : null,
      ]
    );
    if (Array.isArray(permissions)) {
      await client.query(`DELETE FROM admin_role_permission WHERE role_key=$1`, [
        String(roleKey),
      ]);
      for (const permission of permissions) {
        await client.query(
          `INSERT INTO admin_role_permission
             (role_key, permission_key, scope, granted_by_user_id)
           VALUES ($1,$2,$3,$4)`,
          [
            String(roleKey),
            String(permission.permissionKey),
            String(permission.scope || "all"),
            actorUserId ? Number(actorUserId) : null,
          ]
        );
      }
    }
    const affectedUsers = await bumpUsersForRoleTx(client, roleKey);
    await client.query(
      `INSERT INTO admin_permission_change_log
         (actor_user_id, action, role_key, target_role_key, before_value, after_value, reason)
       VALUES ($1, 'role_update', $2, $2, $3, $4, $5)`,
      [
        actorUserId ? Number(actorUserId) : null,
        String(roleKey),
        JSON.stringify(beforeRole.rows[0]),
        JSON.stringify({ ...updated.rows[0], permissions, affectedUsers }),
        reason,
      ]
    );
    await client.query("COMMIT");
    return { role: updated.rows[0], affectedUsers };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function copyAdminRole({
  sourceRoleKey,
  roleKey,
  displayName,
  description = null,
  actorUserId = null,
  reason = null,
}) {
  const sourcePermissions = await listAdminRolePermissions(sourceRoleKey);
  return createAdminRole({
    roleKey,
    displayName,
    description,
    category: "custom",
    actorUserId,
    permissions: sourcePermissions.map((permission) => ({
      permissionKey: permission.permission_key,
      scope: permission.scope,
    })),
    reason,
  });
}

export async function archiveAdminRole({ roleKey, actorUserId = null, reason = null }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const users = await client.query(
      `SELECT id FROM app_user WHERE admin_role_key=$1 LIMIT 1`,
      [String(roleKey)]
    );
    if (users.rows[0]) {
      const error = new Error("ADMIN_ROLE_IN_USE");
      error.status = 409;
      throw error;
    }
    const archived = await client.query(
      `UPDATE admin_role
       SET is_archived = TRUE,
           archived_at = NOW(),
           archived_by_user_id = $2,
           updated_by_user_id = $2,
           updated_at = NOW()
       WHERE role_key = $1
         AND is_archived = FALSE
       RETURNING *`,
      [String(roleKey), actorUserId ? Number(actorUserId) : null]
    );
    if (!archived.rows[0]) {
      const error = new Error("ADMIN_ROLE_NOT_FOUND");
      error.status = 404;
      throw error;
    }
    await client.query(
      `INSERT INTO admin_permission_change_log
         (actor_user_id, action, role_key, target_role_key, after_value, reason)
       VALUES ($1, 'role_archive', $2, $2, $3, $4)`,
      [
        actorUserId ? Number(actorUserId) : null,
        String(roleKey),
        JSON.stringify(archived.rows[0]),
        reason,
      ]
    );
    await client.query("COMMIT");
    return archived.rows[0];
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
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
