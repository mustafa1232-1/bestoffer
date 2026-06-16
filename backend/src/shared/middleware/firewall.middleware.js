import { env } from "../../config/env.js";
import { getRedisClient, isRedisConfigured } from "../../config/redis.js";
import { buildRedisKey, redisPrefixes } from "../../config/redis-keys.js";
import { AppError } from "../utils/errors.js";

const localViolationState = new Map();
const LOCAL_STATE_CLEANUP_INTERVAL_MS = 30_000;
let lastCleanupAt = 0;

const cpBadUaPatterns = [
  /sqlmap/i,
  /acunetix/i,
  /nikto/i,
  /masscan/i,
  /nmap/i,
  /zgrab/i,
  /arachni/i,
  /havij/i,
];

const sqliPattern =
  /\b(union(\s+all)?\s+select|select\s+.+\s+from|insert\s+into|update\s+\w+\s+set|delete\s+from|drop\s+table|or\s+1\s*=\s*1|benchmark\s*\(|sleep\s*\(|pg_sleep\s*\(|information_schema)\b/i;
const xssPattern =
  /(<\s*script|javascript:|onerror\s*=|onload\s*=|<\s*svg|document\.cookie|<\s*iframe)/i;
const pathTraversalPattern = /(\.\.\/|\.\.\\)/i;
const commandInjectionPattern =
  /(;|\|\||&&)\s*(curl|wget|bash|sh|python|node|perl)\b/i;

function nowMs() {
  return Date.now();
}

function toLowerSet(items) {
  return new Set(
    (Array.isArray(items) ? items : [])
      .map((item) => String(item || "").trim().toUpperCase())
      .filter(Boolean)
  );
}

const allowedMethods = toLowerSet(env.firewallAllowedMethods);
const trustedIps = new Set(
  (Array.isArray(env.firewallTrustedIps) ? env.firewallTrustedIps : [])
    .map((item) => String(item || "").trim())
    .filter(Boolean)
);

function extractIp(req) {
  const forwardedFor = req.headers["x-forwarded-for"];
  const firstForwarded = Array.isArray(forwardedFor)
    ? forwardedFor[0]
    : String(forwardedFor || "")
        .split(",")[0]
        .trim();
  return firstForwarded || req.ip || req.socket?.remoteAddress || "unknown";
}

function utf8ByteLength(value) {
  return Buffer.byteLength(String(value || ""), "utf8");
}

function headerByteSize(req) {
  let total = 0;
  for (const [key, value] of Object.entries(req.headers || {})) {
    total += utf8ByteLength(key);
    if (Array.isArray(value)) {
      for (const item of value) total += utf8ByteLength(item);
    } else {
      total += utf8ByteLength(value);
    }
  }
  return total;
}

function getRawQuery(req) {
  const original = String(req.originalUrl || req.url || "");
  const idx = original.indexOf("?");
  if (idx < 0) return "";
  return original.slice(idx + 1);
}

function cleanupLocalState(now = nowMs()) {
  if (now - lastCleanupAt < LOCAL_STATE_CLEANUP_INTERVAL_MS) return;
  lastCleanupAt = now;
  for (const [ip, state] of localViolationState.entries()) {
    const resetExpired = !state?.windowResetAt || state.windowResetAt <= now;
    const blockExpired = !state?.blockedUntil || state.blockedUntil <= now;
    if (resetExpired && blockExpired) {
      localViolationState.delete(ip);
    }
  }
}

function getOrCreateLocalState(ip) {
  const now = nowMs();
  let state = localViolationState.get(ip);
  if (!state) {
    state = {
      count: 0,
      windowResetAt: now + env.firewallViolationWindowMs,
      blockedUntil: 0,
      lastReason: null,
    };
    localViolationState.set(ip, state);
    return state;
  }

  if (state.windowResetAt <= now) {
    state.count = 0;
    state.windowResetAt = now + env.firewallViolationWindowMs;
  }
  return state;
}

function recordLocalViolation(ip, reason) {
  const state = getOrCreateLocalState(ip);
  state.count += 1;
  state.lastReason = reason || state.lastReason;
  if (state.count >= env.firewallViolationMax) {
    state.blockedUntil = nowMs() + env.firewallBlockDurationMs;
  }
  return state;
}

function isLocalBlocked(ip) {
  const state = localViolationState.get(ip);
  if (!state?.blockedUntil) return false;
  return state.blockedUntil > nowMs();
}

async function isRedisBlocked(ip) {
  if (!isRedisConfigured()) return false;
  const client = await getRedisClient();
  if (!client) return false;
  const key = buildRedisKey(redisPrefixes.firewall, "block", ip);
  const exists = await client.exists(key);
  return Number(exists || 0) > 0;
}

async function recordRedisViolation(ip, reason) {
  if (!isRedisConfigured()) return null;
  const client = await getRedisClient();
  if (!client) return null;

  const now = nowMs();
  const violationsKey = buildRedisKey(redisPrefixes.firewall, "violations", ip);
  const blockKey = buildRedisKey(redisPrefixes.firewall, "block", ip);
  const reasonKey = buildRedisKey(redisPrefixes.firewall, "last-reason", ip);
  const tx = client.multi();
  tx.incr(violationsKey);
  tx.pexpire(violationsKey, env.firewallViolationWindowMs, "NX");
  tx.set(reasonKey, String(reason || "unknown"), "PX", env.firewallViolationWindowMs);
  tx.pttl(violationsKey);

  const out = await tx.exec();
  const count = Number(out?.[0]?.[1] || 0);
  const ttlMsRaw = Number(out?.[3]?.[1] || -1);
  const ttlMs = ttlMsRaw > 0 ? ttlMsRaw : env.firewallViolationWindowMs;

  if (count >= env.firewallViolationMax) {
    await client.set(blockKey, "1", "PX", env.firewallBlockDurationMs);
  }

  return {
    count,
    resetAt: now + ttlMs,
    blocked: count >= env.firewallViolationMax,
  };
}

function containsSuspiciousPattern(text) {
  const value = String(text || "");
  if (!value) return null;
  if (env.firewallBlockPathTraversal && pathTraversalPattern.test(value)) {
    return "path_traversal_pattern";
  }
  if (env.firewallBlockSqli && sqliPattern.test(value)) {
    return "sqli_pattern";
  }
  if (env.firewallBlockXss && xssPattern.test(value)) {
    return "xss_pattern";
  }
  if (commandInjectionPattern.test(value)) {
    return "command_injection_pattern";
  }
  return null;
}

function inspectValue(value, depth = 0) {
  if (depth > 6 || value == null) return null;
  if (typeof value === "string") {
    return containsSuspiciousPattern(value);
  }
  if (Array.isArray(value)) {
    for (const entry of value) {
      const reason = inspectValue(entry, depth + 1);
      if (reason) return reason;
    }
    return null;
  }
  if (typeof value === "object") {
    for (const [key, entry] of Object.entries(value)) {
      const keyReason = containsSuspiciousPattern(key);
      if (keyReason) return keyReason;
      const valueReason = inspectValue(entry, depth + 1);
      if (valueReason) return valueReason;
    }
    return null;
  }
  return null;
}

function inspectRequestPre(req) {
  const method = String(req.method || "").toUpperCase();
  if (!allowedMethods.has(method)) {
    return { reason: "method_not_allowed", stage: "pre", value: method };
  }

  const path = String(req.originalUrl || req.url || "");
  if (utf8ByteLength(path) > env.firewallMaxPathLength) {
    return { reason: "path_too_long", stage: "pre", value: path.slice(0, 120) };
  }

  const rawQuery = getRawQuery(req);
  if (utf8ByteLength(rawQuery) > env.firewallMaxQueryLength) {
    return {
      reason: "query_too_long",
      stage: "pre",
      value: rawQuery.slice(0, 120),
    };
  }

  const bytes = headerByteSize(req);
  if (bytes > env.firewallMaxHeaderBytes) {
    return { reason: "headers_too_large", stage: "pre", value: String(bytes) };
  }

  const ua = String(req.headers["user-agent"] || "");
  if (env.firewallBlockBadUserAgent && ua) {
    const badUa = cpBadUaPatterns.find((pattern) => pattern.test(ua));
    if (badUa) {
      return { reason: "bad_user_agent", stage: "pre", value: ua.slice(0, 120) };
    }
  }

  const inlineReason = containsSuspiciousPattern(path) || containsSuspiciousPattern(rawQuery);
  if (inlineReason) {
    return {
      reason: inlineReason,
      stage: "pre",
      value: path.slice(0, 120),
    };
  }

  return null;
}

function inspectRequestPost(req) {
  const queryReason = inspectValue(req.query);
  if (queryReason) {
    return { reason: queryReason, stage: "post", value: "query" };
  }

  const bodyReason = inspectValue(req.body);
  if (bodyReason) {
    return { reason: bodyReason, stage: "post", value: "body" };
  }

  return null;
}

function blockedError(reason, ip, stage, value, blockedForMs = null) {
  return new AppError("FIREWALL_BLOCKED_REQUEST", {
    status: 403,
    code: "FIREWALL_BLOCKED_REQUEST",
    details: {
      reason,
      stage,
      ip,
      value,
      blockedForSec:
        typeof blockedForMs === "number" && blockedForMs > 0
          ? Math.ceil(blockedForMs / 1000)
          : null,
    },
  });
}

export function firewallGuard({ stage = "pre" } = {}) {
  const normalizedStage = stage === "post" ? "post" : "pre";
  return async function firewallMiddleware(req, res, next) {
    try {
      if (!env.firewallEnabled) return next();
      cleanupLocalState();

      const ip = extractIp(req);
      if (trustedIps.has(ip)) return next();

      if (isLocalBlocked(ip)) {
        const blockedForMs = (localViolationState.get(ip)?.blockedUntil || 0) - nowMs();
        return next(
          blockedError("ip_temporarily_blocked", ip, normalizedStage, null, blockedForMs)
        );
      }

      const redisBlocked = await isRedisBlocked(ip);
      if (redisBlocked) {
        return next(blockedError("ip_temporarily_blocked", ip, normalizedStage, null));
      }

      const inspection =
        normalizedStage === "pre" ? inspectRequestPre(req) : inspectRequestPost(req);
      if (!inspection) return next();

      const localState = recordLocalViolation(ip, inspection.reason);
      const redisState = await recordRedisViolation(ip, inspection.reason);
      const blockedNow = Boolean(
        redisState?.blocked || localState.blockedUntil > nowMs()
      );

      if (blockedNow) {
        const blockedForMs = Math.max(0, localState.blockedUntil - nowMs());
        return next(
          blockedError(
            `${inspection.reason}:threshold`,
            ip,
            inspection.stage,
            inspection.value,
            blockedForMs || env.firewallBlockDurationMs
          )
        );
      }

      return next(
        blockedError(inspection.reason, ip, inspection.stage, inspection.value)
      );
    } catch (error) {
      return next(error);
    }
  };
}
