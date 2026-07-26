const STATUSES = new Set([
  "DRAFT",
  "AWAITING_CUSTOMER",
  "AWAITING_MERCHANT",
  "AWAITING_BOTH",
  "APPROVED",
  "APPLYING",
  "APPLIED",
  "REJECTED",
  "CANCELLED",
  "EXPIRED",
  "FAILED",
]);

function text(value, max = 1000) {
  if (value == null) return "";
  return String(value).trim().slice(0, max);
}

function id(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : "INVALID";
}

function normalizeItem(raw, index, errors) {
  const productId = id(raw?.productId ?? raw?.product_id);
  const orderItemId = id(raw?.orderItemId ?? raw?.order_item_id);
  const variantId = id(raw?.variantId ?? raw?.variant_id ?? raw?.selectedVariantId);
  const quantity = Number(raw?.quantity);
  if (productId === "INVALID" || productId == null) errors.push(`items.${index}.productId`);
  if (orderItemId === "INVALID") errors.push(`items.${index}.orderItemId`);
  if (variantId === "INVALID") errors.push(`items.${index}.variantId`);
  if (!Number.isInteger(quantity) || quantity < 0) errors.push(`items.${index}.quantity`);
  return {
    orderItemId: orderItemId === "INVALID" ? null : orderItemId,
    productId: productId === "INVALID" ? null : productId,
    variantId: variantId === "INVALID" ? null : variantId,
    quantity: Number.isInteger(quantity) ? quantity : 0,
    selectedVariant: raw?.selectedVariant && typeof raw.selectedVariant === "object"
      ? raw.selectedVariant
      : null,
    selectedModifiers: Array.isArray(raw?.selectedModifiers)
      ? raw.selectedModifiers
      : [],
    note: text(raw?.note ?? raw?.userNote, 1000) || null,
  };
}

export function validateCreateOrderRevision(body = {}) {
  const errors = [];
  const orderId = id(body.orderId ?? body.order_id);
  const reason = text(body.reason, 2000);
  if (orderId === "INVALID") errors.push("orderId");
  if (!reason) errors.push("reason");
  if (!Array.isArray(body.items) || body.items.length === 0) {
    errors.push("items");
  }
  const items = Array.isArray(body.items)
    ? body.items.map((item, index) => normalizeItem(item, index, errors))
    : [];
  const note =
    body.note === undefined ? undefined : text(body.note, 1000) || null;
  return {
    ok: errors.length === 0,
    errors,
    value: {
      orderId: orderId === "INVALID" ? null : orderId,
      reason,
      items,
      note,
      expiresInMinutes: Math.max(5, Math.min(1440, Number(body.expiresInMinutes) || 240)),
    },
  };
}

export function validatePatchOrderRevision(body = {}) {
  const errors = [];
  const patch = {};
  if (body.reason !== undefined) {
    patch.reason = text(body.reason, 2000);
    if (!patch.reason) errors.push("reason");
  }
  if (body.note !== undefined) {
    patch.note = text(body.note, 1000) || null;
  }
  if (body.items !== undefined) {
    if (!Array.isArray(body.items) || body.items.length === 0) {
      errors.push("items");
    } else {
      patch.items = body.items.map((item, index) => normalizeItem(item, index, errors));
    }
  }
  return { ok: errors.length === 0, errors, value: patch };
}

export function validateRevisionDecision(body = {}) {
  return {
    ok: true,
    errors: [],
    value: { note: text(body.note ?? body.reason, 1000) || null },
  };
}

export function validateRevisionStatus(status) {
  const value = text(status, 32).toUpperCase();
  return STATUSES.has(value) ? value : null;
}
