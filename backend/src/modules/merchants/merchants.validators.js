function isNonEmptyString(v, max = 200) {
  return typeof v === "string" && v.trim().length > 0 && v.trim().length <= max;
}

function isOptionalString(v, max = 500) {
  return v === undefined || v === null || (typeof v === "string" && v.trim().length <= max);
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

function isOptionalStringArray(v, maxItems = 24, maxItemLength = 80) {
  if (v === undefined || v === null) return true;
  if (!Array.isArray(v)) return false;
  if (v.length > maxItems) return false;
  return v.every((item) => typeof item === "string" && item.trim().length <= maxItemLength);
}

export function validateCreateMerchant(body) {
  const errors = [];

  if (!isNonEmptyString(body.name, 150)) errors.push("name");
  if (!["restaurant", "market"].includes(body.type)) errors.push("type");
  // Activity (real store category) is mandatory on creation — no silent default.
  if (!isNonEmptyString(body.activityType, 80)) errors.push("activityType");
  if (!isOptionalString(body.discoverySubcategory, 120)) {
    errors.push("discoverySubcategory");
  }
  if (!isOptionalStringArray(body.discoverySubcategories, 40, 120)) {
    errors.push("discoverySubcategories");
  }
  if (!isOptionalBool(body.discoverySelectAll)) {
    errors.push("discoverySelectAll");
  }
  if (!isOptionalString(body.description, 1000)) errors.push("description");
  if (!isOptionalString(body.phone, 20)) errors.push("phone");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");
  if (!isOptionalObject(body.serviceFlags)) errors.push("serviceFlags");
  if (!isOptionalStringArray(body.badges, 30, 80)) errors.push("badges");
  if (!isOptionalBool(body.supportsChat)) errors.push("supportsChat");
  if (!isOptionalBool(body.supportsAttachments)) errors.push("supportsAttachments");
  if (!isOptionalBool(body.supportsPharmacyWorkflow)) {
    errors.push("supportsPharmacyWorkflow");
  }

  const hasOwnerUserId = body.ownerUserId !== undefined && body.ownerUserId !== null && body.ownerUserId !== "";
  const hasOwnerObject = body.owner !== undefined && body.owner !== null;

  if (!hasOwnerUserId && !hasOwnerObject) errors.push("owner");
  if (hasOwnerUserId && hasOwnerObject) errors.push("owner_conflict");

  if (hasOwnerUserId && !isPositiveInt(body.ownerUserId)) {
    errors.push("ownerUserId");
  }

  if (hasOwnerObject) {
    const owner = body.owner;
    if (typeof owner !== "object") {
      errors.push("owner");
    } else {
      if (!isNonEmptyString(owner.fullName, 120)) errors.push("owner.fullName");
      if (!isNonEmptyString(owner.phone, 20)) errors.push("owner.phone");
      if (!isNonEmptyString(owner.pin, 20)) errors.push("owner.pin");
      if (!isNonEmptyString(owner.block, 20)) errors.push("owner.block");
      if (!isNonEmptyString(owner.buildingNumber, 20)) errors.push("owner.buildingNumber");
      if (!isNonEmptyString(owner.apartment, 20)) errors.push("owner.apartment");
      if (!isOptionalString(owner.imageUrl, 1000)) errors.push("owner.imageUrl");

      const pinStr = String(owner.pin || "");
      if (!/^\d{4,8}$/.test(pinStr)) errors.push("owner.pin_format");
    }
  }

  return { ok: errors.length === 0, errors };
}
