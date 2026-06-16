const SENSITIVE_KEYS = new Set([
  "password",
  "pin_hash",
  "token",
  "refreshToken",
  "refresh_token",
  "accessToken",
  "access_token",
  "otp",
  "phone",
  "phoneNumber",
  "phone_number",
  "address",
  "fullAddress",
  "full_address",
  "paymentCredentials",
  "payment_credentials",
  "cardNumber",
  "card_number",
  "cvv",
  "iban",
  "secret",
  "serviceRoleKey",
  "service_role_key",
  "internalAdminNote",
  "internal_admin_note",
  "adminNote",
  "admin_note",
]);

function toIntOrNull(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  return Math.trunc(parsed);
}

function toNumberOrNull(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  return parsed;
}

function pick(source, keys = []) {
  const out = {};
  for (const key of keys) {
    if (source?.[key] !== undefined) out[key] = source[key];
  }
  return out;
}

function sanitizeAttachment(value) {
  if (!value || typeof value !== "object") return null;
  const out = stripSensitiveDeep(
    pick(value, [
      "id",
      "name",
      "fileName",
      "file_name",
      "url",
      "publicUrl",
      "public_url",
      "mimeType",
      "mime_type",
      "thumbnailUrl",
      "thumbnail_url",
      "sizeBytes",
      "size_bytes",
      "durationSeconds",
      "duration_seconds",
      "width",
      "height",
    ])
  );
  return Object.keys(out).length ? out : null;
}

function sanitizeActorProfile(value) {
  if (!value || typeof value !== "object") return null;
  const out = stripSensitiveDeep(
    pick(value, [
      "id",
      "userId",
      "user_id",
      "fullName",
      "full_name",
      "username",
      "imageUrl",
      "image_url",
      "role",
      "isPremiumCreator",
      "is_premium_creator",
    ])
  );
  return Object.keys(out).length ? out : null;
}

function sanitizeNotification(value) {
  if (!value || typeof value !== "object") return null;
  const out = {
    ...stripSensitiveDeep(
      pick(value, [
        "id",
        "user_id",
        "userId",
        "order_id",
        "orderId",
        "merchant_id",
        "merchantId",
        "type",
        "title",
        "body",
        "is_read",
        "isRead",
        "created_at",
        "createdAt",
        "read_at",
        "readAt",
      ])
    ),
  };
  if (value.payload && typeof value.payload === "object") {
    out.payload = stripSensitiveDeep(
      pick(value.payload, [
        "target",
        "targetModule",
        "target_module",
        "roleScope",
        "role_scope",
        "action",
        "orderId",
        "order_id",
        "rideId",
        "ride_id",
        "threadId",
        "thread_id",
        "status",
        "entityId",
        "entity_id",
        "targetEntity",
        "target_entity",
        "notificationType",
        "notification_type",
        "requiresAction",
        "scopeType",
        "scopeCode",
      ])
    );
  }
  return out;
}

function sanitizeChatMessage(value) {
  if (!value || typeof value !== "object") return null;
  const out = {
    ...stripSensitiveDeep(
      pick(value, [
        "id",
        "threadId",
        "thread_id",
        "senderUserId",
        "sender_user_id",
        "senderRole",
        "sender_role",
        "messageType",
        "message_type",
        "body",
        "messageText",
        "message_text",
        "createdAt",
        "created_at",
        "updatedAt",
        "updated_at",
        "editedAt",
        "edited_at",
        "deletedAt",
        "deleted_at",
        "offeredFareIqd",
        "offered_fare_iqd",
        "reactionCounts",
        "reaction_counts",
        "reactionTotalCount",
        "reaction_total_count",
        "myReaction",
        "my_reaction",
      ])
    ),
  };

  const attachment =
    sanitizeAttachment(value.attachment) ||
    sanitizeAttachment(value.media) ||
    sanitizeAttachment(value.file);
  if (attachment) out.attachment = attachment;

  const author =
    sanitizeActorProfile(value.author) ||
    sanitizeActorProfile(value.sender);
  if (author) out.author = author;

  return out;
}

function sanitizeRide(value) {
  if (!value || typeof value !== "object") return null;
  return stripSensitiveDeep(
    pick(value, [
      "id",
      "status",
      "proposedFareIqd",
      "proposed_fare_iqd",
      "agreedFareIqd",
      "agreed_fare_iqd",
      "currentBidId",
      "current_bid_id",
      "customerUserId",
      "customer_user_id",
      "assignedCaptainUserId",
      "assigned_captain_user_id",
      "searchPhase",
      "search_phase",
      "searchRadiusM",
      "search_radius_m",
      "rejectedCaptainsCount",
      "rejected_captains_count",
      "priceRaiseRecommended",
      "price_raise_recommended",
      "priceRaisePromptedAt",
      "price_raise_prompted_at",
      "finalAcceptanceDeadlineAt",
      "final_acceptance_deadline_at",
      "captainRating",
      "captainReview",
      "captainRatedAt",
      "pickup",
      "dropoff",
      "createdAt",
      "created_at",
      "updatedAt",
      "updated_at",
    ])
  );
}

function sanitizeLocation(value) {
  if (!value || typeof value !== "object") return null;
  return stripSensitiveDeep(
    pick(value, [
      "latitude",
      "longitude",
      "headingDeg",
      "heading_deg",
      "speedKmh",
      "speed_kmh",
      "accuracyM",
      "accuracy_m",
      "createdAt",
      "created_at",
      "updatedAt",
      "updated_at",
      "source",
    ])
  );
}

function sanitizeOrder(value) {
  if (!value || typeof value !== "object") return null;
  return stripSensitiveDeep(
    pick(value, [
      "id",
      "orderId",
      "status",
      "merchantId",
      "merchant_id",
      "customerUserId",
      "customer_user_id",
      "ownerUserId",
      "owner_user_id",
      "deliveryUserId",
      "delivery_user_id",
      "courierUserId",
      "courier_user_id",
      "target",
      "targetModule",
      "target_module",
      "roleScope",
      "role_scope",
      "action",
      "notificationType",
      "notification_type",
      "createdAt",
      "created_at",
      "updatedAt",
      "updated_at",
    ])
  );
}

function stripSensitiveDeep(value, depth = 0) {
  if (value == null) return value;
  if (depth > 6) return null;
  if (Array.isArray(value)) {
    return value
      .map((item) => stripSensitiveDeep(item, depth + 1))
      .filter((item) => item !== undefined);
  }
  if (typeof value !== "object") return value;

  const out = {};
  for (const [rawKey, rawValue] of Object.entries(value)) {
    const key = String(rawKey || "");
    const normalized = key.replace(/[^a-zA-Z0-9]/g, "").toLowerCase();
    if (SENSITIVE_KEYS.has(key) || SENSITIVE_KEYS.has(normalized)) continue;
    const nextValue = stripSensitiveDeep(rawValue, depth + 1);
    if (nextValue !== undefined) out[key] = nextValue;
  }
  return out;
}

function sanitizeNotificationEvent(data) {
  const out = stripSensitiveDeep(
    pick(data || {}, ["notificationId", "updatedCount", "orderId", "status"])
  );
  if (data?.notification) {
    out.notification = sanitizeNotification(data.notification);
  }
  return out;
}

function sanitizeSocialEvent(data) {
  const out = stripSensitiveDeep(
    pick(data || {}, [
      "threadId",
      "messageId",
      "actorUserId",
      "actorDisplayName",
      "typing",
      "action",
      "readerUserId",
      "lastReadMessageId",
      "lastDeliveredMessageId",
      "postId",
      "storyId",
      "reelId",
      "scopeType",
      "scopeCode",
      "sessionId",
    ])
  );
  if (data?.message) out.message = sanitizeChatMessage(data.message);
  if (data?.relation) out.relation = stripSensitiveDeep(data.relation);
  if (data?.call || data?.session) {
    out.session = stripSensitiveDeep(data.call || data.session);
  }
  if (data?.post) out.post = stripSensitiveDeep(data.post);
  if (data?.story) out.story = stripSensitiveDeep(data.story);
  return out;
}

function sanitizeTaxiEvent(data) {
  const out = stripSensitiveDeep(
    pick(data || {}, [
      "rideId",
      "bidId",
      "eventType",
      "status",
      "offeredFareIqd",
      "offered_fare_iqd",
      "agreedFareIqd",
      "agreed_fare_iqd",
      "currentBidId",
      "current_bid_id",
      "nextBidId",
      "next_bid_id",
      "timedOutBidId",
      "timed_out_bid_id",
      "rejectedCaptainsCount",
      "rejected_captains_count",
      "distanceM",
      "etaMinutes",
      "eta_minutes",
      "rating",
      "captainRatingAvg",
      "captain_rating_avg",
      "customerUserId",
      "captainUserId",
      "friendUserId",
      "timeoutSeconds",
    ])
  );
  if (data?.ride) out.ride = sanitizeRide(data.ride);
  if (data?.location) out.location = sanitizeLocation(data.location);
  if (data?.session) out.session = stripSensitiveDeep(data.session);
  if (data?.signal) out.signal = stripSensitiveDeep(data.signal);
  if (data?.bidQueue) out.bidQueue = stripSensitiveDeep(data.bidQueue);
  return out;
}

function sanitizeOrderEvent(data) {
  const out = stripSensitiveDeep(
    pick(data || {}, [
      "orderId",
      "status",
      "merchantId",
      "customerUserId",
      "ownerUserId",
      "deliveryUserId",
      "courierUserId",
      "action",
      "target",
      "targetModule",
      "roleScope",
      "notificationType",
      "previousStatus",
      "source",
    ])
  );
  if (data?.order) out.order = sanitizeOrder(data.order);
  return out;
}

export function sanitizeRealtimePayload(event, data) {
  const normalizedEvent = String(event || "").trim().toLowerCase();
  if (normalizedEvent.startsWith("notification")) {
    return sanitizeNotificationEvent(data || {});
  }
  if (normalizedEvent.startsWith("social_")) {
    return sanitizeSocialEvent(data || {});
  }
  if (normalizedEvent.startsWith("taxi_")) {
    return sanitizeTaxiEvent(data || {});
  }
  if (normalizedEvent.startsWith("order_")) {
    return sanitizeOrderEvent(data || {});
  }
  return stripSensitiveDeep(data || {});
}

export const __realtimeSanitizerTestApi = {
  stripSensitiveDeep,
  sanitizeNotification,
  sanitizeChatMessage,
  sanitizeRide,
  sanitizeOrder,
};
