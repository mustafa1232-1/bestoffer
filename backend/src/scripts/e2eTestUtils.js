/* eslint-disable no-console */
import assert from "node:assert/strict";

import { pool, q } from "../config/db.js";
import { env } from "../config/env.js";
import { allocateRegistrationUsername } from "../modules/auth/auth.service.js";
import { hashPin } from "../shared/utils/hash.js";

export function buildRunTag(prefix = "e2e") {
  return `${prefix}-${Date.now().toString(36)}-${Math.random()
    .toString(36)
    .slice(2, 8)}`;
}

export function buildPhone(prefix, seed) {
  const suffix = String(seed).padStart(8, "0").slice(-8);
  return `${prefix}${suffix}`;
}

export function createActor(name, runTag, appVersion = "e2e/1") {
  return {
    name,
    token: null,
    sessionId: null,
    deviceId: `${runTag}-${name}-device`,
    platform: "e2e",
    appFlavor: null,
    appVersion,
    model: `${name}-simulator`,
    userAgent: `${appVersion}/${name}`,
  };
}

export function buildHeaders(actor, { withBody = false } = {}) {
  const appFlavor = String(actor.appFlavor || "").trim();
  const headers = {
    "X-Device-Id": actor.deviceId,
    "X-App-Version": actor.appVersion,
    "X-Device-Model": actor.model,
    "User-Agent": actor.userAgent,
  };
  if (appFlavor) {
    headers["X-Client-Platform"] = `flutter:${appFlavor}`;
    headers["X-App-Flavor"] = appFlavor;
  } else {
    headers["X-Client-Platform"] = actor.platform;
  }
  if (actor.token) {
    headers.Authorization = `Bearer ${actor.token}`;
  }
  if (withBody) {
    headers["Content-Type"] = "application/json";
  }
  return headers;
}

export async function request(baseUrl, actor, method, path, body) {
  const max429Retries = 4;
  const maxTransportRetries = 3;
  for (let attempt = 0; ; attempt += 1) {
    let response;
    try {
      response = await fetch(`${baseUrl}${path}`, {
        method,
        headers: buildHeaders(actor, { withBody: body !== undefined }),
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(20000),
      });
    } catch (error) {
      if (attempt >= maxTransportRetries) {
        throw error;
      }
      await new Promise((resolve) => setTimeout(resolve, (attempt + 1) * 1000));
      continue;
    }

    const raw = await response.text();
    const data = raw
      ? (() => {
          try {
            return JSON.parse(raw);
          } catch (_) {
            return raw;
          }
        })()
      : null;

    if (response.status !== 429 || attempt >= max429Retries) {
      return {
        status: response.status,
        ok: response.ok,
        data,
      };
    }

    const retryHeader = Number(response.headers.get("retry-after") || 0);
    const retryDetails = Number(data?.details?.retryAfterSeconds || 0);
    const waitSec = Math.max(1, retryHeader || retryDetails || 1);
    await new Promise((resolve) => setTimeout(resolve, waitSec * 1000));
  }
}

export function assertStatus(response, expectedStatus, label) {
  assert.equal(
    response.status,
    expectedStatus,
    `${label} -> expected ${expectedStatus}, received ${
      response.status
    }, body=${JSON.stringify(response.data)}`
  );
}

export function readId(value) {
  const id = Number(value?.id || 0);
  return Number.isFinite(id) && id > 0 ? id : null;
}

export async function startLocalServer(app) {
  return new Promise((resolve, reject) => {
    const startedServer = app.listen(0, "127.0.0.1", () => {
      const address = startedServer.address();
      resolve({
        server: startedServer,
        baseUrl: `http://127.0.0.1:${address.port}`,
      });
    });
    startedServer.on("error", reject);
  });
}

export async function stopLocalServer(server) {
  if (!server) return;
  await new Promise((resolve) => server.close(resolve));
}

export async function ensureSuperAdminAccount() {
  const superPhone = String(env.superAdminPhone || "").trim();
  const superPin = String(env.superAdminPin || "").trim();
  const superName = String(env.superAdminName || "Super Admin").trim();

  if (!/^\d{8,20}$/.test(superPhone)) {
    throw new Error("SUPER_ADMIN_PHONE_INVALID");
  }
  if (!/^\d{4,8}$/.test(superPin)) {
    throw new Error("SUPER_ADMIN_PIN_INVALID");
  }

  const pinHash = await hashPin(superPin);
  const username = await allocateRegistrationUsername({
    fullName: superName,
    phone: superPhone,
  });
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `UPDATE app_user
       SET is_super_admin = FALSE
       WHERE is_super_admin = TRUE`
    );
    await client.query(
      `INSERT INTO app_user
        (
          full_name,
          username,
          phone,
          pin_hash,
          block,
          building_number,
          apartment,
          role,
          is_super_admin,
          analytics_consent_granted,
          analytics_consent_version,
          analytics_consent_granted_at
        )
       VALUES ($1,$2,$3,$4,'A','1','1','admin',TRUE,TRUE,'system_seed_v1',NOW())
       ON CONFLICT (phone)
       DO UPDATE SET
         full_name = EXCLUDED.full_name,
         username = COALESCE(NULLIF(app_user.username, ''), EXCLUDED.username),
         pin_hash = EXCLUDED.pin_hash,
         role = 'admin',
         is_super_admin = TRUE,
         analytics_consent_granted = TRUE,
         analytics_consent_version = 'system_seed_v1',
         analytics_consent_granted_at = COALESCE(
           app_user.analytics_consent_granted_at,
           NOW()
         )`,
      [superName, username, superPhone, pinHash]
    );
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }

  const seeded = await q(
    `SELECT id
     FROM app_user
     WHERE phone = $1
     LIMIT 1`,
    [superPhone]
  );
  const superAdminId = Number(seeded.rows[0]?.id || 0);
  assert.ok(superAdminId > 0, "Super admin seeding failed");
  return superAdminId;
}

export async function getLatestNotification({
  userId,
  type,
  payloadChecks = null,
}) {
  const clauses = ["user_id = $1", "type = $2"];
  const params = [Number(userId), String(type)];

  if (payloadChecks && typeof payloadChecks === "object") {
    for (const [key, value] of Object.entries(payloadChecks)) {
      params.push(String(value));
      clauses.push(`COALESCE(payload->>'${key}', '') = $${params.length}`);
    }
  }

  const result = await q(
    `SELECT id, type, title, body, payload, created_at
     FROM app_notification
     WHERE ${clauses.join(" AND ")}
     ORDER BY id DESC
     LIMIT 1`,
    params
  );

  return result.rows[0] || null;
}

export async function expectNotification(check, label) {
  let notification = null;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    notification = await getLatestNotification(check);
    if (notification) break;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.ok(notification, `${label} -> notification not found`);
  return notification;
}

export async function cleanupAdminArtifacts({
  adminSessionId = null,
  adminSessionIds = [],
  superAdminId = null,
  runTag = null,
  approvalPaths = [],
}) {
  const allSessionIds = [...adminSessionIds, adminSessionId]
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value) && value > 0);

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    if (allSessionIds.length > 0) {
      await client.query(`DELETE FROM user_session WHERE id = ANY($1::bigint[])`, [
        allSessionIds,
      ]);
    }
    if (superAdminId && approvalPaths.length > 0) {
      await client.query(
        `DELETE FROM user_activity_event
         WHERE user_id = $1
           AND path = ANY($2::text[])`,
        [Number(superAdminId), approvalPaths]
      );
    }
    if (runTag) {
      await client.query(
        `DELETE FROM admin_audit_event
         WHERE summary ILIKE $1
            OR COALESCE(target_label, '') ILIKE $1
            OR COALESCE(metadata::text, '') ILIKE $1`,
        [`%${runTag}%`]
      );
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
