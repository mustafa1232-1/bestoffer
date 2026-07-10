import compression from "compression";
import cors from "cors";
import express from "express";
import fs from "fs";

import { getDbFailoverState, q } from "./config/db.js";
import { env } from "./config/env.js";
import { redisHealthSnapshot } from "./config/redis.js";
import { getSupabaseRealtimeReadiness } from "./config/supabase.js";
import { adminRouter } from "./modules/admin/admin.routes.js";
import { assistantRouter } from "./modules/assistant/assistant.routes.js";
import { authRouter } from "./modules/auth/auth.routes.js";
import { behaviorRouter } from "./modules/behavior/behavior.routes.js";
import { getUserPublicById } from "./modules/auth/auth.repo.js";
import { carsRouter } from "./modules/cars/cars.routes.js";
import { commerceRouter } from "./modules/commerce/commerce.routes.js";
import { companyRouter } from "./modules/company/company.routes.js";
import { couponsRouter } from "./modules/coupons/coupons.routes.js";
import { deliveryRouter } from "./modules/delivery/delivery.routes.js";
import { accountantRouter } from "./modules/accountant/accountant.routes.js";
import { feedRouter } from "./modules/feed/feed.routes.js";
import { hrRouter } from "./modules/hr/hr.routes.js";
import { jobsRouter } from "./modules/jobs/jobs.routes.js";
import {
  merchantsRouter,
} from "./modules/merchants/merchants.routes.js";
import * as merchantsController from "./modules/merchants/merchants.controller.js";
import { notificationsRouter } from "./modules/notifications/notifications.routes.js";
import { ordersRouter } from "./modules/orders/orders.routes.js";
import { ownerRouter } from "./modules/owner/owner.routes.js";
import * as adminOpsController from "./modules/admin/admin.ops.controller.js";
import {
  paidUpgradesAdminRouter,
  paidUpgradesRouter,
} from "./modules/paid-upgrades/paid-upgrades.routes.js";
import { pharmacyRouter } from "./modules/pharmacy/pharmacy.routes.js";
import { subscriptionsAdminRouter } from "./modules/subscriptions/subscriptions.routes.js";
import { productsRouter } from "./modules/products/products.routes.js";
import { realtimeRouter } from "./modules/realtime/realtime.routes.js";
import { securityRouter } from "./modules/security/security.routes.js";
import {
  realEstateAdminRouter,
  realEstateRouter,
} from "./modules/real-estate/real-estate.routes.js";
import {
  servicesAdminRouter,
  servicesProviderRouter,
  servicesPublicRouter,
  servicesRequestsRouter,
  servicesReviewsRouter,
} from "./modules/services/services.routes.js";
import {
  sectionAvailabilityAdminRouter,
  sectionAvailabilityPublicRouter,
} from "./modules/sections/sections.routes.js";
import { taxiRouter } from "./modules/taxi/taxi.routes.js";
import { usersRouter } from "./modules/users/users.routes.js";
import { requireAuth } from "./shared/middleware/auth.middleware.js";
import { createOpsRouter } from "./ops/routes/ops.routes.js";
import { createOpsWebhooksRouter } from "./ops/routes/opsWebhooks.routes.js";
import { attachDatadogRequestMetrics } from "./ops/tools/datadogTool.js";
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
import { sanitizeInputMiddleware } from "./shared/middleware/input-sanitize.middleware.js";
import { attachOptionalAuth } from "./shared/middleware/optional-auth.middleware.js";
import { firewallGuard } from "./shared/middleware/firewall.middleware.js";
import { securityHeaders } from "./shared/middleware/security.middleware.js";
import { activityAuditMiddleware } from "./shared/middleware/activity-audit.middleware.js";
import { getRequestSigningRuntimeStatus } from "./modules/security/security.service.js";
import { getUploadRuntimeStatus } from "./shared/utils/upload.js";
import {
  missingImagePng,
  resolveUploadFilePath,
  uploadsDir,
} from "./shared/utils/uploads.js";

export const app = express();

function normalizeRateLimitPath(req) {
  const raw = String(req.originalUrl || req.url || req.path || "").trim();
  const withoutQuery = raw.split("?")[0] || "";
  if (withoutQuery.startsWith("/api/v1/")) {
    return withoutQuery.replace(/^\/api\/v1\//, "/api/");
  }
  if (withoutQuery === "/api/v1") return "/api";
  if (withoutQuery.startsWith("/api/")) return withoutQuery;
  if (withoutQuery.startsWith("/")) return `/api${withoutQuery}`;
  return `/api/${withoutQuery}`;
}

function isPublicCatalogPath(path) {
  if (path === "/api/merchants") return true;
  if (path === "/api/merchants/activities") return true;
  if (path === "/api/merchants/discovery/options") return true;
  return /^\/api\/merchants\/\d+(?:\/(?:products|categories))?$/.test(path);
}

function shouldSkipGlobalRateLimit(req) {
  if (req.method !== "GET") return false;
  if (Number(req.userId) > 0 || Number(req.authUserId) > 0) return false;
  return isPublicCatalogPath(normalizeRateLimitPath(req));
}

function shouldCompress(req, res) {
  const contentType = String(res.getHeader("Content-Type") || "");
  if (contentType.includes("text/event-stream")) return false;
  if (req.path.includes("/stream")) return false;
  return compression.filter(req, res);
}

function setUploadResponseHeaders(res, filePath) {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");
  const safeInlineExtRe =
    /\.(?:png|jpe?g|webp|gif|mp4|mov|webm|mkv|3gp|m4a|aac|mp3|wav|ogg|opus|pdf)$/i;
  if (!safeInlineExtRe.test(String(filePath || ""))) {
    res.setHeader("Content-Disposition", "attachment");
  }
}

function setNoStoreHeaders(res) {
  res.setHeader("Cache-Control", "no-store, private");
  res.setHeader("Pragma", "no-cache");
}

function registerPublicCatalogRoutes(prefix = "/api") {
  app.get(`${prefix}/merchants`, merchantsController.list);
  app.get(`${prefix}/merchants/activities`, merchantsController.listActivities);
  app.get(
    `${prefix}/merchants/discovery/options`,
    merchantsController.listActivityDiscoveryOptions
  );
  app.get(`${prefix}/merchants/:merchantId(\\d+)`, merchantsController.getById);
  app.get(
    `${prefix}/merchants/:merchantId(\\d+)/products`,
    merchantsController.listProducts
  );
  app.get(
    `${prefix}/merchants/:merchantId(\\d+)/categories`,
    merchantsController.listCategories
  );
}

function mountApiSurface(prefix = "/api") {
  app.use(`${prefix}/auth`, authRouter);
  app.use(`${prefix}/users`, usersRouter);
  app.use(`${prefix}/admin`, adminRouter);
  app.use(`${prefix}/merchants`, merchantsRouter);
  app.use(`${prefix}/owner`, ownerRouter);
  app.use(`${prefix}/orders`, ordersRouter);
  app.use(`${prefix}/delivery`, deliveryRouter);
  app.use(`${prefix}/notifications`, notificationsRouter);
  app.use(`${prefix}/paid-upgrades`, paidUpgradesRouter);
  app.use(`${prefix}/coupons`, couponsRouter);
  app.use(`${prefix}/assistant`, assistantRouter);
  app.use(`${prefix}/cars`, carsRouter);
  app.use(`${prefix}/behavior`, behaviorRouter);
  app.use(`${prefix}/taxi`, taxiRouter);
  app.use(`${prefix}/real-estate`, realEstateRouter);
  app.use(`${prefix}/sections`, sectionAvailabilityPublicRouter);
  app.use(`${prefix}/services/public`, servicesPublicRouter);
  app.use(`${prefix}/services/provider`, servicesProviderRouter);
  app.use(`${prefix}/services/requests`, servicesRequestsRouter);
  app.use(`${prefix}/services/reviews`, servicesReviewsRouter);
  app.use(`${prefix}/pharmacy`, pharmacyRouter);
  app.use(`${prefix}/products`, productsRouter);
  app.use(`${prefix}/realtime`, realtimeRouter);
  app.use(`${prefix}/security`, securityRouter);
  app.use(`${prefix}/feed`, feedRouter);
  app.use(`${prefix}/jobs`, jobsRouter);
  app.use(`${prefix}/company`, companyRouter);
  app.use(`${prefix}/hr`, hrRouter);
  app.use(`${prefix}/accountant`, accountantRouter);
  app.post(`${prefix}/system/crash-events`, adminOpsController.reportCrashEvent);
  app.use(prefix, commerceRouter);
  app.use(`${prefix}/admin/paid-upgrades`, paidUpgradesAdminRouter);
  app.use(`${prefix}/admin/merchant-subscriptions`, subscriptionsAdminRouter);
  app.use(`${prefix}/admin/real-estate`, realEstateAdminRouter);
  app.use(`${prefix}/admin/services`, servicesAdminRouter);
  app.use(`${prefix}/admin/sections`, sectionAvailabilityAdminRouter);
  app.get(`${prefix}/me`, requireAuth, async (req, res, next) => {
    try {
      const user = await getUserPublicById(req.userId);
      res.json({ user });
    } catch (e) {
      next(e);
    }
  });
  app.get(`${prefix}/users/me`, requireAuth, async (req, res, next) => {
    try {
      const user = await getUserPublicById(req.userId);
      res.json({ user });
    } catch (e) {
      next(e);
    }
  });
}

app.set("trust proxy", true);

const corsOrigins = env.corsOrigins;
const allowAllOrigins =
  !env.isProduction &&
  (corsOrigins.length === 0 || corsOrigins.includes("*"));

app.use(withRequestContext);
app.use(requestLogger({ enabled: env.logHttpRequests }));
app.use(attachDatadogRequestMetrics());
app.use(securityHeaders);
app.use(firewallGuard({ stage: "pre" }));
app.use(
  compression({
    filter: shouldCompress,
    threshold: 1024,
    level: 6,
  })
);
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
    allowedHeaders: [
      "Content-Type",
      "Authorization",
      "X-Request-Id",
      "X-Device-Id",
      "X-Installation-Id",
      "X-Client-Platform",
      "X-App-Flavor",
      "X-App-Version",
      "X-Device-Model",
      "X-Request-Timestamp",
      "X-Request-Nonce",
      "X-Request-Signature",
      "X-Request-Key-Id",
    ],
  })
);
registerPublicCatalogRoutes("/api");
registerPublicCatalogRoutes("/api/v1");
app.use(
  createRateLimiter({
    windowMs: env.rateLimitWindowMs,
    maxRequests: Math.max(env.rateLimitMaxRequests, env.globalRateLimitFloor),
    keyPrefix: "api",
    skip: shouldSkipGlobalRateLimit,
  })
);
app.use(activityAuditMiddleware());
app.use(express.json({ limit: env.jsonBodyLimit }));
app.use(express.urlencoded({ extended: true, limit: env.jsonBodyLimit }));
app.use(jsonSyntaxErrorHandler);
app.use(
  "/api/auth",
  (req, res, next) => {
    setNoStoreHeaders(res);
    next();
  },
  createRateLimiter({
    windowMs: env.rateLimitWindowMs,
    maxRequests: env.rateLimitAuthMaxRequests,
    keyPrefix: "auth",
  })
);
app.use(sanitizeInputMiddleware);
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
    maxAge: "30d",
    immutable: true,
    dotfiles: "ignore",
    setHeaders: setUploadResponseHeaders,
  })
);
app.get("/uploads/:fileName", (req, res) => {
  const filePath = resolveUploadFilePath(req.params.fileName);
  if (fs.existsSync(filePath)) {
    setUploadResponseHeaders(res, filePath);
    res.sendFile(filePath);
    return;
  }

  // Avoid broken image responses when historical files are missing on disk.
  res
    .status(200)
    .set("Content-Type", "image/png")
    .set("Cache-Control", "public, max-age=300")
    .set("X-Content-Type-Options", "nosniff")
    .set("Cross-Origin-Resource-Policy", "cross-origin")
    .send(missingImagePng);
});

app.get("/health", async (req, res, next) => {
  try {
    const startedAt = Date.now();
    await q("SELECT 1");
    const [redis, realtime, requestSigning] = await Promise.all([
      redisHealthSnapshot(),
      getSupabaseRealtimeReadiness(),
      getRequestSigningRuntimeStatus(),
    ]);
    res.json({
      status: "ok",
      service: "maslaki-api",
      uptimeSec: Math.round(process.uptime()),
      db: {
        ok: true,
        topology: getDbFailoverState(),
      },
      redis,
      security: {
        requestSigning,
      },
      realtime,
      uploads: getUploadRuntimeStatus(),
      responseMs: Date.now() - startedAt,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    next(error);
  }
});

app.get("/ready", async (req, res, next) => {
  try {
    const startedAt = Date.now();
    await q("SELECT 1");
    const [redis, realtime, requestSigning] = await Promise.all([
      redisHealthSnapshot(),
      getSupabaseRealtimeReadiness(),
      getRequestSigningRuntimeStatus(),
    ]);
    const reasons = [];
    if (realtime.releaseBlocking) {
      reasons.push(realtime.reason || "realtime_blocked");
    }
    if (env.securityRequestSigningEnabled === true && requestSigning.ok !== true) {
      reasons.push(requestSigning.reason || "request_signing_unavailable");
    }
    if (env.securityRequestSigningEnabled === true && redis.ok !== true) {
      reasons.push(redis.error || "redis_unavailable");
    }

    if (reasons.length > 0) {
      return res.status(503).json({
        status: "not_ready",
        reason: reasons[0],
        reasons,
        db: {
          ok: true,
          topology: getDbFailoverState(),
        },
        redis,
        security: {
          requestSigning,
        },
        realtime,
        uploads: getUploadRuntimeStatus(),
        responseMs: Date.now() - startedAt,
        timestamp: new Date().toISOString(),
      });
    }
    return res.json({
      status: "ready",
      db: {
        ok: true,
        topology: getDbFailoverState(),
      },
      redis,
      security: {
        requestSigning,
      },
      realtime,
      uploads: getUploadRuntimeStatus(),
      responseMs: Date.now() - startedAt,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    return next(error);
  }
});

app.get("/version", (req, res) => {
  res.json({
    appVersion: env.appVersion || "unknown",
    appEnv: env.appEnv || env.nodeEnv || "development",
    gitCommitSha: env.gitCommitSha || "unknown",
    timestamp: new Date().toISOString(),
  });
});

mountApiSurface("/api/v1");
mountApiSurface("/api");
app.use("/ops", createOpsRouter());
app.use("/ops/webhooks", createOpsWebhooksRouter());
app.use("/api/admin/ops", createOpsRouter());
app.use("/api/admin/ops/webhooks", createOpsWebhooksRouter());
app.use("/api/v1/admin/ops", createOpsRouter());
app.use("/api/v1/admin/ops/webhooks", createOpsWebhooksRouter());

app.use(notFoundHandler);
app.use(errorHandler);
