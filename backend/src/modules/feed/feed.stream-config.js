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

/**
 * Per-variable classification: PRESENT | MISSING | INVALID_FORMAT (§6).
 * Never returns the secret value.
 */
export function classifyStreamConfig(source = env) {
  const str = (v) => (typeof v === "string" ? v.trim() : "");
  const num = (v) => (typeof v === "number" ? v : Number.NaN);
  const classifyStr = (v) => (str(v).length > 0 ? "PRESENT" : "MISSING");
  const classifyUrl = (v) => {
    const s = str(v);
    if (!s) return "MISSING";
    return /^https?:\/\//i.test(s) ? "PRESENT" : "INVALID_FORMAT";
  };
  const classifyPosInt = (v) => {
    const n = num(v);
    if (!Number.isFinite(n)) return "MISSING";
    return Number.isInteger(n) && n > 0 ? "PRESENT" : "INVALID_FORMAT";
  };

  return {
    CF_STREAM_ACCOUNT_ID: classifyStr(source.cfStreamAccountId ?? source.cfAccountId),
    CF_STREAM_API_TOKEN: classifyStr(source.cfStreamApiToken),
    CF_STREAM_CUSTOMER_CODE: classifyStr(source.cfStreamCustomerCode),
    CF_STREAM_PLAYBACK_BASE_URL: classifyUrl(source.cfStreamPlaybackBaseUrl),
    CF_STREAM_THUMBNAIL_BASE_URL: classifyUrl(source.cfStreamThumbnailBaseUrl),
    CF_STREAM_WEBHOOK_SECRET: classifyStr(source.cfStreamWebhookSecret),
    SOCIAL_STREAM_RECONCILE_INTERVAL_MS: classifyPosInt(
      source.socialStreamReconcileIntervalMs
    ),
    SOCIAL_STREAM_RECONCILE_BATCH_SIZE: classifyPosInt(
      source.socialStreamReconcileBatchSize
    ),
  };
}

/**
 * Emits a single secret-free startup line, e.g.
 *   "Social Stream configuration: READY"
 *   "Social Stream configuration: UNAVAILABLE (missing: CF_STREAM_API_TOKEN)"
 */
export function logStreamConfigStartup(source = env, log = console.log) {
  const d = describeStreamConfig(source);
  if (d.streamAvailable && d.webhookConfigured) {
    log("Social Stream configuration: READY");
  } else {
    const gaps = d.missing.length ? ` (missing: ${d.missing.join(", ")})` : "";
    log(`Social Stream configuration: UNAVAILABLE${gaps}`);
  }
}
