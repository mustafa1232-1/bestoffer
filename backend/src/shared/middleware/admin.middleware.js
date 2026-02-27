import { requireRoles } from './role.middleware.js';

export const requireAdmin = requireRoles('admin', 'FORBIDDEN_ADMIN_ONLY');

