import { env } from "../../config/env.js";
import {
  getSupabaseBroadcastEndpoint,
  getSupabaseBroadcastHeaders,
  getSupabaseRealtimeStatus,
} from "../../config/supabase.js";
import {
  createRealtimeError,
  fetchWithTimeout,
  isRetryableError,
  redactSecrets,
  runWithCircuit,
  stripHtml,
  supabaseCircuit,
} from "./realtime-resilience.js";

const dependencies = {
  fetchImpl: (url, options) => fetch(url, options),
  circuit: supabaseCircuit,
};

function buildPublishError(message, details = {}) {
  return createRealtimeError(message, {
    status: details.status ?? null,
    retryable: details.retryable ?? null,
    details,
  });
}

/**
 * Publish a single broadcast message to Supabase Realtime.
 *
 * Resilience:
 * - Bounded by a request timeout (no hung sockets).
 * - Routed through the shared Supabase circuit breaker so a 520 storm fails
 *   fast and lets the gateway drop straight to the outbox.
 * - Error bodies are HTML-stripped, secret-redacted and truncated. We never
 *   surface a full Cloudflare error page or any auth header / api key.
 */
export async function publishSupabaseBroadcast(
  topic,
  event,
  payload,
  { private: isPrivate = true } = {}
) {
  const status = getSupabaseRealtimeStatus();
  if (!status.canUseSupabase) {
    throw buildPublishError("SUPABASE_REALTIME_UNAVAILABLE", {
      reason: status.reason,
      missingKeys: status.missingKeys,
      retryable: true,
    });
  }

  const endpoint = getSupabaseBroadcastEndpoint();
  const headers = getSupabaseBroadcastHeaders();
  if (!endpoint || !headers) {
    throw buildPublishError("SUPABASE_REALTIME_NOT_CONFIGURED", {
      retryable: false,
    });
  }

  const safeTopic = String(topic || "").trim();
  const safeEvent = String(event || "").trim() || "message";
  if (!safeTopic) {
    throw buildPublishError("SUPABASE_REALTIME_INVALID_TOPIC", {
      retryable: false,
    });
  }

  const timeoutMs = Number(env.supabaseRealtimePublishTimeoutMs) || 8000;

  return runWithCircuit(dependencies.circuit, async () => {
    const response = await fetchWithTimeout(
      endpoint,
      {
        method: "POST",
        headers,
        body: JSON.stringify({
          messages: [
            {
              topic: safeTopic,
              event: safeEvent,
              payload,
              private: isPrivate === true,
            },
          ],
        }),
      },
      timeoutMs,
      dependencies.fetchImpl
    );

    if (response.ok) {
      const contentType = String(response.headers.get("content-type") || "");
      if (contentType.includes("application/json")) {
        return response.json().catch(() => null);
      }
      return null;
    }

    const bodyText = await response.text().catch(() => "");
    // Cloudflare 5xx pages are large HTML blobs — never log them raw.
    const safeBody = redactSecrets(stripHtml(bodyText)).slice(0, 300);
    const error = buildPublishError("SUPABASE_BROADCAST_FAILED", {
      status: response.status,
      body: safeBody,
      topic: safeTopic,
      event: safeEvent,
    });
    error.retryable = isRetryableError(error);
    throw error;
  });
}

export const __realtimeSupabasePublisherTestApi = {
  setFetchImpl(fn) {
    dependencies.fetchImpl = fn;
  },
  setCircuit(circuit) {
    dependencies.circuit = circuit;
  },
  reset() {
    dependencies.fetchImpl = (url, options) => fetch(url, options);
    dependencies.circuit = supabaseCircuit;
    supabaseCircuit.reset();
  },
};
