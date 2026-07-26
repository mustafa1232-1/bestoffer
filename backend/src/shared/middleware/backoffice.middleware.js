import { requireRoles } from './role.middleware.js';
import { getEffectivePermissionsResponse } from '../../modules/security/permissions.service.js';
import { AppError } from '../utils/errors.js';

function isSuperAdminRequest(req) {
  return (
    req?.userIsSuperAdmin === true ||
    req?.authUserIsSuperAdmin === true ||
    req?.user?.is_super_admin === true ||
    req?.user?.isSuperAdmin === true
  );
}

export async function requireBackoffice(req, res, next) {
  if (isSuperAdminRequest(req)) return next();
  const role = String(req.userRole || req.authUserRole || '').trim().toLowerCase();
  const rawBackofficeRole = role === 'admin' || role === 'deputy_admin';
  try {
    const effective = await getEffectivePermissionsResponse(req.userId || req.authUserId);
    const hasPermissions =
      effective.disabled !== true &&
      (effective.wildcard === true ||
        (Array.isArray(effective.permissions) && effective.permissions.length > 0));
    if (hasPermissions && (rawBackofficeRole || effective.roleKey)) {
      req.effectivePermissions = effective;
      return next();
    }
  } catch (error) {
    return next(
      error instanceof AppError
        ? error
        : new AppError('PERMISSION_RESOLUTION_FAILED', { status: 403 }),
    );
  }
  if (rawBackofficeRole) {
    return next(new AppError('FORBIDDEN_BACKOFFICE_PERMISSION_REQUIRED', { status: 403 }));
  }
  return requireRoles(['admin', 'deputy_admin'], 'FORBIDDEN_BACKOFFICE_ONLY')(req, res, next);
}

export const requireAdminOrOwner = requireRoles(
  ['admin', 'owner'],
  'FORBIDDEN_ADMIN_OR_OWNER_ONLY',
);
