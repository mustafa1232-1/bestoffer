/**
 * Purpose:
 * حسم الصلاحيات الفعّالة وفرضها (المرحلة 2 - أساس RBAC).
 * القراءة حيّة من قاعدة البيانات لكل طلب (deny-by-default) فلا تبقى صلاحيات
 * قديمة سارية. Super Admin يتجاوز كل شيء.
 */

import { AppError } from "../../shared/utils/errors.js";
import * as repo from "./permissions.repo.js";
import {
  ROLE_TEMPLATES,
  ROLE_TEMPLATE_KEYS,
  WILDCARD_PERMISSION,
  PERMISSION_KEYS,
  isValidPermissionKey,
  isValidScope,
  scopeSatisfies,
  defaultRoleTemplateForBaseRole,
} from "./permissions.catalog.js";

/**
 * يحسم الصلاحيات الفعّالة لمستخدم. يعيد:
 *   { isSuperAdmin, disabled, permissionVersion, roleKey, permissions: Map<key, scope> }
 * وعند الصلاحية الكاملة تكون permissions === "ALL".
 */
export async function resolveEffectivePermissions(userId) {
  const row = await repo.getUserAuthzRow(userId);
  if (!row) {
    return {
      isSuperAdmin: false,
      disabled: true,
      permissionVersion: 0,
      roleKey: null,
      permissions: new Map(),
    };
  }

  if (row.is_account_disabled === true) {
    return {
      isSuperAdmin: row.is_super_admin === true,
      disabled: true,
      permissionVersion: Number(row.permission_version || 1),
      roleKey: row.admin_role_key || null,
      permissions: new Map(),
    };
  }

  if (row.is_super_admin === true) {
    return {
      isSuperAdmin: true,
      disabled: false,
      permissionVersion: Number(row.permission_version || 1),
      roleKey: "super_admin",
      permissions: "ALL",
    };
  }

  const roleKey =
    (row.admin_role_key && ROLE_TEMPLATES[row.admin_role_key]
      ? row.admin_role_key
      : defaultRoleTemplateForBaseRole(row.role)) || null;

  const permissions = new Map();

  const template = roleKey ? ROLE_TEMPLATES[roleKey] : null;
  if (template) {
    if (template.includes(WILDCARD_PERMISSION)) {
      return {
        isSuperAdmin: false,
        disabled: false,
        permissionVersion: Number(row.permission_version || 1),
        roleKey,
        permissions: "ALL",
      };
    }
    for (const key of template) {
      if (isValidPermissionKey(key)) permissions.set(key, "all");
    }
  }

  // توجيهات على مستوى الدور (enable/disable) من role_permission_override.
  if (roleKey) {
    const overrides = await repo.listRoleOverrides(roleKey);
    for (const o of overrides) {
      const key = String(o.capability_key || "").trim();
      if (!isValidPermissionKey(key)) continue;
      if (o.is_enabled === true) permissions.set(key, permissions.get(key) || "all");
      else permissions.delete(key);
    }
  }

  // منح/سحب فردية (غير منتهية) — لها الأولوية النهائية.
  const grants = await repo.listUserPermissionGrants(userId);
  for (const g of grants) {
    const key = String(g.permission_key || "").trim();
    if (!isValidPermissionKey(key)) continue;
    if (g.effect === "revoke") {
      permissions.delete(key);
    } else {
      permissions.set(key, isValidScope(g.scope) ? g.scope : "all");
    }
  }

  return {
    isSuperAdmin: false,
    disabled: false,
    permissionVersion: Number(row.permission_version || 1),
    roleKey,
    permissions,
  };
}

/**
 * فحص صلاحية واحدة بنطاق مطلوب (افتراضياً "own" أي "يملك المفتاح بأي نطاق").
 * يعيد { allowed, scope, effective } دون رمي استثناء.
 */
export async function checkPermission(userId, permissionKey, requiredScope = "own") {
  const effective = await resolveEffectivePermissions(userId);
  if (effective.disabled) {
    return { allowed: false, reason: "DISABLED", effective };
  }
  if (effective.isSuperAdmin || effective.permissions === "ALL") {
    return { allowed: true, scope: "all", effective };
  }
  const grantedScope = effective.permissions.get(permissionKey);
  if (!grantedScope) {
    return { allowed: false, reason: "NO_PERMISSION", effective };
  }
  if (!scopeSatisfies(grantedScope, requiredScope)) {
    return { allowed: false, reason: "SCOPE", scope: grantedScope, effective };
  }
  return { allowed: true, scope: grantedScope, effective };
}

/**
 * صيغة عرض الصلاحيات الفعّالة للعميل (لبناء القائمة). الفرض دائماً في الخادم.
 */
export async function getEffectivePermissionsResponse(userId) {
  const effective = await resolveEffectivePermissions(userId);
  const wildcard = effective.isSuperAdmin || effective.permissions === "ALL";
  return {
    isSuperAdmin: effective.isSuperAdmin,
    roleKey: effective.roleKey,
    permissionVersion: effective.permissionVersion,
    wildcard,
    disabled: effective.disabled === true,
    permissions: wildcard
      ? PERMISSION_KEYS.map((key) => ({ key, scope: "all" }))
      : Array.from(effective.permissions.entries()).map(([key, scope]) => ({
          key,
          scope,
        })),
  };
}

export function assertValidPermissionKey(key) {
  if (!isValidPermissionKey(key)) {
    throw new AppError("INVALID_PERMISSION_KEY", { status: 400 });
  }
}

export async function grantUserPermission({
  actorUserId,
  targetUserId,
  permissionKey,
  scope = "all",
  effect = "grant",
  expiresAt = null,
  reason = null,
}) {
  assertValidPermissionKey(permissionKey);
  if (!isValidScope(scope)) {
    throw new AppError("INVALID_PERMISSION_SCOPE", { status: 400 });
  }
  if (effect !== "grant" && effect !== "revoke") {
    throw new AppError("INVALID_PERMISSION_EFFECT", { status: 400 });
  }
  return repo.upsertUserPermission({
    targetUserId,
    actorUserId,
    permissionKey,
    effect,
    scope,
    expiresAt,
    reason,
  });
}

export async function clearUserPermission({
  actorUserId,
  targetUserId,
  permissionKey,
  reason = null,
}) {
  assertValidPermissionKey(permissionKey);
  return repo.deleteUserPermission({
    targetUserId,
    actorUserId,
    permissionKey,
    reason,
  });
}

export async function assignAdminRole({
  actorUserId,
  targetUserId,
  roleKey,
  reason = null,
}) {
  if (roleKey != null && !ROLE_TEMPLATE_KEYS.includes(String(roleKey))) {
    throw new AppError("INVALID_ROLE_TEMPLATE", { status: 400 });
  }
  return repo.setUserAdminRole({ targetUserId, actorUserId, roleKey, reason });
}

export async function listUserPermissions(userId) {
  const [grants, effective] = await Promise.all([
    repo.listAllUserPermissionGrants(userId),
    getEffectivePermissionsResponse(userId),
  ]);
  return { grants, effective };
}

export async function listPermissionChangeLog(opts) {
  return repo.listPermissionChangeLog(opts);
}
