import { Router } from "express";

import { requireAdmin } from "../../shared/middleware/admin.middleware.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import { requirePermission } from "../../shared/middleware/permission.middleware.js";
import { createRateLimiter } from "../../shared/middleware/rate-limit.middleware.js";
import * as c from "./mimo.controller.js";

export const mimoRouter = Router();

const perMinute = createRateLimiter({
  windowMs: 60 * 1000,
  maxRequests: Number(process.env.MIMO_PER_MINUTE_LIMIT) || 12,
  keyPrefix: "mimo-minute",
});
const perDay = createRateLimiter({
  windowMs: 24 * 60 * 60 * 1000,
  maxRequests: Number(process.env.MIMO_DAILY_LIMIT) || 120,
  keyPrefix: "mimo-day",
});

mimoRouter.post("/chat", requireAuth, requireCustomer, perMinute, perDay, c.chat);
const signals = createRateLimiter({
  windowMs: 60 * 1000,
  maxRequests: 30,
  keyPrefix: "mimo-signal",
});

mimoRouter.post("/feedback", requireAuth, requireCustomer, signals, c.feedback);
mimoRouter.post("/cart-added", requireAuth, requireCustomer, signals, c.cartAdded);
mimoRouter.get("/admin/insights", requireAuth, requireAdmin, c.insights);
mimoRouter.post(
  "/admin/tickets/:ticketId/teach",
  requireAuth,
  requirePermission("support.tickets.reply"),
  c.adminTeach
);
mimoRouter.get("/admin/dashboard", requireAuth, requireAdmin, c.adminDashboard);
mimoRouter.get("/admin/knowledge", requireAuth, requireAdmin, c.adminKnowledge);
mimoRouter.patch("/admin/knowledge/:id", requireAuth, requireAdmin, c.adminUpdateKnowledge);
mimoRouter.delete("/admin/knowledge/:id", requireAuth, requireAdmin, c.adminDeleteKnowledge);
mimoRouter.get("/directory", requireAuth, signals, c.directory);
mimoRouter.get("/nudge", requireAuth, requireCustomer, signals, c.nudge);
mimoRouter.post("/proactive", requireAuth, requireCustomer, signals, c.proactiveEvent);
