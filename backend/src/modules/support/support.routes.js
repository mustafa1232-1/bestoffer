import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import * as c from "./support.controller.js";

// مسارات المستخدم لتذاكر الدعم (مصادقة عادية). الإدارة في admin.routes.js.
export const supportRouter = Router();

supportRouter.use(requireAuth);

supportRouter.post("/tickets", c.createTicket);
supportRouter.get("/tickets/mine", c.listMyTickets);
supportRouter.get("/tickets/:ticketId", c.getMyTicket);
supportRouter.post("/tickets/:ticketId/messages", c.postMyMessage);
supportRouter.post("/tickets/:ticketId/reopen", c.reopenMyTicket);
supportRouter.post("/tickets/:ticketId/rate", c.rateMyTicket);
