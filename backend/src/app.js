import cors from "cors";
import express from "express";
import fs from "fs";

import { q } from "./config/db.js";
import { env } from "./config/env.js";
import { adminRouter } from "./modules/admin/admin.routes.js";
import { assistantRouter } from "./modules/assistant/assistant.routes.js";
import { authRouter } from "./modules/auth/auth.routes.js";
import { behaviorRouter } from "./modules/behavior/behavior.routes.js";
import { getUserPublicById } from "./modules/auth/auth.repo.js";
import { carsRouter } from "./modules/cars/cars.routes.js";
import { deliveryRouter } from "./modules/delivery/delivery.routes.js";
import { merchantsRouter } from "./modules/merchants/merchants.routes.js";
import { notificationsRouter } from "./modules/notifications/notifications.routes.js";
import { ordersRouter } from "./modules/orders/orders.routes.js";
import { ownerRouter } from "./modules/owner/owner.routes.js";
import { taxiRouter } from "./modules/taxi/taxi.routes.js";
import { requireAuth } from "./shared/middleware/auth.middleware.js";
import {
  errorHandler,
  jsonSyntaxErrorHandler,
  notFoundHandler,
} from "./shared/middleware/error.middleware.js";
import { createRateLimiter } from "./shared/middleware/rate-limit.middleware.js";
import {
  requestLogger,
  withRequestContext,
} from "./shared/middleware/request-context.middleware.js";
import { attachOptionalAuth } from "./shared/middleware/optional-auth.middleware.js";
import { securityHeaders } from "./shared/middleware/security.middleware.js";
import { activityAuditMiddleware } from "./shared/middleware/activity-audit.middleware.js";
import {
  missingImagePng,
  resolveUploadFilePath,
  uploadsDir,
} from "./shared/utils/uploads.js";

export const app = express();

app.set("trust proxy", true);

const corsOrigins = env.corsOrigins;
const allowAllOrigins = corsOrigins.length === 0 || corsOrigins.includes("*");

app.use(withRequestContext);
app.use(requestLogger({ enabled: env.logHttpRequests }));
app.use(securityHeaders);
app.use(attachOptionalAuth);
app.use(
  cors({
    origin(origin, callback) {
      if (!origin || allowAllOrigins || corsOrigins.includes(origin)) {
        callback(null, true);
        return;
      }

      const error = new Error("CORS_NOT_ALLOWED");
      error.status = 403;
      callback(error);
    },
    credentials: true,
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization", "X-Request-Id"],
  })
);
app.use(
  createRateLimiter({
    windowMs: env.rateLimitWindowMs,
    maxRequests: env.rateLimitMaxRequests,
    keyPrefix: "api",
  })
);
app.use(
  "/api/auth",
  createRateLimiter({
    windowMs: env.rateLimitWindowMs,
    maxRequests: env.rateLimitAuthMaxRequests,
    keyPrefix: "auth",
  })
);
app.use(activityAuditMiddleware());
app.use(express.json({ limit: env.jsonBodyLimit }));
app.use(express.urlencoded({ extended: true, limit: env.jsonBodyLimit }));
app.use(jsonSyntaxErrorHandler);
app.use((req, res, next) => {
  if (req.path.startsWith("/api/")) {
    res.setHeader("Content-Type", "application/json; charset=utf-8");
  }
  next();
});
app.use(
  "/uploads",
  express.static(uploadsDir, {
    fallthrough: true,
    maxAge: "7d",
  })
);
app.get("/uploads/:fileName", (req, res) => {
  const filePath = resolveUploadFilePath(req.params.fileName);
  if (fs.existsSync(filePath)) {
    res.sendFile(filePath);
    return;
  }

  // Avoid broken image responses when historical files are missing on disk.
  res
    .status(200)
    .set("Content-Type", "image/png")
    .set("Cache-Control", "public, max-age=300")
    .send(missingImagePng);
});

app.get("/health", async (req, res, next) => {
  try {
    const startedAt = Date.now();
    await q("SELECT 1");
    res.json({
      status: "ok",
      service: "bestoffer-api",
      uptimeSec: Math.round(process.uptime()),
      db: "ok",
      responseMs: Date.now() - startedAt,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    next(error);
  }
});

app.get("/ready", (req, res) => {
  res.json({
    status: "ready",
    timestamp: new Date().toISOString(),
  });
});

app.use("/api/auth", authRouter);
app.use("/api/merchants", merchantsRouter);
app.use("/api/admin", adminRouter);
app.use("/api/owner", ownerRouter);
app.use("/api/orders", ordersRouter);
app.use("/api/delivery", deliveryRouter);
app.use("/api/notifications", notificationsRouter);
app.use("/api/assistant", assistantRouter);
app.use("/api/cars", carsRouter);
app.use("/api/behavior", behaviorRouter);
app.use("/api/taxi", taxiRouter);

app.get("/api/me", requireAuth, async (req, res, next) => {
  try {
    const user = await getUserPublicById(req.userId);
    res.json({ user });
  } catch (e) {
    next(e);
  }
});

app.use(notFoundHandler);
app.use(errorHandler);
