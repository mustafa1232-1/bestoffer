function isNonEmptyString(v, max = 200) {
  return typeof v === "string" && v.trim().length > 0 && v.trim().length <= max;
}

function isOptionalString(v, max = 1000) {
  return v === undefined || v === null || (typeof v === "string" && v.trim().length <= max);
}

export function validateDeliveryRegister(body) {
  const errors = [];

  if (!isNonEmptyString(body.fullName, 120)) errors.push("fullName");
  if (!isNonEmptyString(body.phone, 20)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");
  if (!isNonEmptyString(body.block, 20)) errors.push("block");
  if (!isNonEmptyString(body.buildingNumber, 20)) errors.push("buildingNumber");
  if (!isNonEmptyString(body.apartment, 20)) errors.push("apartment");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");

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
