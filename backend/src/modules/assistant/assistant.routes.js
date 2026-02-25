import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import * as c from "./assistant.controller.js";

export const assistantRouter = Router();

assistantRouter.use(requireAuth, requireCustomer);

assistantRouter.get("/session", c.getCurrentSession);
assistantRouter.post("/session/new", c.startNewSession);
assistantRouter.post("/chat", c.chat);
assistantRouter.post("/draft/:token/confirm", c.confirmDraft);
