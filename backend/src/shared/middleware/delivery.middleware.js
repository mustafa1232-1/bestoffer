import { requireRoles } from './role.middleware.js';

export const requireDelivery = requireRoles('delivery', 'FORBIDDEN_DELIVERY_ONLY');

