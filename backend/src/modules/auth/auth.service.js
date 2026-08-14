import {
  createUserSession,
  createUser,
  createCustomerAddress,
  deactivateCustomerAddress,
  findRefreshSessionForUpdate,
  findRecoverableSessionByDeviceSessionForUpdate,
  findUserByIdWithAuthFields,
  findUserByPhone,
  getCustomerDefaultAddress,
  getCustomerAddressById,
  listCustomerAddresses,
  listUserActiveSessions,
  pruneUserSessions,
  registerFailedLoginAttempt,
  resetLoginProtection,
  revokeAllUserSessionsDetailed,
  revokeUserSession,
  recoverUserSessionTx,
  rotateUserSessionTokensTx,
  setCustomerDefaultAddress,
  touchRefreshSessionTx,
  withAuthTransaction,
  isUsernameTaken,
  updateCustomerAddress,
  updateUserAccount,
} from "./auth.repo.js";
import {
  hashPin,
  verifyPinDetailed,
} from "../../shared/utils/hash.js";
import { signAccessToken } from "../../shared/utils/jwt.js";
import { env } from "../../config/env.js";
import crypto from "crypto";
import { AppError } from "../../shared/utils/errors.js";
import {
  deactivatePushTokensForSession,
  deactivatePushTokensForUser,
} from "../notifications/notifications.repo.js";
import {
  isRoleAllowedForSurface,
  resolveRoleAppSurface,
} from "../../shared/utils/app-surface.js";
import {
  invalidateSessionAccessCacheForSession,
  invalidateSessionAccessCacheForUser,
  markSessionRevoked,
} from "../../shared/middleware/access-auth.js";

const APP_USER_USERNAME_MAX_LENGTH = 24;
const USERNAME_SUFFIX_LENGTH = 4;
const APP_USER_USERNAME_MIN_LENGTH = 4;
const APP_USER_USERNAME_FORMAT_RE = /^[a-z0-9](?:[a-z0-9._]{2,22})[a-z0-9]$/;
const REFRESH_PREVIOUS_TOKEN_GRACE_MS = 45_000;

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

function normalizeUsernameBase(fullName, phone) {
  const fullNamePart = String(fullName || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  const phoneDigits = normalizePhone(phone || "");
  const phoneTail = phoneDigits.length >= 4 ? phoneDigits.slice(-4) : "";
  const fallback = "user";
  const base = fullNamePart || fallback;
  const withPhone = phoneTail ? `${base}_${phoneTail}` : base;
  return withPhone.slice(0, APP_USER_USERNAME_MAX_LENGTH);
}

function randomUsernameSuffix() {
  return crypto.randomBytes(2).toString("hex");
}

function normalizeUsernameForConstraint(value) {
  let out = String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._]+/g, "_")
    .replace(/\.{2,}/g, ".")
    .replace(/_{2,}/g, "_");

  if (out.length > APP_USER_USERNAME_MAX_LENGTH) {
    out = out.slice(0, APP_USER_USERNAME_MAX_LENGTH);
  }

  out = out.replace(/^[._]+/, "").replace(/[._]+$/, "");

  if (!out) out = "user";
  if (!/^[a-z0-9]/.test(out)) out = `u${out}`;
  if (!/[a-z0-9]$/.test(out)) out = `${out}0`;

  if (out.length < APP_USER_USERNAME_MIN_LENGTH) {
    out = `${out}${"0".repeat(APP_USER_USERNAME_MIN_LENGTH)}`.slice(
      0,
      APP_USER_USERNAME_MIN_LENGTH
    );
  }

  if (out.length > APP_USER_USERNAME_MAX_LENGTH) {
    out = out.slice(0, APP_USER_USERNAME_MAX_LENGTH);
    out = out.replace(/[._]+$/, "");
    if (out.length < APP_USER_USERNAME_MIN_LENGTH) {
      out = `${out}${"0".repeat(APP_USER_USERNAME_MIN_LENGTH)}`.slice(
        0,
        APP_USER_USERNAME_MIN_LENGTH
      );
    }
  }

  if (!APP_USER_USERNAME_FORMAT_RE.test(out) || out.includes("..") || out.includes("__")) {
    out = out
      .replace(/\.{2,}/g, ".")
      .replace(/_{2,}/g, "_")
      .replace(/^[^a-z0-9]+/, "u")
      .replace(/[^a-z0-9]+$/, "0");
    if (out.length < APP_USER_USERNAME_MIN_LENGTH) {
      out = `${out}0000`.slice(0, APP_USER_USERNAME_MIN_LENGTH);
    }
    if (out.length > APP_USER_USERNAME_MAX_LENGTH) {
      out = out.slice(0, APP_USER_USERNAME_MAX_LENGTH).replace(/[._]+$/, "0");
    }
  }

  return out;
}

function buildUsernameCandidate(fullName, phone) {
  const maxBaseLength = Math.max(
    1,
    APP_USER_USERNAME_MAX_LENGTH - USERNAME_SUFFIX_LENGTH - 1
  );
  const base = normalizeUsernameForConstraint(
    normalizeUsernameBase(fullName, phone).slice(0, maxBaseLength)
  ).replace(/[._]+$/, "");
  const suffix = randomUsernameSuffix();
  return normalizeUsernameForConstraint(
    `${base || "user"}_${suffix}`.slice(0, APP_USER_USERNAME_MAX_LENGTH)
  );
}

function isDuplicateUsernameError(error) {
  if (!error) return false;
  const code = String(error.code || "");
  if (code !== "23505") return false;
  const constraint = String(error.constraint || "").toLowerCase();
  return constraint.includes("username");
}

function normalizeConsentAccepted(value) {
  if (value === true) return true;
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes";
}

function normalizeEnvPhone(value) {
  return String(value || "").replace(/[^\d]/g, "");
}

function resolveSuperAdmin(user) {
  if (!user) return false;
  if (user.is_super_admin === true) return true;

  const envUserId = Number(env.superAdminUserId || 0);
  if (Number.isFinite(envUserId) && envUserId > 0 && Number(user.id) === envUserId) {
    return true;
  }

  const envPhone = normalizeEnvPhone(env.superAdminPhone);
  const userPhone = normalizeEnvPhone(user.phone);
  return envPhone.length > 0 && userPhone === envPhone;
}

function isRequestedSurfaceAllowedForUser(user, requestedSurface) {
  if (!requestedSurface) return true;
  if (requestedSurface === "user") {
    // Only super-admin can bootstrap through the user app. Regular company
    // back-office accounts must sign in through the company surface.
    return (
      resolveSuperAdmin(user) ||
      resolveRoleAppSurface(user?.role) === "user"
    );
  }
  return isRoleAllowedForSurface(user?.role, requestedSurface);
}

function mapUser(u) {
  return {
    id: u.id,
    fullName: u.full_name,
    phone: u.phone,
    preferredLocale: u.preferred_locale || "ar",
    role: u.role,
    isSuperAdmin: resolveSuperAdmin(u),
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

function createRefreshToken() {
  return crypto.randomBytes(32).toString("base64url");
}

function createTokenJti() {
  return crypto.randomBytes(18).toString("base64url");
}

function createDeviceSessionId() {
  return crypto.randomBytes(24).toString("base64url");
}

function createDeviceRecoverySecret() {
  return crypto.randomBytes(32).toString("base64url");
}

function hashRecoverySecret(secret) {
  const value = String(secret || "").trim();
  if (!value) return null;
  return crypto.createHash("sha256").update(value).digest("hex");
}

function hashRefreshToken(token) {
  const value = String(token || "").trim();
  if (!value) return null;
  return crypto.createHash("sha256").update(value).digest("hex");
}

function recoverySecretMatches(candidate, storedHash) {
  const candidateHash = hashRecoverySecret(candidate);
  const stored = String(storedHash || "").trim();
  if (!candidateHash || !stored) return false;
  const left = Buffer.from(candidateHash, "utf8");
  const right = Buffer.from(stored, "utf8");
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

async function markRevokedSessionsInCache(sessionIds = []) {
  const ids = Array.isArray(sessionIds)
    ? sessionIds
        .map((id) => Number(id))
        .filter((id) => Number.isInteger(id) && id > 0)
    : [];
  if (ids.length === 0) return;
  await Promise.all(ids.map((sessionId) => markSessionRevoked(sessionId)));
}

async function issueSessionToken(user, deviceContext = {}) {
  const tokenJti = createTokenJti();
  const refreshToken = createRefreshToken();
  const deviceSessionId = createDeviceSessionId();
  const deviceRecoverySecret = createDeviceRecoverySecret();
  const { expiresAt } = buildSessionTimestamps();
  const appSurface = resolveRoleAppSurface(user.role);

  const session = await createUserSession({
    userId: user.id,
    refreshToken,
    tokenJti,
    deviceFingerprint: deviceContext.deviceFingerprint || null,
    userAgent: deviceContext.userAgent || null,
    ipAddress: deviceContext.ipAddress || null,
    expiresAt,
    accessExpiresAt: null,
    deviceSessionId,
    recoverySecretHash: hashRecoverySecret(deviceRecoverySecret),
    appSurface,
  });

  const token = signAccessToken(
    {
      id: user.id,
      role: user.role || "user",
      isSuperAdmin: resolveSuperAdmin(user),
      appSurface,
      permissionVersion: user.permission_version,
    },
    {
      sessionId: session?.id || null,
      tokenJti,
      deviceFingerprint: deviceContext.deviceFingerprint || null,
    }
  );

  const pruned = await pruneUserSessions(user.id, {
    maxActive: env.authMaxActiveSessionsPerUser,
  });
  if (Array.isArray(pruned?.revokedSessionIds) && pruned.revokedSessionIds.length > 0) {
    await Promise.all(
      pruned.revokedSessionIds.map((revokedSessionId) =>
        markSessionRevoked(revokedSessionId)
      )
    );
  }

  return {
    token,
    refreshToken,
    sessionId: session?.id || null,
    deviceSessionId,
    deviceRecoverySecret,
  };
}

export async function register(dto, deviceContext = {}) {
  const phone = normalizePhone(dto.phone);
  const pin = normalizePin(dto.pin);
  const fullName = String(dto.fullName || "").trim();
  const requestedSurface = deviceContext.appFlavor || null;
  if (requestedSurface && !isRoleAllowedForSurface("user", requestedSurface)) {
    const err = new AppError("FORBIDDEN_APP_SURFACE", { status: 403 });
    err.details = { appSurface: requestedSurface };
    throw err;
  }
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
  const username = await allocateRegistrationUsername({
    fullName,
    phone,
  });

  const created = await createUser({
    fullName,
    username,
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

  await createCustomerAddress(created.id, {
    label: "home",
    city: "Basmaya",
    block: dto.block.trim(),
    buildingNumber: dto.buildingNumber.trim(),
    apartment: dto.apartment.trim(),
    isDefault: true,
  });

  const session = await issueSessionToken(created, deviceContext);

  return {
    token: session.token,
    refreshToken: session.refreshToken,
    sessionId: session.sessionId,
    deviceSessionId: session.deviceSessionId,
    deviceRecoverySecret: session.deviceRecoverySecret,
    user: mapUser(created),
  };
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

  if (user.is_account_disabled === true) {
    const err = new Error("ACCOUNT_DISABLED");
    err.status = 403;
    const note = String(user.account_disabled_note || "").trim();
    err.details = {
      note: note || null,
    };
    throw err;
  }

  if (isLockedNow(user)) {
    const err = new Error("ACCOUNT_LOCKED");
    err.status = 423;
    err.details = { retryAfterSeconds: lockRetrySeconds(user) };
    throw err;
  }

  const pinVerification = await verifyPinDetailed(normalizedPin, user.pin_hash);
  if (!pinVerification.ok) {
    await registerFailedLoginAttempt(user.id, {
      maxAttempts: env.authMaxFailedAttempts,
      lockMinutes: env.authLockMinutes,
    });
    await applyCredentialFailureDelay();
    const err = new Error("INVALID_CREDENTIALS");
    err.status = 401;
    throw err;
  }

  if (pinVerification.needsUpgrade) {
    const upgradedPinHash = await hashPin(normalizedPin);
    await updateUserAccount({
      id: user.id,
      pinHash: upgradedPinHash,
    }).catch(() => null);
  }

  if (
    user.role === "delivery" &&
    user.delivery_account_approved !== true
  ) {
    const err = new Error("DELIVERY_ACCOUNT_PENDING_APPROVAL");
    err.status = 403;
    throw err;
  }

  if (
    user.role === "taxi_captain" &&
    user.taxi_account_approved !== true
  ) {
    const err = new Error("TAXI_CAPTAIN_ACCOUNT_PENDING_APPROVAL");
    err.status = 403;
    throw err;
  }

  const requestedSurface = deviceContext.appFlavor || null;
  if (requestedSurface && !isRequestedSurfaceAllowedForUser(user, requestedSurface)) {
    const err = new AppError("FORBIDDEN_APP_SURFACE", { status: 403 });
    err.details = { appSurface: requestedSurface };
    throw err;
  }

  await resetLoginProtection(user.id);
  const session = await issueSessionToken(user, deviceContext);

  return {
    token: session.token,
    refreshToken: session.refreshToken,
    sessionId: session.sessionId,
    deviceSessionId: session.deviceSessionId,
    deviceRecoverySecret: session.deviceRecoverySecret,
    user: {
      id: user.id,
      fullName: user.full_name,
      phone: user.phone,
      role: user.role,
      isSuperAdmin: resolveSuperAdmin(user),
      block: user.block,
      buildingNumber: user.building_number,
      apartment: user.apartment,
      imageUrl: user.image_url,
    },
  };
}

export async function refreshSession(refreshToken, deviceContext = {}) {
  const normalizedRefreshToken = String(refreshToken || "").trim();
  if (normalizedRefreshToken.length < 24 || normalizedRefreshToken.length > 256) {
    const err = new Error("SESSION_RECOVERY_REQUIRED");
    err.status = 401;
    throw err;
  }

  const refreshTokenHash = hashRefreshToken(normalizedRefreshToken);
  const outcome = await withAuthTransaction(async (client) => {
    const row = await findRefreshSessionForUpdate(client, {
      refreshToken: normalizedRefreshToken,
      refreshTokenHash,
    });
    if (!row) {
      const err = new Error("SESSION_RECOVERY_REQUIRED");
      err.status = 401;
      throw err;
    }

    const requestedSurface = deviceContext.appFlavor || null;
    if (
      requestedSurface &&
      !isRequestedSurfaceAllowedForUser(row, requestedSurface)
    ) {
      const err = new AppError("FORBIDDEN_APP_SURFACE", { status: 403 });
      err.details = { appSurface: requestedSurface };
      throw err;
    }

    const expectedDevice = String(row.device_fingerprint || "").trim();
    const currentDevice = String(deviceContext.deviceFingerprint || "").trim();
    if (env.authDeviceBindingRequired) {
      if (!expectedDevice || !currentDevice || expectedDevice !== currentDevice) {
        const err = new Error("SESSION_RECOVERY_REQUIRED");
        err.status = 401;
        throw err;
      }
    } else if (expectedDevice && currentDevice && expectedDevice !== currentDevice) {
      const err = new Error("SESSION_RECOVERY_REQUIRED");
      err.status = 401;
      throw err;
    }

    const matchedCurrent = row.refresh_token === normalizedRefreshToken;
    if (!matchedCurrent) {
      const touched = await touchRefreshSessionTx(client, row.session_id, {
        ipAddress: deviceContext.ipAddress || null,
        userAgent: deviceContext.userAgent || null,
      });
      return {
        row,
        session: touched || row,
        refreshToken: row.refresh_token,
        tokenJti: row.token_jti,
        deviceSessionId: row.device_session_id,
        recoverySecret: null,
        deviceFingerprint: expectedDevice || currentDevice || null,
      };
    }

    const nextRefreshToken = createRefreshToken();
    const nextTokenJti = createTokenJti();
    const needsRecoverySeed = !row.device_session_id || !row.recovery_secret_hash;
    const nextDeviceSessionId = row.device_session_id || createDeviceSessionId();
    const nextRecoverySecret = needsRecoverySeed ? createDeviceRecoverySecret() : null;
    const { expiresAt } = buildSessionTimestamps();
    const session = await rotateUserSessionTokensTx(client, {
      sessionId: row.session_id,
      userId: row.id,
      oldRefreshToken: normalizedRefreshToken,
      oldRefreshGeneration: row.refresh_generation,
      previousRefreshTokenHash: refreshTokenHash,
      previousRefreshValidUntil: new Date(Date.now() + REFRESH_PREVIOUS_TOKEN_GRACE_MS),
      refreshToken: nextRefreshToken,
      tokenJti: nextTokenJti,
      ipAddress: deviceContext.ipAddress || null,
      userAgent: deviceContext.userAgent || null,
      deviceFingerprint: currentDevice || expectedDevice || null,
      expiresAt,
      deviceSessionId: needsRecoverySeed ? nextDeviceSessionId : null,
      recoverySecretHash: nextRecoverySecret
        ? hashRecoverySecret(nextRecoverySecret)
        : null,
      appSurface: resolveRoleAppSurface(row.role),
    });
    if (!session) {
      const err = new Error("SESSION_RECOVERY_REQUIRED");
      err.status = 401;
      throw err;
    }
    return {
      row,
      session,
      refreshToken: nextRefreshToken,
      tokenJti: nextTokenJti,
      deviceSessionId: session.device_session_id || nextDeviceSessionId,
      recoverySecret: nextRecoverySecret,
      deviceFingerprint: expectedDevice || currentDevice || null,
    };
  });

  const { row, session, tokenJti } = outcome;

  invalidateSessionAccessCacheForSession({
    sessionId: row.session_id,
    userId: row.id,
  });

  const user = {
    id: row.id,
    username: row.username,
    full_name: row.full_name,
    phone: row.phone,
    preferred_locale: row.preferred_locale,
    role: row.role,
    block: row.block,
    building_number: row.building_number,
    apartment: row.apartment,
    image_url: row.image_url,
    work_title: row.work_title,
    work_company: row.work_company,
    is_super_admin: row.is_super_admin,
    is_taxi_captain: row.is_taxi_captain,
    taxi_account_approved: row.taxi_account_approved,
  };

  const token = signAccessToken(
    {
      id: row.id,
      role: row.role || "user",
      isSuperAdmin: resolveSuperAdmin(row),
      isTaxiCaptain: row.is_taxi_captain === true,
      appSurface: resolveRoleAppSurface(row.role),
      permissionVersion: row.permission_version,
    },
    {
      sessionId: session.id,
      tokenJti,
      deviceFingerprint: outcome.deviceFingerprint || null,
    }
  );

  return {
    token,
    refreshToken: outcome.refreshToken,
    sessionId: session.id,
    deviceSessionId: session.device_session_id || outcome.deviceSessionId,
    ...(outcome.recoverySecret ? { deviceRecoverySecret: outcome.recoverySecret } : {}),
    user: mapUser(user),
  };
}

export async function recoverSession(dto = {}, deviceContext = {}) {
  const deviceSessionId = String(dto.deviceSessionId || dto.device_session_id || "").trim();
  const deviceRecoverySecret = String(
    dto.deviceRecoverySecret || dto.device_recovery_secret || ""
  ).trim();

  if (
    deviceSessionId.length < 16 ||
    deviceSessionId.length > 120 ||
    deviceRecoverySecret.length < 24 ||
    deviceRecoverySecret.length > 256
  ) {
    const err = new Error("SESSION_RECOVERY_REQUIRED");
    err.status = 401;
    throw err;
  }

  const requestedSurface = String(
    dto.appFlavor || dto.app_flavor || deviceContext.appFlavor || ""
  ).trim() || null;
  const outcome = await withAuthTransaction(async (client) => {
    const row = await findRecoverableSessionByDeviceSessionForUpdate(
      client,
      deviceSessionId
    );
    if (!row || !recoverySecretMatches(deviceRecoverySecret, row.recovery_secret_hash)) {
      const err = new Error("SESSION_RECOVERY_REQUIRED");
      err.status = 401;
      throw err;
    }

    if (row.is_account_disabled === true) {
      const err = new Error("ACCOUNT_DISABLED");
      err.status = 403;
      const note = String(row.account_disabled_note || "").trim();
      err.details = { note: note || null };
      throw err;
    }

    if (requestedSurface && !isRequestedSurfaceAllowedForUser(row, requestedSurface)) {
      const err = new AppError("FORBIDDEN_APP_SURFACE", { status: 403 });
      err.details = { appSurface: requestedSurface };
      throw err;
    }

    const currentDevice = String(deviceContext.deviceFingerprint || "").trim();
    const existingDevice = String(row.device_fingerprint || "").trim();
    if (existingDevice && currentDevice && existingDevice !== currentDevice) {
      const err = new Error("DEVICE_REVERIFICATION_REQUIRED");
      err.status = 403;
      throw err;
    }
    if (env.authDeviceBindingRequired && (!existingDevice || !currentDevice)) {
      const err = new Error("DEVICE_REVERIFICATION_REQUIRED");
      err.status = 403;
      throw err;
    }

    const nextTokenJti = row.token_jti || createTokenJti();
    const appSurface = resolveRoleAppSurface(row.role);
    const session = await recoverUserSessionTx(client, {
      sessionId: row.session_id,
      userId: row.id,
      tokenJti: row.token_jti ? null : nextTokenJti,
      ipAddress: deviceContext.ipAddress || null,
      userAgent: deviceContext.userAgent || null,
      deviceFingerprint: !existingDevice && currentDevice ? currentDevice : null,
      deviceFingerprintSet: !existingDevice && Boolean(currentDevice),
      appSurface,
    });

    if (!session) {
      const err = new Error("SESSION_RECOVERY_REQUIRED");
      err.status = 401;
      throw err;
    }

    return {
      row,
      session,
      tokenJti: nextTokenJti,
      deviceFingerprint: existingDevice || currentDevice || null,
      appSurface,
    };
  });

  const { row, session, tokenJti, appSurface } = outcome;

  invalidateSessionAccessCacheForSession({
    sessionId: row.session_id,
    userId: row.id,
  });

  const token = signAccessToken(
    {
      id: row.id,
      role: row.role || "user",
      isSuperAdmin: resolveSuperAdmin(row),
      isTaxiCaptain: row.is_taxi_captain === true,
      appSurface,
      permissionVersion: row.permission_version,
    },
    {
      sessionId: session.id,
      tokenJti,
      deviceFingerprint: outcome.deviceFingerprint || null,
    }
  );

  return {
    token,
    refreshToken: session.refresh_token,
    sessionId: session.id,
    deviceSessionId: session.device_session_id || deviceSessionId,
    user: mapUser(row),
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
  const currentPinVerification = await verifyPinDetailed(currentPin, user.pin_hash);
  if (!currentPinVerification.ok) {
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

  const pinHash = nextPin
    ? await hashPin(nextPin)
    : currentPinVerification.needsUpgrade
      ? await hashPin(currentPin)
      : null;
  const updated = await updateUserAccount({
    id: user.id,
    phone: nextPhone && nextPhone !== normalizedCurrentPhone ? nextPhone : null,
    pinHash,
  });

  return { user: mapUser(updated || user) };
}

export async function logout(userId, sessionId) {
  if (!sessionId) return { revoked: false };
  const revoked = await revokeUserSession({
    userId,
    sessionId,
    reason: "logout",
  });
  await markSessionRevoked(sessionId);
  invalidateSessionAccessCacheForSession({ userId, sessionId });
  if (revoked) {
    await deactivatePushTokensForSession(userId, sessionId);
  }
  return { revoked: !!revoked };
}

export async function logoutAll(userId, currentSessionId = null) {
  const revoked = await revokeAllUserSessionsDetailed({
    userId,
    exceptSessionId: currentSessionId,
    reason: "logout_all",
  });
  await markRevokedSessionsInCache(revoked.revokedSessionIds);
  await deactivatePushTokensForUser(userId);
  invalidateSessionAccessCacheForUser({
    userId,
    exceptSessionId: currentSessionId,
  });
  return { revokedCount: revoked.revokedCount };
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

export async function runWithGeneratedAppUserUsername({
  fullName,
  phone,
  execute,
  maxAttempts = 8,
}) {
  if (typeof execute !== "function") {
    const err = new Error("USERNAME_EXECUTOR_REQUIRED");
    err.status = 500;
    throw err;
  }

  const attempts = Math.max(1, Number(maxAttempts) || 1);
  let lastError = null;
  for (let index = 0; index < attempts; index += 1) {
    const username = buildUsernameCandidate(fullName, phone);
    try {
      return await execute(username);
    } catch (error) {
      lastError = error;
      if (isDuplicateUsernameError(error)) {
        continue;
      }
      throw error;
    }
  }

  throw lastError || new Error("USERNAME_GENERATION_FAILED");
}

export async function allocateRegistrationUsername({
  fullName,
  phone,
  maxAttempts = 12,
}) {
  const attempts = Math.max(1, Number(maxAttempts) || 1);
  for (let index = 0; index < attempts; index += 1) {
    const candidate = buildUsernameCandidate(fullName, phone);
    const taken = await isUsernameTaken(candidate);
    if (!taken) return candidate;
  }

  const fallbackBase = normalizeUsernameBase(fullName, phone);
  const fallbackSuffix = Date.now().toString(36).slice(-4);
  const maxBaseLength = Math.max(
    1,
    APP_USER_USERNAME_MAX_LENGTH - fallbackSuffix.length - 1
  );
  return normalizeUsernameForConstraint(
    `${fallbackBase.slice(0, maxBaseLength)}_${fallbackSuffix}`.slice(
      0,
      APP_USER_USERNAME_MAX_LENGTH
    )
  );
}
