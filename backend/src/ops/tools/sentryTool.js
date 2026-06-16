export function mapSentryWebhookToIncident(payload = {}) {
  const event = payload?.event || payload;
  const level = String(event?.level || payload?.level || "error").toLowerCase();
  const title =
    String(event?.title || payload?.title || event?.message || payload?.message || "Sentry alert")
      .trim();
  const transaction =
    String(event?.transaction || payload?.transaction || event?.culprit || "")
      .trim();

  const summary = [
    title,
    transaction ? `transaction: ${transaction}` : "",
    event?.project ? `project: ${event.project}` : "",
  ]
    .filter(Boolean)
    .join(" | ");

  return {
    source: "sentry",
    title,
    summary,
    payload: payload || {},
    metadata: {
      sentryEventId: event?.event_id || payload?.event_id || null,
      issueUrl: event?.url || payload?.url || null,
      level,
    },
  };
}

export async function initSentryBackend({ env, app }) {
  const dsn = String(env.sentryDsn || "").trim();
  if (!dsn || !app) {
    return {
      enabled: false,
      reason: "missing_dsn_or_app",
    };
  }

  try {
    const sentry = await import("@sentry/node");
    sentry.init({
      dsn,
      environment: env.appEnv || env.nodeEnv || "development",
      release: env.appVersion || env.gitCommitSha || "unknown",
      tracesSampleRate: 0.05,
      sendDefaultPii: false,
      initialScope: {
        tags: {
          service: env.sentryServiceName || "maslaki-backend",
        },
      },
      beforeSend(event) {
        const scrubbed = { ...event };
        if (scrubbed.request?.headers) {
          const headers = { ...scrubbed.request.headers };
          for (const key of Object.keys(headers)) {
            const lower = key.toLowerCase();
            if (
              lower.includes("authorization") ||
              lower.includes("cookie") ||
              lower.includes("token") ||
              lower.includes("secret")
            ) {
              headers[key] = "[redacted]";
            }
          }
          scrubbed.request.headers = headers;
        }
        return scrubbed;
      },
    });

    app.use(sentry.Handlers.requestHandler());
    app.use(sentry.Handlers.errorHandler());

    process.on("unhandledRejection", (reason) => {
      sentry.captureException(reason);
    });
    process.on("uncaughtException", (error) => {
      sentry.captureException(error);
    });

    return {
      enabled: true,
    };
  } catch (error) {
    console.warn("[ops] Sentry init skipped:", error?.message || error);
    return {
      enabled: false,
      reason: "package_missing_or_init_failed",
    };
  }
}
