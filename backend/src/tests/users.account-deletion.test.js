import assert from "node:assert/strict";
import { randomInt, randomUUID } from "node:crypto";
import test from "node:test";

import { app } from "../app.js";
import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { createProviderProfile } from "../modules/services/services.repo.js";
import { deleteMyAccount } from "../modules/users/users.service.js";
import { hashPin } from "../shared/utils/hash.js";
import {
  assertStatus,
  createActor,
  request,
  startLocalServer,
  stopLocalServer,
} from "../scripts/e2eTestUtils.js";

function makePhone(prefix = "077") {
  return `${prefix}${String(randomInt(0, 10_000_000)).padStart(7, "0")}`;
}

function makeUsername(prefix) {
  return `${prefix}_${randomUUID().replace(/-/g, "").slice(0, 8)}`.slice(0, 24);
}

async function firstServiceCategoryId() {
  const r = await q(
    `SELECT id
     FROM service_categories
     WHERE level = 1
       AND is_active = TRUE
     ORDER BY id ASC
     LIMIT 1`
  );
  const id = Number(r.rows[0]?.id || 0);
  assert.ok(id > 0, "expected a seeded service category");
  return id;
}

async function createAuthUser({ role = "user", phone = makePhone(), name }) {
  return createUser({
    fullName: name || `Delete Test ${randomUUID().slice(0, 8)}`,
    username: makeUsername("del"),
    phone,
    pinHash: await hashPin("1234"),
    block: "A1",
    buildingNumber: "A101",
    apartment: "101",
    imageUrl: "https://cdn.example.com/profile.jpg",
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "account_deletion_test_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
}

async function createProviderUserFixture() {
  const user = await createAuthUser({
    role: "service_provider",
    phone: makePhone("078"),
    name: "Provider Delete Test",
  });
  const provider = await createProviderProfile({
    userId: Number(user.id),
    dto: {
      businessName: "Visible Provider Before Delete",
      mainCategoryId: await firstServiceCategoryId(),
      bio: "provider should disappear after account deletion",
      phone: user.phone,
      city: "Baghdad",
      area: "Karrada",
      addressLine: "Test address",
      servesAtHome: true,
      servesAtShop: false,
      servesRemote: false,
      hasEmergencyService: false,
      bookingPolicy: "approval_required",
      pricingMode: "mixed",
      yearsExperience: 3,
      hasTeam: false,
      teamSize: 0,
      acceptsCash: true,
      acceptsElectronic: false,
      averageResponseMinutes: 20,
      available247: false,
      providerGender: "mixed",
      languages: ["ar"],
      areas: [],
      availabilityRules: [],
    },
    moderation: {
      approvalStatus: "approved",
      approvalNote: "Approved for deletion test",
      approvedByUserId: Number(user.id),
      approvedAt: new Date().toISOString(),
    },
  });
  return { user, provider };
}

async function cleanupUsers(userIds) {
  const ids = userIds.map(Number).filter((id) => id > 0);
  if (ids.length === 0) return;
  await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [ids]).catch(
    () => {}
  );
}

test("account deletion rejects unauthenticated requests", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  try {
    const actor = createActor("guest-delete", `acct-${Date.now()}`);
    actor.appFlavor = "user";
    const res = await request(baseUrl, actor, "DELETE", "/api/users/me", {});
    assertStatus(res, 401, "unauthenticated account deletion");
    assert.match(String(res.data?.message || ""), /NO_TOKEN|INVALID_TOKEN/);
  } finally {
    await stopLocalServer(server);
  }
});

test("account deletion anonymizes profile, revokes sessions and push tokens, blocks login, and hides provider profile", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `acct-delete-${Date.now().toString(36)}`;
  const actor = createActor("delete-primary", runTag);
  const second = createActor("delete-secondary", runTag);
  actor.appFlavor = "user";
  second.appFlavor = "user";
  const fixture = await createProviderUserFixture();
  const userId = Number(fixture.user.id);
  const providerId = Number(fixture.provider.id);

  try {
    const login = await request(baseUrl, actor, "POST", "/api/auth/login", {
      phone: fixture.user.phone,
      pin: "1234",
    });
    assertStatus(login, 200, "primary login");
    actor.token = String(login.data?.token || "");
    actor.sessionId = Number(login.data?.sessionId || 0);

    const secondLogin = await request(baseUrl, second, "POST", "/api/auth/login", {
      phone: fixture.user.phone,
      pin: "1234",
    });
    assertStatus(secondLogin, 200, "secondary login");
    second.token = String(secondLogin.data?.token || "");

    const publicBefore = await request(
      baseUrl,
      actor,
      "GET",
      `/api/services/public/providers/${providerId}`
    );
    assertStatus(publicBefore, 200, "public provider before deletion");

    const pushToken = `push-${runTag}`;
    const push = await request(
      baseUrl,
      actor,
      "POST",
      "/api/notifications/push-token",
      {
        token: pushToken,
        platform: "fcm",
        appVersion: "test/1",
        deviceModel: "node-test",
        locale: "en",
      }
    );
    assertStatus(push, 204, "register push token");

    const deleted = await request(baseUrl, actor, "DELETE", "/api/users/me", {
      note: "test requested deletion",
    });
    assertStatus(deleted, 200, "delete account");
    assert.equal(deleted.data?.success, true);
    assert.equal(deleted.data?.status, "deleted");

    const sessionsAfter = await request(
      baseUrl,
      second,
      "GET",
      "/api/auth/sessions"
    );
    assertStatus(sessionsAfter, 401, "other session revoked after deletion");

    const loginAfter = await request(baseUrl, actor, "POST", "/api/auth/login", {
      phone: fixture.user.phone,
      pin: "1234",
    });
    assertStatus(loginAfter, 401, "login with deleted phone blocked");
    assert.equal(loginAfter.data?.message, "INVALID_CREDENTIALS");

    const publicAfter = await request(
      baseUrl,
      actor,
      "GET",
      `/api/services/public/providers/${providerId}`
    );
    assertStatus(publicAfter, 404, "public provider hidden after deletion");

    const db = await q(
      `SELECT
         u.full_name,
         u.phone,
         u.is_account_disabled,
         u.account_deleted,
         u.account_deletion_completed_at,
         p.is_active AS provider_active,
         p.provider_approval_status
       FROM app_user u
       LEFT JOIN service_provider_profiles p ON p.user_id = u.id
       WHERE u.id = $1`,
      [userId]
    );
    const row = db.rows[0];
    assert.equal(row.full_name, "Deleted account");
    assert.equal(row.phone, `deleted_${userId}`);
    assert.equal(row.is_account_disabled, true);
    assert.equal(row.account_deleted, true);
    assert.ok(row.account_deletion_completed_at);
    assert.equal(row.provider_active, false);
    assert.equal(row.provider_approval_status, "suspended");

    const pushRows = await q(
      `SELECT is_active, push_token, device_model, locale
       FROM user_push_token
       WHERE user_id = $1`,
      [userId]
    );
    assert.equal(pushRows.rows.length >= 1, true);
    assert.equal(pushRows.rows.every((row) => row.is_active === false), true);
    assert.equal(
      pushRows.rows.every((row) => String(row.push_token || "").startsWith("deleted:")),
      true
    );
  } finally {
    await stopLocalServer(server);
    await cleanupUsers([userId]);
  }
});

test("account deletion service returns a safe idempotent response when already completed", async () => {
  const user = await createAuthUser({ role: "user", phone: makePhone("079") });
  const userId = Number(user.id);
  try {
    const first = await deleteMyAccount(
      userId,
      { note: "first delete" },
      { authSessionId: 1 }
    );
    assert.equal(first.success, true);
    assert.equal(first.status, "deleted");

    const second = await deleteMyAccount(
      userId,
      { note: "second delete" },
      { authSessionId: 1 }
    );
    assert.equal(second.success, true);
    assert.equal(second.status, "already_deleted");
  } finally {
    await cleanupUsers([userId]);
  }
});
