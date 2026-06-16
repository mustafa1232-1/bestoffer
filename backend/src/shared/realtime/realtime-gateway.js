import { getSupabaseRealtimeMode } from "../../config/supabase.js";
import { emitToUser as emitLegacySseToUser, allocateLiveEventId } from "./live-events.js";
import { sanitizeRealtimePayload } from "./realtime-sanitizer.js";
import { publishSupabaseBroadcast } from "./realtime-supabase-publisher.js";
import { enqueueRealtimeOutbox } from "./realtime-outbox.js";
import {
  syncChatThreadMembers,
  syncOrderMembers,
  syncTaxiRideMembers,
} from "./realtime-membership.js";

const SHARED_TOPIC_DEDUP_TTL_MS = 5000;
const sharedTopicDedupCache = new Map();

const dependencies = {
  getMode: () => getSupabaseRealtimeMode(),
  allocateId: () => allocateLiveEventId(),
  sseEmit: (userId, event, data, options) =>
    emitLegacySseToUser(userId, event, data, options),
  sanitize: (event, data) => sanitizeRealtimePayload(event, data),
  publish: (topic, event, payload, options) =>
    publishSupabaseBroadcast(topic, event, payload, options),
  enqueueOutbox: (entry) => enqueueRealtimeOutbox(entry),
  syncChatThreadMembers: (threadId) => syncChatThreadMembers(threadId),
  syncTaxiRideMembers: (rideId) => syncTaxiRideMembers(rideId),
  syncOrderMembers: (orderId) => syncOrderMembers(orderId),
  logger: console,
  now: () => new Date().toISOString(),
};

function toIntOrNull(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return Math.trunc(parsed);
}

function deriveModule(event) {
  const normalized = String(event || "").trim().toLowerCase();
  if (normalized.startsWith("notification")) return "notifications";
  if (normalized.startsWith("social_")) return "feed";
  if (normalized.startsWith("taxi_")) return "taxi";
  if (normalized.startsWith("order_")) return "orders";
  return "app";
}

function inferThreadId(data) {
  return (
    toIntOrNull(data?.threadId) ||
    toIntOrNull(data?.thread_id) ||
    toIntOrNull(data?.message?.threadId) ||
    toIntOrNull(data?.message?.thread_id) ||
    toIntOrNull(data?.notification?.payload?.threadId) ||
    toIntOrNull(data?.notification?.payload?.thread_id) ||
    null
  );
}

function inferRideId(data) {
  return (
    toIntOrNull(data?.rideId) ||
    toIntOrNull(data?.ride_id) ||
    toIntOrNull(data?.ride?.id) ||
    toIntOrNull(data?.notification?.payload?.rideId) ||
    toIntOrNull(data?.notification?.payload?.ride_id) ||
    null
  );
}

function inferOrderId(data) {
  return (
    toIntOrNull(data?.orderId) ||
    toIntOrNull(data?.order_id) ||
    toIntOrNull(data?.order?.id) ||
    toIntOrNull(data?.notification?.order_id) ||
    toIntOrNull(data?.notification?.orderId) ||
    toIntOrNull(data?.notification?.payload?.orderId) ||
    toIntOrNull(data?.notification?.payload?.order_id) ||
    null
  );
}

function inferActorUserId(data, fallback = null) {
  return (
    toIntOrNull(fallback) ||
    toIntOrNull(data?.actorUserId) ||
    toIntOrNull(data?.actor_user_id) ||
    toIntOrNull(data?.senderUserId) ||
    toIntOrNull(data?.sender_user_id) ||
    toIntOrNull(data?.message?.senderUserId) ||
    toIntOrNull(data?.message?.sender_user_id) ||
    toIntOrNull(data?.message?.author?.userId) ||
    toIntOrNull(data?.message?.author?.user_id) ||
    toIntOrNull(data?.notification?.payload?.actorUserId) ||
    toIntOrNull(data?.notification?.payload?.actor_user_id) ||
    null
  );
}

function inferEntity(event, data, options = {}) {
  if (options.entityType && options.entityId != null) {
    return {
      entityType: String(options.entityType),
      entityId: toIntOrNull(options.entityId),
    };
  }

  const normalizedEvent = String(event || "").trim().toLowerCase();
  const threadId = inferThreadId(data);
  const rideId = inferRideId(data);
  const orderId = inferOrderId(data);
  const notificationId =
    toIntOrNull(data?.notification?.id) ||
    toIntOrNull(data?.notificationId) ||
    null;
  const postId = toIntOrNull(data?.postId) || toIntOrNull(data?.post?.id) || null;
  const storyId =
    toIntOrNull(data?.storyId) || toIntOrNull(data?.story?.id) || null;

  if (normalizedEvent.startsWith("notification") && notificationId) {
    return { entityType: "notification", entityId: notificationId };
  }
  if (threadId) return { entityType: "chat_thread", entityId: threadId };
  if (rideId) return { entityType: "taxi_ride", entityId: rideId };
  if (orderId) return { entityType: "order", entityId: orderId };
  if (postId) return { entityType: "social_post", entityId: postId };
  if (storyId) return { entityType: "social_story", entityId: storyId };
  return { entityType: null, entityId: null };
}

function buildPrimaryTopic({ recipientUserId, event, topic = null }) {
  const safeRecipientUserId = toIntOrNull(recipientUserId);
  if (topic) return String(topic).trim();
  if (!safeRecipientUserId) return "";

  const normalizedEvent = String(event || "").trim().toLowerCase();
  if (normalizedEvent.startsWith("notification")) {
    return `notifications:user:${safeRecipientUserId}`;
  }
  if (normalizedEvent.startsWith("social_")) {
    return `social:user:${safeRecipientUserId}`;
  }
  if (normalizedEvent.startsWith("taxi_")) {
    return `taxi:user:${safeRecipientUserId}`;
  }
  return `user:${safeRecipientUserId}`;
}

function collectSharedTopics(event, data, options = {}) {
  const sharedTopics = new Set(
    Array.isArray(options.extraTopics)
      ? options.extraTopics.map((item) => String(item || "").trim()).filter(Boolean)
      : []
  );
  const normalizedEvent = String(event || "").trim().toLowerCase();
  const threadId = inferThreadId(data);
  const rideId = inferRideId(data);
  const orderId = inferOrderId(data);

  if (
    normalizedEvent.startsWith("social_chat_") ||
    normalizedEvent === "social_call_update"
  ) {
    if (threadId) sharedTopics.add(`chat:thread:${threadId}`);
  }
  if (normalizedEvent.startsWith("taxi_")) {
    if (rideId) sharedTopics.add(`taxi:ride:${rideId}`);
  }
  if (normalizedEvent.startsWith("order_") || orderId) {
    if (orderId) sharedTopics.add(`order:${orderId}`);
  }

  return [...sharedTopics].filter(Boolean);
}

function buildEnvelope({
  id,
  event,
  channel,
  recipientUserId = null,
  actorUserId = null,
  data,
  options = {},
}) {
  const sanitizedData = dependencies.sanitize(event, data);
  const { entityType, entityId } = inferEntity(event, data, options);
  return {
    id: Number(id),
    event: String(event || "").trim(),
    channel: String(channel || "").trim(),
    module: String(options.module || deriveModule(event)),
    recipientUserId: toIntOrNull(recipientUserId),
    actorUserId: inferActorUserId(data, actorUserId),
    entityType,
    entityId,
    createdAt: dependencies.now(),
    data: sanitizedData,
  };
}

function buildSharedTopicDedupKey(topic, event, envelope) {
  return JSON.stringify({
    topic,
    event,
    entityType: envelope.entityType || null,
    entityId: envelope.entityId || null,
    actorUserId: envelope.actorUserId || null,
    data: envelope.data || null,
  });
}

function shouldSkipSharedTopicPublish(topic, event, envelope) {
  const now = Date.now();
  for (const [key, expiresAt] of sharedTopicDedupCache.entries()) {
    if (expiresAt <= now) sharedTopicDedupCache.delete(key);
  }

  if (
    !String(topic || "").startsWith("chat:thread:") &&
    !String(topic || "").startsWith("taxi:ride:") &&
    !String(topic || "").startsWith("order:")
  ) {
    return false;
  }

  const dedupKey = buildSharedTopicDedupKey(topic, event, envelope);
  const expiresAt = sharedTopicDedupCache.get(dedupKey) || 0;
  if (expiresAt > now) return true;
  sharedTopicDedupCache.set(dedupKey, now + SHARED_TOPIC_DEDUP_TTL_MS);
  return false;
}

async function ensureTopicMembership(topic) {
  if (String(topic || "").startsWith("chat:thread:")) {
    const threadId = toIntOrNull(String(topic).split(":").pop());
    if (threadId) {
      try {
        const result = await dependencies.syncChatThreadMembers(threadId);
        if (result?.ok === true) {
          return true;
        }
        dependencies.logger.warn?.("[realtime-gateway] chat membership unavailable", {
          topic,
          reason: result?.reason || result?.error?.message || "membership_unavailable",
        });
      } catch (error) {
        dependencies.logger.warn?.(
          "[realtime-gateway] chat membership sync failed",
          error?.message || error
        );
      }
    }
    return false;
  }
  if (String(topic || "").startsWith("taxi:ride:")) {
    const rideId = toIntOrNull(String(topic).split(":").pop());
    if (rideId) {
      try {
        const result = await dependencies.syncTaxiRideMembers(rideId);
        if (result?.ok === true) {
          return true;
        }
        dependencies.logger.warn?.("[realtime-gateway] taxi membership unavailable", {
          topic,
          reason: result?.reason || result?.error?.message || "membership_unavailable",
        });
      } catch (error) {
        dependencies.logger.warn?.(
          "[realtime-gateway] taxi membership sync failed",
          error?.message || error
        );
      }
    }
    return false;
  }
  if (String(topic || "").startsWith("order:")) {
    const orderId = toIntOrNull(String(topic).split(":").pop());
    if (orderId) {
      try {
        const result = await dependencies.syncOrderMembers(orderId);
        if (result?.ok === true) {
          return true;
        }
        dependencies.logger.warn?.("[realtime-gateway] order membership unavailable", {
          topic,
          reason: result?.reason || result?.error?.message || "membership_unavailable",
        });
      } catch (error) {
        dependencies.logger.warn?.(
          "[realtime-gateway] order membership sync failed",
          error?.message || error
        );
      }
    }
    return false;
  }
  return true;
}

async function publishSupabaseWithFallback(topic, event, envelope) {
  try {
    await dependencies.publish(topic, event, envelope, { private: true });
    return { ok: true, queued: false };
  } catch (error) {
    await dependencies.enqueueOutbox({
      topic,
      event,
      payload: envelope,
      error,
    });
    dependencies.logger.warn?.("[realtime-gateway] supabase publish failed", {
      topic,
      event,
      error: error?.message || error,
    });
    return { ok: false, queued: true, error };
  }
}

export async function emitRealtimeToUser(
  userId,
  event,
  data,
  { channel = null, id = null, topic = null, actorUserId = null, ...options } = {}
) {
  const safeUserId = toIntOrNull(userId);
  if (!safeUserId) return null;

  const mode = dependencies.getMode();
  const eventId = toIntOrNull(id) || dependencies.allocateId();
  const normalizedEvent = String(event || "").trim();
  const primaryTopic = buildPrimaryTopic({
    recipientUserId: safeUserId,
    event: normalizedEvent,
    topic,
  });

  if (mode !== "supabase_only") {
    dependencies.sseEmit(safeUserId, normalizedEvent, data, {
      channel,
      id: eventId,
    });
  }

  if (mode === "sse_only" || !primaryTopic) return eventId;

  const baseEnvelope = buildEnvelope({
    id: eventId,
    event: normalizedEvent,
    channel: primaryTopic,
    recipientUserId: safeUserId,
    actorUserId,
    data,
    options,
  });

  await publishSupabaseWithFallback(primaryTopic, normalizedEvent, baseEnvelope);

  const sharedTopics = collectSharedTopics(normalizedEvent, data, options).filter(
    (value) => value && value !== primaryTopic
  );
  for (const sharedTopic of sharedTopics) {
    const sharedTopicReady = await ensureTopicMembership(sharedTopic);
    if (!sharedTopicReady) {
      continue;
    }
    const sharedEnvelope = {
      ...baseEnvelope,
      channel: sharedTopic,
      recipientUserId: null,
    };
    if (shouldSkipSharedTopicPublish(sharedTopic, normalizedEvent, sharedEnvelope)) {
      continue;
    }
    await publishSupabaseWithFallback(sharedTopic, normalizedEvent, sharedEnvelope);
  }

  return eventId;
}

export async function emitRealtimeToUsers(
  userIds,
  event,
  data,
  options = {}
) {
  const safeUserIds = [...new Set(
    (Array.isArray(userIds) ? userIds : [])
      .map((value) => toIntOrNull(value))
      .filter(Boolean)
  )];
  if (safeUserIds.length <= 0) return [];
  const eventId = toIntOrNull(options.id) || dependencies.allocateId();
  for (const userId of safeUserIds) {
    await emitRealtimeToUser(userId, event, data, { ...options, id: eventId });
  }
  return safeUserIds;
}

export async function emitRealtimeToTopic(
  topic,
  event,
  data,
  { id = null, actorUserId = null, ...options } = {}
) {
  const mode = dependencies.getMode();
  if (mode === "sse_only") return null;

  const safeTopic = String(topic || "").trim();
  const normalizedEvent = String(event || "").trim();
  if (!safeTopic || !normalizedEvent) return null;

  const sharedTopicReady = await ensureTopicMembership(safeTopic);
  if (!sharedTopicReady) {
    return toIntOrNull(id) || dependencies.allocateId();
  }

  const eventId = toIntOrNull(id) || dependencies.allocateId();
  const envelope = buildEnvelope({
    id: eventId,
    event: normalizedEvent,
    channel: safeTopic,
    actorUserId,
    data,
    options,
  });

  if (shouldSkipSharedTopicPublish(safeTopic, normalizedEvent, envelope)) {
    return eventId;
  }

  await publishSupabaseWithFallback(safeTopic, normalizedEvent, envelope);
  return eventId;
}

export async function emitPresenceEvent(userId, event, data, options = {}) {
  const safeUserId = toIntOrNull(userId);
  if (!safeUserId) return null;
  return emitRealtimeToUser(safeUserId, event, data, {
    ...options,
    topic: options.topic || `social:user:${safeUserId}`,
    module: options.module || "presence",
  });
}

export const __realtimeGatewayTestApi = {
  buildPrimaryTopic,
  collectSharedTopics,
  buildEnvelope,
  setModeResolver(fn) {
    dependencies.getMode = fn;
  },
  setAllocateId(fn) {
    dependencies.allocateId = fn;
  },
  setSseEmitter(fn) {
    dependencies.sseEmit = fn;
  },
  setSanitizer(fn) {
    dependencies.sanitize = fn;
  },
  setPublisher(fn) {
    dependencies.publish = fn;
  },
  setOutboxEnqueuer(fn) {
    dependencies.enqueueOutbox = fn;
  },
  setMembershipSyncers(overrides = {}) {
    if (overrides.syncChatThreadMembers) {
      dependencies.syncChatThreadMembers = overrides.syncChatThreadMembers;
    }
    if (overrides.syncTaxiRideMembers) {
      dependencies.syncTaxiRideMembers = overrides.syncTaxiRideMembers;
    }
    if (overrides.syncOrderMembers) {
      dependencies.syncOrderMembers = overrides.syncOrderMembers;
    }
  },
  reset() {
    dependencies.getMode = () => getSupabaseRealtimeMode();
    dependencies.allocateId = () => allocateLiveEventId();
    dependencies.sseEmit = (userId, event, data, options) =>
      emitLegacySseToUser(userId, event, data, options);
    dependencies.sanitize = (event, data) => sanitizeRealtimePayload(event, data);
    dependencies.publish = (topic, event, payload, options) =>
      publishSupabaseBroadcast(topic, event, payload, options);
    dependencies.enqueueOutbox = (entry) => enqueueRealtimeOutbox(entry);
    dependencies.syncChatThreadMembers = (threadId) => syncChatThreadMembers(threadId);
    dependencies.syncTaxiRideMembers = (rideId) => syncTaxiRideMembers(rideId);
    dependencies.syncOrderMembers = (orderId) => syncOrderMembers(orderId);
    dependencies.logger = console;
    dependencies.now = () => new Date().toISOString();
    sharedTopicDedupCache.clear();
  },
};
