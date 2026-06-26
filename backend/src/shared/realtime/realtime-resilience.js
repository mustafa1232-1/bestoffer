import { env } from "../../config/env.js";

/**
 * Shared resilience primitives for the realtime layer.
 *
 * Goals (launch hardening):
 * - Never leak full HTML error pages (Cloudflare 520/521/…) or secrets into logs.
 * - Extract an HTTP status code from heterogeneous error shapes.
 * - Decide retryability consistently (5xx / 429 / network / timeout => retryable).
 * - Bound every outbound call with a timeout.
 * - Back off exponentially with jitter on retry.
 * - Fail fast with a circuit breaker when Supabase is in a failure storm.
 * - Track lightweight in-memory counters for observability.
 *
 * Used by: realtime-membership, realtime-supabase-publisher, realtime-outbox,
 * realtime-gateway.
 */

const DEFAULT_ERROR_LOG_MAX = 300;

// JWTs, bearer tokens, api keys and service-role values must never reach logs.
const SECRET_PATTERNS = [
  /eyJ[a-zA-Z0-9_-]{6,}\.[a-zA-Z0-9_-]{6,}\.[a-zA-Z0-9_-]{6,}/g, // JWT
  /Bearer\s+[A-Za-z0-9._-]+/gi,
  /apikey["':=\s]+[A-Za-z0-9._-]{6,}/gi,
  /authorization["':=\s]+[A-Za-z0-9._-]{6,}/gi,
  /service_role[A-Za-z0-9._-]*/gi,
];

export function stripHtml(text) {
  return String(text == null ? "" : text)
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&[a-zA-Z#0-9]+;/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function redactSecrets(text) {
  let out = String(text == null ? "" : text);
  for (const pattern of SECRET_PATTERNS) {
    out = out.replace(pattern, "[redacted]");
  }
  return out;
}

export function extractStatusCode(error) {
  if (error == null) return null;
  const candidates = [
    error.status,
    error.statusCode,
    error.httpStatus,
    error?.details?.status,
    error?.response?.status,
  ];
  for (const candidate of candidates) {
    const value = Number(candidate);
    if (Number.isInteger(value) && value >= 100 && value <= 599) return value;
  }
  // Supabase-js uses `code` for postgrest error strings; only treat it as a
  // status if it parses as a real HTTP status number.
  const code = Number(error.code);
  if (Number.isInteger(code) && code >= 100 && code <= 599) return code;
  const message = String(error?.message || error || "");
  const match = message.match(/\b(1\d\d|2\d\d|3\d\d|4\d\d|5\d\d)\b/);
  return match ? Number(match[1]) : null;
}

export function isRetryableError(error) {
  if (error == null) return false;
  if (error.retryable === true) return true;
  if (error.retryable === false) return false;

  const status = extractStatusCode(error);
  if (status != null) {
    if (status === 408 || status === 425 || status === 429) return true;
    // 5xx including Cloudflare 520-526 are transient upstream failures.
    return status >= 500;
  }

  const code = String(error?.code || error?.cause?.code || "");
  if (
    /ECONNRESET|ETIMEDOUT|ECONNREFUSED|EAI_AGAIN|ENOTFOUND|EPIPE|ECONNABORTED|UND_ERR/i.test(
      code
    )
  ) {
    return true;
  }

  const name = String(error?.name || "");
  if (name === "AbortError" || name === "TimeoutError") return true;

  const message = String(error?.message || "");
  return /timeout|timed out|network|fetch failed|socket hang up|terminated/i.test(
    message
  );
}

/**
 * Produce a compact, safe descriptor for logging. Never returns HTML, secrets,
 * or more than `maxLen` characters of message text.
 */
export function sanitizeErrorForLog(error, maxLen = DEFAULT_ERROR_LOG_MAX) {
  if (error == null) return null;
  const rawMessage =
    typeof error === "string" ? error : error?.message || String(error);
  const cleaned = redactSecrets(stripHtml(rawMessage));
  return {
    message: cleaned.slice(0, Math.max(1, maxLen)),
    statusCode: extractStatusCode(error),
    retryable: isRetryableError(error),
  };
}

export function createRealtimeError(
  code,
  { status = null, retryable = null, details = {} } = {}
) {
  const error = new Error(code);
  error.code = code;
  if (status != null) error.status = status;
  if (retryable != null) error.retryable = retryable;
  error.details = details;
  return error;
}

const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export function computeBackoffDelay(
  attempt,
  { baseDelayMs = 250, maxDelayMs = 8000, jitter = true, random = Math.random } = {}
) {
  const safeAttempt = Math.max(1, Number(attempt) || 1);
  const exp = Math.min(maxDelayMs, baseDelayMs * 2 ** (safeAttempt - 1));
  if (!jitter) return exp;
  // Full jitter on the upper half keeps a sane floor while spreading load.
  return Math.floor(exp / 2 + random() * (exp / 2));
}

/**
 * Race a promise against a timeout. The original work is not cancelled (the
 * caller may pass an AbortController for that), but the awaiter is released.
 */
export function withTimeout(promise, timeoutMs, label = "realtime_operation") {
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) return Promise.resolve(promise);
  let timer = null;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(
        createRealtimeError("REALTIME_TIMEOUT", {
          status: 504,
          retryable: true,
          details: { label, timeoutMs },
        })
      );
    }, timeoutMs);
  });
  return Promise.race([Promise.resolve(promise), timeout]).finally(() => {
    if (timer) clearTimeout(timer);
  });
}

export async function fetchWithTimeout(
  url,
  options = {},
  timeoutMs = 8000,
  fetchImpl = fetch
) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Math.max(1, timeoutMs));
  try {
    return await fetchImpl(url, { ...options, signal: controller.signal });
  } catch (error) {
    if (error?.name === "AbortError") {
      throw createRealtimeError("REALTIME_FETCH_TIMEOUT", {
        status: 504,
        retryable: true,
        details: { timeoutMs },
      });
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Run `fn` up to `retries + 1` times with exponential backoff. Only retries
 * when `shouldRetry(error)` is true. `fn` receives the 1-based attempt number.
 */
export async function withRetry(
  fn,
  {
    retries = 2,
    baseDelayMs = 250,
    maxDelayMs = 8000,
    shouldRetry = isRetryableError,
    sleep = defaultSleep,
    onRetry = null,
    random = Math.random,
  } = {}
) {
  let attempt = 0;
  // eslint-disable-next-line no-constant-condition
  for (;;) {
    attempt += 1;
    try {
      return await fn(attempt);
    } catch (error) {
      if (attempt > retries || !shouldRetry(error)) throw error;
      const delay = computeBackoffDelay(attempt, {
        baseDelayMs,
        maxDelayMs,
        random,
      });
      if (typeof onRetry === "function") onRetry(error, attempt, delay);
      await sleep(delay);
    }
  }
}

/**
 * Minimal circuit breaker: closed -> open (after N consecutive failures) ->
 * half_open (after cooldown, allows a single trial) -> closed on success.
 */
export class CircuitBreaker {
  constructor({
    failureThreshold = 5,
    cooldownMs = 15000,
    now = () => Date.now(),
  } = {}) {
    this.failureThreshold = Math.max(1, Number(failureThreshold) || 5);
    this.cooldownMs = Math.max(1000, Number(cooldownMs) || 15000);
    this.now = now;
    this.failures = 0;
    this.state = "closed";
    this.openedAt = 0;
  }

  canRequest() {
    if (this.state === "closed" || this.state === "half_open") return true;
    if (this.now() - this.openedAt >= this.cooldownMs) {
      this.state = "half_open";
      return true;
    }
    return false;
  }

  recordSuccess() {
    this.failures = 0;
    this.state = "closed";
    this.openedAt = 0;
  }

  recordFailure() {
    this.failures += 1;
    if (this.failures >= this.failureThreshold) {
      this.state = "open";
      this.openedAt = this.now();
    }
  }

  snapshot() {
    return { state: this.state, failures: this.failures };
  }

  reset() {
    this.failures = 0;
    this.state = "closed";
    this.openedAt = 0;
  }
}

export const supabaseCircuit = new CircuitBreaker({
  failureThreshold: Number(env.supabaseRealtimeCircuitThreshold) || 5,
  cooldownMs: Number(env.supabaseRealtimeCircuitCooldownMs) || 15000,
});

/**
 * Execute `fn` through a circuit breaker. When the circuit is open the call is
 * rejected immediately with a retryable REALTIME_CIRCUIT_OPEN error so callers
 * (gateway) fall straight through to the outbox instead of hammering Supabase.
 */
export async function runWithCircuit(circuit, fn, { onOpen = null } = {}) {
  if (!circuit.canRequest()) {
    if (typeof onOpen === "function") onOpen();
    throw createRealtimeError("REALTIME_CIRCUIT_OPEN", {
      status: 503,
      retryable: true,
      details: { circuit: circuit.snapshot() },
    });
  }
  try {
    const result = await fn();
    circuit.recordSuccess();
    return result;
  } catch (error) {
    circuit.recordFailure();
    throw error;
  }
}

// --- Lightweight in-memory metrics ------------------------------------------

const metrics = Object.create(null);

export const REALTIME_METRICS = Object.freeze({
  PUBLISH_SUCCESS: "realtime_publish_success",
  PUBLISH_FAILURE: "realtime_publish_failure",
  FALLBACK_OUTBOX_USED: "realtime_fallback_outbox_used",
  MEMBERSHIP_FAILURE: "realtime_membership_failure",
  MEMBERSHIP_RETRY: "realtime_membership_retry",
  OUTBOX_RETRY: "realtime_outbox_retry",
  OUTBOX_DEAD_LETTER: "realtime_outbox_dead_letter",
  OUTBOX_PUBLISHED: "realtime_outbox_published",
  CIRCUIT_OPEN: "realtime_circuit_open",
});

export function incMetric(name, by = 1) {
  if (!name) return 0;
  metrics[name] = (metrics[name] || 0) + by;
  return metrics[name];
}

export function getMetricsSnapshot() {
  return { ...metrics };
}

export function resetMetrics() {
  for (const key of Object.keys(metrics)) delete metrics[key];
}
