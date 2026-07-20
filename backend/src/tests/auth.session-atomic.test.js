import "dotenv/config";

import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";

import { q } from "../config/db.js";
import {
  createUser,
  createUserSession,
} from "../modules/auth/auth.repo.js";
import * as authService from "../modules/auth/auth.service.js";
import { hashPin } from "../shared/utils/hash.js";

function uniqueSuffix() {
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

function hashSecret(value) {
  return crypto.createHash("sha256").update(String(value || "")).digest("hex");
}

function token(label) {
  return `${label}_${crypto.randomBytes(32).toString("base64url")}`;
}

async function createSessionFixture(label) {
  const suffix = uniqueSuffix();
  const user = await createUser({
    fullName: `Atomic Session ${label} ${suffix}`,
    username: `atomic_${label}_${suffix}`.slice(0, 24),
    phone: `07${String(Date.now()).slice(-9)}`,
    pinHash: await hashPin("1234"),
    block: "B1",
    buildingNumber: "B101",
    apartment: "101",
    analyticsConsentGranted: true,
    analyticsConsentVersion: "auth_atomic_test_v1",
    analyticsConsentGrantedAt: new Date(),
  });
  const refreshToken = token(`${label}_refresh`);
  const recoverySecret = token(`${label}_recovery`);
  const session = await createUserSession({
    userId: user.id,
    refreshToken,
    tokenJti: token(`${label}_jti`),
    deviceFingerprint: "device-a",
    userAgent: "atomic-session-test",
    ipAddress: "127.0.0.1",
    expiresAt: new Date(Date.now() + 86400_000),
    deviceSessionId: token(`${label}_device`).slice(0, 80),
    recoverySecretHash: hashSecret(recoverySecret),
    appSurface: "user",
  });
  return {
    userId: Number(user.id),
    sessionId: Number(session.id),
    refreshToken,
    recoverySecret,
    deviceSessionId: session.device_session_id,
  };
}

async function cleanupFixture(fx) {
  if (!fx?.userId) return;
  await q(`DELETE FROM user_session WHERE user_id=$1`, [fx.userId]).catch(() => {});
  await q(`DELETE FROM app_user WHERE id=$1`, [fx.userId]).catch(() => {});
}

test("atomic refresh burst rotates one generation and shares the current bundle", async () => {
  const fx = await createSessionFixture("refresh");
  try {
    const results = await Promise.all(
      Array.from({ length: 50 }, () =>
        authService.refreshSession(fx.refreshToken, {
          deviceFingerprint: "device-a",
          appFlavor: "user",
          userAgent: "atomic-session-test",
          ipAddress: "127.0.0.1",
        })
      )
    );

    const refreshTokens = new Set(results.map((result) => result.refreshToken));
    assert.equal(refreshTokens.size, 1);
    assert.notEqual([...refreshTokens][0], fx.refreshToken);

    const row = (
      await q(
        `SELECT refresh_generation, previous_refresh_token_hash, refresh_token, is_revoked
         FROM user_session
         WHERE id=$1`,
        [fx.sessionId]
      )
    ).rows[0];
    assert.equal(row.is_revoked, false);
    assert.equal(row.refresh_generation, 1);
    assert.equal(row.previous_refresh_token_hash, hashSecret(fx.refreshToken));
    assert.equal(row.refresh_token, [...refreshTokens][0]);
  } finally {
    await cleanupFixture(fx);
  }
});

test("atomic recovery keeps device binding and does not rotate recovery secret", async () => {
  const fx = await createSessionFixture("recover");
  try {
    const results = await Promise.all(
      Array.from({ length: 20 }, () =>
        authService.recoverSession(
          {
            deviceSessionId: fx.deviceSessionId,
            deviceRecoverySecret: fx.recoverySecret,
            appFlavor: "user",
          },
          {
            deviceFingerprint: "device-a",
            appFlavor: "user",
            userAgent: "atomic-session-test",
            ipAddress: "127.0.0.1",
          }
        )
      )
    );
    assert.equal(new Set(results.map((result) => result.refreshToken)).size, 1);
    assert.equal(results.some((result) => result.deviceRecoverySecret), false);

    await assert.rejects(
      authService.recoverSession(
        {
          deviceSessionId: fx.deviceSessionId,
          deviceRecoverySecret: fx.recoverySecret,
          appFlavor: "user",
        },
        {
          deviceFingerprint: "device-b",
          appFlavor: "user",
        }
      ),
      (error) => error?.message === "DEVICE_REVERIFICATION_REQUIRED"
    );
  } finally {
    await cleanupFixture(fx);
  }
});
