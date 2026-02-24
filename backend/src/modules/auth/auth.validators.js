function isNonEmptyString(v, max = 200) {
  return typeof v === "string" && v.trim().length > 0 && v.trim().length <= max;
}

function isOptionalString(v, max = 1000) {
  return v === undefined || v === null || (typeof v === "string" && v.trim().length <= max);
}

function normalizeDigits(value) {
  return String(value || "")
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

export function validateRegister(body) {
  const errors = [];

  if (!isNonEmptyString(body.fullName, 120)) errors.push("fullName");
  if (!isNonEmptyString(body.phone, 20)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");
  if (!isNonEmptyString(body.block, 20)) errors.push("block");
  if (!isNonEmptyString(body.buildingNumber, 20)) errors.push("buildingNumber");
  if (!isNonEmptyString(body.apartment, 20)) errors.push("apartment");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");

  // PIN: نخليه 4-8 أرقام (تقدر تغير)
  const pinStr = normalizeDigits(body.pin).replace(/[^\d]/g, "");
  if (!/^\d{4,8}$/.test(pinStr)) errors.push("pin_format");

  return { ok: errors.length === 0, errors };
}

export function validateLogin(body) {
  const errors = [];
  const phoneStr = String(body.phone || "").trim();
  const pinStr = normalizeDigits(body.pin).replace(/[^\d]/g, "");

  if (!isNonEmptyString(phoneStr, 20)) errors.push("phone");
  if (!isNonEmptyString(pinStr, 20)) errors.push("pin");

  if (!/^\d{4,8}$/.test(pinStr)) errors.push("pin_format");

  return { ok: errors.length === 0, errors };
}

export function validateUpdateAccount(body) {
  const errors = [];

  const currentPin = normalizeDigits(body.currentPin).replace(/[^\d]/g, "");
  const hasPhone = typeof body.newPhone === "string" && body.newPhone.trim().length > 0;
  const hasPin = typeof body.newPin === "string" && body.newPin.trim().length > 0;
  const nextPin = normalizeDigits(body.newPin).replace(/[^\d]/g, "");

  if (!/^\d{4,8}$/.test(currentPin)) errors.push("currentPin");
  if (!hasPhone && !hasPin) errors.push("changes_required");

  if (hasPhone) {
    const phoneDigits = normalizeDigits(body.newPhone).replace(/[^\d]/g, "");
    if (phoneDigits.length < 8 || phoneDigits.length > 20) errors.push("newPhone");
  }

  if (hasPin && !/^\d{4,8}$/.test(nextPin)) errors.push("newPin");

  return { ok: errors.length === 0, errors };
}

export function validateAddressCreate(body) {
  const errors = [];

  if (!isNonEmptyString(body.label, 80)) errors.push("label");
  if (body.city !== undefined && !isOptionalString(body.city, 80)) errors.push("city");
  if (!isNonEmptyString(body.block, 20)) errors.push("block");
  if (!isNonEmptyString(body.buildingNumber, 20)) errors.push("buildingNumber");
  if (!isNonEmptyString(body.apartment, 20)) errors.push("apartment");
  if (
    body.isDefault !== undefined &&
    typeof body.isDefault !== "boolean"
  ) {
    errors.push("isDefault");
  }

  return { ok: errors.length === 0, errors };
}

export function validateAddressUpdate(body) {
  const errors = [];
  const hasAny =
    body.label !== undefined ||
    body.city !== undefined ||
    body.block !== undefined ||
    body.buildingNumber !== undefined ||
    body.apartment !== undefined ||
    body.isDefault !== undefined;

  if (!hasAny) errors.push("changes_required");

  if (body.label !== undefined && !isNonEmptyString(body.label, 80)) errors.push("label");
  if (body.city !== undefined && !isOptionalString(body.city, 80)) errors.push("city");
  if (body.block !== undefined && !isNonEmptyString(body.block, 20)) errors.push("block");
  if (body.buildingNumber !== undefined && !isNonEmptyString(body.buildingNumber, 20)) {
    errors.push("buildingNumber");
  }
  if (body.apartment !== undefined && !isNonEmptyString(body.apartment, 20)) {
    errors.push("apartment");
  }
  if (body.isDefault !== undefined && typeof body.isDefault !== "boolean") {
    errors.push("isDefault");
  }

  return { ok: errors.length === 0, errors };
}
