/* eslint-disable no-console */
import "dotenv/config";

import assert from "node:assert/strict";

import { q } from "../config/db.js";
import { env } from "../config/env.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { allocateRegistrationUsername } from "../modules/auth/auth.service.js";
import { hashPin } from "../shared/utils/hash.js";
import { cleanupLoadArtifactsByRunTag } from "../shared/utils/testArtifactCleanup.js";
import { assertSafeE2EDatabaseTarget } from "./e2eDbSafety.js";
import {
  buildPhone,
  buildRunTag,
  createActor,
  request,
  assertStatus,
  readId,
} from "./e2eTestUtils.js";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    baseUrl:
      String(
        process.env.E2E_BASE_URL ||
          process.env.LOAD_BASE_URL ||
          process.env.BASE_URL ||
          DEFAULT_BASE_URL
      )
        .trim()
        .replace(/\/+$/, ""),
    runTag:
      String(process.env.AUTH_SESSION_PUSH_RUN_TAG || "").trim() ||
      buildRunTag("auth-session-push"),
  };

  for (let i = 0; i < args.length; i += 1) {
    const key = String(args[i] || "").trim();
    const next = String(args[i + 1] || "").trim();
    if (key === "--base-url" && next) {
      out.baseUrl = next.replace(/\/+$/, "");
      i += 1;
      continue;
    }
    if (key === "--run-tag" && next) {
      out.runTag = next;
      i += 1;
    }
  }

  return out;
}

function readString(value) {
  return String(value ?? "").trim();
}

function readErrorCode(response) {
  return readString(response?.data?.message || response?.data?.code).toUpperCase();
}

function assertErrorCode(response, expectedCode, label) {
  assert.equal(
    readErrorCode(response),
    expectedCode,
    `${label} -> expected error code ${expectedCode}, received ${readErrorCode(
      response
    )}, body=${JSON.stringify(response.data)}`
  );
}

function makePhone(prefix, seedOffset) {
  return buildPhone(prefix, Number(String(Date.now() + seedOffset).slice(-8)));
}

async function loginWithSurface(baseUrl, actor, phone, pin, label) {
  const response = await request(baseUrl, actor, "POST", "/api/auth/login", {
    phone,
    pin,
  });
  assertStatus(response, 200, label);
  actor.token = readString(response.data?.token);
  actor.refreshToken = readString(response.data?.refreshToken);
  actor.sessionId = Number(response.data?.sessionId || 0) || null;
  actor.userId = readId(response.data?.user);
  assert.ok(actor.token, `${label} -> missing access token`);
  assert.ok(actor.refreshToken, `${label} -> missing refresh token`);
  assert.ok(actor.sessionId, `${label} -> missing session id`);
  assert.ok(actor.userId, `${label} -> missing user id`);
  return response;
}

async function expectLoginForbidden(baseUrl, actor, phone, pin, label) {
  const response = await request(baseUrl, actor, "POST", "/api/auth/login", {
    phone,
    pin,
  });
  assertStatus(response, 403, label);
  assertErrorCode(response, "FORBIDDEN_APP_SURFACE", label);
  return response;
}

async function registerPushTokenCycle(baseUrl, actor, label) {
  const pushToken = `push-${actor.name}-${actor.userId}-${actor.sessionId}`;
  const register = await request(baseUrl, actor, "POST", "/api/notifications/push-token", {
    token: pushToken,
    userId: actor.userId,
    sessionId: actor.sessionId,
    appFlavor: actor.appFlavor,
    platform: "android",
    appVersion: actor.appVersion,
    deviceModel: actor.model,
    locale: "ar",
  });
  assertStatus(register, 204, `${label} register push token`);

  const statusAfterRegister = await request(
    baseUrl,
    actor,
    "GET",
    "/api/notifications/push-status"
  );
  assertStatus(statusAfterRegister, 200, `${label} push status after register`);
  assert.ok(
    Number(statusAfterRegister.data?.activeTokens || 0) >= 1,
    `${label} -> expected at least one active push token`
  );

  const unregister = await request(baseUrl, actor, "DELETE", "/api/notifications/push-token", {
    token: pushToken,
  });
  assertStatus(unregister, 204, `${label} unregister push token`);

  const statusAfterUnregister = await request(
    baseUrl,
    actor,
    "GET",
    "/api/notifications/push-status"
  );
  assertStatus(
    statusAfterUnregister,
    200,
    `${label} push status after unregister`
  );
  assert.equal(
    Number(statusAfterUnregister.data?.activeTokens || 0),
    0,
    `${label} -> expected zero active push tokens after unregister`
  );
}

async function verifyRealtimeToken(baseUrl, actor, label) {
  const response = await request(baseUrl, actor, "POST", "/api/realtime/token");
  assertStatus(response, 200, label);
  assert.equal(
    readString(response.data?.supabaseUrl).length > 0,
    true,
    `${label} -> missing supabaseUrl`
  );
  assert.equal(
    readString(response.data?.supabaseAnonKey).length > 0,
    true,
    `${label} -> missing supabaseAnonKey`
  );
  assert.equal(
    readString(response.data?.realtimeToken).length > 20,
    true,
    `${label} -> missing realtimeToken`
  );
  assert.equal(
    Number(response.data?.userId || 0),
    Number(actor.userId || 0),
    `${label} -> realtime token user mismatch`
  );
  return response;
}

async function createCompanyAdmin(runTag) {
  const fullName = `Phase 1C Company Admin ${runTag}`;
  const phone = makePhone("071", 11);
  const username = await allocateRegistrationUsername({ fullName, phone });
  const pinHash = await hashPin("1234");
  const user = await createUser({
    fullName,
    username,
    phone,
    pinHash,
    block: "A1",
    buildingNumber: "101",
    apartment: "1",
    role: "admin",
    analyticsConsentGranted: true,
    analyticsConsentVersion: "phase1c_auth_v1",
    analyticsConsentGrantedAt: new Date(),
  });
  return { fullName, phone, pin: "1234", userId: Number(user.id) };
}

async function seedCaptain(baseUrl, companyAdmin, runTag) {
  const actor = createActor("taxi-captain-seed", runTag, "auth-session-push/1");
  actor.appFlavor = "taxi";
  const phone = makePhone("077", 22);
  const response = await request(baseUrl, actor, "POST", "/api/taxi/captain/register", {
    fullName: `Phase 1C Taxi Captain ${runTag}`,
    phone,
    pin: "1234",
    block: "B1",
    buildingNumber: "B101",
    apartment: "201",
    vehicleType: "car",
    carMake: "Toyota",
    carModel: "Corolla",
    carYear: 2022,
    carColor: "White",
    plateNumber: `CAP-${String(Date.now()).slice(-4)}`,
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "phase1c_auth_v1",
  });
  assertStatus(response, 201, "captain register");
  const captainUserId = readId(response.data?.user);
  assert.ok(captainUserId, "captain register -> missing user id");

  const pendingBeforeApproval = await request(
    baseUrl,
    companyAdmin,
    "GET",
    "/api/admin/taxi-captains/pending"
  );
  assertStatus(
    pendingBeforeApproval,
    200,
    "company admin pending captains before approval"
  );
  assert.equal(
    Array.isArray(pendingBeforeApproval.data) &&
      pendingBeforeApproval.data.some((item) => Number(item?.id || 0) === captainUserId),
    true,
    "captain should appear in pending list before approval"
  );

  const approve = await request(
    baseUrl,
    companyAdmin,
    "PATCH",
    `/api/admin/taxi-captains/${captainUserId}/approve`
  );
  assertStatus(approve, 200, "approve taxi captain");

  const pendingAfterApproval = await request(
    baseUrl,
    companyAdmin,
    "GET",
    "/api/admin/taxi-captains/pending"
  );
  assertStatus(
    pendingAfterApproval,
    200,
    "company admin pending captains after approval"
  );
  assert.equal(
    Array.isArray(pendingAfterApproval.data) &&
      pendingAfterApproval.data.some((item) => Number(item?.id || 0) === captainUserId),
    false,
    "captain should disappear from pending list after approval"
  );

  const loginActor = createActor("taxi-captain", runTag, "auth-session-push/1");
  loginActor.appFlavor = "taxi";
  await loginWithSurface(
    baseUrl,
    loginActor,
    phone,
    "1234",
    "taxi captain login after approval"
  );

  return {
    phone,
    userId: captainUserId,
    actor: loginActor,
  };
}

async function createDeliveryUser(baseUrl, companyAdmin, runTag) {
  const phone = makePhone("076", 33);
  const response = await request(baseUrl, companyAdmin, "POST", "/api/admin/users", {
    fullName: `Phase 1C Delivery ${runTag}`,
    phone,
    pin: "1234",
    block: "A2",
    buildingNumber: "A201",
    apartment: "202",
    role: "delivery",
    driverType: "app_driver",
  });
  assertStatus(response, 201, "admin create delivery user");
  const userId = readId(response.data?.user);
  assert.ok(userId, "delivery user -> missing user id");

  const loginActor = createActor("delivery", runTag, "auth-session-push/1");
  loginActor.appFlavor = "delivery";
  await loginWithSurface(baseUrl, loginActor, phone, "1234", "delivery login");
  return { phone, userId, actor: loginActor };
}

async function createOwner(baseUrl, runTag) {
  const phone = makePhone("078", 44);
  const registerActor = createActor("owner-register", runTag, "auth-session-push/1");
  registerActor.appFlavor = "store";
  const register = await request(baseUrl, registerActor, "POST", "/api/owner/register", {
    phone,
    pin: "1234",
    block: "A2",
    buildingNumber: "A201",
    apartment: "301",
    merchantName: `Phase 1C Owner Store ${runTag}`,
    merchantType: "restaurant",
    merchantActivityType: "restaurant",
    merchantDiscoverySelectAll: true,
    merchantDescription: `phase1c-owner-${runTag}`,
    merchantTagline: `phase1c-owner-tag-${runTag}`,
    merchantWorkingHours: "10:00-22:00",
    merchantServiceAreaNote: `phase1c-service-area-${runTag}`,
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "phase1c_auth_v1",
  });
  assertStatus(register, 201, "owner register");
  const ownerUserId = readId(register.data?.user);
  const merchantId = readId(register.data?.merchant);
  assert.ok(ownerUserId, "owner register -> missing user id");
  assert.ok(merchantId, "owner register -> missing merchant id");

  const loginActor = createActor("owner", runTag, "auth-session-push/1");
  loginActor.appFlavor = "store";
  await loginWithSurface(baseUrl, loginActor, phone, "1234", "owner login");

  return {
    phone,
    userId: ownerUserId,
    merchantId,
    actor: loginActor,
  };
}

async function createCustomer(baseUrl, runTag) {
  const phone = makePhone("079", 55);
  const registerActor = createActor("customer", runTag, "auth-session-push/1");
  registerActor.appFlavor = "user";
  const register = await request(baseUrl, registerActor, "POST", "/api/auth/register", {
    fullName: `Phase 1C Customer ${runTag}`,
    phone,
    pin: "1234",
    block: "A1",
    buildingNumber: "A101",
    apartment: "101",
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "phase1c_auth_v1",
  });
  assertStatus(register, 201, "customer register");
  const userId = readId(register.data?.user);
  assert.ok(userId, "customer register -> missing user id");

  registerActor.token = readString(register.data?.token);
  registerActor.refreshToken = readString(register.data?.refreshToken);
  registerActor.sessionId = Number(register.data?.sessionId || 0) || null;
  registerActor.userId = userId;
  assert.ok(registerActor.token, "customer register -> missing access token");
  assert.ok(registerActor.refreshToken, "customer register -> missing refresh token");

  const refreshProbe = { ...registerActor, token: null };
  const refresh = await request(baseUrl, refreshProbe, "POST", "/api/auth/refresh", {
    refreshToken: registerActor.refreshToken,
  });
  assertStatus(refresh, 200, "customer refresh");
  assert.equal(
    Number(refresh.data?.user?.id || 0),
    userId,
    "customer refresh -> user mismatch"
  );
  registerActor.token = readString(refresh.data?.token || registerActor.token);
  registerActor.refreshToken = readString(
    refresh.data?.refreshToken || registerActor.refreshToken
  );

  const secondLoginActor = createActor("customer-second-session", runTag, "auth-session-push/1");
  secondLoginActor.appFlavor = "user";
  await loginWithSurface(baseUrl, secondLoginActor, phone, "1234", "customer second login");

  return {
    phone,
    userId,
    actor: registerActor,
    secondActor: secondLoginActor,
  };
}

async function verifyGuestAuthEdgeCases(baseUrl) {
  const guest = createActor("guest", "guest", "auth-session-push/1");
  guest.appFlavor = "user";

  const realtime = await request(baseUrl, guest, "POST", "/api/realtime/token");
  assertStatus(realtime, 401, "guest realtime token");
  assertErrorCode(realtime, "NO_TOKEN", "guest realtime token");

  const push = await request(baseUrl, guest, "POST", "/api/notifications/push-token", {
    token: "guest-token",
    appFlavor: "user",
    platform: "android",
  });
  assertStatus(push, 401, "guest push token");
  assertErrorCode(push, "NO_TOKEN", "guest push token");

  const refresh = await request(baseUrl, guest, "POST", "/api/auth/refresh", {});
  assertStatus(refresh, 400, "guest refresh without token");
  assertErrorCode(refresh, "VALIDATION_ERROR", "guest refresh without token");

  const logout = await request(baseUrl, guest, "POST", "/api/auth/logout");
  assertStatus(logout, 200, "guest logout");
  assert.equal(Boolean(logout.data?.revoked), false, "guest logout should not revoke");

  const logoutAll = await request(baseUrl, guest, "POST", "/api/auth/logout-all");
  assertStatus(logoutAll, 200, "guest logout-all");
  assert.equal(
    Number(logoutAll.data?.revokedCount || 0),
    0,
    "guest logout-all should not revoke anything"
  );
}

async function verifyWrongSurfaceLoginBlocks(baseUrl, phone, pin, surface, label) {
  const actor = createActor(`${label}-wrong-surface`, label, "auth-session-push/1");
  actor.appFlavor = surface;
  const response = await request(baseUrl, actor, "POST", "/api/auth/login", {
    phone,
    pin,
  });
  assertStatus(response, 403, `${label} wrong surface login`);
  assertErrorCode(response, "FORBIDDEN_APP_SURFACE", `${label} wrong surface login`);
}

async function verifyActorSessionLifecycle(baseUrl, actor, label) {
  const me = await request(baseUrl, actor, "GET", "/api/notifications/unread-count");
  assertStatus(me, 200, `${label} unread count`);

  const realtime = await verifyRealtimeToken(baseUrl, actor, `${label} realtime token`);
  assert.ok(realtime.data || realtime, `${label} realtime token response missing`);
  await registerPushTokenCycle(baseUrl, actor, label);
}

async function main() {
  const cfg = parseArgs();
  console.log(`[auth-session-push] baseUrl=${cfg.baseUrl}`);
  console.log(`[auth-session-push] runTag=${cfg.runTag}`);
  assertSafeE2EDatabaseTarget({
    scriptName: "auth-session-push-check",
    databaseUrl: env.databaseUrl,
  });

  const stepResults = [];
  const runStep = async (label, fn) => {
    const startedAt = Date.now();
    try {
      const value = await fn();
      const elapsed = Date.now() - startedAt;
      stepResults.push({ label, status: "PASS", ms: elapsed });
      console.log(`[auth-session-push] PASS ${label} (${elapsed}ms)`);
      return value;
    } catch (error) {
      const elapsed = Date.now() - startedAt;
      stepResults.push({
        label,
        status: "FAIL",
        ms: elapsed,
        error: String(error?.message || error),
      });
      console.error(`[auth-session-push] FAIL ${label} (${elapsed}ms)`);
      throw error;
    }
  };

  let cleanupSummary = null;
  try {
    cleanupSummary = await runStep("preflight cleanup", () =>
      cleanupLoadArtifactsByRunTag(cfg.runTag)
    );

    await runStep("guest auth edge cases", () =>
      verifyGuestAuthEdgeCases(cfg.baseUrl)
    );

    const superAdminActor = createActor(
      "super-admin",
      cfg.runTag,
      "auth-session-push/1"
    );
    superAdminActor.appFlavor = "user";
    const superAdminLogin = await runStep("super admin user-surface login", () =>
      loginWithSurface(
        cfg.baseUrl,
        superAdminActor,
        env.superAdminPhone,
        env.superAdminPin,
        "super admin user-surface login"
      )
    );
    assert.equal(
      Number(superAdminLogin.data?.user?.isSuperAdmin ? 1 : 0),
      1,
      "super admin should remain super admin on user surface"
    );

    await runStep("super admin store-surface blocked", () =>
      expectLoginForbidden(
        cfg.baseUrl,
        {
          ...createActor("super-admin-store", cfg.runTag, "auth-session-push/1"),
          appFlavor: "store",
        },
        env.superAdminPhone,
        env.superAdminPin,
        "super admin store-surface login"
      )
    );

    await runStep("super admin shell smoke", async () => {
      const unread = await request(
        cfg.baseUrl,
        superAdminActor,
        "GET",
        "/api/notifications/unread-count"
      );
      assertStatus(unread, 200, "super admin unread count");
      const realtime = await verifyRealtimeToken(
        cfg.baseUrl,
        superAdminActor,
        "super admin realtime token"
      );
      assert.equal(
        Number(realtime.data?.userId || 0),
        Number(superAdminActor.userId || 0),
        "super admin realtime token user mismatch"
      );
    });

    const companyAdminSeed = await runStep("seed company admin", () =>
      createCompanyAdmin(cfg.runTag)
    );
    const companyAdmin = createActor("company-admin", cfg.runTag, "auth-session-push/1");
    companyAdmin.appFlavor = "company";
    await runStep("company admin login", () =>
      loginWithSurface(
        cfg.baseUrl,
        companyAdmin,
        companyAdminSeed.phone,
        companyAdminSeed.pin,
        "company admin login"
      )
    );
    await runStep("company admin analytics", async () => {
      const analytics = await request(
        cfg.baseUrl,
        companyAdmin,
        "GET",
        "/api/admin/analytics"
      );
      assertStatus(analytics, 200, "company admin analytics");
    });
    await runStep("company admin wrong-surface blocked", () =>
      expectLoginForbidden(
        cfg.baseUrl,
        {
          ...createActor("company-admin-user", cfg.runTag, "auth-session-push/1"),
          appFlavor: "user",
        },
        companyAdminSeed.phone,
        companyAdminSeed.pin,
        "company admin user-surface"
      )
    );

    const owner = await runStep("owner register/login", () =>
      createOwner(cfg.baseUrl, cfg.runTag)
    );
    await runStep("owner shell smoke", async () => {
      const merchant = await request(cfg.baseUrl, owner.actor, "GET", "/api/owner/merchant");
      assertStatus(merchant, 200, "owner merchant");
      await verifyActorSessionLifecycle(cfg.baseUrl, owner.actor, "owner");
    });
    await runStep("owner wrong-surface blocked", () =>
      expectLoginForbidden(
        cfg.baseUrl,
        {
          ...createActor("owner-user", cfg.runTag, "auth-session-push/1"),
          appFlavor: "user",
        },
        owner.phone,
        "1234",
        "owner user-surface"
      )
    );

    const customer = await runStep("customer register/refresh", () =>
      createCustomer(cfg.baseUrl, cfg.runTag)
    );
    await runStep("customer shell smoke", async () => {
      const unread = await request(
        cfg.baseUrl,
        customer.actor,
        "GET",
        "/api/notifications/unread-count"
      );
      assertStatus(unread, 200, "customer unread count");
      await verifyActorSessionLifecycle(cfg.baseUrl, customer.actor, "customer");
    });
    await runStep("customer wrong-surface blocked", () =>
      expectLoginForbidden(
        cfg.baseUrl,
        {
          ...createActor("customer-store", cfg.runTag, "auth-session-push/1"),
          appFlavor: "store",
        },
        customer.phone,
        "1234",
        "customer store-surface"
      )
    );

    await runStep("customer logout-all revokes second session", async () => {
      const logoutAll = await request(
        cfg.baseUrl,
        customer.actor,
        "POST",
        "/api/auth/logout-all"
      );
      assertStatus(logoutAll, 200, "customer logout-all");
      assert.equal(
        Number(logoutAll.data?.revokedCount || 0) >= 1,
        true,
        "customer logout-all should revoke at least one session"
      );
      const afterRevoke = await request(
        cfg.baseUrl,
        customer.secondActor,
        "GET",
        "/api/notifications/push-status"
      );
      assertStatus(afterRevoke, 401, "customer second session after logout-all");
      assertErrorCode(afterRevoke, "INVALID_TOKEN", "customer second session after logout-all");
    });

    const delivery = await runStep("delivery login", () =>
      createDeliveryUser(cfg.baseUrl, companyAdmin, cfg.runTag)
    );
    await runStep("delivery shell smoke", async () => {
      const readiness = await request(
        cfg.baseUrl,
        delivery.actor,
        "GET",
        "/api/delivery/end-day/readiness"
      );
      assertStatus(readiness, 200, "delivery end-day readiness");
      await verifyActorSessionLifecycle(cfg.baseUrl, delivery.actor, "delivery");
    });
    await runStep("delivery wrong-surface blocked", () =>
      expectLoginForbidden(
        cfg.baseUrl,
        {
          ...createActor("delivery-store", cfg.runTag, "auth-session-push/1"),
          appFlavor: "store",
        },
        delivery.phone,
        "1234",
        "delivery store-surface"
      )
    );

    const captain = await runStep("captain register/approve/login", () =>
      seedCaptain(cfg.baseUrl, companyAdmin, cfg.runTag)
    );
    await runStep("captain shell smoke", async () => {
      const profile = await request(
        cfg.baseUrl,
        captain.actor,
        "GET",
        "/api/taxi/captain/profile"
      );
      assertStatus(profile, 200, "captain profile");
      const currentRide = await request(
        cfg.baseUrl,
        captain.actor,
        "GET",
        "/api/taxi/captain/current-ride"
      );
      assertStatus(currentRide, 200, "captain current ride");
      await verifyActorSessionLifecycle(cfg.baseUrl, captain.actor, "captain");
    });
    await runStep("captain wrong-surface blocked", () =>
      expectLoginForbidden(
        cfg.baseUrl,
        {
          ...createActor("captain-user", cfg.runTag, "auth-session-push/1"),
          appFlavor: "user",
        },
        captain.phone,
        "1234",
        "captain user-surface"
      )
    );

    const loginRefreshProbe = {
      ...customer.actor,
      token: null,
    };
    await runStep("customer refresh lifecycle", async () => {
      const refresh = await request(
        cfg.baseUrl,
        loginRefreshProbe,
        "POST",
        "/api/auth/refresh",
        {
          refreshToken: customer.actor.refreshToken,
        }
      );
      assertStatus(refresh, 200, "customer refresh");
      assert.equal(
        Number(refresh.data?.user?.id || 0),
        Number(customer.userId || 0),
        "customer refresh user mismatch"
      );
    });

    await runStep("company admin push/realtime", async () => {
      await verifyActorSessionLifecycle(cfg.baseUrl, companyAdmin, "company admin");
    });

    console.log(
      JSON.stringify(
        {
          ok: true,
          runTag: cfg.runTag,
          cleanupSummary,
          steps: stepResults,
        },
        null,
        2
      )
    );
  } finally {
    const cleanup = await cleanupLoadArtifactsByRunTag(cfg.runTag).catch((error) => {
      console.warn(`[auth-session-push] cleanup failed: ${error?.message || error}`);
      return null;
    });
    if (cleanup) {
      const residual = await q(
        `SELECT COUNT(*)::int AS count
         FROM app_user
         WHERE full_name ILIKE $1`,
        [`%${cfg.runTag}%`]
      );
      assert.equal(
        Number(residual.rows[0]?.count || 0),
        0,
        "cleanup should remove all runTag-bound users"
      );
      console.log(
        `[auth-session-push] cleanup removed users=${cleanup.removedUsers} merchants=${cleanup.removedMerchants} pharmacyConversations=${cleanup.removedPharmacyConversations}`
      );
    }
  }
}

main().catch((error) => {
  console.error("[auth-session-push] failed", error);
  process.exit(1);
});
