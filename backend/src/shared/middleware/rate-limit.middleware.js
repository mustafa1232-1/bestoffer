import { AppError } from "../utils/errors.js";

const buckets = new Map();

function nowMs() {
  return Date.now();
}

function keyFromRequest(req, prefix = "global") {
  const forwardedFor = req.headers["x-forwarded-for"];
  const firstForwarded = Array.isArray(forwardedFor)
    ? forwardedFor[0]
    : String(forwardedFor || "").split(",")[0].trim();
  const ip = firstForwarded || req.ip || req.socket?.remoteAddress || "unknown";
  return `${prefix}:${ip}`;
}

function consumeBucket({ key, windowMs, limit }) {
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

export function createRateLimiter({
  windowMs = 60000,
  maxRequests = 120,
  keyPrefix = "global",
} = {}) {
  return function rateLimit(req, res, next) {
    const key = keyFromRequest(req, keyPrefix);
    const state = consumeBucket({
      key,
      windowMs,
      limit: maxRequests,
    });

    const remaining = Math.max(0, maxRequests - state.count);
    const retryAfter = Math.max(1, Math.ceil((state.resetAt - nowMs()) / 1000));

    res.setHeader("X-RateLimit-Limit", String(maxRequests));
    res.setHeader("X-RateLimit-Remaining", String(remaining));
    res.setHeader("X-RateLimit-Reset", String(Math.floor(state.resetAt / 1000)));

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
