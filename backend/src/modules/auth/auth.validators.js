import { validateBasmayaAddress } from "../../shared/utils/basmaya-address.js";

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

function isExplicitTrue(value) {
  if (value === true) return true;
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes";
}

export function validateRegister(body) {
  const errors = [];

  if (!isNonEmptyString(body.fullName, 120)) errors.push("fullName");
  if (!isNonEmptyString(body.phone, 20)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");
  if (!isNonEmptyString(body.block, 20)) errors.push("block");
  if (!isNonEmptyString(body.buildingNumber, 20)) errors.push("buildingNumber");
  if (!isNonEmptyString(body.apartment, 20)) errors.push("apartment");
  if (!isOptionalString(body.workTitle, 160)) errors.push("workTitle");
  if (!isOptionalString(body.workCompany, 180)) errors.push("workCompany");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");
  if (!isExplicitTrue(body.analyticsConsentAccepted)) {
    errors.push("analyticsConsentAccepted");
  }
  if (!isOptionalString(body.analyticsConsentVersion, 32)) {
    errors.push("analyticsConsentVersion");
  }

  if (
    isNonEmptyString(body.block, 20) &&
    isNonEmptyString(body.buildingNumber, 20) &&
    isNonEmptyString(body.apartment, 20)
  ) {
    const addressValidation = validateBasmayaAddress({
      block: body.block,
      buildingNumber: body.buildingNumber,
      apartment: body.apartment,
    });
    if (!addressValidation.ok) {
      errors.push(...addressValidation.errors);
    }
  }

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

export function validateRefreshSession(body) {
  const errors = [];
  const refreshToken = String(body?.refreshToken || body?.refresh_token || "").trim();
  if (refreshToken.length < 24 || refreshToken.length > 256) {
    errors.push("refreshToken");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: { refreshToken },
  };
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

  if (
    isNonEmptyString(body.block, 20) &&
    isNonEmptyString(body.buildingNumber, 20) &&
    isNonEmptyString(body.apartment, 20)
  ) {
    const addressValidation = validateBasmayaAddress({
      block: body.block,
      buildingNumber: body.buildingNumber,
      apartment: body.apartment,
    });
    if (!addressValidation.ok) {
      errors.push(...addressValidation.errors);
    }
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

  if (
    isNonEmptyString(body.block, 20) &&
    isNonEmptyString(body.buildingNumber, 20) &&
    isNonEmptyString(body.apartment, 20)
  ) {
    const addressValidation = validateBasmayaAddress({
      block: body.block,
      buildingNumber: body.buildingNumber,
      apartment: body.apartment,
    });
    if (!addressValidation.ok) {
      errors.push(...addressValidation.errors);
    }
  }

  return { ok: errors.length === 0, errors };
}

function isOptionalNumericString(v, minLen = 1, maxLen = 40) {
  if (v === undefined || v === null || v === "") return true;
  const out = normalizeDigits(v).replace(/[^\d]/g, "");
  return out.length >= minLen && out.length <= maxLen;
}

function isOptionalTown(v) {
  if (v === undefined || v === null || v === "") return true;
  return /^[A-Za-z]$/.test(String(v).trim());
}

function isOptionalIsoOrDmyDate(v) {
  if (v === undefined || v === null || v === "") return true;
  const text = normalizeDigits(String(v).trim());
  return /^\d{4}-\d{2}-\d{2}$/.test(text) || /^\d{1,2}[\/\-.]\d{1,2}[\/\-.]\d{4}$/.test(text);
}

export function validateRegisterWithCard(body) {
  const base = validateRegister(body || {});
  const errors = [...base.errors];

  if (!isOptionalString(body.documentType, 40)) errors.push("documentType");
  if (!isOptionalString(body.full_name ?? body.fullName, 180)) errors.push("full_name");
  if (!isOptionalTown(body.town)) errors.push("town");
  if (!isOptionalNumericString(body.building_number ?? body.buildingNumber, 1, 24)) {
    errors.push("building_number");
  }
  if (!isOptionalIsoOrDmyDate(body.issue_date ?? body.issueDate)) errors.push("issue_date");
  if (!isOptionalNumericString(body.contract_number ?? body.contractNumber, 3, 40)) {
    errors.push("contract_number");
  }
  if (!isOptionalNumericString(body.floor_number ?? body.floorNumber, 1, 24)) {
    errors.push("floor_number");
  }
  if (!isOptionalNumericString(body.apartment_number ?? body.apartmentNumber, 1, 24)) {
    errors.push("apartment_number");
  }
  if (!isOptionalNumericString(body.visible_id_number ?? body.visibleIdNumber, 2, 40)) {
    errors.push("visible_id_number");
  }
  if (!isOptionalString(body.cardImageUrl, 1000)) errors.push("cardImageUrl");
  if (
    body.extractionConfidence !== undefined &&
    body.extractionConfidence !== null &&
    !Number.isFinite(Number(body.extractionConfidence))
  ) {
    errors.push("extractionConfidence");
  }

  return { ok: errors.length === 0, errors };
}
