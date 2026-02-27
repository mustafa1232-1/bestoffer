import { requireRoles } from './role.middleware.js';

export const requireOwner = requireRoles('owner', 'FORBIDDEN_OWNER_ONLY');

