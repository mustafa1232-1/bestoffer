import { Router } from "express";

import * as c from "./settings.controller.js";

// Router عام (بلا مصادقة) — يخدم إعدادات الدعم لكل التطبيقات بما فيها الضيوف.
export const settingsPublicRouter = Router();

settingsPublicRouter.get("/public", c.publicSettings);
