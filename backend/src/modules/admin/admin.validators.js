function isNonEmptyString(v, max = 200) {
  return typeof v === "string" && v.trim().length > 0 && v.trim().length <= max;
}

function isOptionalString(v, max = 1000) {
  return v === undefined || v === null || (typeof v === "string" && v.trim().length <= max);
}

const allowedRoles = [
  "user",
  "owner",
  "delivery",
  "deputy_admin",
  "call_center",
  "admin",
];

export function validateAdminCreateUser(body) {
  const errors = [];

  if (!isNonEmptyString(body.fullName, 120)) errors.push("fullName");
  if (!isNonEmptyString(body.phone, 20)) errors.push("phone");
  if (!isNonEmptyString(body.pin, 20)) errors.push("pin");
  if (!isNonEmptyString(body.block, 20)) errors.push("block");
  if (!isNonEmptyString(body.buildingNumber, 20)) errors.push("buildingNumber");
  if (!isNonEmptyString(body.apartment, 20)) errors.push("apartment");
  if (!allowedRoles.includes(body.role)) errors.push("role");
  if (!isOptionalString(body.imageUrl, 1000)) errors.push("imageUrl");

  const pinStr = String(body.pin || "");
  if (!/^\d{4,8}$/.test(pinStr)) errors.push("pin_format");

  return { ok: errors.length === 0, errors };
}

export function validateApproveSettlement(body) {
  const errors = [];
  if (
    body.adminNote !== undefined &&
    body.adminNote !== null &&
    (typeof body.adminNote !== "string" || body.adminNote.trim().length > 1000)
  ) {
    errors.push("adminNote");
  }
  return { ok: errors.length === 0, errors };
}

export function validateToggleMerchantDisabled(body) {
  const errors = [];
  if (typeof body.isDisabled !== "boolean") errors.push("isDisabled");
  return { ok: errors.length === 0, errors };
}
