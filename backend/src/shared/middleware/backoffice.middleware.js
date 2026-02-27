import { requireRoles } from './role.middleware.js';

export const requireBackoffice = requireRoles(['admin','deputy_admin'], 'FORBIDDEN_BACKOFFICE_ONLY');
export const requireAdminOrOwner = requireRoles(['admin','owner'], 'FORBIDDEN_ADMIN_OR_OWNER_ONLY');

