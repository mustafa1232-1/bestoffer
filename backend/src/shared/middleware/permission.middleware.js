/**
 * Purpose:
 * middleware فرض الصلاحيات الدقيقة (المرحلة 2 - RBAC).
 * المنع افتراضياً. يقرأ الصلاحيات الفعّالة حيّاً من قاعدة البيانات لكل طلب،
 * فلا تبقى صلاحيات قديمة سارية داخل التوكن. Super Admin يتجاوز.
 *
 * يُركّب بعد requireAuth (يحتاج req.userId / req.userIsSuperAdmin).
 */

import { AppError } from "../utils/errors.js";
import { checkPermission } from "../../modules/security/permissions.service.js";

/**
 * @param {string} permissionKey مفتاح الصلاحية المطلوب.
 * @param {{ scope?: 'own'|'assigned'|'department'|'all' }} options
 *   scope: النطاق الأدنى المطلوب (افتراضياً "own" = يملك المفتاح بأي نطاق).
 */
export function requirePermission(permissionKey, { scope = "own" } = {}) {
  return async function permissionGuard(req, res, next) {
    try {
      const userId = Number(req.userId);
      if (!Number.isInteger(userId) || userId <= 0) {
        return next(new AppError("NO_TOKEN", { status: 401 }));
      }

      // مسار سريع: Super Admin يتجاوز الفحص التفصيلي.
      if (req.userIsSuperAdmin === true || req.authUserIsSuperAdmin === true) {
        req.permissionScope = "all";
        return next();
      }

      const result = await checkPermission(userId, permissionKey, scope);
      if (!result.allowed) {
        return next(
          new AppError("FORBIDDEN_PERMISSION", {
            status: 403,
            details: { permission: permissionKey, requiredScope: scope },
          })
        );
      }

      // يتاح للـhandler لتصفية البيانات حسب النطاق (own/assigned/department/all).
      req.permissionScope = result.scope || "all";
      req.effectivePermissions = result.effective || null;
      return next();
    } catch (error) {
      if (error instanceof AppError) return next(error);
      return next(new AppError("FORBIDDEN_PERMISSION", { status: 403 }));
    }
  };
}

/**
 * يسمح بالمرور إذا توفّر أي مفتاح من القائمة (OR).
 */
export function requireAnyPermission(permissionKeys = [], { scope = "own" } = {}) {
  const keys = Array.isArray(permissionKeys) ? permissionKeys : [permissionKeys];
  return async function anyPermissionGuard(req, res, next) {
    try {
      const userId = Number(req.userId);
      if (!Number.isInteger(userId) || userId <= 0) {
        return next(new AppError("NO_TOKEN", { status: 401 }));
      }
      if (req.userIsSuperAdmin === true || req.authUserIsSuperAdmin === true) {
        req.permissionScope = "all";
        return next();
      }
      for (const key of keys) {
        const result = await checkPermission(userId, key, scope);
        if (result.allowed) {
          req.permissionScope = result.scope || "all";
          req.effectivePermissions = result.effective || null;
          return next();
        }
      }
      return next(
        new AppError("FORBIDDEN_PERMISSION", {
          status: 403,
          details: { permission: keys, requiredScope: scope },
        })
      );
    } catch (error) {
      if (error instanceof AppError) return next(error);
      return next(new AppError("FORBIDDEN_PERMISSION", { status: 403 }));
    }
  };
}
