import crypto from "node:crypto";

import { env } from "../../config/env.js";
import { getRedisClient } from "../../config/redis.js";
import { AppError } from "../../shared/utils/errors.js";

const SIGNING_ALGORITHM = "hmac-sha256";
const SIGNING_KEY_PREFIX = "security:request-signing:key:";
const SIGNING_NONCE_PREFIX = "security:request-signing:nonce:";

const dependencies = {
  now: () => Date.now(),
  getRedisClient: () => getRedisClient(),
  randomBytes: (size) => crypto.randomBytes(size),
  randomUUID: () => crypto.randomUUID(),
  createHash: (algorithm) => crypto.createHash(algorithm),
  createHmac: (algorithm, secret) => crypto.createHmac(algorithm, secret),
};

function signingTtlSec() {
  return Math.max(60, Number(env.securityRequestSigningTtlSec || 900));
}

function signingRefreshWindowSec() {
  return Math.max(
    15,
    Math.min(
      signingTtlSec() - 1,
      Number(env.securityRequestSigningRefreshWindowSec || 120)
    )
  );
}

function signingClockSkewMs() {
  return (
    Math.max(30, Number(env.securityRequestSigningMaxClockSkewSec || 300)) * 1000
  );
}

function signingNonceTtlSec() {
  return Math.max(60, Number(env.securityRequestSigningNonceTtlSec || 1200));
}

function normalizeHeaderValue(value) {
  if (Array.isArray(value)) return String(value[0] || "").trim();
  return String(value || "").trim();
}

function normalizePath(pathname) {
  const trimmed = String(pathname || "")
    .trim()
    .split("?")[0];
  if (!trimmed) return "/";
  return trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
}

function stableClone(value) {
  if (Array.isArray(value)) return value.map(stableClone);
  if (value && typeof value === "object") {
    return Object.keys(value)
      .sort((a, b) => a.localeCompare(b))
      .reduce((acc, key) => {
        acc[key] = stableClone(value[key]);
        return acc;
      }, {});
  }
  return value;
}

export function stableStringify(value) {
  if (value === undefined || value === null || value === "") return "";
  if (typeof value === "string") return value;
  return JSON.stringify(stableClone(value));
}

export function buildRequestBodyHash(body) {
  return dependencies
    .createHash("sha256")
    .update(stableStringify(body))
    .digest("hex");
}

export function buildRequestSigningCanonical({
  method,
  path,
  timestamp,
  nonce,
  sessionId,
  deviceFingerprint,
  bodyHash,
}) {
  return [
    String(method || "GET").trim().toUpperCase(),
    normalizePath(path),
    String(timestamp || "").trim(),
    String(nonce || "").trim(),
    String(sessionId || "").trim(),
    String(deviceFingerprint || "").trim(),
    String(bodyHash || "").trim(),
  ].join("\n");
}

export function signRequestCanonical({ secret, canonical }) {
  return dependencies
    .createHmac("sha256", String(secret || ""))
    .update(String(canonical || ""))
    .digest("base64url");
}

function compareSignature(expected, received) {
  const expectedBytes = Buffer.from(String(expected || ""));
  const receivedBytes = Buffer.from(String(received || ""));
  if (expectedBytes.length !== receivedBytes.length) return false;
  return crypto.timingSafeEqual(expectedBytes, receivedBytes);
}

function buildSigningKeyId() {
  return dependencies.randomUUID().replace(/-/g, "");
}

function normalizeSigningTimestamp(value) {
  const raw = Number(value);
  if (!Number.isFinite(raw) || raw <= 0) return 0;
  if (raw > 10_000_000_000) return Math.trunc(raw);
  return Math.trunc(raw * 1000);
}

function parseSigningRecord(raw) {
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function requireSigningRedisClient() {
  const redis = await dependencies.getRedisClient().catch(() => null);
  if (redis) return redis;
  throw new AppError("REQUEST_SIGNING_UNAVAILABLE", {
    status: 503,
    details: { reason: "REDIS_UNAVAILABLE" },
  });
}

function buildSigningRecord({
  userId,
  sessionId,
  deviceFingerprint,
  secret,
  issuedAtMs,
  expiresInSec,
}) {
  return {
    userId: Number(userId),
    sessionId: Number(sessionId),
    deviceFingerprint: String(deviceFingerprint || ""),
    secret: String(secret || ""),
    algorithm: SIGNING_ALGORITHM,
    issuedAtMs,
    expiresAtMs: issuedAtMs + expiresInSec * 1000,
  };
}

export async function issueRequestSigningMaterial({
  userId,
  sessionId,
  deviceFingerprint,
}) {
  if (env.securityRequestSigningEnabled !== true) {
    throw new AppError("REQUEST_SIGNING_DISABLED", { status: 503 });
  }

  const safeUserId = Number(userId);
  const safeSessionId = Number(sessionId);
  const safeDeviceFingerprint = String(deviceFingerprint || "").trim();
  if (!Number.isInteger(safeUserId) || safeUserId <= 0) {
    throw new AppError("REQUEST_SIGNING_INVALID_USER", { status: 400 });
  }
  if (!Number.isInteger(safeSessionId) || safeSessionId <= 0) {
    throw new AppError("REQUEST_SIGNING_INVALID_SESSION", { status: 400 });
  }
  if (!safeDeviceFingerprint) {
    throw new AppError("REQUEST_SIGNING_INVALID_DEVICE", { status: 400 });
  }

  const redis = await requireSigningRedisClient();
  const keyId = buildSigningKeyId();
  const secret = dependencies.randomBytes(32).toString("base64url");
  const expiresIn = signingTtlSec();
  const issuedAtMs = dependencies.now();
  const record = buildSigningRecord({
    userId: safeUserId,
    sessionId: safeSessionId,
    deviceFingerprint: safeDeviceFingerprint,
    secret,
    issuedAtMs,
    expiresInSec: expiresIn,
  });

  await redis.set(
    `${SIGNING_KEY_PREFIX}${keyId}`,
    JSON.stringify(record),
    "EX",
    expiresIn
  );

  return {
    keyId,
    signingSecret: secret,
    issuedAt: new Date(issuedAtMs).toISOString(),
    expiresIn,
    refreshWindowSec: signingRefreshWindowSec(),
    algorithm: SIGNING_ALGORITHM,
  };
}

export async function getRequestSigningRuntimeStatus() {
  if (env.securityRequestSigningEnabled !== true) {
    return {
      enabled: false,
      ok: true,
      reason: "disabled",
      ttlSec: signingTtlSec(),
      refreshWindowSec: signingRefreshWindowSec(),
      nonceTtlSec: signingNonceTtlSec(),
    };
  }

  const redis = await dependencies.getRedisClient().catch(() => null);
  return {
    enabled: true,
    ok: !!redis,
    reason: redis ? "ok" : "redis_unavailable",
    ttlSec: signingTtlSec(),
    refreshWindowSec: signingRefreshWindowSec(),
    nonceTtlSec: signingNonceTtlSec(),
  };
}

export async function verifySignedRequest(req) {
  if (env.securityRequestSigningEnabled !== true) {
    return { ok: true, skipped: true, reason: "disabled" };
  }

  const redis = await requireSigningRedisClient();
  const keyId = normalizeHeaderValue(req.headers["x-request-key-id"]);
  const timestampRaw = normalizeHeaderValue(req.headers["x-request-timestamp"]);
  const nonce = normalizeHeaderValue(req.headers["x-request-nonce"]);
  const signature = normalizeHeaderValue(req.headers["x-request-signature"]);

  if (!keyId || !timestampRaw || !nonce || !signature) {
    throw new AppError("REQUEST_SIGNATURE_REQUIRED", {
      status: 428,
      details: {
        requiredHeaders: [
          "X-Request-Key-Id",
          "X-Request-Timestamp",
          "X-Request-Nonce",
          "X-Request-Signature",
        ],
      },
    });
  }

  const record = parseSigningRecord(
    await redis.get(`${SIGNING_KEY_PREFIX}${keyId}`)
  );
  if (!record) {
    throw new AppError("REQUEST_SIGNING_MATERIAL_EXPIRED", {
      status: 401,
      details: { keyId },
    });
  }

  const nowMs = dependencies.now();
  const timestampMs = normalizeSigningTimestamp(timestampRaw);
  if (!timestampMs) {
    throw new AppError("REQUEST_SIGNATURE_TIMESTAMP_INVALID", { status: 400 });
  }
  if (Math.abs(nowMs - timestampMs) > signingClockSkewMs()) {
    throw new AppError("REQUEST_SIGNATURE_EXPIRED", {
      status: 401,
      details: { maxClockSkewSec: Number(env.securityRequestSigningMaxClockSkewSec || 300) },
    });
  }
  if (Number(record.expiresAtMs || 0) <= nowMs) {
    throw new AppError("REQUEST_SIGNING_MATERIAL_EXPIRED", {
      status: 401,
      details: { keyId },
    });
  }

  const boundUserId = Number(req.userId || req.authUserId || 0);
  const boundSessionId = Number(req.authSessionId || 0);
  const boundDeviceFingerprint = String(
    req.authDeviceContext?.deviceFingerprint || ""
  ).trim();
  if (boundUserId <= 0 || boundSessionId <= 0 || !boundDeviceFingerprint) {
    throw new AppError("REQUEST_SIGNATURE_CONTEXT_INVALID", { status: 401 });
  }
  if (
    Number(record.userId) !== boundUserId ||
    Number(record.sessionId) !== boundSessionId ||
    String(record.deviceFingerprint || "") !== boundDeviceFingerprint
  ) {
    throw new AppError("REQUEST_SIGNATURE_CONTEXT_MISMATCH", {
      status: 401,
    });
  }

  const canonical = buildRequestSigningCanonical({
    method: req.method,
    path: req.originalUrl || req.url || req.path,
    timestamp: timestampRaw,
    nonce,
    sessionId: boundSessionId,
    deviceFingerprint: boundDeviceFingerprint,
    bodyHash: buildRequestBodyHash(req.body),
  });
  const expectedSignature = signRequestCanonical({
    secret: record.secret,
    canonical,
  });
  if (!compareSignature(expectedSignature, signature)) {
    throw new AppError("REQUEST_SIGNATURE_INVALID", { status: 401 });
  }

  const nonceResult = await redis.set(
    `${SIGNING_NONCE_PREFIX}${keyId}:${nonce}`,
    "1",
    "NX",
    "EX",
    signingNonceTtlSec()
  );
  if (nonceResult !== "OK") {
    throw new AppError("REQUEST_SIGNATURE_REPLAYED", {
      status: 409,
      details: { nonce },
    });
  }

  return {
    ok: true,
    keyId,
    timestampMs,
  };
}

export const __securitySigningTestApi = {
  reset() {
    dependencies.now = () => Date.now();
    dependencies.getRedisClient = () => getRedisClient();
    dependencies.randomBytes = (size) => crypto.randomBytes(size);
    dependencies.randomUUID = () => crypto.randomUUID();
    dependencies.createHash = (algorithm) => crypto.createHash(algorithm);
    dependencies.createHmac = (algorithm, secret) =>
      crypto.createHmac(algorithm, secret);
  },
  setNow(nextNow) {
    dependencies.now = nextNow;
  },
  setRedisClientFactory(factory) {
    dependencies.getRedisClient = factory;
  },
  setRandomBytes(factory) {
    dependencies.randomBytes = factory;
  },
  setRandomUUID(factory) {
    dependencies.randomUUID = factory;
  },
};
