import { requireRoles } from './role.middleware.js';

export const requireServiceProvider = requireRoles(
  'service_provider',
  'FORBIDDEN_SERVICE_PROVIDER_ONLY'
);
