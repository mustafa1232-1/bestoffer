/**
 * Purpose:
 * controllers إدارة الصلاحيات الدقيقة (المرحلة 2). كلها خلف requireBackoffice
 * + requirePermission('employees.permissions.manage') عدا /me/permissions.
 */

import * as service from "./permissions.service.js";
import { recordAudit, auditContextFromReq } from "./audit.service.js";
import {
  PERMISSION_KEYS,
  PERMISSION_SCOPES,
  ROLE_TEMPLATE_KEYS,
  ROLE_TEMPLATES,
} from "./permissions.catalog.js";

function badRequest(res, fields) {
  return res.status(400).json({ message: "VALIDATION_ERROR", fields });
}

function parseUserId(req, res) {
  const id = Number(req.params?.userId);
  if (!Number.isInteger(id) || id <= 0) {
    badRequest(res, ["userId"]);
    return null;
  }
  return id;
}

export async function getMyPermissions(req, res, next) {
  try {
    const out = await service.getEffectivePermissionsResponse(req.userId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getCatalog(req, res, next) {
  try {
    return res.json({
      permissions: PERMISSION_KEYS,
      scopes: PERMISSION_SCOPES,
      roleTemplates: ROLE_TEMPLATE_KEYS.map((key) => ({
        key,
        permissions: ROLE_TEMPLATES[key],
      })),
    });
  } catch (error) {
    return next(error);
  }
}

export async function getUserPermissions(req, res, next) {
  try {
    const userId = parseUserId(req, res);
    if (!userId) return;
    const out = await service.listUserPermissions(userId);
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "employees.permissions.read",
      summary: `عرض صلاحيات الموظف #${userId}`,
      targetType: "app_user",
      targetId: userId,
      permissionKey: "employees.permissions.manage",
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function upsertUserPermission(req, res, next) {
  try {
    const userId = parseUserId(req, res);
    if (!userId) return;
    const permissionKey = String(req.body?.permissionKey || "").trim();
    const effect = String(req.body?.effect || "grant").trim();
    const scope = String(req.body?.scope || "all").trim();
    const reason =
      typeof req.body?.reason === "string" ? req.body.reason.trim() || null : null;
    let expiresAt = null;
    if (req.body?.expiresAt) {
      const d = new Date(req.body.expiresAt);
      if (Number.isNaN(d.getTime())) return badRequest(res, ["expiresAt"]);
      expiresAt = d.toISOString();
    }
    if (!permissionKey) return badRequest(res, ["permissionKey"]);

    const out = await service.grantUserPermission({
      actorUserId: req.userId,
      targetUserId: userId,
      permissionKey,
      effect,
      scope,
      expiresAt,
      reason,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function clearUserPermission(req, res, next) {
  try {
    const userId = parseUserId(req, res);
    if (!userId) return;
    const permissionKey = String(req.params?.permissionKey || "").trim();
    if (!permissionKey) return badRequest(res, ["permissionKey"]);
    const out = await service.clearUserPermission({
      actorUserId: req.userId,
      targetUserId: userId,
      permissionKey,
      reason:
        typeof req.body?.reason === "string" ? req.body.reason.trim() || null : null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function assignAdminRole(req, res, next) {
  try {
    const userId = parseUserId(req, res);
    if (!userId) return;
    const roleKey =
      req.body?.roleKey === null || req.body?.roleKey === ""
        ? null
        : String(req.body?.roleKey || "").trim() || null;
    const out = await service.assignAdminRole({
      actorUserId: req.userId,
      targetUserId: userId,
      roleKey,
      reason:
        typeof req.body?.reason === "string" ? req.body.reason.trim() || null : null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getChangeLog(req, res, next) {
  try {
    const targetUserId = req.query?.userId ? Number(req.query.userId) : null;
    const items = await service.listPermissionChangeLog({
      targetUserId: targetUserId && targetUserId > 0 ? targetUserId : null,
      limit: req.query?.limit ? Number(req.query.limit) : 100,
    });
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}
