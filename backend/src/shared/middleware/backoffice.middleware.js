import { requireRoles } from './role.middleware.js';

function isSuperAdminRequest(req) {
  return (
    req?.userIsSuperAdmin === true ||
    req?.authUserIsSuperAdmin === true ||
    req?.user?.is_super_admin === true ||
    req?.user?.isSuperAdmin === true
  );
}

export function requireBackoffice(req, res, next) {
  if (isSuperAdminRequest(req)) return next();
  return requireRoles(['admin', 'deputy_admin'], 'FORBIDDEN_BACKOFFICE_ONLY')(
    req,
    res,
    next,
  );
}

export const requireAdminOrOwner = requireRoles(
  ['admin', 'owner'],
  'FORBIDDEN_ADMIN_OR_OWNER_ONLY',
);
