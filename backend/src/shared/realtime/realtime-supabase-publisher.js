import {
  getSupabaseBroadcastEndpoint,
  getSupabaseBroadcastHeaders,
  getSupabaseRealtimeStatus,
} from "../../config/supabase.js";

function buildPublishError(message, details = {}) {
  const error = new Error(message);
  error.code = message;
  error.details = details;
  return error;
}

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
    });
  }

  const endpoint = getSupabaseBroadcastEndpoint();
  const headers = getSupabaseBroadcastHeaders();
  if (!endpoint || !headers) {
    throw buildPublishError("SUPABASE_REALTIME_NOT_CONFIGURED");
  }

  const safeTopic = String(topic || "").trim();
  const safeEvent = String(event || "").trim() || "message";
  if (!safeTopic) {
    throw buildPublishError("SUPABASE_REALTIME_INVALID_TOPIC");
  }

  const response = await fetch(endpoint, {
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
  });

  if (response.ok) {
    const contentType = String(response.headers.get("content-type") || "");
    if (contentType.includes("application/json")) {
      return response.json().catch(() => null);
    }
    return null;
  }

  const bodyText = await response.text().catch(() => "");
  throw buildPublishError("SUPABASE_BROADCAST_FAILED", {
    status: response.status,
    body: bodyText.slice(0, 1200),
    topic: safeTopic,
    event: safeEvent,
  });
}
