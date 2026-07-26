/**
 * Purpose:
 * حسم الصلاحيات الفعّالة وفرضها (المرحلة 2 - أساس RBAC).
 * القراءة حيّة من قاعدة البيانات لكل طلب (deny-by-default) فلا تبقى صلاحيات
 * قديمة سارية. Super Admin يتجاوز كل شيء.
 */

import { AppError } from "../../shared/utils/errors.js";
import { invalidateSessionAccessCacheForUser } from "../../shared/middleware/access-auth.js";
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

const PERMISSION_CACHE_TTL_MS = 10_000;
const permissionCache = new Map();

function permissionCacheKey(userId, permissionVersion) {
  return `${Number(userId)}:${Number(permissionVersion || 0)}`;
}

function readPermissionCache(userId, permissionVersion) {
  const key = permissionCacheKey(userId, permissionVersion);
  const hit = permissionCache.get(key);
  if (!hit || hit.expiresAt <= Date.now()) {
    permissionCache.delete(key);
    return null;
  }
  return hit.value;
}

function writePermissionCache(userId, permissionVersion, value) {
  permissionCache.set(permissionCacheKey(userId, permissionVersion), {
    value,
    expiresAt: Date.now() + PERMISSION_CACHE_TTL_MS,
  });
  return value;
}

export function invalidatePermissionCacheForUser(userId) {
  const prefix = `${Number(userId)}:`;
  for (const key of permissionCache.keys()) {
    if (key.startsWith(prefix)) permissionCache.delete(key);
  }
  invalidateSessionAccessCacheForUser({ userId });
}

function normalizeRoleKey(value) {
  return String(value || "").trim().toLowerCase();
}

function assertValidRoleKey(roleKey) {
  const key = normalizeRoleKey(roleKey);
  if (!/^[a-z][a-z0-9_]{2,47}$/.test(key)) {
    throw new AppError("INVALID_ROLE_KEY", { status: 400 });
  }
  return key;
}

function normalizePermissionPayloadList(permissions = []) {
  if (!Array.isArray(permissions)) return [];
  return permissions.map((permission) => {
    const permissionKey = String(
      permission?.permissionKey || permission?.permission_key || permission?.key || ""
    ).trim();
    assertValidPermissionKey(permissionKey);
    const scope = String(permission?.scope || "all").trim();
    if (!isValidScope(scope)) {
      throw new AppError("INVALID_PERMISSION_SCOPE", { status: 400 });
    }
    return { permissionKey, scope };
  });
}

function isSensitivePermissionKey(permissionKey) {
  return [
    "employees.permissions.manage",
    "accounts.delete_approve",
    "payroll.release",
    "payroll.approve",
    "taxi.rides.emergency_cancel",
  ].includes(String(permissionKey || "").trim());
}

function roleTemplatePermissions(roleKey) {
  const template = ROLE_TEMPLATES[roleKey];
  if (!template) return null;
  if (template.includes(WILDCARD_PERMISSION)) {
    return PERMISSION_KEYS.map((permissionKey) => ({ permissionKey, scope: "all" }));
  }
  return template
    .filter((permissionKey) => isValidPermissionKey(permissionKey))
    .map((permissionKey) => ({ permissionKey, scope: "all" }));
}

async function assertActorCanManagePermission({
  actorUserId,
  targetUserId = null,
  permissionKey = null,
}) {
  const actorId = Number(actorUserId);
  if (!actorId) throw new AppError("PERMISSION_ACTOR_REQUIRED", { status: 403 });
  const actor = await resolveEffectivePermissions(actorId);
  if (actor.disabled) throw new AppError("PERMISSION_ACTOR_DISABLED", { status: 403 });
  if (actor.isSuperAdmin || actor.permissions === "ALL") return;
  if (Number(targetUserId) === actorId && isSensitivePermissionKey(permissionKey)) {
    throw new AppError("SELF_PRIVILEGE_ESCALATION_BLOCKED", { status: 403 });
  }
  const hasPermissionManager =
    actor.permissions instanceof Map &&
    actor.permissions.has("employees.permissions.manage");
  if (!hasPermissionManager) {
    throw new AppError("FORBIDDEN_PERMISSION_MANAGER_REQUIRED", { status: 403 });
  }
  if (isSensitivePermissionKey(permissionKey)) {
    throw new AppError("SENSITIVE_PERMISSION_REQUIRES_SUPER_ADMIN", { status: 403 });
  }
}

async function assertActorCanManagePermissionList({
  actorUserId,
  targetUserId = null,
  permissions = [],
}) {
  if (!permissions.length) {
    await assertActorCanManagePermission({ actorUserId, targetUserId });
    return;
  }
  for (const permission of permissions) {
    await assertActorCanManagePermission({
      actorUserId,
      targetUserId,
      permissionKey: permission.permissionKey,
    });
  }
}

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

  const cached = readPermissionCache(userId, row.permission_version);
  if (cached) return cached;

  if (row.is_super_admin === true) {
    return writePermissionCache(userId, row.permission_version, {
      isSuperAdmin: true,
      disabled: false,
      permissionVersion: Number(row.permission_version || 1),
      roleKey: "super_admin",
      permissions: "ALL",
    });
  }

  let roleKey = row.admin_role_key || defaultRoleTemplateForBaseRole(row.role) || null;
  let customRole = null;
  if (roleKey && !ROLE_TEMPLATES[roleKey]) {
    customRole = await repo.getAdminRole(roleKey);
    if (!customRole || customRole.is_archived === true) {
      roleKey = null;
    }
  }

  const permissions = new Map();

  const template = roleKey ? ROLE_TEMPLATES[roleKey] : null;
  if (template) {
    if (template.includes(WILDCARD_PERMISSION)) {
      return writePermissionCache(userId, row.permission_version, {
        isSuperAdmin: false,
        disabled: false,
        permissionVersion: Number(row.permission_version || 1),
        roleKey,
        permissions: "ALL",
      });
    }
    for (const key of template) {
      if (isValidPermissionKey(key)) permissions.set(key, "all");
    }
  } else if (customRole) {
    const rolePermissions = await repo.listAdminRolePermissions(roleKey);
    for (const permission of rolePermissions) {
      const key = String(permission.permission_key || "").trim();
      const scope = String(permission.scope || "all").trim();
      if (isValidPermissionKey(key) && isValidScope(scope)) {
        permissions.set(key, scope);
      }
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

  return writePermissionCache(userId, row.permission_version, {
    isSuperAdmin: false,
    disabled: false,
    permissionVersion: Number(row.permission_version || 1),
    roleKey,
    permissions,
  });
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
  await assertActorCanManagePermission({ actorUserId, targetUserId, permissionKey });
  const out = await repo.upsertUserPermission({
    targetUserId,
    actorUserId,
    permissionKey,
    effect,
    scope,
    expiresAt,
    reason,
  });
  invalidatePermissionCacheForUser(targetUserId);
  return out;
}

export async function clearUserPermission({
  actorUserId,
  targetUserId,
  permissionKey,
  reason = null,
}) {
  assertValidPermissionKey(permissionKey);
  const out = await repo.deleteUserPermission({
    targetUserId,
    actorUserId,
    permissionKey,
    reason,
  });
  invalidatePermissionCacheForUser(targetUserId);
  return out;
}

export async function assignAdminRole({
  actorUserId,
  targetUserId,
  roleKey,
  reason = null,
}) {
  const normalizedRoleKey = roleKey == null ? null : normalizeRoleKey(roleKey);
  let rolePermissions = [];
  if (normalizedRoleKey) {
    const templatePermissions = roleTemplatePermissions(normalizedRoleKey);
    if (templatePermissions) {
      rolePermissions = templatePermissions;
    } else if (!ROLE_TEMPLATE_KEYS.includes(normalizedRoleKey)) {
      const custom = await repo.getAdminRole(normalizedRoleKey);
      if (!custom || custom.is_archived === true) {
        throw new AppError("INVALID_ROLE_TEMPLATE", { status: 400 });
      }
      const customPermissions = await repo.listAdminRolePermissions(normalizedRoleKey);
      rolePermissions = customPermissions.map((permission) => ({
        permissionKey: permission.permission_key,
        scope: permission.scope,
      }));
    }
  }
  await assertActorCanManagePermissionList({
    actorUserId,
    targetUserId,
    permissions: rolePermissions,
  });
  if (normalizedRoleKey != null && !ROLE_TEMPLATE_KEYS.includes(normalizedRoleKey)) {
    const custom = await repo.getAdminRole(normalizedRoleKey);
    if (!custom || custom.is_archived === true) {
      throw new AppError("INVALID_ROLE_TEMPLATE", { status: 400 });
    }
  }
  const out = await repo.setUserAdminRole({
    targetUserId,
    actorUserId,
    roleKey: normalizedRoleKey,
    reason,
  });
  invalidatePermissionCacheForUser(targetUserId);
  return out;
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

export async function listAdminRoles(options) {
  return repo.listAdminRoles(options);
}

export async function createAdminRole({
  actorUserId,
  roleKey,
  displayName,
  description = null,
  category = "custom",
  permissions = [],
  reason = null,
}) {
  const key = assertValidRoleKey(roleKey);
  const normalizedPermissions = normalizePermissionPayloadList(permissions);
  await assertActorCanManagePermissionList({
    actorUserId,
    permissions: normalizedPermissions,
  });
  return repo.createAdminRole({
    actorUserId,
    roleKey: key,
    displayName,
    description,
    category,
    permissions: normalizedPermissions,
    reason,
  });
}

export async function updateAdminRole({
  actorUserId,
  roleKey,
  displayName,
  description = null,
  category = "custom",
  permissions = null,
  reason = null,
}) {
  const key = assertValidRoleKey(roleKey);
  const normalizedPermissions = permissions == null
    ? null
    : normalizePermissionPayloadList(permissions);
  await assertActorCanManagePermissionList({
    actorUserId,
    permissions: normalizedPermissions || [],
  });
  const out = await repo.updateAdminRole({
    actorUserId,
    roleKey: key,
    displayName,
    description,
    category,
    permissions: normalizedPermissions,
    reason,
  });
  for (const userId of out.affectedUsers || []) {
    invalidatePermissionCacheForUser(userId);
  }
  return out;
}

export async function copyAdminRole({
  actorUserId,
  sourceRoleKey,
  roleKey,
  displayName,
  description = null,
  reason = null,
}) {
  const sourceKey = normalizeRoleKey(sourceRoleKey);
  const templatePermissions = roleTemplatePermissions(sourceKey);
  if (templatePermissions) {
    return createAdminRole({
      actorUserId,
      roleKey,
      displayName,
      description,
      category: "custom",
      permissions: templatePermissions,
      reason,
    });
  }
  const source = await repo.getAdminRole(sourceKey);
  if (!source || source.is_archived === true) {
    throw new AppError("ADMIN_ROLE_NOT_FOUND", { status: 404 });
  }
  const sourcePermissions = await repo.listAdminRolePermissions(sourceKey);
  return createAdminRole({
    actorUserId,
    displayName,
    description,
    roleKey,
    category: "custom",
    permissions: sourcePermissions.map((permission) => ({
      permissionKey: permission.permission_key,
      scope: permission.scope,
    })),
    reason,
  });
}

export async function archiveAdminRole({ actorUserId, roleKey, reason = null }) {
  return repo.archiveAdminRole({
    actorUserId,
    roleKey: assertValidRoleKey(roleKey),
    reason,
  });
}

export const __permissionCacheTestApi = Object.freeze({
  clear() {
    permissionCache.clear();
  },
  size() {
    return permissionCache.size;
  },
});
