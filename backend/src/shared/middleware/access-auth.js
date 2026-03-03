import { env } from "../../config/env.js";
import {
  getActiveSessionByAccess,
  touchUserSession,
} from "../../modules/auth/auth.repo.js";
import { extractDeviceContext } from "../utils/device-fingerprint.js";
import { verifyAccessToken } from "../utils/jwt.js";
import { AppError } from "../utils/errors.js";

const sessionTouchCache = new Map();

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

  // Cap memory usage for long-lived processes.
  if (sessionTouchCache.size > 50_000) {
    for (const [key, value] of sessionTouchCache.entries()) {
      if (now - value > intervalMs * 2) {
        sessionTouchCache.delete(key);
      }
      if (sessionTouchCache.size <= 40_000) break;
    }
  }
  return true;
}

function asInvalidToken() {
  return new AppError("INVALID_TOKEN", { status: 401 });
}

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
  const sessionId = payload?.sid == null ? null : Number(payload.sid);
  const tokenJti = payload?.jti ? String(payload.jti) : null;
  const deviceHashInJwt = payload?.dvh ? String(payload.dvh) : null;
  const deviceContext = extractDeviceContext(req);

  if (!sessionId) {
    if (!env.authAllowLegacyTokens) {
      if (strict) throw asInvalidToken();
      return null;
    }

    return {
      userId,
      role,
      isSuperAdmin,
      sessionId: null,
      tokenJti,
      deviceContext,
    };
  }

  const session = await getActiveSessionByAccess({
    sessionId,
    userId,
    tokenJti,
  });
  if (!session) {
    if (strict) throw asInvalidToken();
    return null;
  }

  const expectedDevice = String(session.device_fingerprint || "").trim();
  if (env.authDeviceBindingRequired && expectedDevice) {
    if (deviceContext.deviceFingerprint !== expectedDevice) {
      if (strict) throw asInvalidToken();
      return null;
    }
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
    sessionId,
    tokenJti,
    deviceContext,
  };
}

