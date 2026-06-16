function isOptionalPositiveInt(value) {
  if (value === undefined || value === null || value === "") return true;
  const n = Number(value);
  return Number.isInteger(n) && n > 0;
}

function isOptionalString(value, max = 1500) {
  return (
    value === undefined ||
    value === null ||
    (typeof value === "string" && value.trim().length <= max)
  );
}

export function validateChatBody(body) {
  const errors = [];

  const hasMessage = typeof body.message === "string" && body.message.trim().length > 0;
  const hasConfirm = body.confirmDraft === true;

  if (!hasMessage && !hasConfirm) {
    errors.push("message");
  }

  if (!isOptionalString(body.message, 1500)) errors.push("message");
  if (!isOptionalString(body.draftToken, 80)) errors.push("draftToken");
  if (!isOptionalString(body.note, 500)) errors.push("note");
  if (!isOptionalPositiveInt(body.sessionId)) errors.push("sessionId");
  if (!isOptionalPositiveInt(body.addressId)) errors.push("addressId");

  if (
    body.confirmDraft !== undefined &&
    body.confirmDraft !== null &&
    typeof body.confirmDraft !== "boolean"
  ) {
    errors.push("confirmDraft");
  }

  if (
    body.createDraft !== undefined &&
    body.createDraft !== null &&
    typeof body.createDraft !== "boolean"
  ) {
    errors.push("createDraft");
  }

  return { ok: errors.length === 0, errors };
}

export function validateSessionQuery(query) {
  const errors = [];
  if (!isOptionalPositiveInt(query.sessionId)) errors.push("sessionId");
  if (!isOptionalPositiveInt(query.limit)) errors.push("limit");
  return { ok: errors.length === 0, errors };
}

export function validateConfirmDraft(body) {
  const errors = [];
  if (!isOptionalPositiveInt(body.addressId)) errors.push("addressId");
  if (!isOptionalString(body.note, 500)) errors.push("note");
  if (!isOptionalPositiveInt(body.sessionId)) errors.push("sessionId");
  return { ok: errors.length === 0, errors };
}

const homeAudienceValues = new Set([
  "women",
  "men",
  "family",
  "mixed",
  "any",
]);
const homePriorityValues = new Set([
  "offers",
  "price",
  "speed",
  "rating",
  "balanced",
]);

function isOptionalEnum(value, allowedValues) {
  if (value === undefined || value === null || value === "") return true;
  if (typeof value !== "string") return false;
  return allowedValues.has(value.trim().toLowerCase());
}

function isOptionalStringList(value, { maxItems = 20, maxItemLength = 40 } = {}) {
  if (value === undefined || value === null) return true;
  if (!Array.isArray(value)) return false;
  if (value.length > maxItems) return false;
  return value.every(
    (entry) =>
      typeof entry === "string" &&
      entry.trim().length > 0 &&
      entry.trim().length <= maxItemLength
  );
}

export function validateHomePreferencesBody(body) {
  const errors = [];

  if (!isOptionalEnum(body.audience, homeAudienceValues)) errors.push("audience");
  if (!isOptionalEnum(body.priority, homePriorityValues)) errors.push("priority");
  if (!isOptionalStringList(body.interests, { maxItems: 24, maxItemLength: 48 })) {
    errors.push("interests");
  }
  if (
    body.completed !== undefined &&
    body.completed !== null &&
    typeof body.completed !== "boolean"
  ) {
    errors.push("completed");
  }

  return { ok: errors.length === 0, errors };
}

function parseLimit(value, fallback = 12, min = 1, max = 60) {
  if (value === undefined || value === null || value === "") return fallback;
  const n = Number(value);
  if (!Number.isInteger(n)) return fallback;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

export function validateRecommendJobsBody(body) {
  const errors = [];
  if (!isOptionalString(body?.query, 300)) errors.push("query");
  const limit = parseLimit(body?.limit, 12, 1, 40);
  return {
    ok: errors.length === 0,
    errors,
    value: {
      query: body?.query == null ? null : String(body.query).trim(),
      limit,
    },
  };
}

export function validateRecommendCommerceBody(body) {
  const errors = [];
  if (!isOptionalString(body?.query, 300)) errors.push("query");
  const kindRaw = String(body?.kind || "shopping").trim().toLowerCase();
  const kind = kindRaw === "restaurants" ? "restaurants" : "shopping";
  const limit = parseLimit(body?.limit, 12, 1, 60);
  return {
    ok: errors.length === 0,
    errors,
    value: {
      kind,
      query: body?.query == null ? null : String(body.query).trim(),
      limit,
    },
  };
}

function parseIntInRange(value, { fallback = null, min = 0, max = 100000 } = {}) {
  if (value === undefined || value === null || value === "") return fallback;
  const n = Number(value);
  if (!Number.isInteger(n)) return null;
  if (n < min || n > max) return null;
  return n;
}

function isOptionalBool(value) {
  return (
    value === undefined ||
    value === null ||
    typeof value === "boolean"
  );
}

function normalizeBool(value, fallback = false) {
  if (typeof value === "boolean") return value;
  if (value === undefined || value === null || value === "") return fallback;
  if (typeof value === "string") {
    const raw = value.trim().toLowerCase();
    if (["1", "true", "yes", "on"].includes(raw)) return true;
    if (["0", "false", "no", "off"].includes(raw)) return false;
  }
  return fallback;
}

function isOptionalObject(value) {
  return value === undefined || value === null || (typeof value === "object" && !Array.isArray(value));
}

function isOptionalStringArray(value, { maxItems = 120, maxItemLength = 180 } = {}) {
  if (value === undefined || value === null) return true;
  if (!Array.isArray(value)) return false;
  if (value.length > maxItems) return false;
  return value.every(
    (item) => typeof item === "string" && item.trim().length > 0 && item.trim().length <= maxItemLength
  );
}

function normalizeStringArray(value) {
  if (!Array.isArray(value)) return [];
  const out = [];
  for (const item of value) {
    const text = String(item || "").trim();
    if (!text) continue;
    if (!out.includes(text)) out.push(text);
  }
  return out;
}

function pickConsentFlags(input = {}) {
  const allowed = [
    "memoryEnabled",
    "profileStorage",
    "personalization",
    "adminReview",
    "improveModel",
  ];
  const out = {};
  for (const key of allowed) {
    if (!Object.prototype.hasOwnProperty.call(input || {}, key)) continue;
    if (typeof input[key] !== "boolean") continue;
    out[key] = input[key];
  }
  return out;
}

export function validateAiMemoryConsentBody(body) {
  const errors = [];
  const consent = body?.consentFlags;

  if (!isOptionalObject(consent)) {
    errors.push("consentFlags");
    return { ok: false, errors };
  }

  if (consent && typeof consent === "object") {
    const keys = [
      "memoryEnabled",
      "profileStorage",
      "personalization",
      "adminReview",
      "improveModel",
    ];
    for (const key of keys) {
      if (!isOptionalBool(consent[key])) errors.push(`consentFlags.${key}`);
    }
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      consentFlags: pickConsentFlags(consent || {}),
    },
  };
}

export function validateAiProfilePatchBody(body) {
  const errors = [];
  const value = {};

  const assignOptionalString = (key, maxLen = 180) => {
    if (!Object.prototype.hasOwnProperty.call(body || {}, key)) return;
    if (!isOptionalString(body?.[key], maxLen)) {
      errors.push(key);
      return;
    }
    value[key] = body?.[key] == null ? null : String(body[key]).trim();
  };

  assignOptionalString("displayName", 160);
  assignOptionalString("realName", 160);
  assignOptionalString("nickname", 160);
  assignOptionalString("preferredLanguage", 12);
  assignOptionalString("dialect", 32);
  assignOptionalString("gender", 20);
  assignOptionalString("ageRange", 40);
  assignOptionalString("city", 120);
  assignOptionalString("bioSummary", 4000);
  assignOptionalString("occupation", 160);
  assignOptionalString("personalityNotes", 4000);
  assignOptionalString("familyNotes", 4000);

  if (Object.prototype.hasOwnProperty.call(body || {}, "interests")) {
    if (!isOptionalStringArray(body?.interests, { maxItems: 120, maxItemLength: 180 })) {
      errors.push("interests");
    } else {
      value.interests = normalizeStringArray(body?.interests);
    }
  }

  if (Object.prototype.hasOwnProperty.call(body || {}, "goals")) {
    if (!isOptionalStringArray(body?.goals, { maxItems: 120, maxItemLength: 180 })) {
      errors.push("goals");
    } else {
      value.goals = normalizeStringArray(body?.goals);
    }
  }

  if (Object.prototype.hasOwnProperty.call(body || {}, "painPoints")) {
    if (!isOptionalStringArray(body?.painPoints, { maxItems: 120, maxItemLength: 220 })) {
      errors.push("painPoints");
    } else {
      value.painPoints = normalizeStringArray(body?.painPoints);
    }
  }

  if (Object.prototype.hasOwnProperty.call(body || {}, "preferences")) {
    if (!isOptionalObject(body?.preferences)) {
      errors.push("preferences");
    } else {
      value.preferences = body?.preferences || {};
    }
  }

  if (Object.prototype.hasOwnProperty.call(body || {}, "consentFlags")) {
    const consent = validateAiMemoryConsentBody({ consentFlags: body?.consentFlags });
    if (!consent.ok) {
      errors.push(...consent.errors);
    } else {
      value.consentFlags = consent.value.consentFlags;
    }
  }

  if (Object.keys(value).length === 0) {
    errors.push("emptyBody");
  }

  return {
    ok: errors.length === 0,
    errors,
    value,
  };
}

export function validateAiConversationListQuery(query) {
  const errors = [];
  const limit = parseIntInRange(query?.limit, { fallback: 20, min: 1, max: 200 });
  const offset = parseIntInRange(query?.offset, { fallback: 0, min: 0, max: 500000 });
  if (limit == null) errors.push("limit");
  if (offset == null) errors.push("offset");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: limit ?? 20,
      offset: offset ?? 0,
    },
  };
}

export function validateAiConversationMessagesQuery(query) {
  const errors = [];
  const messageLimit = parseIntInRange(query?.messageLimit, {
    fallback: 120,
    min: 1,
    max: 400,
  });
  const beforeId = parseIntInRange(query?.beforeId, {
    fallback: null,
    min: 1,
    max: 1000000000,
  });
  if (messageLimit == null) errors.push("messageLimit");
  if (
    query?.beforeId !== undefined &&
    query?.beforeId !== null &&
    query?.beforeId !== "" &&
    beforeId == null
  ) {
    errors.push("beforeId");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      messageLimit: messageLimit ?? 120,
      beforeId,
    },
  };
}

export function validateAiMemoryListQuery(query) {
  const errors = [];
  const limit = parseIntInRange(query?.limit, { fallback: 120, min: 1, max: 500 });
  const offset = parseIntInRange(query?.offset, { fallback: 0, min: 0, max: 500000 });
  const activeOnly = normalizeBool(query?.activeOnly, true);
  const memoryType =
    query?.memoryType === undefined || query?.memoryType === null || query?.memoryType === ""
      ? null
      : String(query.memoryType).trim();
  if (limit == null) errors.push("limit");
  if (offset == null) errors.push("offset");
  if (memoryType != null && memoryType.length > 40) errors.push("memoryType");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: limit ?? 120,
      offset: offset ?? 0,
      activeOnly,
      memoryType,
    },
  };
}

export function validateAiMemoryClearQuery(query) {
  const errors = [];
  const activeOnly = normalizeBool(query?.activeOnly, false);
  const memoryType =
    query?.memoryType === undefined || query?.memoryType === null || query?.memoryType === ""
      ? null
      : String(query.memoryType).trim();

  if (memoryType != null && memoryType.length > 40) errors.push("memoryType");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      activeOnly,
      memoryType,
    },
  };
}

export function validateAiMemoryCreateBody(body) {
  const errors = [];
  if (!isOptionalString(body?.memoryType, 40)) errors.push("memoryType");
  if (!isOptionalString(body?.memoryKey, 120)) errors.push("memoryKey");
  if (!isOptionalString(body?.memoryValue, 4000) || !String(body?.memoryValue || "").trim()) {
    errors.push("memoryValue");
  }
  if (
    body?.confidenceScore !== undefined &&
    body?.confidenceScore !== null &&
    (Number(body.confidenceScore) < 0 || Number(body.confidenceScore) > 1)
  ) {
    errors.push("confidenceScore");
  }
  if (!isOptionalPositiveInt(body?.sourceConversationId)) errors.push("sourceConversationId");
  if (!isOptionalPositiveInt(body?.sourceMessageId)) errors.push("sourceMessageId");
  if (!isOptionalBool(body?.isActive)) errors.push("isActive");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      memoryType: body?.memoryType,
      memoryKey: body?.memoryKey,
      memoryValue: String(body?.memoryValue || "").trim(),
      confidenceScore:
        body?.confidenceScore == null ? null : Number(body.confidenceScore),
      sourceConversationId: body?.sourceConversationId,
      sourceMessageId: body?.sourceMessageId,
      isActive: body?.isActive,
    },
  };
}

export function validateAiMemoryUpdateBody(body) {
  const errors = [];
  const value = {};
  if (Object.prototype.hasOwnProperty.call(body || {}, "memoryType")) {
    if (!isOptionalString(body?.memoryType, 40)) errors.push("memoryType");
    else value.memoryType = body?.memoryType;
  }
  if (Object.prototype.hasOwnProperty.call(body || {}, "memoryKey")) {
    if (!isOptionalString(body?.memoryKey, 120)) errors.push("memoryKey");
    else value.memoryKey = body?.memoryKey;
  }
  if (Object.prototype.hasOwnProperty.call(body || {}, "memoryValue")) {
    if (!isOptionalString(body?.memoryValue, 4000)) errors.push("memoryValue");
    else value.memoryValue = body?.memoryValue;
  }
  if (Object.prototype.hasOwnProperty.call(body || {}, "confidenceScore")) {
    const n = Number(body?.confidenceScore);
    if (!Number.isFinite(n) || n < 0 || n > 1) errors.push("confidenceScore");
    else value.confidenceScore = n;
  }
  if (Object.prototype.hasOwnProperty.call(body || {}, "isActive")) {
    if (!isOptionalBool(body?.isActive)) errors.push("isActive");
    else value.isActive = body?.isActive === true;
  }
  if (Object.keys(value).length === 0) errors.push("emptyBody");
  return { ok: errors.length === 0, errors, value };
}

export function validateAiTopicsQuery(query) {
  const errors = [];
  const limit = parseIntInRange(query?.limit, { fallback: 80, min: 1, max: 500 });
  if (limit == null) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: limit ?? 80,
    },
  };
}

export function validateAssistantAppSearchBody(body) {
  const errors = [];
  const kind = String(body?.kind || "commerce").trim().toLowerCase();
  if (!["commerce", "shopping", "restaurants", "jobs"].includes(kind)) {
    errors.push("kind");
  }
  if (!isOptionalString(body?.query, 600)) errors.push("query");
  const limit = parseIntInRange(body?.limit, { fallback: 12, min: 1, max: 50 });
  if (limit == null) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      kind,
      query: body?.query == null ? null : String(body.query).trim(),
      limit: limit ?? 12,
    },
  };
}

export function validateAssistantWebSearchBody(body) {
  const errors = [];
  const query = String(body?.query || "").trim();
  if (!query) errors.push("query");
  if (!isOptionalString(body?.query, 600)) errors.push("query");
  const language =
    body?.language === undefined || body?.language === null
      ? "ar"
      : String(body.language).trim().toLowerCase();
  if (language.length > 8) errors.push("language");
  const limit = parseIntInRange(body?.limit, { fallback: 5, min: 1, max: 10 });
  if (limit == null) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      query,
      language,
      limit: limit ?? 5,
    },
  };
}
