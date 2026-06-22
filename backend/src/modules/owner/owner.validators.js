import { validateBasmayaAddress } from "../../shared/utils/basmaya-address.js";

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

function isOptionalBool(v) {
  return v === undefined || v === null || typeof v === "boolean";
}

function isOptionalObject(v) {
  return v === undefined || v === null || (typeof v === "object" && !Array.isArray(v));
}

function isOptionalStringArray(v, maxItems = 30, maxLength = 80) {
  if (v === undefined || v === null) return true;
  if (!Array.isArray(v)) return false;
  if (v.length > maxItems) return false;
  return v.every((item) => typeof item === "string" && item.trim().length <= maxLength);
}

function isIsoDate(v) {
  if (v === undefined || v === null || v === "") return true;
  const d = new Date(v);
  return !Number.isNaN(d.getTime());
}

function isExplicitTrue(value) {
  if (value === true) return true;
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes";
}

export function validateOwnerRegister(body) {
  const errors = [];

  if (!isNonEmptyString(body.phone, 20)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");

  if (!isNonEmptyString(body.merchantName, 150)) errors.push("merchantName");
  if (
    body.merchantType !== undefined &&
    body.merchantType !== null &&
    body.merchantType !== "" &&
    !["restaurant", "market"].includes(String(body.merchantType).trim())
  ) {
    errors.push("merchantType");
  }
  // Store category is mandatory on owner self-registration — no legacy
  // merchant-type fallback / silent inference for new stores.
  if (!isNonEmptyString(body.merchantActivityType, 80)) {
    errors.push("merchantActivityType");
  }
  if (!isOptionalString(body.merchantDiscoverySubcategory, 120)) {
    errors.push("merchantDiscoverySubcategory");
  }
  if (!isOptionalStringArray(body.merchantDiscoverySubcategories, 40, 120)) {
    errors.push("merchantDiscoverySubcategories");
  }
  if (!isOptionalBool(body.merchantDiscoverySelectAll)) {
    errors.push("merchantDiscoverySelectAll");
  }
  if (!isOptionalObject(body.merchantServiceFlags)) errors.push("merchantServiceFlags");
  if (!isOptionalStringArray(body.merchantBadges, 30, 80)) errors.push("merchantBadges");
  if (!isOptionalBool(body.merchantSupportsChat)) errors.push("merchantSupportsChat");
  if (!isOptionalBool(body.merchantSupportsAttachments)) {
    errors.push("merchantSupportsAttachments");
  }
  if (!isOptionalBool(body.merchantSupportsPharmacyWorkflow)) {
    errors.push("merchantSupportsPharmacyWorkflow");
  }
  if (!isOptionalString(body.merchantDescription, 1000)) errors.push("merchantDescription");
  if (!isOptionalString(body.merchantPhone, 20)) errors.push("merchantPhone");
  if (!isOptionalString(body.merchantTagline, 160)) errors.push("merchantTagline");
  if (!isOptionalString(body.merchantWorkingHours, 160)) errors.push("merchantWorkingHours");
  if (!isOptionalString(body.merchantServiceAreaNote, 240)) errors.push("merchantServiceAreaNote");
  if (!isOptionalString(body.ownerImageUrl, 1000)) errors.push("ownerImageUrl");
  if (!isOptionalString(body.merchantImageUrl, 1000)) errors.push("merchantImageUrl");
  if (!isExplicitTrue(body.analyticsConsentAccepted)) errors.push("analyticsConsentAccepted");
  if (!isOptionalString(body.analyticsConsentVersion, 32)) errors.push("analyticsConsentVersion");

  const hasBlock = isNonEmptyString(body.block, 20);
  const hasBuilding = isNonEmptyString(body.buildingNumber, 20);
  const hasApartment = isNonEmptyString(body.apartment, 20);
  const addressFieldsCount = [hasBlock, hasBuilding, hasApartment].filter(Boolean).length;

  if (addressFieldsCount > 0 && addressFieldsCount < 3) {
    errors.push("block", "buildingNumber", "apartment");
  }

  if (addressFieldsCount === 3) {
    const addressValidation = validateBasmayaAddress({
      block: body.block,
      buildingNumber: body.buildingNumber,
      apartment: body.apartment,
    });
    if (!addressValidation.ok) errors.push(...addressValidation.errors);
  }

  const pinStr = String(body.pin || "");
  if (!/^\d{4,8}$/.test(pinStr)) errors.push("pin_format");

  return { ok: errors.length === 0, errors };
}

export function validateOwnerMerchantUpdate(body) {
  const errors = [];
  const hasAnyField =
    body.name !== undefined ||
    body.type !== undefined ||
    body.activityType !== undefined ||
    body.discoverySubcategory !== undefined ||
    body.discoverySubcategories !== undefined ||
    body.discoverySelectAll !== undefined ||
    body.description !== undefined ||
    body.phone !== undefined ||
    body.imageUrl !== undefined ||
    body.isOpen !== undefined ||
    body.tagline !== undefined ||
    body.workingHours !== undefined ||
    body.serviceAreaNote !== undefined ||
    body.serviceFlags !== undefined ||
    body.supportsChat !== undefined ||
    body.supportsAttachments !== undefined ||
    body.supportsPharmacyWorkflow !== undefined ||
    body.badges !== undefined;

  if (!hasAnyField) errors.push("empty_update");

  if (body.name !== undefined && !isNonEmptyString(body.name, 150)) errors.push("name");
  if (body.type !== undefined && !["restaurant", "market"].includes(body.type)) errors.push("type");
  if (body.activityType !== undefined && !isOptionalString(body.activityType, 80)) {
    errors.push("activityType");
  }
  if (
    body.discoverySubcategory !== undefined &&
    !isOptionalString(body.discoverySubcategory, 120)
  ) {
    errors.push("discoverySubcategory");
  }
  if (
    body.discoverySubcategories !== undefined &&
    !isOptionalStringArray(body.discoverySubcategories, 40, 120)
  ) {
    errors.push("discoverySubcategories");
  }
  if (body.discoverySelectAll !== undefined && !isOptionalBool(body.discoverySelectAll)) {
    errors.push("discoverySelectAll");
  }
  if (body.description !== undefined && !isOptionalString(body.description, 1000)) errors.push("description");
  if (body.phone !== undefined && !isOptionalString(body.phone, 20)) errors.push("phone");
  if (body.imageUrl !== undefined && !isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");
  if (body.tagline !== undefined && !isOptionalString(body.tagline, 160)) errors.push("tagline");
  if (body.workingHours !== undefined && !isOptionalString(body.workingHours, 160)) {
    errors.push("workingHours");
  }
  if (body.serviceAreaNote !== undefined && !isOptionalString(body.serviceAreaNote, 240)) {
    errors.push("serviceAreaNote");
  }
  if (body.isOpen !== undefined && typeof body.isOpen !== "boolean") errors.push("isOpen");
  if (body.serviceFlags !== undefined && !isOptionalObject(body.serviceFlags)) {
    errors.push("serviceFlags");
  }
  if (body.supportsChat !== undefined && !isOptionalBool(body.supportsChat)) {
    errors.push("supportsChat");
  }
  if (
    body.supportsAttachments !== undefined &&
    !isOptionalBool(body.supportsAttachments)
  ) {
    errors.push("supportsAttachments");
  }
  if (
    body.supportsPharmacyWorkflow !== undefined &&
    !isOptionalBool(body.supportsPharmacyWorkflow)
  ) {
    errors.push("supportsPharmacyWorkflow");
  }
  if (body.badges !== undefined && !isOptionalStringArray(body.badges, 30, 80)) {
    errors.push("badges");
  }

  return { ok: errors.length === 0, errors };
}

export function validateOwnerProductCreate(body) {
  const errors = [];

  if (!isNonEmptyString(body.name, 150)) errors.push("name");
  if (!isPositiveInt(body.categoryId)) errors.push("categoryId");
  if (!isValidPrice(body.price)) errors.push("price");
  if (body.discountedPrice !== undefined && body.discountedPrice !== null && body.discountedPrice !== "") {
    if (!isValidPrice(body.discountedPrice)) errors.push("discountedPrice");
  }
  if (!isOptionalString(body.description, 1000)) errors.push("description");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");
  if (body.freeDelivery !== undefined && typeof body.freeDelivery !== "boolean") errors.push("freeDelivery");
  if (!isOptionalString(body.offerLabel, 80)) errors.push("offerLabel");
  if (body.isAvailable !== undefined && typeof body.isAvailable !== "boolean") errors.push("isAvailable");
  if (
    body.requiresPrescription !== undefined &&
    typeof body.requiresPrescription !== "boolean"
  ) {
    errors.push("requiresPrescription");
  }
  if (
    body.requiresReview !== undefined &&
    typeof body.requiresReview !== "boolean"
  ) {
    errors.push("requiresReview");
  }
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
    body.requiresPrescription !== undefined ||
    body.requiresReview !== undefined ||
    body.sortOrder !== undefined;

  if (!hasAnyField) errors.push("empty_update");

  if (body.name !== undefined && !isNonEmptyString(body.name, 150)) errors.push("name");
  if (body.price !== undefined && !isValidPrice(body.price)) errors.push("price");
  if (body.discountedPrice !== undefined && body.discountedPrice !== null && body.discountedPrice !== "") {
    if (!isValidPrice(body.discountedPrice)) errors.push("discountedPrice");
  }
  if (body.description !== undefined && !isOptionalString(body.description, 1000)) errors.push("description");
  if (body.imageUrl !== undefined && !isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");
  if (body.categoryId !== undefined) {
    if (body.categoryId === null || body.categoryId === "") {
      errors.push("categoryId");
    } else if (!isPositiveInt(body.categoryId)) {
      errors.push("categoryId");
    }
  }
  if (body.freeDelivery !== undefined && typeof body.freeDelivery !== "boolean") errors.push("freeDelivery");
  if (body.offerLabel !== undefined && !isOptionalString(body.offerLabel, 80)) errors.push("offerLabel");
  if (body.isAvailable !== undefined && typeof body.isAvailable !== "boolean") errors.push("isAvailable");
  if (
    body.requiresPrescription !== undefined &&
    typeof body.requiresPrescription !== "boolean"
  ) {
    errors.push("requiresPrescription");
  }
  if (
    body.requiresReview !== undefined &&
    typeof body.requiresReview !== "boolean"
  ) {
    errors.push("requiresReview");
  }
  if (body.sortOrder !== undefined && !Number.isInteger(Number(body.sortOrder))) errors.push("sortOrder");

  return { ok: errors.length === 0, errors };
}

export function validateOwnerOfferCreate(body) {
  const errors = [];

  if (!isNonEmptyString(body.title, 160)) errors.push("title");
  if (!isOptionalString(body.description, 600)) errors.push("description");
  if (!["percentage", "fixed_amount", "buy_x_get_y"].includes(body.offerType)) {
    errors.push("offerType");
  }
  if (!["draft", "scheduled", "active", "disabled"].includes(String(body.status || "draft"))) {
    errors.push("status");
  }
  if (!Array.isArray(body.productIds) || body.productIds.length === 0) {
    errors.push("productIds");
  } else if (!body.productIds.every(isPositiveInt)) {
    errors.push("productIds");
  }
  if (!isIsoDate(body.startsAt)) errors.push("startsAt");
  if (!isIsoDate(body.endsAt)) errors.push("endsAt");
  if (body.maxUsage !== undefined && body.maxUsage !== null && body.maxUsage !== "") {
    if (!isPositiveInt(body.maxUsage)) errors.push("maxUsage");
  }

  if (body.offerType === "percentage" || body.offerType === "fixed_amount") {
    if (!isValidPrice(body.discountValue) || Number(body.discountValue) <= 0) {
      errors.push("discountValue");
    }
    if (body.offerType === "percentage" && Number(body.discountValue) > 100) {
      errors.push("discountValue");
    }
  }

  if (body.offerType === "buy_x_get_y") {
    if (!isPositiveInt(body.buyQuantity)) errors.push("buyQuantity");
    if (!isPositiveInt(body.getQuantity)) errors.push("getQuantity");
  }

  if (
    body.startsAt &&
    body.endsAt &&
    !Number.isNaN(new Date(body.startsAt).getTime()) &&
    !Number.isNaN(new Date(body.endsAt).getTime()) &&
    new Date(body.endsAt).getTime() < new Date(body.startsAt).getTime()
  ) {
    errors.push("endsAt");
  }

  return { ok: errors.length === 0, errors };
}

export function validateOwnerOfferUpdate(body) {
  const errors = [];
  const hasAnyField =
    body.title !== undefined ||
    body.description !== undefined ||
    body.offerType !== undefined ||
    body.discountValue !== undefined ||
    body.buyQuantity !== undefined ||
    body.getQuantity !== undefined ||
    body.startsAt !== undefined ||
    body.endsAt !== undefined ||
    body.status !== undefined ||
    body.maxUsage !== undefined ||
    body.productIds !== undefined;

  if (!hasAnyField) errors.push("empty_update");

  if (body.title !== undefined && !isNonEmptyString(body.title, 160)) errors.push("title");
  if (body.description !== undefined && !isOptionalString(body.description, 600)) {
    errors.push("description");
  }
  if (
    body.offerType !== undefined &&
    !["percentage", "fixed_amount", "buy_x_get_y"].includes(body.offerType)
  ) {
    errors.push("offerType");
  }
  if (
    body.status !== undefined &&
    !["draft", "scheduled", "active", "disabled"].includes(String(body.status || "").trim())
  ) {
    errors.push("status");
  }
  if (body.productIds !== undefined) {
    if (!Array.isArray(body.productIds) || !body.productIds.every(isPositiveInt)) {
      errors.push("productIds");
    }
  }
  if (!isIsoDate(body.startsAt)) errors.push("startsAt");
  if (!isIsoDate(body.endsAt)) errors.push("endsAt");
  if (body.maxUsage !== undefined && body.maxUsage !== null && body.maxUsage !== "") {
    if (!isPositiveInt(body.maxUsage)) errors.push("maxUsage");
  }
  if (body.discountValue !== undefined && body.discountValue !== null && body.discountValue !== "") {
    if (!isValidPrice(body.discountValue) || Number(body.discountValue) <= 0) {
      errors.push("discountValue");
    }
  }
  if (body.buyQuantity !== undefined && !isPositiveInt(body.buyQuantity)) {
    errors.push("buyQuantity");
  }
  if (body.getQuantity !== undefined && !isPositiveInt(body.getQuantity)) {
    errors.push("getQuantity");
  }

  if (
    body.startsAt &&
    body.endsAt &&
    !Number.isNaN(new Date(body.startsAt).getTime()) &&
    !Number.isNaN(new Date(body.endsAt).getTime()) &&
    new Date(body.endsAt).getTime() < new Date(body.startsAt).getTime()
  ) {
    errors.push("endsAt");
  }

  return { ok: errors.length === 0, errors };
}

export function validateOwnerOrderStatusUpdate(body) {
  const errors = [];

  const allowedStatuses = [
    "approved",
    "preparing",
    "ready_for_delivery",
    "on_the_way",
    "arrived",
    "delivered",
    "cancelled",
  ];
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
  const assignmentMode = String(body?.assignmentMode || "platform_delivery");
  if (!["platform_delivery", "merchant_delivery"].includes(assignmentMode)) {
    errors.push("assignmentMode");
  }
  if (
    assignmentMode === "platform_delivery" &&
    !Number.isInteger(Number(body?.deliveryUserId))
  ) {
    errors.push("deliveryUserId");
  }
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

export function validateOwnerDeliveryAgentCreate(body) {
  const errors = [];

  if (!isNonEmptyString(body.fullName, 120)) errors.push("fullName");
  if (!isNonEmptyString(body.phone, 20)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");

  const pinStr = String(body.pin || "");
  if (!/^\d{4,8}$/.test(pinStr)) errors.push("pin_format");

  return { ok: errors.length === 0, errors };
}

export function validateOwnerAccountantCreate(body) {
  const errors = [];

  if (!isNonEmptyString(body.fullName, 120)) errors.push("fullName");
  if (!isNonEmptyString(body.phone, 20)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");

  const pinStr = String(body.pin || "");
  if (!/^\d{4,8}$/.test(pinStr)) errors.push("pin_format");

  return { ok: errors.length === 0, errors };
}

export function validateOwnerHrCreate(body) {
  const errors = [];

  if (!isNonEmptyString(body.fullName, 120)) errors.push("fullName");
  if (!isNonEmptyString(body.phone, 20)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");

  const pinStr = String(body.pin || "");
  if (!/^\d{4,8}$/.test(pinStr)) errors.push("pin_format");

  return { ok: errors.length === 0, errors };
}

export function validateOwnerAssignExistingStaff(body) {
  const errors = [];
  const userId = Number(body?.userId);
  if (!Number.isInteger(userId) || userId <= 0) errors.push("userId");
  return { ok: errors.length === 0, errors };
}

export function validateOwnerStaffSearchQuery(query) {
  const errors = [];
  const search = query?.search == null ? "" : String(query.search).trim();
  const limit = Number(query?.limit ?? 100);
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      search,
      limit: Number.isInteger(limit) ? Math.max(1, Math.min(200, limit)) : 100,
    },
  };
}
