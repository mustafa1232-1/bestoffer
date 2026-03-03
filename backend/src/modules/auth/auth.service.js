import {
  createUserSession,
  createUser,
  createCustomerAddress,
  deactivateCustomerAddress,
  findUserByIdWithAuthFields,
  findUserByPhone,
  getCustomerDefaultAddress,
  getCustomerAddressById,
  listCustomerAddresses,
  listUserActiveSessions,
  pruneUserSessions,
  registerFailedLoginAttempt,
  resetLoginProtection,
  revokeAllUserSessions,
  revokeUserSession,
  setCustomerDefaultAddress,
  updateCustomerAddress,
  updateUserAccount,
} from "./auth.repo.js";
import { hashPin, verifyPin } from "../../shared/utils/hash.js";
import { signAccessToken } from "../../shared/utils/jwt.js";
import { env } from "../../config/env.js";
import crypto from "crypto";

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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function applyCredentialFailureDelay() {
  const jitter = 120 + Math.floor(Math.random() * 180);
  await sleep(jitter);
}

function isLockedNow(user) {
  if (!user?.locked_until) return false;
  return new Date(user.locked_until).getTime() > Date.now();
}

function lockRetrySeconds(user) {
  if (!user?.locked_until) return 0;
  const ms = new Date(user.locked_until).getTime() - Date.now();
  return ms > 0 ? Math.ceil(ms / 1000) : 0;
}

function buildSessionTimestamps() {
  const now = new Date();
  const expiresAt = new Date(
    now.getTime() + Math.max(1, Number(env.authSessionTtlDays || 30)) * 24 * 60 * 60 * 1000
  );
  return {
    createdAt: now,
    expiresAt,
  };
}

async function issueSessionToken(user, deviceContext = {}) {
  const tokenJti = crypto.randomBytes(18).toString("base64url");
  const refreshToken = crypto.randomBytes(24).toString("base64url");
  const { expiresAt } = buildSessionTimestamps();

  const session = await createUserSession({
    userId: user.id,
    refreshToken,
    tokenJti,
    deviceFingerprint: deviceContext.deviceFingerprint || null,
    userAgent: deviceContext.userAgent || null,
    ipAddress: deviceContext.ipAddress || null,
    expiresAt,
    accessExpiresAt: null,
  });

  const token = signAccessToken(
    {
      id: user.id,
      role: user.role || "user",
      isSuperAdmin: user.is_super_admin === true,
    },
    {
      sessionId: session?.id || null,
      tokenJti,
      deviceFingerprint: deviceContext.deviceFingerprint || null,
    }
  );

  await pruneUserSessions(user.id, {
    maxActive: env.authMaxActiveSessionsPerUser,
  });

  return {
    token,
    sessionId: session?.id || null,
  };
}

export async function register(dto, deviceContext = {}) {
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

  const session = await issueSessionToken(created, deviceContext);

  return { token: session.token, sessionId: session.sessionId, user: mapUser(created) };
}

export async function login({ phone, pin }, deviceContext = {}) {
  const normalizedPhone = normalizePhone(phone);
  const normalizedPin = normalizePin(pin);

  const user = await findUserByPhone(normalizedPhone);
  if (!user) {
    await applyCredentialFailureDelay();
    const err = new Error("INVALID_CREDENTIALS");
    err.status = 401;
    throw err;
  }

  if (isLockedNow(user)) {
    const err = new Error("ACCOUNT_LOCKED");
    err.status = 423;
    err.details = { retryAfterSeconds: lockRetrySeconds(user) };
    throw err;
  }

  const ok = await verifyPin(normalizedPin, user.pin_hash);
  if (!ok) {
    await registerFailedLoginAttempt(user.id, {
      maxAttempts: env.authMaxFailedAttempts,
      lockMinutes: env.authLockMinutes,
    });
    await applyCredentialFailureDelay();
    const err = new Error("INVALID_CREDENTIALS");
    err.status = 401;
    throw err;
  }

  if (
    user.role === "delivery" &&
    user.delivery_account_approved !== true
  ) {
    const err = new Error("DELIVERY_ACCOUNT_PENDING_APPROVAL");
    err.status = 403;
    throw err;
  }

  await resetLoginProtection(user.id);
  const session = await issueSessionToken(user, deviceContext);

  return {
    token: session.token,
    sessionId: session.sessionId,
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

export async function updateAccount(userId, dto, { currentSessionId = null } = {}) {
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

  if (nextPin) {
    await revokeAllUserSessions({
      userId: user.id,
      exceptSessionId: currentSessionId,
      reason: "pin_changed",
    });
  }

  return { user: mapUser(updated || user) };
}

export async function logout(userId, sessionId) {
  if (!sessionId) return { revoked: false };
  const revoked = await revokeUserSession({
    userId,
    sessionId,
    reason: "logout",
  });
  return { revoked: !!revoked };
}

export async function logoutAll(userId, currentSessionId = null) {
  const revokedCount = await revokeAllUserSessions({
    userId,
    exceptSessionId: currentSessionId,
    reason: "logout_all",
  });
  return { revokedCount };
}

export async function listSessions(userId) {
  const rows = await listUserActiveSessions(userId);
  return rows.map((row) => ({
    id: Number(row.id),
    userAgent: row.user_agent || null,
    ipAddress: row.ip || null,
    deviceFingerprint: row.device_fingerprint || null,
    createdAt: row.created_at,
    lastSeenAt: row.last_seen_at,
    expiresAt: row.expires_at,
    accessExpiresAt: row.access_expires_at,
  }));
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
