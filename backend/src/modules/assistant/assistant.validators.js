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
