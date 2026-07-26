import {
  isValidDomain,
  isValidType,
  isValidPriority,
  TICKET_STATUSES,
} from "./support.policy.js";

const ENTITY_TYPES = new Set([
  "order",
  "invoice",
  "ride",
  "service",
  "listing",
  "job",
  "post",
  "story",
  "reel",
  "user",
  "merchant",
  "delivery_job",
  "other",
]);

function text(value, max) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function numberId(value) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : "INVALID";
}

function validateAttachments(value) {
  const errors = [];
  const rows = [];
  if (value === undefined || value === null) return { ok: true, errors, value: rows };
  if (!Array.isArray(value)) return { ok: false, errors: ["attachments"], value: rows };
  if (value.length > 10) return { ok: false, errors: ["attachments.max"], value: rows };

  value.forEach((raw, index) => {
    if (!raw || typeof raw !== "object") {
      errors.push(`attachments.${index}`);
      return;
    }
    const fileUrl = text(raw.fileUrl ?? raw.file_url, 2000);
    const visibilityRaw = text(raw.visibility, 16).toLowerCase();
    const visibility = visibilityRaw === "internal" ? "internal" : "customer";
    const size =
      raw.fileSizeBytes !== undefined || raw.file_size_bytes !== undefined
        ? Number(raw.fileSizeBytes ?? raw.file_size_bytes)
        : null;
    if (!fileUrl) errors.push(`attachments.${index}.fileUrl`);
    if (size !== null && (!Number.isFinite(size) || size < 0)) {
      errors.push(`attachments.${index}.fileSizeBytes`);
    }
    rows.push({
      visibility,
      fileUrl,
      storageKey: text(raw.storageKey ?? raw.storage_key, 1000) || null,
      fileName: text(raw.fileName ?? raw.file_name, 255) || null,
      mimeType: text(raw.mimeType ?? raw.mime_type, 120) || null,
      fileSizeBytes: size,
      metadata: raw.metadata && typeof raw.metadata === "object" ? raw.metadata : {},
    });
  });
  return { ok: errors.length === 0, errors, value: rows };
}

function validateEntityType(value) {
  const entityType = text(value, 48).toLowerCase();
  if (!entityType) return null;
  return ENTITY_TYPES.has(entityType) ? entityType : "INVALID";
}

export function validateCreateTicket(body = {}) {
  const errors = {};
  const domain = text(body.domain, 24).toUpperCase();
  const type = text(body.type, 24).toUpperCase();
  const priority = text(body.priority, 12).toLowerCase() || "normal";
  const subject = text(body.subject, 240);
  const description = text(body.description, 5000);
  const entityType = validateEntityType(body.entityType ?? body.entity_type);
  const entityId = numberId(body.entityId ?? body.entity_id);
  const entityLabel = text(body.entityLabel ?? body.entity_label, 240) || null;
  const attachments = validateAttachments(body.attachments);

  if (!isValidDomain(domain)) errors.domain = "INVALID";
  if (!isValidType(type)) errors.type = "INVALID";
  if (!isValidPriority(priority)) errors.priority = "INVALID";
  if (!subject) errors.subject = "REQUIRED";
  if (entityType === "INVALID") errors.entityType = "INVALID";
  if (entityId === "INVALID") errors.entityId = "INVALID";
  if (!attachments.ok) errors.attachments = attachments.errors;

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      domain,
      type,
      priority,
      subject,
      description: description || null,
      entityType,
      entityId: entityId === "INVALID" ? null : entityId,
      entityLabel,
      attachments: attachments.value,
    },
  };
}

export function validateMessage(body = {}) {
  const errors = {};
  const bodyText = text(body.body, 5000);
  const attachments = validateAttachments(body.attachments);
  if (!bodyText && attachments.value.length === 0) errors.body = "REQUIRED";
  if (!attachments.ok) errors.attachments = attachments.errors;
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      body: bodyText,
      isInternal: body.isInternal === true || body.internal === true,
      attachments: attachments.value,
    },
  };
}

export function validateResolve(body = {}) {
  const errors = {};
  const summary = text(body.summary, 5000);
  const reason = text(body.reason, 64) || null;
  if (!summary) errors.summary = "REQUIRED";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: { summary, reason },
  };
}

export function validateTransition(body = {}) {
  const errors = {};
  const toStatus = text(body.toStatus ?? body.status, 28).toUpperCase();
  if (!TICKET_STATUSES.includes(toStatus)) errors.toStatus = "INVALID";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: { toStatus },
  };
}

export function validateAssign(body = {}) {
  const errors = {};
  const assigneeUserId = numberId(body.assigneeUserId ?? body.assignee_user_id);
  const team = text(body.team, 48) || null;
  if (assigneeUserId === "INVALID") errors.assigneeUserId = "INVALID";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: { assigneeUserId: assigneeUserId === "INVALID" ? null : assigneeUserId, team },
  };
}

export function validateLinkEntity(body = {}) {
  const errors = {};
  const entityType = validateEntityType(body.entityType ?? body.entity_type);
  const entityId = numberId(body.entityId ?? body.entity_id);
  const label = text(body.label, 240) || null;
  const reason = text(body.reason, 500) || null;
  if (!entityType || entityType === "INVALID") errors.entityType = "INVALID";
  if (entityId === "INVALID" || entityId === null) errors.entityId = "INVALID";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      entityType: entityType === "INVALID" ? null : entityType,
      entityId: entityId === "INVALID" ? null : entityId,
      label,
      reason,
    },
  };
}

export function validateRating(body = {}) {
  const errors = {};
  const rating = Number(body.rating);
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    errors.rating = "SELECT_OPTION";
  }
  const opt = (v) => {
    if (v === undefined || v === null || v === "") return null;
    const n = Number(v);
    return Number.isInteger(n) && n >= 1 && n <= 5 ? n : "INVALID";
  };
  const speed = opt(body.speed);
  const quality = opt(body.quality);
  if (speed === "INVALID") errors.speed = "INVALID";
  if (quality === "INVALID") errors.quality = "INVALID";
  const comment = text(body.comment, 2000) || null;
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      rating,
      speed: speed === "INVALID" ? null : speed,
      quality: quality === "INVALID" ? null : quality,
      comment,
    },
  };
}
