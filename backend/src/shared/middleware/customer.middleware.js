import { requireRoles } from './role.middleware.js';

export const requireCustomer = requireRoles('user', 'FORBIDDEN_CUSTOMER_ONLY');

