import { AppError } from "../utils/errors.js";
import { getRedisClient } from "../../config/redis.js";
import { createHash } from "node:crypto";

// In-memory fallback used when Redis is unavailable
const buckets = new Map();
const CLEANUP_INTERVAL_MS = 30_000;
const MAX_BUCKETS = 50_000;
let lastCleanupAt = 0;

function nowMs() {
  return Date.now();
}

function normalizeAuthIdentity(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  const digits = raw.replace(/\D/g, "");
  if (digits.length >= 7 && digits.length <= 20) return `p:${digits}`;
  return `s:${raw.toLowerCase().slice(0, 80)}`;
}

function extractAuthIdentity(req) {
  const body = req && typeof req.body === "object" && req.body ? req.body : null;
  if (!body) return "";
  const candidate =
    body.phone || body.identifier || body.email || body.username || body.login;
  return normalizeAuthIdentity(candidate);
}

function hashIdentity(value) {
  return createHash("sha256").update(String(value)).digest("hex").slice(0, 16);
}

function extractAnonymousClientIdentity(req) {
  const headers = req?.headers || {};
  const deviceId = String(headers["x-device-id"] || "").trim();
  const appFlavor = String(headers["x-app-flavor"] || "").trim().toLowerCase();
  if (deviceId) {
    return `device:${appFlavor || "default"}:${deviceId.slice(0, 128)}`;
  }

  const installationId = String(headers["x-installation-id"] || "").trim();
  if (installationId) {
    return `install:${appFlavor || "default"}:${installationId.slice(0, 128)}`;
  }

  const userAgent = String(headers["user-agent"] || "").trim().toLowerCase();
  const platform = String(headers["x-client-platform"] || "")
    .trim()
    .toLowerCase();
  if (!userAgent && !platform && !appFlavor) return "";
  return `ua:${hashIdentity(`${appFlavor}|${platform}|${userAgent}`)}`;
}

export function buildRateLimitKey(req, prefix = "global") {
  const forwardedFor = req.headers["x-forwarded-for"];
  const firstForwarded = Array.isArray(forwardedFor)
    ? forwardedFor[0]
    : String(forwardedFor || "").split(",")[0].trim();
  const ip = firstForwarded || req.ip || req.socket?.remoteAddress || "unknown";
  const resolvedUserId =
    Number(req.userId) > 0
      ? Number(req.userId)
      : Number(req.authUserId) > 0
        ? Number(req.authUserId)
        : null;
  const sessionId =
    Number(req.authSessionId) > 0 ? Number(req.authSessionId) : null;
  const authIdentity = prefix === "auth" ? extractAuthIdentity(req) : "";
  const anonymousClientIdentity = extractAnonymousClientIdentity(req);
  const authKey = resolvedUserId
    ? `u:${resolvedUserId}:${sessionId || "na"}`
    : authIdentity
      ? `anon-id:${hashIdentity(authIdentity)}`
      : anonymousClientIdentity
        ? `anon-client:${hashIdentity(anonymousClientIdentity)}`
      : "anon";
  return `rl:${prefix}:${ip}:${authKey}`;
}

function consumeBucketLocal({ key, windowMs }) {
  const now = nowMs();
  const resetAt = now + windowMs;
  const current = buckets.get(key);
  if (!current || current.resetAt <= now) {
    const fresh = { count: 1, resetAt };
    buckets.set(key, fresh);
    return fresh;
  }
  current.count += 1;
  return current;
}

function cleanupBuckets(now = nowMs()) {
  if (now - lastCleanupAt < CLEANUP_INTERVAL_MS && buckets.size < MAX_BUCKETS) {
    return;
  }
  lastCleanupAt = now;
  for (const [key, state] of buckets.entries()) {
    if (!state || state.resetAt <= now) buckets.delete(key);
  }
  if (buckets.size <= MAX_BUCKETS) return;
  const overflow = buckets.size - MAX_BUCKETS;
  let removed = 0;
  for (const key of buckets.keys()) {
    buckets.delete(key);
    if (++removed >= overflow) break;
  }
}

// Lua script: atomic INCR + EXPIRE on first hit, returns current count
const INCR_SCRIPT = `
local count = redis.call('INCR', KEYS[1])
if count == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
return count
`;

async function consumeBucketRedis(redis, key, windowMs) {
  const windowSec = Math.ceil(windowMs / 1000);
  const count = Number(await redis.eval(INCR_SCRIPT, 1, key, String(windowSec)));
  const pttl = await redis.pttl(key);
  const resetAt = Date.now() + Math.max(0, pttl);
  return { count, resetAt };
}

export function createRateLimiter({
  windowMs = 60000,
  maxRequests = 120,
  keyPrefix = "global",
  skip = null,
  requireRedis = false,
} = {}) {
  return async function rateLimit(req, res, next) {
    if (typeof skip === "function" && skip(req) === true) {
      return next();
    }
    const key = buildRateLimitKey(req, keyPrefix);
    let state;
    let mode = "local-fallback";

    try {
      const redis = await getRedisClient();
      if (redis) {
        state = await consumeBucketRedis(redis, key, windowMs);
        mode = "redis";
      } else {
        if (requireRedis) {
          return next(
            new AppError("RATE_LIMIT_BACKEND_UNAVAILABLE", {
              status: 503,
              details: { keyPrefix },
            })
          );
        }
        cleanupBuckets();
        state = consumeBucketLocal({ key, windowMs });
      }
    } catch (_) {
      if (requireRedis) {
        return next(
          new AppError("RATE_LIMIT_BACKEND_UNAVAILABLE", {
            status: 503,
            details: { keyPrefix },
          })
        );
      }
      cleanupBuckets();
      state = consumeBucketLocal({ key, windowMs });
    }

    const remaining = Math.max(0, maxRequests - state.count);
    const retryAfter = Math.max(1, Math.ceil((state.resetAt - nowMs()) / 1000));

    res.setHeader("X-RateLimit-Limit", String(maxRequests));
    res.setHeader("X-RateLimit-Remaining", String(remaining));
    res.setHeader("X-RateLimit-Reset", String(Math.floor(state.resetAt / 1000)));
    res.setHeader("X-RateLimit-Mode", mode);

    if (state.count > maxRequests) {
      res.setHeader("Retry-After", String(retryAfter));
      return next(
        new AppError("RATE_LIMIT_EXCEEDED", {
          status: 429,
          details: { retryAfterSeconds: retryAfter },
        })
      );
    }

    return next();
  };
}
