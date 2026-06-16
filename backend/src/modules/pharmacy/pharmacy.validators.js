const PHARMACY_CONVERSATION_STATUSES = new Set([
  "open",
  "awaiting_customer",
  "awaiting_pharmacy",
  "cart_proposed",
  "cart_revision_requested",
  "order_created",
  "in_preparation",
  "out_for_delivery",
  "completed",
  "closed_no_sale",
  "cancelled",
  "unavailable",
]);

const PHARMACY_ALLOWED_ATTACHMENT_MIME = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/pdf",
  "text/plain",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
]);

function toPositiveInt(value) {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}

function toOptionalText(value, max = 2000) {
  if (value === undefined || value === null) return null;
  const out = String(value).trim();
  if (!out.length) return null;
  return out.length <= max ? out : null;
}

function toOptionalBool(value) {
  if (value === undefined || value === null) return null;
  if (typeof value === "boolean") return value;
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  if (["true", "1", "yes", "on"].includes(normalized)) return true;
  if (["false", "0", "no", "off"].includes(normalized)) return false;
  return null;
}

function normalizeConversationStatus(value) {
  const out = String(value || "").trim().toLowerCase();
  return PHARMACY_CONVERSATION_STATUSES.has(out) ? out : null;
}

export function validateConversationCreate(body = {}) {
  const errors = {};
  const merchantId = toPositiveInt(body.merchantId ?? body.merchant_id);
  if (!merchantId) errors.merchantId = "REQUIRED";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      merchantId,
      initialMessage: toOptionalText(body.initialMessage ?? body.message, 4000),
      metadata:
        body.metadata && typeof body.metadata === "object" && !Array.isArray(body.metadata)
          ? body.metadata
          : {},
    },
  };
}

export function validateConversationListQuery(query = {}) {
  const status = normalizeConversationStatus(query.status);
  const bucket = String(query.bucket || "").trim().toLowerCase() || null;
  const q = toOptionalText(query.q ?? query.search, 120);
  const limitRaw = Number(query.limit);
  const limit = Number.isInteger(limitRaw)
    ? Math.max(1, Math.min(120, limitRaw))
    : 50;
  return {
    ok: true,
    errors: {},
    value: {
      status,
      bucket: ["active", "completed", "closed"].includes(bucket) ? bucket : null,
      q,
      limit,
    },
  };
}

export function validateSendMessage(body = {}) {
  const errors = {};
  const message = toOptionalText(body.message ?? body.text, 6000);
  if (!message) errors.message = "REQUIRED";
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      message,
      metadata:
        body.metadata && typeof body.metadata === "object" && !Array.isArray(body.metadata)
          ? body.metadata
          : {},
    },
  };
}

export function validateAttachmentUpload(file) {
  const errors = {};
  const mime = String(file?.mimetype || "").trim().toLowerCase();
  const size = Number(file?.size || 0);
  if (!mime || !PHARMACY_ALLOWED_ATTACHMENT_MIME.has(mime)) {
    errors.attachment = "INVALID_ATTACHMENT_TYPE";
  }
  if (!Number.isFinite(size) || size <= 0) {
    errors.attachment = "INVALID_ATTACHMENT_SIZE";
  } else if (size > 12 * 1024 * 1024) {
    errors.attachment = "ATTACHMENT_TOO_LARGE";
  }
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      mime,
      size,
    },
  };
}

function normalizeCartItem(raw = {}) {
  const productId = raw.productId == null ? null : toPositiveInt(raw.productId);
  const productName = toOptionalText(raw.productName ?? raw.name, 220);
  const quantity = toPositiveInt(raw.quantity);
  const unitPriceRaw = Number(raw.unitPrice ?? raw.price);
  const unitPrice = Number.isFinite(unitPriceRaw) && unitPriceRaw >= 0 ? unitPriceRaw : null;
  const requiresPrescription = toOptionalBool(raw.requiresPrescription);
  const requiresReview = toOptionalBool(raw.requiresReview);
  const note = toOptionalText(raw.note, 1200);
  const alternativeGroupId = toOptionalText(raw.alternativeGroupId, 80);
  return {
    productId,
    productName,
    quantity,
    unitPrice,
    requiresPrescription: requiresPrescription === true,
    requiresReview: requiresReview === true,
    note,
    alternativeGroupId,
    metadata:
      raw.metadata && typeof raw.metadata === "object" && !Array.isArray(raw.metadata)
        ? raw.metadata
        : {},
  };
}

export function validateCreateProposedCart(body = {}) {
  const errors = {};
  const itemsRaw = Array.isArray(body.items) ? body.items : [];
  if (!itemsRaw.length) {
    errors.items = "REQUIRED";
  }
  const items = itemsRaw.map(normalizeCartItem);
  for (let i = 0; i < items.length; i += 1) {
    const item = items[i];
    if (!item.productName) errors[`items.${i}.productName`] = "REQUIRED";
    if (!item.quantity) errors[`items.${i}.quantity`] = "INVALID_NUMBER";
    if (item.unitPrice == null) errors[`items.${i}.unitPrice`] = "INVALID_NUMBER";
  }
  const deliveryFeeRaw = Number(body.deliveryFee ?? body.delivery_fee ?? 0);
  const deliveryFee =
    Number.isFinite(deliveryFeeRaw) && deliveryFeeRaw >= 0 ? deliveryFeeRaw : null;
  if (deliveryFee == null) errors.deliveryFee = "INVALID_NUMBER";
  const expiresAtRaw = toOptionalText(body.expiresAt ?? body.expires_at, 120);
  let expiresAt = null;
  if (expiresAtRaw) {
    const parsed = new Date(expiresAtRaw);
    if (Number.isNaN(parsed.getTime())) errors.expiresAt = "INVALID_DATE";
    else expiresAt = parsed.toISOString();
  }
  const notes = toOptionalText(body.notes, 2000);
  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      items,
      deliveryFee: deliveryFee ?? 0,
      expiresAt,
      notes,
    },
  };
}

export function validateCartAction(payload = {}) {
  return {
    ok: true,
    errors: {},
    value: {
      note: toOptionalText(payload.note, 1200),
    },
  };
}

export function validateConvertToOrder(body = {}) {
  const note = toOptionalText(body.note, 1200);
  return {
    ok: true,
    errors: {},
    value: { note },
  };
}

export function validateIdParam(value, field = "id") {
  const id = toPositiveInt(value);
  if (!id) {
    return { ok: false, errors: { [field]: "INVALID_ID" }, value: null };
  }
  return { ok: true, errors: {}, value: id };
}
