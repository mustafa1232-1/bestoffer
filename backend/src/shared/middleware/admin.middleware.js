import { requireRoles } from './role.middleware.js';

export function requireAdmin(req, res, next) {
  if (req.userIsSuperAdmin === true || req.authUserIsSuperAdmin === true) {
    return next();
  }
  return requireRoles('admin', 'FORBIDDEN_ADMIN_ONLY')(req, res, next);
}

