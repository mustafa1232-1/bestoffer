import { env } from "../../config/env.js";
import { getRedisClient } from "../../config/redis.js";
import {
  getActiveSessionByAccess,
  touchUserSession,
} from "../../modules/auth/auth.repo.js";
import { extractDeviceContext } from "../utils/device-fingerprint.js";
import { verifyAccessToken } from "../utils/jwt.js";
import { AppError } from "../utils/errors.js";
import {
  normalizeAppSurface,
  resolveRouteAppSurface,
  resolveRoleAppSurface,
} from "../utils/app-surface.js";

const sessionTouchCache = new Map();
const sessionAccessCache = new Map();
const SESSION_ACCESS_CACHE_TTL_MS = Math.max(
  1000,
  Math.min(15000, Number(env.authSessionCacheTtlSec || 10) * 1000)
);
const SESSION_REVOCATION_TTL_SEC = Math.max(
  60,
  Math.min(
    120 * 24 * 60 * 60,
    Math.trunc(Math.max(1, Number(env.authSessionTtlDays || 30)) * 24 * 60 * 60)
  )
);

// Periodic cleanup every 5 minutes — evicts entries older than 2x the touch interval
const SESSION_TOUCH_CLEANUP_INTERVAL_MS = 5 * 60 * 1000;
const _sessionTouchCleanupTimer = setInterval(() => {
  const now = Date.now();
  const intervalMs = Math.max(10, Number(env.authSessionTouchIntervalSec || 60)) * 1000;
  const maxAge = intervalMs * 2;
  for (const [key, lastTouch] of sessionTouchCache.entries()) {
    if (now - lastTouch > maxAge) sessionTouchCache.delete(key);
  }
  for (const [key, entry] of sessionAccessCache.entries()) {
    if (!entry || entry.expiresAt <= now) sessionAccessCache.delete(key);
  }
}, SESSION_TOUCH_CLEANUP_INTERVAL_MS);
_sessionTouchCleanupTimer.unref?.();

function readBearerToken(req) {
  const h = req.headers.authorization || "";
  return h.startsWith("Bearer ") ? h.slice(7) : null;
}

function shouldTouchSession(sessionId) {
  const now = Date.now();
  const intervalMs = Math.max(10, Number(env.authSessionTouchIntervalSec || 60)) * 1000;
  const lastTouch = sessionTouchCache.get(sessionId) || 0;
  if (now - lastTouch < intervalMs) return false;
  sessionTouchCache.set(sessionId, now);
  return true;
}

function asInvalidToken() {
  return new AppError("INVALID_TOKEN", { status: 401 });
}

function asForbiddenAppSurface({
  appSurface = null,
  roleSurface = null,
  headerSurface = null,
} = {}) {
  const error = new AppError("FORBIDDEN_APP_SURFACE", { status: 403 });
  error.details = {
    appSurface: appSurface || null,
    roleSurface: roleSurface || null,
    headerSurface: headerSurface || null,
  };
  return error;
}

function isSuperAdminUserSurfaceBypass({
  routeSurface = null,
  headerSurface = null,
  isSuperAdmin = false,
} = {}) {
  if (isSuperAdmin !== true) return false;
  if (routeSurface === "user") {
    return headerSurface == null || headerSurface === "user";
  }
  if (routeSurface === "company") {
    return headerSurface == null || headerSurface === "user";
  }
  return routeSurface == null && headerSurface === "user";
}

function buildSessionAccessCacheKey({
  sessionId,
  userId,
  tokenJti,
  deviceFingerprint,
}) {
  return [
    Number(sessionId),
    Number(userId),
    tokenJti || "",
    deviceFingerprint || "",
  ].join(":");
}

function readSessionAccessCache(cacheKey) {
  const cached = sessionAccessCache.get(cacheKey);
  if (!cached) return null;
  if (cached.expiresAt <= Date.now()) {
    sessionAccessCache.delete(cacheKey);
    return null;
  }
  return cached.session;
}

function writeSessionAccessCache(cacheKey, session) {
  sessionAccessCache.set(cacheKey, {
    session,
    expiresAt: Date.now() + SESSION_ACCESS_CACHE_TTL_MS,
  });
  return session;
}

function parseSessionAccessCacheKey(cacheKey) {
  const [sessionIdRaw, userIdRaw] = String(cacheKey || "").split(":", 3);
  const sessionId = Number(sessionIdRaw);
  const userId = Number(userIdRaw);
  return {
    sessionId: Number.isFinite(sessionId) ? sessionId : 0,
    userId: Number.isFinite(userId) ? userId : 0,
  };
}

export function invalidateSessionAccessCacheForSession({
  sessionId,
  userId = null,
} = {}) {
  const normalizedSessionId = Number(sessionId);
  const normalizedUserId =
    userId == null ? null : Number.isFinite(Number(userId)) ? Number(userId) : null;
  if (!Number.isFinite(normalizedSessionId) || normalizedSessionId <= 0) return 0;

  let removed = 0;
  for (const cacheKey of sessionAccessCache.keys()) {
    const parsed = parseSessionAccessCacheKey(cacheKey);
    if (parsed.sessionId !== normalizedSessionId) continue;
    if (normalizedUserId != null && parsed.userId !== normalizedUserId) continue;
    sessionAccessCache.delete(cacheKey);
    removed += 1;
  }
  sessionTouchCache.delete(normalizedSessionId);
  return removed;
}

export function invalidateSessionAccessCacheForUser({
  userId,
  exceptSessionId = null,
} = {}) {
  const normalizedUserId = Number(userId);
  const normalizedExceptSessionId =
    exceptSessionId == null
      ? null
      : Number.isFinite(Number(exceptSessionId))
        ? Number(exceptSessionId)
        : null;
  if (!Number.isFinite(normalizedUserId) || normalizedUserId <= 0) return 0;

  let removed = 0;
  for (const cacheKey of sessionAccessCache.keys()) {
    const parsed = parseSessionAccessCacheKey(cacheKey);
    if (parsed.userId !== normalizedUserId) continue;
    if (
      normalizedExceptSessionId != null &&
      parsed.sessionId === normalizedExceptSessionId
    ) {
      continue;
    }
    sessionAccessCache.delete(cacheKey);
    sessionTouchCache.delete(parsed.sessionId);
    removed += 1;
  }
  return removed;
}

async function readSessionRevocationState({ sessionId, userId, tokenIssuedAtSec }) {
  const redis = await getRedisClient().catch(() => null);
  if (!redis) return false;
  try {
    const [sessionRevoked, userRevokedAfterRaw] = await redis.mget(
      `auth:session:revoked:${Number(sessionId)}`,
      `auth:user:revoked_after:${Number(userId)}`
    );
    if (sessionRevoked === "1") return true;
    const userRevokedAfter = Number(userRevokedAfterRaw || 0);
    if (
      Number.isFinite(userRevokedAfter) &&
      userRevokedAfter > 0 &&
      Number.isFinite(tokenIssuedAtSec) &&
      tokenIssuedAtSec > 0 &&
      userRevokedAfter >= tokenIssuedAtSec
    ) {
      return true;
    }
  } catch (_) {
    return false;
  }
  return false;
}

export async function markSessionRevoked(sessionId) {
  const normalizedSessionId = Number(sessionId);
  if (!Number.isFinite(normalizedSessionId) || normalizedSessionId <= 0) return;
  const redis = await getRedisClient().catch(() => null);
  if (!redis) return;
  await redis
    .set(
      `auth:session:revoked:${normalizedSessionId}`,
      "1",
      "EX",
      SESSION_REVOCATION_TTL_SEC
    )
    .catch(() => {});
}

export async function markUserSessionsRevokedAfter(userId, issuedAtSec = null) {
  const normalizedUserId = Number(userId);
  if (!Number.isFinite(normalizedUserId) || normalizedUserId <= 0) return;
  const redis = await getRedisClient().catch(() => null);
  if (!redis) return;
  const timestampSec =
    Number.isFinite(Number(issuedAtSec)) && Number(issuedAtSec) > 0
      ? Math.trunc(Number(issuedAtSec))
      : Math.trunc(Date.now() / 1000);
  await redis
    .set(
      `auth:user:revoked_after:${normalizedUserId}`,
      String(timestampSec),
      "EX",
      SESSION_REVOCATION_TTL_SEC
    )
    .catch(() => {});
}

export const __sessionAccessCacheTestApi = {
  write(cacheKey, session) {
    return writeSessionAccessCache(cacheKey, session);
  },
  read(cacheKey) {
    return readSessionAccessCache(cacheKey);
  },
  clear() {
    sessionAccessCache.clear();
    sessionTouchCache.clear();
  },
  size() {
    return sessionAccessCache.size;
  },
};

export async function resolveAccessAuth(req, { strict = true } = {}) {
  const token = readBearerToken(req);
  if (!token) {
    if (strict) throw new AppError("NO_TOKEN", { status: 401 });
    return null;
  }

  let payload;
  try {
    payload = verifyAccessToken(token);
  } catch (_) {
    if (strict) throw asInvalidToken();
    return null;
  }

  const userId = Number(payload?.sub);
  if (!Number.isInteger(userId) || userId <= 0) {
    if (strict) throw asInvalidToken();
    return null;
  }

  const role = String(payload?.role || "");
  const isSuperAdmin = payload?.sa === true;
  const isTaxiCaptain = payload?.tc === true;
  const sessionId = payload?.sid == null ? null : Number(payload.sid);
  const tokenJti = payload?.jti ? String(payload.jti) : null;
  const deviceHashInJwt = payload?.dvh ? String(payload.dvh) : null;
  const deviceContext = extractDeviceContext(req);
  const headerSurface = normalizeAppSurface(
    req?.headers?.["x-app-flavor"] || req?.headers?.["x-client-platform"]
  );
  const routeSurface = resolveRouteAppSurface(req);
  const roleSurface = resolveRoleAppSurface(role);
  const claimSurface = normalizeAppSurface(payload?.appSurface);
  const allowSuperAdminUserSurface = isSuperAdminUserSurfaceBypass({
    routeSurface,
    headerSurface,
    isSuperAdmin,
  });

  if (claimSurface && roleSurface && claimSurface !== roleSurface) {
    if (strict) throw asInvalidToken();
    return null;
  }
  if (routeSurface) {
    if (roleSurface !== routeSurface && !allowSuperAdminUserSurface) {
      if (strict) {
        throw asForbiddenAppSurface({
          appSurface: routeSurface,
          roleSurface,
          headerSurface,
        });
      }
      return null;
    }
    if (
      headerSurface &&
      headerSurface !== routeSurface &&
      !allowSuperAdminUserSurface
    ) {
      if (strict) {
        throw asForbiddenAppSurface({
          appSurface: routeSurface,
          roleSurface,
          headerSurface,
        });
      }
      return null;
    }
  } else if (
    headerSurface &&
    roleSurface &&
    headerSurface !== roleSurface &&
    !allowSuperAdminUserSurface
  ) {
    if (strict) {
      throw asForbiddenAppSurface({
        appSurface: headerSurface,
        roleSurface,
        headerSurface,
      });
    }
    return null;
  }

  if (!sessionId) {
    if (!env.authAllowLegacyTokens) {
      if (strict) throw asInvalidToken();
      return null;
    }

    return {
      userId,
      role,
      isSuperAdmin,
      isTaxiCaptain,
      sessionId: null,
      tokenJti,
      deviceContext,
      appSurface: roleSurface,
      requestSurface: routeSurface || headerSurface || null,
    };
  }

  const sessionCacheKey = buildSessionAccessCacheKey({
    sessionId,
    userId,
    tokenJti,
    deviceFingerprint: deviceContext.deviceFingerprint,
  });
  const cachedSession = readSessionAccessCache(sessionCacheKey);
  let session = null;
  if (cachedSession) {
    const revoked = await readSessionRevocationState({
      sessionId,
      userId,
      tokenIssuedAtSec: Number(payload?.iat || 0),
    });
    if (revoked) {
      invalidateSessionAccessCacheForSession({ sessionId, userId });
      if (strict) throw asInvalidToken();
      return null;
    }
    session = cachedSession;
  } else {
    session = writeSessionAccessCache(
      sessionCacheKey,
      await getActiveSessionByAccess({
        sessionId,
        userId,
        tokenJti,
      })
    );
  }
  if (!session) {
    if (strict) throw asInvalidToken();
    return null;
  }

  const expectedDevice = String(session.device_fingerprint || "").trim();
  // When binding is required, reject mismatches — including sessions with no stored fingerprint
  // to prevent tokens issued before fingerprint enforcement from bypassing the check.
  if (env.authDeviceBindingRequired) {
    if (!expectedDevice || deviceContext.deviceFingerprint !== expectedDevice) {
      if (strict) throw asInvalidToken();
      return null;
    }
  } else if (expectedDevice && deviceContext.deviceFingerprint !== expectedDevice) {
    if (strict) throw asInvalidToken();
    return null;
  }
  if (deviceHashInJwt && expectedDevice && deviceHashInJwt !== expectedDevice) {
    if (strict) throw asInvalidToken();
    return null;
  }

  if (shouldTouchSession(sessionId)) {
    await touchUserSession(sessionId, {
      ipAddress: deviceContext.ipAddress,
      userAgent: deviceContext.userAgent,
    });
  }

  return {
    userId,
    role,
    isSuperAdmin,
    isTaxiCaptain,
    sessionId,
    tokenJti,
    deviceContext,
    appSurface: roleSurface,
    requestSurface: routeSurface || headerSurface || null,
  };
}
