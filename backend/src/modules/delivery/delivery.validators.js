import { validateBasmayaAddress } from "../../shared/utils/basmaya-address.js";

function isNonEmptyString(v, max = 200) {
  return typeof v === "string" && v.trim().length > 0 && v.trim().length <= max;
}

function isOptionalString(v, max = 1000) {
  return v === undefined || v === null || (typeof v === "string" && v.trim().length <= max);
}

function isExplicitTrue(value) {
  if (value === true) return true;
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes";
}

export function validateDeliveryRegister(body) {
  const errors = [];

  if (!isNonEmptyString(body.fullName, 120)) errors.push("fullName");
  if (!isNonEmptyString(body.phone, 20)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");
  if (!isNonEmptyString(body.block, 20)) errors.push("block");
  if (!isNonEmptyString(body.buildingNumber, 20)) errors.push("buildingNumber");
  if (!isNonEmptyString(body.apartment, 20)) errors.push("apartment");
  if (!isOptionalString(body.profileImageUrl, 1000)) errors.push("profileImageUrl");
  if (!isOptionalString(body.carImageUrl, 1000)) errors.push("carImageUrl");
  if (!isNonEmptyString(body.carMake, 80)) errors.push("carMake");
  if (!isNonEmptyString(body.carModel, 80)) errors.push("carModel");
  if (!isNonEmptyString(body.vehicleType, 60)) errors.push("vehicleType");
  if (!isOptionalString(body.carColor, 40)) errors.push("carColor");
  if (!isNonEmptyString(body.plateNumber, 40)) errors.push("plateNumber");
  if (!isOptionalString(body.plateGovernorate, 80)) errors.push("plateGovernorate");
  if (!isOptionalString(body.plateCategory, 40)) errors.push("plateCategory");
  if (!isOptionalString(body.plateLetter, 8)) errors.push("plateLetter");
  if (!isOptionalString(body.plateDigits, 20)) errors.push("plateDigits");
  if (!isExplicitTrue(body.analyticsConsentAccepted)) errors.push("analyticsConsentAccepted");
  if (!isOptionalString(body.analyticsConsentVersion, 32)) errors.push("analyticsConsentVersion");

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
    if (!addressValidation.ok) errors.push(...addressValidation.errors);
  }

  const carYear = Number(body.carYear);
  if (!Number.isInteger(carYear) || carYear < 1980 || carYear > 2035) {
    errors.push("carYear");
  }

  const pinStr = String(body.pin || "");
  if (!/^\d{4,8}$/.test(pinStr)) errors.push("pin_format");

  return { ok: errors.length === 0, errors };
}

export function validateStartDelivery(body) {
  const errors = [];
  if (
    body.estimatedDeliveryMinutes !== undefined &&
    !Number.isInteger(Number(body.estimatedDeliveryMinutes))
  ) {
    errors.push("estimatedDeliveryMinutes");
  }
  return { ok: errors.length === 0, errors };
}
