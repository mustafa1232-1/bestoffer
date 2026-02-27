import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import * as c from "./behavior.controller.js";

export const behaviorRouter = Router();

behaviorRouter.use(requireAuth);

behaviorRouter.post("/events", c.track);
behaviorRouter.get("/events/me", c.myEvents);
