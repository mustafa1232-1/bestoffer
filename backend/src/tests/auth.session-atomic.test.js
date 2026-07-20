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

function decodeClaims(accessToken) {
  const payload = String(accessToken || "").split(".")[1] || "";
  return JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
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
  await q(`DELETE FROM taxi_captain_profile WHERE user_id=$1`, [fx.userId]).catch(
    () => {}
  );
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

test("previous refresh token stays usable inside the grace window", async () => {
  const fx = await createSessionFixture("grace");
  try {
    const rotated = await authService.refreshSession(fx.refreshToken, {
      deviceFingerprint: "device-a",
      appFlavor: "user",
      userAgent: "atomic-session-test",
      ipAddress: "127.0.0.1",
    });
    assert.notEqual(rotated.refreshToken, fx.refreshToken);

    // The already-rotated token must still authenticate during the grace
    // window and must hand back the current bundle instead of revoking.
    const graced = await authService.refreshSession(fx.refreshToken, {
      deviceFingerprint: "device-a",
      appFlavor: "user",
      userAgent: "atomic-session-test",
      ipAddress: "127.0.0.1",
    });
    assert.equal(graced.refreshToken, rotated.refreshToken);

    const row = (
      await q(
        `SELECT is_revoked, refresh_generation, refresh_token
         FROM user_session WHERE id=$1`,
        [fx.sessionId]
      )
    ).rows[0];
    assert.equal(row.is_revoked, false);
    // Replaying the stale token must not burn another generation.
    assert.equal(row.refresh_generation, 1);
    assert.equal(row.refresh_token, rotated.refreshToken);
  } finally {
    await cleanupFixture(fx);
  }
});

test("atomic recovery keeps device binding and does not rotate recovery secret", async () => {
  const fx = await createSessionFixture("recover");
  try {
    const secretHashBefore = (
      await q(`SELECT recovery_secret_hash FROM user_session WHERE id=$1`, [
        fx.sessionId,
      ])
    ).rows[0].recovery_secret_hash;

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

    // A concurrent recovery burst must leave the stored secret untouched,
    // otherwise the device could never recover again.
    const secretHashAfter = (
      await q(`SELECT recovery_secret_hash, is_revoked FROM user_session WHERE id=$1`, [
        fx.sessionId,
      ])
    ).rows[0];
    assert.equal(secretHashAfter.recovery_secret_hash, secretHashBefore);
    assert.equal(secretHashAfter.is_revoked, false);

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

test("legacy delivery account with a taxi profile stays delivery after refresh and recovery", async () => {
  const fx = await createSessionFixture("legacy");
  try {
    // Legacy shape: the account is a courier that also carries a taxi captain
    // profile. Neither refresh nor recovery may promote it onto the taxi
    // surface.
    await q(
      `UPDATE app_user
          SET role='delivery',
              taxi_account_approved=TRUE,
              delivery_account_approved=TRUE
        WHERE id=$1`,
      [fx.userId]
    );
    await q(
      `INSERT INTO taxi_captain_profile
         (user_id, vehicle_type, car_make, car_model, car_year, plate_number)
       VALUES ($1, 'sedan', 'Toyota', 'Corolla', 2020, $2)
       ON CONFLICT (user_id) DO NOTHING`,
      [fx.userId, `LEG${String(fx.userId).slice(-6)}`]
    );
    await q(`UPDATE user_session SET app_surface='delivery' WHERE id=$1`, [
      fx.sessionId,
    ]);

    const refreshed = await authService.refreshSession(fx.refreshToken, {
      deviceFingerprint: "device-a",
      appFlavor: "delivery",
      userAgent: "atomic-session-test",
      ipAddress: "127.0.0.1",
    });
    assert.equal(refreshed.user.role, "delivery");
    // sessionAuthSelect drives both paths. If its is_taxi_captain lacks the
    // role guard, the refreshed access token claims a captain identity for a
    // courier and the account drifts off the delivery surface.
    assert.equal(decodeClaims(refreshed.token).tc, false);

    const recovered = await authService.recoverSession(
      {
        deviceSessionId: fx.deviceSessionId,
        deviceRecoverySecret: fx.recoverySecret,
        appFlavor: "delivery",
      },
      {
        deviceFingerprint: "device-a",
        appFlavor: "delivery",
        userAgent: "atomic-session-test",
        ipAddress: "127.0.0.1",
      }
    );
    assert.equal(recovered.user.role, "delivery");
    assert.equal(decodeClaims(recovered.token).tc, false);

    const row = (
      await q(`SELECT app_surface, is_revoked FROM user_session WHERE id=$1`, [
        fx.sessionId,
      ])
    ).rows[0];
    assert.equal(row.app_surface, "delivery");
    assert.equal(row.is_revoked, false);
  } finally {
    await cleanupFixture(fx);
  }
});
