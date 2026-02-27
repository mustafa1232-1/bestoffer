import { AppError } from "../utils/errors.js";

export function requireRoles(allowedRoles, forbiddenCode = "FORBIDDEN") {
  const allowed = Array.isArray(allowedRoles)
    ? new Set(allowedRoles)
    : new Set([allowedRoles]);

  return function roleGuard(req, res, next) {
    const role = req.userRole;
    if (!role || !allowed.has(role)) {
      return next(new AppError(forbiddenCode, { status: 403 }));
    }
    return next();
  };
}
