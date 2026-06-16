import { env } from "../../config/env.js";

export function mapDatadogWebhookToIncident(payload = {}) {
  const title = String(
    payload?.title || payload?.alert_title || payload?.event_title || "Datadog alert"
  ).trim();

  const summary = String(
    payload?.text || payload?.alert_transition || payload?.event_message || title
  ).trim();

  return {
    source: "datadog",
    title,
    summary,
    payload,
    metadata: {
      alertId: payload?.id || payload?.alert_id || null,
      eventType: payload?.event_type || payload?.alert_type || null,
      url: payload?.url || null,
    },
  };
}

export async function initDatadogTracing({ env }) {
  const apiKey = String(env.ddApiKey || "").trim();
  if (!apiKey) {
    return {
      enabled: false,
      reason: "missing_dd_api_key",
    };
  }

  try {
    const ddTrace = await import("dd-trace");
    const tracer = ddTrace.default.init({
      service: env.ddService || "maslaki-backend",
      env: env.ddEnv || env.nodeEnv || "development",
      version: env.ddVersion || env.appVersion || "unknown",
      logInjection: true,
      runtimeMetrics: true,
      profiling: false,
    });

    return {
      enabled: true,
      tracer,
    };
  } catch (error) {
    console.warn("[ops] Datadog init skipped:", error?.message || error);
    return {
      enabled: false,
      reason: "package_missing_or_init_failed",
    };
  }
}

export function attachDatadogRequestMetrics() {
  return function datadogRequestMetrics(req, res, next) {
    const startedAt = Date.now();
    res.on("finish", () => {
      const durationMs = Date.now() - startedAt;
      const requestId = req.requestId || "n/a";
      const statusCode = Number(res.statusCode || 0);
      const level = statusCode >= 500 ? "error" : statusCode >= 400 ? "warn" : "info";

      const payload = {
        event: "api_request",
        requestId,
        method: req.method,
        path: req.originalUrl,
        statusCode,
        latencyMs: durationMs,
        userId: req.userId || req.authUserId || null,
      };

      if (level === "error") {
        console.error("[dd]", JSON.stringify(payload));
      } else if (level === "warn") {
        console.warn("[dd]", JSON.stringify(payload));
      } else {
        const shouldLogSlow =
          durationMs >= Number(env.ddRequestLogSlowMs || 2500);
        const sampleRate = Math.max(
          0,
          Math.min(1, Number(env.ddRequestLogSampleRate || 0))
        );
        const shouldLogSample = sampleRate > 0 && Math.random() < sampleRate;
        if (!shouldLogSlow && !shouldLogSample) {
          return;
        }
        console.log("[dd]", JSON.stringify(payload));
      }
    });

    next();
  };
}
