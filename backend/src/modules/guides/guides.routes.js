import { Router } from "express";

import { optionalAuth } from "../../shared/middleware/auth.middleware.js";
import * as c from "./guides.controller.js";

// دليل عام: optionalAuth حتى يمكن تصفية أقسام الإدارة حسب صلاحيات الموظف.
export const guidesRouter = Router();

guidesRouter.get("/", optionalAuth, c.getGuide);
