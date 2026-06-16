import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import * as controller from "./realtime.controller.js";

export const realtimeRouter = Router();

realtimeRouter.use(requireAuth);
realtimeRouter.post("/token", controller.issueRealtimeToken);
