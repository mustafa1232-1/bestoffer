import assert from "node:assert/strict";
import { randomInt, randomUUID } from "node:crypto";
import test from "node:test";

import { app } from "../app.js";
import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
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

async function createAdminUser() {
  const admin = await createUser({
    fullName: `Provider Approval Admin ${randomUUID().slice(0, 8)}`,
    username: makeUsername("adm"),
    phone: makePhone("079"),
    pinHash: await hashPin("1234"),
    block: "A1",
    buildingNumber: "A101",
    apartment: "101",
    role: "admin",
    analyticsConsentGranted: true,
    analyticsConsentVersion: "provider_free_activation_test_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
  });
  // role='admin' يكفي لاجتياز requireBackoffice على مسار موافقة مقدّم الخدمة؛
  // لا نرفع is_super_admin حتى لا نصطدم بفهرس السوبر-أدمن الأوحد على قاعدة QA
  // المشتركة (idx_app_user_single_super_admin).
  return { ...admin, is_super_admin: false };
}

async function cleanupUsers(userIds) {
  const ids = userIds.map(Number).filter((id) => id > 0);
  if (ids.length === 0) return;
  await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [ids]).catch(
    () => {}
  );
}

test("free provider application requires moderation approval and legacy payment endpoints stay disabled", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `free-provider-${Date.now().toString(36)}`;
  const providerActor = createActor("provider", runTag);
  const adminActor = createActor("admin", runTag);
  providerActor.appFlavor = "user";
  adminActor.appFlavor = "admin";
  const admin = await createAdminUser();
  const providerPhone = makePhone("078");
  let providerUserId = null;

  try {
    const application = await request(
      baseUrl,
      providerActor,
      "POST",
      "/api/services/provider/register",
      {
        fullName: "Free Provider Applicant",
        businessName: "Free Provider Co",
        phone: providerPhone,
        pin: "1234",
        mainCategoryId: await firstServiceCategoryId(),
        city: "Baghdad",
        area: "Karrada",
        addressLine: "Free provider test address",
        servesAtHome: true,
        servesAtShop: false,
        servesRemote: false,
        hasEmergencyService: false,
        bookingPolicy: "approval_required",
        pricingMode: "mixed",
        acceptsCash: true,
        acceptsElectronic: false,
        paymentConfirmed: true,
        payment_pending_confirmation: true,
        paidActivation: true,
      }
    );
    assertStatus(application, 201, "submit free provider application");
    assert.equal(application.data?.status, "under_review");
    assert.equal(application.data?.canLogin, false);
    assert.equal(application.data?.requiresProviderAction, false);
    const providerId = Number(application.data?.application?.id || 0);
    assert.ok(providerId > 0, "provider application id is returned");

    const pendingStatus = await request(
      baseUrl,
      providerActor,
      "POST",
      "/api/services/provider/application/status",
      { phone: providerPhone, pin: "1234" }
    );
    assertStatus(pendingStatus, 200, "provider application pending status");
    assert.equal(pendingStatus.data?.status, "under_review");
    assert.equal(pendingStatus.data?.canLogin, false);

    const providerLogin = await request(
      baseUrl,
      providerActor,
      "POST",
      "/api/auth/login",
      { phone: providerPhone, pin: "1234" }
    );
    assertStatus(providerLogin, 200, "provider login before approval");
    providerActor.token = String(providerLogin.data?.token || "");
    providerUserId = Number(providerLogin.data?.user?.id || 0);
    assert.ok(providerUserId > 0, "provider user id is returned");

    const deniedWorkspace = await request(
      baseUrl,
      providerActor,
      "GET",
      "/api/services/provider/workspace"
    );
    assertStatus(deniedWorkspace, 403, "workspace denied before approval");
    assert.equal(
      deniedWorkspace.data?.message,
      "SERVICE_PROVIDER_APPLICATION_UNDER_REVIEW"
    );

    const legacyPayment = await request(
      baseUrl,
      providerActor,
      "POST",
      "/api/services/provider/subscription/requests/1/respond-offer",
      {
        phone: providerPhone,
        pin: "1234",
        action: "accept",
        note: "should remain disabled",
      }
    );
    assertStatus(legacyPayment, 410, "legacy provider payment endpoint disabled");
    assert.equal(
      legacyPayment.data?.message,
      "SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED"
    );

    const adminLogin = await request(
      baseUrl,
      adminActor,
      "POST",
      "/api/auth/login",
      { phone: admin.phone, pin: "1234" }
    );
    assertStatus(adminLogin, 200, "admin login");
    adminActor.token = String(adminLogin.data?.token || "");

    const approved = await request(
      baseUrl,
      adminActor,
      "PATCH",
      `/api/admin/services/providers/${providerId}/status`,
      {
        status: "approved",
        note: "Identity and submitted service details reviewed; no payment required.",
        paymentConfirmed: false,
      }
    );
    assertStatus(approved, 200, "approve provider through moderation");
    assert.equal(approved.data?.providerApprovalStatus, "approved");

    const approvedStatus = await request(
      baseUrl,
      providerActor,
      "POST",
      "/api/services/provider/application/status",
      { phone: providerPhone, pin: "1234" }
    );
    assertStatus(approvedStatus, 200, "provider application approved status");
    assert.equal(approvedStatus.data?.status, "approved");
    assert.equal(approvedStatus.data?.canLogin, true);

    const workspace = await request(
      baseUrl,
      providerActor,
      "GET",
      "/api/services/provider/workspace"
    );
    assertStatus(workspace, 200, "workspace available after moderation approval");

    const db = await q(
      `SELECT provider_approval_status, approval_note
       FROM service_provider_profiles
       WHERE id = $1`,
      [providerId]
    );
    assert.equal(db.rows[0]?.provider_approval_status, "approved");
    assert.match(String(db.rows[0]?.approval_note || ""), /10% commission/i);
  } finally {
    await stopLocalServer(server);
    await cleanupUsers([providerUserId, Number(admin.id)]);
  }
});
