import assert from "node:assert/strict";
import test from "node:test";

import { env } from "../config/env.js";
import {
  __securitySigningTestApi,
  buildRequestBodyHash,
  buildRequestSigningCanonical,
  getRequestSigningRuntimeStatus,
  issueRequestSigningMaterial,
  signRequestCanonical,
  verifySignedRequest,
} from "../modules/security/security.service.js";

function createFakeRedis() {
  const values = new Map();
  return {
    async get(key) {
      return values.has(key) ? values.get(key) : null;
    },
    async set(key, value, ...args) {
      const useNx = args.includes("NX");
      if (useNx && values.has(key)) {
        return null;
      }
      values.set(key, value);
      return "OK";
    },
  };
}

const envSnapshot = {
  securityRequestSigningEnabled: env.securityRequestSigningEnabled,
  securityRequestSigningTtlSec: env.securityRequestSigningTtlSec,
  securityRequestSigningRefreshWindowSec:
    env.securityRequestSigningRefreshWindowSec,
  securityRequestSigningMaxClockSkewSec:
    env.securityRequestSigningMaxClockSkewSec,
  securityRequestSigningNonceTtlSec: env.securityRequestSigningNonceTtlSec,
};

test.afterEach(() => {
  env.securityRequestSigningEnabled = envSnapshot.securityRequestSigningEnabled;
  env.securityRequestSigningTtlSec = envSnapshot.securityRequestSigningTtlSec;
  env.securityRequestSigningRefreshWindowSec =
    envSnapshot.securityRequestSigningRefreshWindowSec;
  env.securityRequestSigningMaxClockSkewSec =
    envSnapshot.securityRequestSigningMaxClockSkewSec;
  env.securityRequestSigningNonceTtlSec =
    envSnapshot.securityRequestSigningNonceTtlSec;
  __securitySigningTestApi.reset();
});

test("issueRequestSigningMaterial and verifySignedRequest accept a valid signed request", async () => {
  const fakeRedis = createFakeRedis();
  const fixedNow = 1_710_000_000_000;
  env.securityRequestSigningEnabled = true;
  env.securityRequestSigningTtlSec = 900;
  env.securityRequestSigningRefreshWindowSec = 120;
  env.securityRequestSigningMaxClockSkewSec = 300;
  env.securityRequestSigningNonceTtlSec = 1200;
  __securitySigningTestApi.setRedisClientFactory(async () => fakeRedis);
  __securitySigningTestApi.setNow(() => fixedNow);
  __securitySigningTestApi.setRandomUUID(() => "key-1");
  __securitySigningTestApi.setRandomBytes((size) => Buffer.alloc(size, 7));

  const material = await issueRequestSigningMaterial({
    userId: 7,
    sessionId: 11,
    deviceFingerprint: "device-hash",
  });

  const body = { amount: 5000, currency: "IQD" };
  const timestamp = String(fixedNow);
  const nonce = "nonce-1";
  const canonical = buildRequestSigningCanonical({
    method: "POST",
    path: "/api/owner/settlements/request",
    timestamp,
    nonce,
    sessionId: 11,
    deviceFingerprint: "device-hash",
    bodyHash: buildRequestBodyHash(body),
  });
  const signature = signRequestCanonical({
    secret: material.signingSecret,
    canonical,
  });

  const verified = await verifySignedRequest({
    method: "POST",
    originalUrl: "/api/owner/settlements/request",
    userId: 7,
    authSessionId: 11,
    authDeviceContext: {
      deviceFingerprint: "device-hash",
    },
    body,
    headers: {
      "x-request-key-id": material.keyId,
      "x-request-timestamp": timestamp,
      "x-request-nonce": nonce,
      "x-request-signature": signature,
    },
  });

  assert.equal(verified.ok, true);
  assert.equal(verified.keyId, material.keyId);
});

test("verifySignedRequest rejects nonce replay", async () => {
  const fakeRedis = createFakeRedis();
  const fixedNow = 1_710_000_000_000;
  env.securityRequestSigningEnabled = true;
  env.securityRequestSigningTtlSec = 900;
  env.securityRequestSigningRefreshWindowSec = 120;
  env.securityRequestSigningMaxClockSkewSec = 300;
  env.securityRequestSigningNonceTtlSec = 1200;
  __securitySigningTestApi.setRedisClientFactory(async () => fakeRedis);
  __securitySigningTestApi.setNow(() => fixedNow);
  __securitySigningTestApi.setRandomUUID(() => "key-2");
  __securitySigningTestApi.setRandomBytes((size) => Buffer.alloc(size, 9));

  const material = await issueRequestSigningMaterial({
    userId: 8,
    sessionId: 12,
    deviceFingerprint: "device-2",
  });
  const body = { amount: 7500 };
  const timestamp = String(fixedNow);
  const nonce = "nonce-2";
  const signature = signRequestCanonical({
    secret: material.signingSecret,
    canonical: buildRequestSigningCanonical({
      method: "POST",
      path: "/api/accountant/opening-balance",
      timestamp,
      nonce,
      sessionId: 12,
      deviceFingerprint: "device-2",
      bodyHash: buildRequestBodyHash(body),
    }),
  });

  const request = {
    method: "POST",
    originalUrl: "/api/accountant/opening-balance",
    userId: 8,
    authSessionId: 12,
    authDeviceContext: {
      deviceFingerprint: "device-2",
    },
    body,
    headers: {
      "x-request-key-id": material.keyId,
      "x-request-timestamp": timestamp,
      "x-request-nonce": nonce,
      "x-request-signature": signature,
    },
  };

  await verifySignedRequest(request);
  await assert.rejects(
    () => verifySignedRequest(request),
    /REQUEST_SIGNATURE_REPLAYED/
  );
});

test("getRequestSigningRuntimeStatus reports redis requirement when enabled", async () => {
  env.securityRequestSigningEnabled = true;
  __securitySigningTestApi.setRedisClientFactory(async () => null);

  const status = await getRequestSigningRuntimeStatus();
  assert.equal(status.enabled, true);
  assert.equal(status.ok, false);
  assert.equal(status.reason, "redis_unavailable");
});
