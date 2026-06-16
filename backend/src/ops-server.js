import "dotenv/config";

import cors from "cors";
import express from "express";

import { ensureSchema, pool } from "./config/db.js";
import { env, validateRuntimeEnv } from "./config/env.js";
import { closeRedisClient } from "./config/redis.js";
import { runSqlMigrations } from "./config/sqlMigrations.js";
import { errorHandler, jsonSyntaxErrorHandler, notFoundHandler } from "./shared/middleware/error.middleware.js";
import { requestLogger, withRequestContext } from "./shared/middleware/request-context.middleware.js";
import { createOpsRouter } from "./ops/routes/ops.routes.js";
import { createOpsWebhooksRouter } from "./ops/routes/opsWebhooks.routes.js";
import { seedOpsRunbooks } from "./ops/runbooksLoader.js";
import { attachDatadogRequestMetrics, initDatadogTracing } from "./ops/tools/datadogTool.js";

const app = express();

app.set("trust proxy", true);

const corsOrigins = env.corsOrigins;
const allowAllOrigins = corsOrigins.length === 0 || corsOrigins.includes("*");

app.use(withRequestContext);
app.use(requestLogger({ enabled: env.logHttpRequests }));
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
      "X-App-Version",
      "X-Device-Model",
      "X-Ops-Api-Key",
      "X-Api-Key",
    ],
  })
);
app.use(express.json({ limit: env.jsonBodyLimit }));
app.use(express.urlencoded({ extended: true, limit: env.jsonBodyLimit }));
app.use(jsonSyntaxErrorHandler);
app.use(attachDatadogRequestMetrics());

app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    service: "maslaki-ai-ops-api",
    runtime: "ops",
    uptimeSec: Math.round(process.uptime()),
    timestamp: new Date().toISOString(),
  });
});

app.get("/ready", (req, res) => {
  res.json({ status: "ready", timestamp: new Date().toISOString() });
});

app.use("/ops", createOpsRouter());
app.use("/ops/webhooks", createOpsWebhooksRouter());
app.use("/api/admin/ops", createOpsRouter());
app.use("/api/admin/ops/webhooks", createOpsWebhooksRouter());

app.use(notFoundHandler);
app.use(errorHandler);

const port = env.port;
const host = env.host;
let activeServer = null;
let shutdownInProgress = false;

async function shutdown(signal) {
  if (shutdownInProgress) return;
  shutdownInProgress = true;
  console.log(`[ops] Received ${signal}. Graceful shutdown started.`);

  const closeServer = new Promise((resolve) => {
    if (!activeServer) return resolve();
    activeServer.close(() => resolve());
  });

  const timeout = new Promise((resolve) =>
    setTimeout(() => resolve("timeout"), 10_000).unref?.()
  );
  await Promise.race([closeServer, timeout]);

  await Promise.allSettled([pool.end(), closeRedisClient()]);
  console.log("[ops] Shutdown complete.");
  process.exit(0);
}

process.on("SIGTERM", () => {
  void shutdown("SIGTERM");
});
process.on("SIGINT", () => {
  void shutdown("SIGINT");
});

async function start() {
  validateRuntimeEnv();
  await initDatadogTracing({ env });
  if (env.runSqlMigrations) {
    await runSqlMigrations();
  }
  await ensureSchema();
  await seedOpsRunbooks();

  activeServer = app.listen(port, host, () => {
    console.log(`[ops] Server running on http://${host}:${port}`);
  });
}

start().catch((error) => {
  console.error("[ops] Failed to start server:", error);
  process.exit(1);
});
