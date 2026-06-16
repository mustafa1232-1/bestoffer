import { env } from "../../config/env.js";
import { q } from "../../config/db.js";
import { AppError } from "../utils/errors.js";

function toSafeInt(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.trunc(parsed);
}

function isAdminLikeRole(role) {
  const normalized = String(role || "").trim().toLowerCase();
  return normalized === "admin" || normalized === "super_admin";
}

function normalizeDigits(value) {
  return String(value || "")
    .replace(/[\u0660-\u0669]/g, (digit) =>
      String(digit.charCodeAt(0) - 0x0660)
    )
    .replace(/[\u06F0-\u06F9]/g, (digit) =>
      String(digit.charCodeAt(0) - 0x06f0)
    );
}

function normalizePhone(value) {
  return normalizeDigits(value).replace(/[^\d]/g, "");
}

export async function requireSuperAdmin(req, res, next) {
  if (req.userIsSuperAdmin === true) {
    if (!isAdminLikeRole(req.userRole)) {
      return next(new AppError("FORBIDDEN_ADMIN_ONLY", { status: 403 }));
    }
    return next();
  }

  const currentUserId = toSafeInt(req.userId);
  const currentRole = String(req.userRole || "").trim().toLowerCase();

  if (currentUserId > 0 && isAdminLikeRole(currentRole)) {
    try {
      const r = await q(
        `SELECT is_super_admin, phone
         FROM app_user
         WHERE id = $1
         LIMIT 1`,
        [currentUserId]
      );
      const row = r.rows[0];
      const phoneMatches =
        normalizePhone(row?.phone) !== "" &&
        normalizePhone(row?.phone) === normalizePhone(env.superAdminPhone);
      if (row?.is_super_admin === true || phoneMatches) {
        req.userIsSuperAdmin = true;
        return next();
      }
    } catch (_) {
      return next(new AppError("FORBIDDEN_SUPER_ADMIN_ONLY", { status: 403 }));
    }
  }

  const configuredSuperAdminId = toSafeInt(env.superAdminUserId);

  if (!configuredSuperAdminId || currentUserId !== configuredSuperAdminId) {
    return next(new AppError("FORBIDDEN_SUPER_ADMIN_ONLY", { status: 403 }));
  }

  if (!isAdminLikeRole(currentRole)) {
    return next(new AppError("FORBIDDEN_ADMIN_ONLY", { status: 403 }));
  }

  return next();
}
