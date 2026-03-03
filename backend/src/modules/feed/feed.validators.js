function asTrimmed(value) {
  if (value == null) return "";
  return String(value).trim();
}

function asPositiveInt(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

function isNonEmptyString(value, maxLen) {
  if (value == null) return false;
  const text = String(value).trim();
  if (!text) return false;
  return text.length <= Number(maxLen || 0);
}

function isOptionalString(value, maxLen) {
  if (value == null) return true;
  const text = String(value).trim();
  return text.length <= Number(maxLen || 0);
}

function asBooleanOrNull(value) {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (value === 1) return true;
    if (value === 0) return false;
    return null;
  }
  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  return null;
}

export function validateListPosts(query = {}) {
  const errors = [];
  const limit = Number(query.limit ?? 20);
  const beforeId = query.beforeId == null ? null : asPositiveInt(query.beforeId);
  const kind = asTrimmed(query.kind).toLowerCase();

  if (!Number.isInteger(limit) || limit < 1 || limit > 50) errors.push("limit");
  if (query.beforeId != null && beforeId == null) errors.push("beforeId");
  if (kind && !["text", "image", "video", "merchant_review"].includes(kind)) {
    errors.push("kind");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: Math.min(50, Math.max(1, Number.isInteger(limit) ? limit : 20)),
      beforeId,
      kind: kind || null,
    },
  };
}

export function validateListStories(query = {}) {
  const limitUsers = Number(query.limitUsers ?? 30);
  const maxPerUser = Number(query.maxPerUser ?? 8);
  const errors = [];

  if (!Number.isInteger(limitUsers) || limitUsers < 1 || limitUsers > 80) {
    errors.push("limitUsers");
  }
  if (!Number.isInteger(maxPerUser) || maxPerUser < 1 || maxPerUser > 20) {
    errors.push("maxPerUser");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      limitUsers: Math.min(
        80,
        Math.max(1, Number.isInteger(limitUsers) ? limitUsers : 30)
      ),
      maxPerUser: Math.min(
        20,
        Math.max(1, Number.isInteger(maxPerUser) ? maxPerUser : 8)
      ),
    },
  };
}

export function validateListStoryArchive(query = {}) {
  const errors = [];
  const limit = Number(query.limit ?? 40);
  const beforeId = query.beforeId == null ? null : asPositiveInt(query.beforeId);

  if (!Number.isInteger(limit) || limit < 1 || limit > 100) errors.push("limit");
  if (query.beforeId != null && beforeId == null) errors.push("beforeId");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: Math.min(100, Math.max(1, Number.isInteger(limit) ? limit : 40)),
      beforeId,
    },
  };
}

export function validateCreatePost(body = {}) {
  const errors = [];
  const caption = asTrimmed(body.caption);
  const postKind = asTrimmed(body.postKind || body.post_kind).toLowerCase() || "text";
  const merchantId =
    body.merchantId == null || body.merchantId === ""
      ? null
      : asPositiveInt(body.merchantId);
  const reviewRating =
    body.reviewRating == null || body.reviewRating === ""
      ? null
      : Number(body.reviewRating);

  if (caption.length > 1200) errors.push("caption");
  if (!["text", "image", "video", "merchant_review"].includes(postKind)) {
    errors.push("postKind");
  }
  if (body.merchantId != null && merchantId == null) errors.push("merchantId");
  if (
    body.reviewRating != null &&
    (!Number.isInteger(reviewRating) || reviewRating < 1 || reviewRating > 5)
  ) {
    errors.push("reviewRating");
  }

  if (postKind === "merchant_review") {
    if (merchantId == null) errors.push("merchantId_required");
    if (reviewRating == null) errors.push("reviewRating_required");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      caption,
      postKind,
      merchantId,
      reviewRating: reviewRating == null ? null : Math.trunc(reviewRating),
    },
  };
}

export function validateCreateStory(body = {}) {
  const errors = [];
  const caption = asTrimmed(body.caption);
  const storyStyle = _parseStoryStyle(body.storyStyle ?? body.story_style, errors);

  if (caption.length > 500) errors.push("caption");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      caption,
      storyStyle,
    },
  };
}

export function validatePostId(postId) {
  const value = asPositiveInt(postId);
  return {
    ok: value != null,
    errors: value == null ? ["postId"] : [],
    value,
  };
}

export function validateUserId(userId) {
  const value = asPositiveInt(userId);
  return {
    ok: value != null,
    errors: value == null ? ["userId"] : [],
    value,
  };
}

export function validateStoryId(storyId) {
  const value = asPositiveInt(storyId);
  return {
    ok: value != null,
    errors: value == null ? ["storyId"] : [],
    value,
  };
}

function _parseStoryStyle(rawStyle, errors) {
  if (rawStyle == null || rawStyle === "") return {};

  let style = rawStyle;
  if (typeof rawStyle === "string") {
    try {
      style = JSON.parse(rawStyle);
    } catch (_) {
      errors.push("storyStyle");
      return {};
    }
  }

  if (!style || typeof style !== "object" || Array.isArray(style)) {
    errors.push("storyStyle");
    return {};
  }

  const out = {};

  const backgroundColor = asTrimmed(style.backgroundColor);
  if (backgroundColor) {
    if (/^#[0-9A-Fa-f]{6}$/.test(backgroundColor) || /^#[0-9A-Fa-f]{8}$/.test(backgroundColor)) {
      out.backgroundColor = backgroundColor;
    } else {
      errors.push("storyStyle.backgroundColor");
    }
  }

  const textColor = asTrimmed(style.textColor);
  if (textColor) {
    if (/^#[0-9A-Fa-f]{6}$/.test(textColor) || /^#[0-9A-Fa-f]{8}$/.test(textColor)) {
      out.textColor = textColor;
    } else {
      errors.push("storyStyle.textColor");
    }
  }

  const fontFamily = asTrimmed(style.fontFamily);
  if (fontFamily) {
    const allowed = new Set(["system", "serif", "monospace"]);
    if (allowed.has(fontFamily)) out.fontFamily = fontFamily;
    else errors.push("storyStyle.fontFamily");
  }

  const align = asTrimmed(style.textAlign).toLowerCase();
  if (align) {
    const allowed = new Set(["left", "center", "right"]);
    if (allowed.has(align)) out.textAlign = align;
    else errors.push("storyStyle.textAlign");
  }

  const weight = asTrimmed(style.fontWeight).toLowerCase();
  if (weight) {
    const allowed = new Set(["normal", "bold", "heavy"]);
    if (allowed.has(weight)) out.fontWeight = weight;
    else errors.push("storyStyle.fontWeight");
  }

  const fontScaleRaw = Number(style.fontScale);
  if (style.fontScale != null && style.fontScale !== "") {
    if (Number.isFinite(fontScaleRaw) && fontScaleRaw >= 0.8 && fontScaleRaw <= 2.4) {
      out.fontScale = fontScaleRaw;
    } else {
      errors.push("storyStyle.fontScale");
    }
  }

  return out;
}

export function validateCreateComment(body = {}) {
  const text = asTrimmed(body.body);
  const errors = [];
  if (!text) errors.push("body");
  if (text.length > 600) errors.push("body_length");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      body: text,
    },
  };
}

export function validateMerchantSearch(query = {}) {
  const search = asTrimmed(query.search);
  const limit = Number(query.limit ?? 120);
  const errors = [];
  if (search.length > 80) errors.push("search");
  if (!Number.isInteger(limit) || limit < 1 || limit > 300) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      search,
      limit: Math.min(300, Math.max(1, Number.isInteger(limit) ? limit : 120)),
    },
  };
}

export function validateCreateThread(body = {}) {
  const userId = asPositiveInt(body.userId);
  return {
    ok: userId != null,
    errors: userId == null ? ["userId"] : [],
    value: { userId },
  };
}

export function validateThreadId(threadId) {
  const value = asPositiveInt(threadId);
  return {
    ok: value != null,
    errors: value == null ? ["threadId"] : [],
    value,
  };
}

export function validateMessageId(messageId) {
  const value = asPositiveInt(messageId);
  return {
    ok: value != null,
    errors: value == null ? ["messageId"] : [],
    value,
  };
}

export function validateListMessages(query = {}) {
  const limit = Number(query.limit ?? 40);
  const beforeId = query.beforeId == null ? null : asPositiveInt(query.beforeId);
  const errors = [];
  if (!Number.isInteger(limit) || limit < 1 || limit > 80) errors.push("limit");
  if (query.beforeId != null && beforeId == null) errors.push("beforeId");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: Math.min(80, Math.max(1, Number.isInteger(limit) ? limit : 40)),
      beforeId,
    },
  };
}

export function validateSendMessage(body = {}) {
  const text = asTrimmed(body.body);
  const errors = [];
  if (!text) errors.push("body");
  if (text.length > 1200) errors.push("body_length");
  return {
    ok: errors.length === 0,
    errors,
    value: { body: text },
  };
}

export function validateMessageReaction(body = {}) {
  const reaction = asTrimmed(body.reaction).toLowerCase() || "like";
  const errors = [];
  if (!["like", "heart", "laugh", "fire"].includes(reaction)) {
    errors.push("reaction");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: { reaction },
  };
}

export function validateUpdateSocialProfile(body = {}, opts = {}) {
  const errors = [];
  const hasImageUpload = opts?.hasImageUpload === true;
  const hasFullName =
    body.fullName !== undefined && body.fullName !== null && String(body.fullName).trim().length > 0;
  const hasBio = body.bio !== undefined && body.bio !== null;
  const hasImageUrl =
    body.imageUrl !== undefined && body.imageUrl !== null && String(body.imageUrl).trim().length > 0;
  const hasShowPhone = body.showPhone !== undefined;
  const hasPostsPublic = body.postsPublic !== undefined;
  const hasStoriesPublic = body.storiesPublic !== undefined;
  const showPhone = asBooleanOrNull(body.showPhone);
  const postsPublic = asBooleanOrNull(body.postsPublic);
  const storiesPublic = asBooleanOrNull(body.storiesPublic);

  if (
    !hasFullName &&
    !hasBio &&
    !hasImageUrl &&
    !hasImageUpload &&
    !hasShowPhone &&
    !hasPostsPublic &&
    !hasStoriesPublic
  ) {
    errors.push("changes_required");
  }

  if (hasFullName && !isNonEmptyString(body.fullName, 120)) {
    errors.push("fullName");
  }

  if (hasBio && !isOptionalString(body.bio, 280)) {
    errors.push("bio");
  }

  if (hasImageUrl && !isOptionalString(body.imageUrl, 1000)) {
    errors.push("imageUrl");
  }
  if (hasShowPhone && showPhone == null) {
    errors.push("showPhone");
  }
  if (hasPostsPublic && postsPublic == null) {
    errors.push("postsPublic");
  }
  if (hasStoriesPublic && storiesPublic == null) {
    errors.push("storiesPublic");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      fullName: hasFullName ? String(body.fullName).trim() : undefined,
      bio: hasBio ? String(body.bio || "").trim() : undefined,
      imageUrl: hasImageUrl ? String(body.imageUrl).trim() : undefined,
      showPhone: hasShowPhone ? showPhone : undefined,
      postsPublic: hasPostsPublic ? postsPublic : undefined,
      storiesPublic: hasStoriesPublic ? storiesPublic : undefined,
    },
  };
}

export function validateHighlightStory(body = {}) {
  const title = asTrimmed(body.title);
  const errors = [];
  if (title.length > 60) errors.push("title");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      title: title || null,
    },
  };
}

export function validateHighlightId(highlightId) {
  const value = asPositiveInt(highlightId);
  return {
    ok: value != null,
    errors: value == null ? ["highlightId"] : [],
    value,
  };
}

export function validateRelationListQuery(query = {}) {
  const errors = [];
  const limit = Number(query.limit ?? 80);
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: Math.min(200, Math.max(1, Number.isInteger(limit) ? limit : 80)),
    },
  };
}

export function validateThreadCallStateQuery(query = {}) {
  const errors = [];
  const signalLimit = Number(query.signalLimit ?? 160);
  if (!Number.isInteger(signalLimit) || signalLimit < 1 || signalLimit > 800) {
    errors.push("signalLimit");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      signalLimit: Math.min(
        800,
        Math.max(1, Number.isInteger(signalLimit) ? signalLimit : 160)
      ),
    },
  };
}

export function validateThreadCallSignal(body = {}) {
  const errors = [];
  const sessionId =
    body.sessionId == null || body.sessionId === ""
      ? null
      : asPositiveInt(body.sessionId);
  const signalType = asTrimmed(body.signalType).toLowerCase();
  const signalPayload =
    body.signalPayload && typeof body.signalPayload === "object"
      ? body.signalPayload
      : {};
  const allowedTypes = new Set([
    "offer",
    "answer",
    "ice",
    "accept",
    "decline",
    "hangup",
  ]);

  if (body.sessionId != null && sessionId == null) errors.push("sessionId");
  if (!allowedTypes.has(signalType)) errors.push("signalType");

  if (signalType === "offer" || signalType === "answer") {
    const sdp = String(signalPayload?.sdp || "").trim();
    const sdpType = String(signalPayload?.type || "").trim().toLowerCase();
    if (!sdp || sdp.length < 10) errors.push("signalPayload.sdp");
    if (!["offer", "answer"].includes(sdpType)) errors.push("signalPayload.type");
  }

  if (signalType === "ice") {
    const candidate = String(signalPayload?.candidate || "").trim();
    if (!candidate) errors.push("signalPayload.candidate");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      sessionId,
      signalType,
      signalPayload,
    },
  };
}

export function validateThreadCallEnd(body = {}) {
  const errors = [];
  const status = asTrimmed(body.status).toLowerCase() || "ended";
  const reason = asTrimmed(body.reason);
  const allowedStatus = new Set(["ended", "declined", "missed"]);
  if (!allowedStatus.has(status)) errors.push("status");
  if (reason.length > 80) errors.push("reason");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      status,
      reason: reason || null,
    },
  };
}
