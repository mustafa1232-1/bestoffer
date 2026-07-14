import { env } from "../../config/env.js";

/**
 * Cloudflare Stream configuration validator (Social V3 §5).
 *
 * Reports ONLY whether each value is present — never the secret value itself.
 * Used by health checks and startup logging so operators can see, without
 * leaking secrets, whether direct Stream uploads are available.
 */
export function describeStreamConfig(source = env) {
  const present = (v) => typeof v === "string" && v.trim().length > 0;
  const positive = (v) => typeof v === "number" && Number.isFinite(v) && v > 0;

  const checks = {
    CF_STREAM_ACCOUNT_ID: present(source.cfStreamAccountId ?? source.cfAccountId),
    CF_STREAM_API_TOKEN: present(source.cfStreamApiToken),
    CF_STREAM_CUSTOMER_CODE: present(source.cfStreamCustomerCode),
    CF_STREAM_PLAYBACK_BASE_URL: present(source.cfStreamPlaybackBaseUrl),
    CF_STREAM_THUMBNAIL_BASE_URL: present(source.cfStreamThumbnailBaseUrl),
    CF_STREAM_WEBHOOK_SECRET: present(source.cfStreamWebhookSecret),
    SOCIAL_STREAM_RECONCILE_INTERVAL_MS: positive(
      source.socialStreamReconcileIntervalMs
    ),
    SOCIAL_STREAM_RECONCILE_BATCH_SIZE: positive(
      source.socialStreamReconcileBatchSize
    ),
  };

  // The minimum to accept a direct upload: account + token + customer code +
  // webhook secret (playback/thumbnail base URLs are derivable from the
  // customer code).
  const uploadReady =
    checks.CF_STREAM_ACCOUNT_ID &&
    checks.CF_STREAM_API_TOKEN &&
    checks.CF_STREAM_CUSTOMER_CODE;
  const webhookReady = checks.CF_STREAM_WEBHOOK_SECRET;

  const missing = Object.entries(checks)
    .filter(([, ok]) => !ok)
    .map(([name]) => name);

  return {
    streamAvailable: uploadReady,
    webhookConfigured: webhookReady,
    reconcileConfigured:
      checks.SOCIAL_STREAM_RECONCILE_INTERVAL_MS &&
      checks.SOCIAL_STREAM_RECONCILE_BATCH_SIZE,
    // presence booleans only — no values
    checks,
    missing,
  };
}

/** Health-safe summary (no secrets) for the health endpoint / startup log. */
export function streamConfigHealth(source = env) {
  const d = describeStreamConfig(source);
  return {
    stream: d.streamAvailable ? "available" : "unavailable",
    webhook: d.webhookConfigured ? "configured" : "missing",
    reconcile: d.reconcileConfigured ? "configured" : "missing",
    missing: d.missing,
  };
}
