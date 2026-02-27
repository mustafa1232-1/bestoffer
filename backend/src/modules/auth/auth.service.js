import {
  createUser,
  createCustomerAddress,
  deactivateCustomerAddress,
  findUserByIdWithAuthFields,
  findUserByPhone,
  getCustomerDefaultAddress,
  getCustomerAddressById,
  listCustomerAddresses,
  setCustomerDefaultAddress,
  updateCustomerAddress,
  updateUserAccount,
} from "./auth.repo.js";
import { hashPin, verifyPin } from "../../shared/utils/hash.js";
import { signAccessToken } from "../../shared/utils/jwt.js";

function normalizeDigits(value) {
  return String(value || "")
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

function normalizePhone(value) {
  const digits = normalizeDigits(value).replace(/[^\d]/g, "");
  return digits;
}

function normalizePin(value) {
  return normalizeDigits(value).replace(/[^\d]/g, "");
}

function normalizeConsentAccepted(value) {
  if (value === true) return true;
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes";
}

function mapUser(u) {
  return {
    id: u.id,
    fullName: u.full_name,
    phone: u.phone,
    role: u.role,
    isSuperAdmin: u.is_super_admin === true,
    block: u.block,
    buildingNumber: u.building_number,
    apartment: u.apartment,
    imageUrl: u.image_url,
  };
}

export async function register(dto) {
  const phone = normalizePhone(dto.phone);
  const pin = normalizePin(dto.pin);
  const analyticsConsentAccepted = normalizeConsentAccepted(
    dto.analyticsConsentAccepted
  );
  const analyticsConsentVersion =
    typeof dto.analyticsConsentVersion === "string" &&
    dto.analyticsConsentVersion.trim().length > 0
      ? dto.analyticsConsentVersion.trim().slice(0, 32)
      : "analytics_v1";

  const exists = await findUserByPhone(phone);
  if (exists) {
    const err = new Error("PHONE_EXISTS");
    err.status = 409;
    throw err;
  }

  if (!analyticsConsentAccepted) {
    const err = new Error("ANALYTICS_CONSENT_REQUIRED");
    err.status = 400;
    throw err;
  }

  const pinHash = await hashPin(pin);

  const created = await createUser({
    fullName: dto.fullName.trim(),
    phone,
    pinHash,
    block: dto.block.trim(),
    buildingNumber: dto.buildingNumber.trim(),
    apartment: dto.apartment.trim(),
    imageUrl: dto.imageUrl || null,
    analyticsConsentGranted: true,
    analyticsConsentVersion,
    analyticsConsentGrantedAt: new Date(),
  });

  const token = signAccessToken({
    id: created.id,
    role: created.role || "user",
    isSuperAdmin: created.is_super_admin === true,
  });

  return { token, user: mapUser(created) };
}

export async function login({ phone, pin }) {
  const normalizedPhone = normalizePhone(phone);
  const normalizedPin = normalizePin(pin);

  const user = await findUserByPhone(normalizedPhone);
  if (!user) {
    const err = new Error("INVALID_CREDENTIALS");
    err.status = 401;
    throw err;
  }

  const ok = await verifyPin(normalizedPin, user.pin_hash);
  if (!ok) {
    const err = new Error("INVALID_CREDENTIALS");
    err.status = 401;
    throw err;
  }

  const token = signAccessToken({
    id: user.id,
    role: user.role || "user",
    isSuperAdmin: user.is_super_admin === true,
  });

  return {
    token,
    user: {
      id: user.id,
      fullName: user.full_name,
      phone: user.phone,
      role: user.role,
      isSuperAdmin: user.is_super_admin === true,
      block: user.block,
      buildingNumber: user.building_number,
      apartment: user.apartment,
      imageUrl: user.image_url,
    },
  };
}

export async function updateAccount(userId, dto) {
  const user = await findUserByIdWithAuthFields(userId);
  if (!user) {
    const err = new Error("USER_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const currentPin = normalizePin(dto.currentPin);
  const currentOk = await verifyPin(currentPin, user.pin_hash);
  if (!currentOk) {
    const err = new Error("INVALID_CURRENT_PIN");
    err.status = 401;
    throw err;
  }

  const nextPhoneRaw = dto.newPhone == null ? null : normalizePhone(dto.newPhone);
  const nextPinRaw = dto.newPin == null ? null : normalizePin(dto.newPin);

  const normalizedCurrentPhone = normalizePhone(user.phone);
  const nextPhone =
    typeof nextPhoneRaw === "string" && nextPhoneRaw.length > 0
      ? nextPhoneRaw
      : null;
  const nextPin =
    typeof nextPinRaw === "string" && nextPinRaw.length > 0 ? nextPinRaw : null;

  if (!nextPhone && !nextPin) {
    const err = new Error("NO_CHANGES");
    err.status = 400;
    throw err;
  }

  if (nextPhone && nextPhone !== normalizedCurrentPhone) {
    const exists = await findUserByPhone(nextPhone);
    if (exists && exists.id !== user.id) {
      const err = new Error("PHONE_EXISTS");
      err.status = 409;
      throw err;
    }
  }

  if (nextPin && nextPin === currentPin) {
    const err = new Error("PIN_UNCHANGED");
    err.status = 400;
    throw err;
  }

  const pinHash = nextPin ? await hashPin(nextPin) : null;
  const updated = await updateUserAccount({
    id: user.id,
    phone: nextPhone && nextPhone !== normalizedCurrentPhone ? nextPhone : null,
    pinHash,
  });

  return { user: mapUser(updated || user) };
}

function mapAddress(a) {
  return {
    id: a.id,
    customerUserId: a.customer_user_id,
    label: a.label,
    city: a.city,
    block: a.block,
    buildingNumber: a.building_number,
    apartment: a.apartment,
    isDefault: a.is_default,
    isActive: a.is_active,
    createdAt: a.created_at,
    updatedAt: a.updated_at,
  };
}

function normalizeCity(city) {
  if (typeof city !== "string") return "مدينة بسماية";
  const out = city.trim();
  return out.length ? out : "مدينة بسماية";
}

export async function getAddresses(userId) {
  const rows = await listCustomerAddresses(userId);
  return rows.map(mapAddress);
}

export async function createAddress(userId, dto) {
  const created = await createCustomerAddress(userId, {
    label: dto.label.trim(),
    city: normalizeCity(dto.city),
    block: dto.block.trim(),
    buildingNumber: dto.buildingNumber.trim(),
    apartment: dto.apartment.trim(),
    isDefault: dto.isDefault === true,
  });

  if (!created) {
    const err = new Error("ADDRESS_CREATE_FAILED");
    err.status = 500;
    throw err;
  }

  return mapAddress(created);
}

export async function updateAddress(userId, addressId, dto) {
  const patch = {};
  if (dto.label !== undefined) patch.label = dto.label.trim();
  if (dto.city !== undefined) patch.city = normalizeCity(dto.city);
  if (dto.block !== undefined) patch.block = dto.block.trim();
  if (dto.buildingNumber !== undefined)
    patch.buildingNumber = dto.buildingNumber.trim();
  if (dto.apartment !== undefined) patch.apartment = dto.apartment.trim();
  if (dto.isDefault !== undefined) patch.isDefault = dto.isDefault === true;

  const updated = await updateCustomerAddress(userId, Number(addressId), patch);
  if (!updated) {
    const err = new Error("ADDRESS_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  return mapAddress(updated);
}

export async function setDefaultAddress(userId, addressId) {
  const updated = await setCustomerDefaultAddress(userId, Number(addressId));
  if (!updated) {
    const err = new Error("ADDRESS_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return mapAddress(updated);
}

export async function deleteAddress(userId, addressId) {
  const ok = await deactivateCustomerAddress(userId, Number(addressId));
  if (!ok) {
    const err = new Error("ADDRESS_NOT_FOUND");
    err.status = 404;
    throw err;
  }
}

export async function resolveOrderAddress(userId, addressId) {
  if (addressId !== undefined && addressId !== null) {
    const selected = await getCustomerAddressById(userId, Number(addressId));
    if (!selected) {
      const err = new Error("ADDRESS_NOT_FOUND");
      err.status = 404;
      throw err;
    }
    return selected;
  }

  return getCustomerDefaultAddress(userId);
}
