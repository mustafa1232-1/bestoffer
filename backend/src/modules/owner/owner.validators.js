function isNonEmptyString(v, max = 200) {
  return typeof v === "string" && v.trim().length > 0 && v.trim().length <= max;
}

function isOptionalString(v, max = 500) {
  return v === undefined || v === null || (typeof v === "string" && v.trim().length <= max);
}

function isValidPrice(v) {
  if (v === undefined || v === null || v === "") return false;
  const n = Number(v);
  return Number.isFinite(n) && n >= 0;
}

function isPositiveInt(v) {
  const n = Number(v);
  return Number.isInteger(n) && n > 0;
}

function isExplicitTrue(value) {
  if (value === true) return true;
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes";
}

export function validateOwnerRegister(body) {
  const errors = [];

  if (!isNonEmptyString(body.fullName, 120)) errors.push("fullName");
  if (!isNonEmptyString(body.phone, 20)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");
  if (!isNonEmptyString(body.block, 20)) errors.push("block");
  if (!isNonEmptyString(body.buildingNumber, 20)) errors.push("buildingNumber");
  if (!isNonEmptyString(body.apartment, 20)) errors.push("apartment");

  if (!isNonEmptyString(body.merchantName, 150)) errors.push("merchantName");
  if (!["restaurant", "market"].includes(body.merchantType)) errors.push("merchantType");
  if (!isOptionalString(body.merchantDescription, 1000)) errors.push("merchantDescription");
  if (!isOptionalString(body.merchantPhone, 20)) errors.push("merchantPhone");
  if (!isOptionalString(body.ownerImageUrl, 1000)) errors.push("ownerImageUrl");
  if (!isOptionalString(body.merchantImageUrl, 1000)) errors.push("merchantImageUrl");
  if (!isExplicitTrue(body.analyticsConsentAccepted)) errors.push("analyticsConsentAccepted");
  if (!isOptionalString(body.analyticsConsentVersion, 32)) errors.push("analyticsConsentVersion");

  const pinStr = String(body.pin || "");
  if (!/^\d{4,8}$/.test(pinStr)) errors.push("pin_format");

  return { ok: errors.length === 0, errors };
}

export function validateOwnerMerchantUpdate(body) {
  const errors = [];
  const hasAnyField =
    body.name !== undefined ||
    body.type !== undefined ||
    body.description !== undefined ||
    body.phone !== undefined ||
    body.imageUrl !== undefined ||
    body.isOpen !== undefined;

  if (!hasAnyField) errors.push("empty_update");

  if (body.name !== undefined && !isNonEmptyString(body.name, 150)) errors.push("name");
  if (body.type !== undefined && !["restaurant", "market"].includes(body.type)) errors.push("type");
  if (body.description !== undefined && !isOptionalString(body.description, 1000)) errors.push("description");
  if (body.phone !== undefined && !isOptionalString(body.phone, 20)) errors.push("phone");
  if (body.imageUrl !== undefined && !isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");
  if (body.isOpen !== undefined && typeof body.isOpen !== "boolean") errors.push("isOpen");

  return { ok: errors.length === 0, errors };
}

export function validateOwnerProductCreate(body) {
  const errors = [];

  if (!isNonEmptyString(body.name, 150)) errors.push("name");
  if (!isValidPrice(body.price)) errors.push("price");
  if (body.discountedPrice !== undefined && body.discountedPrice !== null && body.discountedPrice !== "") {
    if (!isValidPrice(body.discountedPrice)) errors.push("discountedPrice");
  }
  if (!isOptionalString(body.description, 1000)) errors.push("description");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");
  if (body.categoryId !== undefined && body.categoryId !== null && body.categoryId !== "") {
    if (!isPositiveInt(body.categoryId)) errors.push("categoryId");
  }
  if (body.freeDelivery !== undefined && typeof body.freeDelivery !== "boolean") errors.push("freeDelivery");
  if (!isOptionalString(body.offerLabel, 80)) errors.push("offerLabel");
  if (body.isAvailable !== undefined && typeof body.isAvailable !== "boolean") errors.push("isAvailable");
  if (body.sortOrder !== undefined && !Number.isInteger(Number(body.sortOrder))) errors.push("sortOrder");

  return { ok: errors.length === 0, errors };
}

export function validateOwnerProductUpdate(body) {
  const errors = [];
  const hasAnyField =
    body.name !== undefined ||
    body.description !== undefined ||
    body.price !== undefined ||
    body.discountedPrice !== undefined ||
    body.imageUrl !== undefined ||
    body.categoryId !== undefined ||
    body.freeDelivery !== undefined ||
    body.offerLabel !== undefined ||
    body.isAvailable !== undefined ||
    body.sortOrder !== undefined;

  if (!hasAnyField) errors.push("empty_update");

  if (body.name !== undefined && !isNonEmptyString(body.name, 150)) errors.push("name");
  if (body.price !== undefined && !isValidPrice(body.price)) errors.push("price");
  if (body.discountedPrice !== undefined && body.discountedPrice !== null && body.discountedPrice !== "") {
    if (!isValidPrice(body.discountedPrice)) errors.push("discountedPrice");
  }
  if (body.description !== undefined && !isOptionalString(body.description, 1000)) errors.push("description");
  if (body.imageUrl !== undefined && !isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");
  if (body.categoryId !== undefined && body.categoryId !== null && body.categoryId !== "") {
    if (!isPositiveInt(body.categoryId)) errors.push("categoryId");
  }
  if (body.freeDelivery !== undefined && typeof body.freeDelivery !== "boolean") errors.push("freeDelivery");
  if (body.offerLabel !== undefined && !isOptionalString(body.offerLabel, 80)) errors.push("offerLabel");
  if (body.isAvailable !== undefined && typeof body.isAvailable !== "boolean") errors.push("isAvailable");
  if (body.sortOrder !== undefined && !Number.isInteger(Number(body.sortOrder))) errors.push("sortOrder");

  return { ok: errors.length === 0, errors };
}

export function validateOwnerOrderStatusUpdate(body) {
  const errors = [];

  const allowedStatuses = ["preparing", "ready_for_delivery", "cancelled"];
  if (!allowedStatuses.includes(body.status)) errors.push("status");

  if (
    body.estimatedPrepMinutes !== undefined &&
    !Number.isInteger(Number(body.estimatedPrepMinutes))
  ) {
    errors.push("estimatedPrepMinutes");
  }

  if (
    body.estimatedDeliveryMinutes !== undefined &&
    !Number.isInteger(Number(body.estimatedDeliveryMinutes))
  ) {
    errors.push("estimatedDeliveryMinutes");
  }

  return { ok: errors.length === 0, errors };
}

export function validateOwnerAssignDelivery(body) {
  const errors = [];
  if (!Number.isInteger(Number(body.deliveryUserId))) errors.push("deliveryUserId");
  return { ok: errors.length === 0, errors };
}

export function validateOwnerCategoryCreate(body) {
  const errors = [];

  if (!isNonEmptyString(body.name, 120)) errors.push("name");
  if (body.sortOrder !== undefined && !Number.isInteger(Number(body.sortOrder))) errors.push("sortOrder");

  return { ok: errors.length === 0, errors };
}

export function validateOwnerCategoryUpdate(body) {
  const errors = [];
  const hasAnyField = body.name !== undefined || body.sortOrder !== undefined;

  if (!hasAnyField) errors.push("empty_update");
  if (body.name !== undefined && !isNonEmptyString(body.name, 120)) errors.push("name");
  if (body.sortOrder !== undefined && !Number.isInteger(Number(body.sortOrder))) errors.push("sortOrder");

  return { ok: errors.length === 0, errors };
}
