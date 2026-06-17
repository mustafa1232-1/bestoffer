import assert from "node:assert/strict";
import test from "node:test";

import { env } from "../config/env.js";
import { createRateLimiter, buildRateLimitKey } from "../shared/middleware/rate-limit.middleware.js";

function buildReq({
  ip = "10.0.0.1",
  forwarded = "",
  userId = null,
  authUserId = null,
  authSessionId = null,
  body = null,
  headers = {},
} = {}) {
  return {
    ip,
    headers: {
      "x-forwarded-for": forwarded,
      ...headers,
    },
    body,
    userId,
    authUserId,
    authSessionId,
    socket: {
      remoteAddress: ip,
    },
  };
}

test("buildRateLimitKey includes user and session context when authenticated", () => {
  const reqA = buildReq({
    ip: "1.1.1.1",
    userId: 77,
    authSessionId: 11,
  });
  const reqB = buildReq({
    ip: "1.1.1.1",
    userId: 77,
    authSessionId: 22,
  });
  const keyA = buildRateLimitKey(reqA, "auth");
  const keyB = buildRateLimitKey(reqB, "auth");
  assert.notEqual(keyA, keyB);
  assert.match(keyA, /rl:auth:1\.1\.1\.1:u:77:11$/);
});

test("buildRateLimitKey falls back to anon when no auth context exists", () => {
  const req = buildReq({
    ip: "2.2.2.2",
    userId: null,
    authUserId: null,
  });
  const key = buildRateLimitKey(req, "api");
  assert.equal(key, "rl:api:2.2.2.2:anon");
});

test("buildRateLimitKey uses device identity for anonymous public traffic", () => {
  const reqA = buildReq({
    ip: "2.2.2.2",
    headers: {
      "x-device-id": "device-alpha",
      "x-client-platform": "flutter",
    },
  });
  const reqB = buildReq({
    ip: "2.2.2.2",
    headers: {
      "x-device-id": "device-beta",
      "x-client-platform": "flutter",
    },
  });
  const reqC = buildReq({
    ip: "2.2.2.2",
    headers: {
      "x-device-id": "device-alpha",
      "x-client-platform": "flutter",
    },
  });

  const keyA = buildRateLimitKey(reqA, "api");
  const keyB = buildRateLimitKey(reqB, "api");
  const keyC = buildRateLimitKey(reqC, "api");

  assert.match(keyA, /^rl:api:2\.2\.2\.2:anon-client:[a-f0-9]{16}$/);
  assert.notEqual(keyA, keyB);
  assert.equal(keyA, keyC);
});

test("buildRateLimitKey prefers forwarded-for first IP", () => {
  const req = buildReq({
    ip: "10.10.10.10",
    forwarded: "8.8.8.8, 1.2.3.4",
    authUserId: 5,
  });
  const key = buildRateLimitKey(req, "api");
  assert.match(key, /^rl:api:8\.8\.8\.8:u:5:na$/);
});

test("buildRateLimitKey uses auth identity hint for anonymous auth requests", () => {
  const reqA = buildReq({
    ip: "3.3.3.3",
    body: { phone: "079 123 45 67" },
  });
  const reqB = buildReq({
    ip: "3.3.3.3",
    body: { phone: "07999999999" },
  });
  const reqC = buildReq({
    ip: "3.3.3.3",
    body: { phone: "079 123 45 67" },
  });

  const keyA = buildRateLimitKey(reqA, "auth");
  const keyB = buildRateLimitKey(reqB, "auth");
  const keyC = buildRateLimitKey(reqC, "auth");

  assert.match(keyA, /^rl:auth:3\.3\.3\.3:anon-id:[a-f0-9]{16}$/);
  assert.notEqual(keyA, keyB);
  assert.equal(keyA, keyC);
});

test("createRateLimiter fails closed when redis is required but unavailable", async () => {
  const redisUrlSnapshot = env.redisUrl;
  env.redisUrl = "";
  const req = buildReq({
    ip: "4.4.4.4",
    userId: 12,
    authSessionId: 99,
  });
  const headers = {};
  const res = {
    setHeader(name, value) {
      headers[name] = value;
    },
  };
  const middleware = createRateLimiter({
    keyPrefix: "sensitive",
    maxRequests: 1,
    windowMs: 1000,
    requireRedis: true,
  });

  let nextError = null;
  try {
    await middleware(req, res, (error) => {
      nextError = error;
    });

    assert.equal(nextError?.message, "RATE_LIMIT_BACKEND_UNAVAILABLE");
    assert.equal(nextError?.status, 503);
    assert.equal(headers["X-RateLimit-Mode"], undefined);
  } finally {
    env.redisUrl = redisUrlSnapshot;
  }
});
