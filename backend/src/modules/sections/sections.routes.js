import { Router } from 'express';

import { requireAuth } from '../../shared/middleware/auth.middleware.js';
import { requireBackoffice } from '../../shared/middleware/backoffice.middleware.js';
import { requireSuperAdmin } from '../../shared/middleware/super-admin.middleware.js';
import * as c from './sections.controller.js';

export const sectionAvailabilityPublicRouter = Router();
export const sectionAvailabilityAdminRouter = Router();

sectionAvailabilityPublicRouter.get('/availability', c.listPublicAvailability);

sectionAvailabilityAdminRouter.use(
  requireAuth,
  requireBackoffice,
  requireSuperAdmin
);
sectionAvailabilityAdminRouter.get('/availability', c.listAdminAvailability);
sectionAvailabilityAdminRouter.get(
  '/availability/audit',
  c.listAvailabilityAudit
);
sectionAvailabilityAdminRouter.patch(
  '/availability/:sectionKey',
  c.updateAvailability
);
