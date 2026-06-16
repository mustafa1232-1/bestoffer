import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireBackoffice } from "../../shared/middleware/backoffice.middleware.js";
import * as c from "./paid-upgrades.controller.js";

export const paidUpgradesRouter = Router();
export const paidUpgradesAdminRouter = Router();

paidUpgradesRouter.use(requireAuth);
paidUpgradesRouter.get("/plans", c.listPlans);
paidUpgradesRouter.get("/me", c.me);
paidUpgradesRouter.get("/requests", c.listMyRequests);
paidUpgradesRouter.post("/requests", c.createRequests);
paidUpgradesRouter.post("/requests/:requestId/cancel", c.cancelRequest);

paidUpgradesAdminRouter.use(requireAuth, requireBackoffice);
paidUpgradesAdminRouter.get("/requests", c.listPendingRequests);
paidUpgradesAdminRouter.patch("/requests/:requestId/approve", c.approveRequest);
paidUpgradesAdminRouter.patch("/requests/:requestId/reject", c.rejectRequest);
paidUpgradesAdminRouter.patch("/requests/:requestId/activate", c.activateRequest);

