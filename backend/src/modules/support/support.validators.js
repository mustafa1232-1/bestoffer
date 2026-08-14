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

const TICKET_CHANNELS = new Set(["app", "phone", "whatsapp", "email", "social", "other"]);
const CALL_OUTCOMES = new Set([
  "resolved_on_call",
  "needs_follow_up",
  "callback_requested",
  "transferred",
  "info_only",
]);
const PRESENCE_STATUSES = new Set(["available", "on_ticket", "acw", "break", "offline"]);
const CALLBACK_STATUSES = new Set(["scheduled", "completed", "cancelled", "missed"]);

// إنشاء تذكرة من قبل الموظف نيابةً عن العميل (توثيق مكالمة/تواصل خارجي).
export function validateAgentCreateTicket(body = {}) {
  const errors = {};
  const domain = text(body.domain, 24).toUpperCase();
  const type = text(body.type, 24).toUpperCase();
  const priority = text(body.priority, 12).toLowerCase() || "normal";
  const subject = text(body.subject, 240);
  const description = text(body.description, 5000);
  const channel = text(body.channel, 16).toLowerCase() || "phone";
  const callOutcome = text(body.callOutcome ?? body.call_outcome, 24).toLowerCase() || null;
  const internalNote = text(body.internalNote ?? body.internal_note, 5000) || null;
  const customerUserId = numberId(body.customerUserId ?? body.customer_user_id);
  const customerPhone = text(body.customerPhone ?? body.customer_phone, 32) || null;
  const entityType = validateEntityType(body.entityType ?? body.entity_type);
  const entityId = numberId(body.entityId ?? body.entity_id);
  const entityLabel = text(body.entityLabel ?? body.entity_label, 240) || null;
  const assignToSelf = body.assignToSelf === undefined ? true : body.assignToSelf === true;

  if (!isValidDomain(domain)) errors.domain = "INVALID";
  if (!isValidType(type)) errors.type = "INVALID";
  if (!isValidPriority(priority)) errors.priority = "INVALID";
  if (!subject) errors.subject = "REQUIRED";
  if (!TICKET_CHANNELS.has(channel)) errors.channel = "INVALID";
  if (callOutcome && !CALL_OUTCOMES.has(callOutcome)) errors.callOutcome = "INVALID";
  if (customerUserId === "INVALID") errors.customerUserId = "INVALID";
  // يلزم تحديد العميل: إما معرّف صحيح أو رقم هاتف.
  if ((customerUserId === null || customerUserId === "INVALID") && !customerPhone) {
    errors.customer = "REQUIRED";
  }
  if (entityType === "INVALID") errors.entityType = "INVALID";
  if (entityId === "INVALID") errors.entityId = "INVALID";

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      domain,
      type,
      priority,
      subject,
      description: description || null,
      channel,
      callOutcome,
      internalNote,
      customerUserId: customerUserId === "INVALID" ? null : customerUserId,
      customerPhone,
      entityType: entityType === "INVALID" ? null : entityType,
      entityId: entityId === "INVALID" ? null : entityId,
      entityLabel,
      assignToSelf,
    },
  };
}

export function validatePresence(body = {}) {
  const errors = {};
  const status = text(body.status, 16).toLowerCase() || "available";
  const team = text(body.team, 48) || null;
  const currentTicketId = numberId(body.currentTicketId ?? body.current_ticket_id);
  const rawSkillDomains = body.skillDomains ?? body.skill_domains;
  const rawDomains = Array.isArray(rawSkillDomains) ? rawSkillDomains : [];
  const skillDomains = rawDomains
    .map((item) => text(item, 24).toUpperCase())
    .filter(Boolean);
  if (!PRESENCE_STATUSES.has(status)) errors.status = "INVALID";
  if (currentTicketId === "INVALID") errors.currentTicketId = "INVALID";
  for (const domain of skillDomains) {
    if (!isValidDomain(domain)) {
      errors.skillDomains = "INVALID";
      break;
    }
  }
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      status,
      team,
      skillDomains,
      currentTicketId: currentTicketId === "INVALID" ? null : currentTicketId,
    },
  };
}

function optionalDomain(value) {
  const domain = text(value, 24).toUpperCase();
  if (!domain) return null;
  return isValidDomain(domain) ? domain : "INVALID";
}

function optionalType(value) {
  const type = text(value, 24).toUpperCase();
  if (!type) return null;
  return isValidType(type) ? type : "INVALID";
}

export function validateCannedResponse(body = {}) {
  const errors = {};
  const title = text(body.title, 160);
  const responseBody = text(body.body, 5000);
  const domain = optionalDomain(body.domain);
  const type = optionalType(body.type);
  if (!title) errors.title = "REQUIRED";
  if (!responseBody) errors.body = "REQUIRED";
  if (domain === "INVALID") errors.domain = "INVALID";
  if (type === "INVALID") errors.type = "INVALID";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      title,
      body: responseBody,
      domain: domain === "INVALID" ? null : domain,
      type: type === "INVALID" ? null : type,
      isActive: body.isActive === undefined ? true : body.isActive === true,
    },
  };
}

export function validateKnowledgeArticle(body = {}) {
  const errors = {};
  const title = text(body.title, 200);
  const articleBody = text(body.body, 15000);
  const domain = optionalDomain(body.domain);
  const rawTags = Array.isArray(body.tags) ? body.tags : [];
  const tags = rawTags.map((tag) => text(tag, 48)).filter(Boolean).slice(0, 20);
  if (!title) errors.title = "REQUIRED";
  if (!articleBody) errors.body = "REQUIRED";
  if (domain === "INVALID") errors.domain = "INVALID";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      title,
      body: articleBody,
      domain: domain === "INVALID" ? null : domain,
      tags,
      isPublished:
        body.isPublished === undefined ? true : body.isPublished === true,
    },
  };
}

export function validateCallback(body = {}) {
  const errors = {};
  const scheduledAtRaw = text(body.scheduledAt ?? body.scheduled_at, 64);
  const scheduledAtMs = scheduledAtRaw ? new Date(scheduledAtRaw).getTime() : NaN;
  const assignedUserId = numberId(body.assignedUserId ?? body.assigned_user_id);
  const phone = text(body.phone, 32) || null;
  const notes = text(body.notes, 3000) || null;
  if (!Number.isFinite(scheduledAtMs)) errors.scheduledAt = "INVALID";
  if (assignedUserId === "INVALID") errors.assignedUserId = "INVALID";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      scheduledAt: Number.isFinite(scheduledAtMs)
        ? new Date(scheduledAtMs).toISOString()
        : null,
      assignedUserId: assignedUserId === "INVALID" ? null : assignedUserId,
      phone,
      notes,
    },
  };
}

export function validateCallbackUpdate(body = {}) {
  const errors = {};
  const status = text(body.status, 16).toLowerCase();
  const notes = text(body.notes, 3000) || null;
  if (!CALLBACK_STATUSES.has(status)) errors.status = "INVALID";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: { status, notes },
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
