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

// role='admin' يكفي لاجتياز requireBackoffice + قالب دور admin يمنح
// merchants.approve و taxi.captains.approve. لا نرفع is_super_admin حتى لا نصطدم
// بفهرس السوبر-أدمن الأوحد على قاعدة QA المشتركة.
async function createAdminUser() {
  const admin = await createUser({
    fullName: `Account Creation Admin ${randomUUID().slice(0, 8)}`,
    username: makeUsername("adm"),
    phone: makePhone("079"),
    pinHash: await hashPin("1234"),
    block: "A1",
    buildingNumber: "A101",
    apartment: "101",
    role: "admin",
    analyticsConsentGranted: true,
    analyticsConsentVersion: "admin_account_creation_test_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
  });
  return admin;
}

async function cleanupMerchant(merchantId) {
  const id = Number(merchantId);
  if (!(id > 0)) return;
  await q(`DELETE FROM merchant_billing_profile WHERE merchant_id = $1`, [id]).catch(
    () => {}
  );
  await q(`DELETE FROM merchant WHERE id = $1`, [id]).catch(() => {});
}

async function cleanupUsers(userIds) {
  const ids = userIds.map(Number).filter((id) => id > 0);
  if (ids.length === 0) return;
  await q(`DELETE FROM taxi_captain_profile WHERE user_id = ANY($1::bigint[])`, [
    ids,
  ]).catch(() => {});
  await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [ids]).catch(
    () => {}
  );
}

test("admin creates an auto-approved store with inline financial terms", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `admin-store-${Date.now().toString(36)}`;
  const adminActor = createActor("admin", runTag);
  adminActor.appFlavor = "admin";
  const admin = await createAdminUser();
  const ownerPhone = makePhone("078");
  let merchantId = null;
  let ownerUserId = null;

  try {
    const adminLogin = await request(baseUrl, adminActor, "POST", "/api/auth/login", {
      phone: admin.phone,
      pin: "1234",
    });
    assertStatus(adminLogin, 200, "admin login");
    adminActor.token = String(adminLogin.data?.token || "");

    const created = await request(
      baseUrl,
      adminActor,
      "POST",
      "/api/admin/accounts/store",
      {
        fullName: "Admin Created Store Owner",
        phone: ownerPhone,
        pin: "1234",
        merchantName: "متجر الاختبار الإداري",
        merchantType: "market",
        merchantActivityType: "furnishings",
        merchantDescription: "وصف متجر تم إنشاؤه من قبل الإدمن",
        merchantPhone: ownerPhone,
        block: "A1",
        buildingNumber: "A101",
        apartment: "101",
        financialTerms: { commissionValue: 12 },
      }
    );
    assertStatus(created, 201, "admin store creation");
    merchantId = Number(created.data?.merchant?.id || 0);
    ownerUserId = Number(created.data?.user?.id || 0);
    assert.ok(merchantId > 0, "merchant id returned");
    assert.ok(ownerUserId > 0, "owner user id returned");
    // الفرق الجوهري: المتجر مُعتمَد فوراً بلا انتظار موافقة المالك.
    assert.equal(created.data?.merchant?.isApproved, true, "store auto-approved");
    assert.equal(created.data?.merchant?.approvalStatus, "approved");

    // الشروط المالية طُبِّقت (العمولة المُدخَلة 12 + الافتراضيات).
    const profile = await q(
      `SELECT commission_value FROM merchant_billing_profile WHERE merchant_id = $1`,
      [merchantId]
    );
    assert.equal(Number(profile.rows[0]?.commission_value), 12);

    // المالك المُنشأ يستطيع تسجيل الدخول مباشرةً.
    const ownerLogin = await request(baseUrl, createActor("owner", runTag), "POST", "/api/auth/login", {
      phone: ownerPhone,
      pin: "1234",
    });
    assertStatus(ownerLogin, 200, "created owner can log in");
    assert.equal(Number(ownerLogin.data?.user?.id || 0), ownerUserId);
  } finally {
    await stopLocalServer(server);
    await cleanupMerchant(merchantId);
    await cleanupUsers([ownerUserId, Number(admin.id)]);
  }
});

test("admin creates an auto-approved taxi captain account", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `admin-taxi-${Date.now().toString(36)}`;
  const adminActor = createActor("admin", runTag);
  adminActor.appFlavor = "admin";
  const admin = await createAdminUser();
  const captainPhone = makePhone("078");
  let captainUserId = null;

  try {
    const adminLogin = await request(baseUrl, adminActor, "POST", "/api/auth/login", {
      phone: admin.phone,
      pin: "1234",
    });
    assertStatus(adminLogin, 200, "admin login");
    adminActor.token = String(adminLogin.data?.token || "");

    const created = await request(
      baseUrl,
      adminActor,
      "POST",
      "/api/admin/accounts/taxi-captain",
      {
        fullName: "Admin Created Captain",
        phone: captainPhone,
        pin: "1234",
        block: "A1",
        buildingNumber: "A101",
        apartment: "101",
        vehicleType: "car",
        carMake: "Toyota",
        carModel: "Corolla",
        carYear: 2019,
        carColor: "White",
        plateNumber: `AC-${String(Date.now()).slice(-4)}`,
        plateGovernorate: "بغداد",
      }
    );
    assertStatus(created, 201, "admin taxi captain creation");
    captainUserId = Number(created.data?.id || 0);
    assert.ok(captainUserId > 0, "captain user id returned");
    // الفرق الجوهري: الحساب مُعتمَد فوراً بلا انتظار موافقة.
    assert.equal(created.data?.taxiAccountApproved, true, "captain auto-approved");
    assert.equal(created.data?.role, "taxi_captain");

    const approvedRow = await q(
      `SELECT taxi_account_approved FROM app_user WHERE id = $1`,
      [captainUserId]
    );
    assert.equal(approvedRow.rows[0]?.taxi_account_approved, true);

    // الكابتن المُنشأ يستطيع تسجيل الدخول مباشرةً.
    const captainLogin = await request(baseUrl, createActor("captain", runTag), "POST", "/api/auth/login", {
      phone: captainPhone,
      pin: "1234",
    });
    assertStatus(captainLogin, 200, "created captain can log in");
    assert.equal(Number(captainLogin.data?.user?.id || 0), captainUserId);
  } finally {
    await stopLocalServer(server);
    await cleanupUsers([captainUserId, Number(admin.id)]);
  }
});

test("non-privileged backoffice user is denied account creation", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `admin-deny-${Date.now().toString(36)}`;
  const actor = createActor("callcenter", runTag);
  actor.appFlavor = "admin";
  // call_center: يجتاز requireBackoffice لكنه لا يملك merchants.approve.
  const staff = await createUser({
    fullName: `Denied Staff ${randomUUID().slice(0, 8)}`,
    username: makeUsername("cc"),
    phone: makePhone("079"),
    pinHash: await hashPin("1234"),
    block: "A1",
    buildingNumber: "A101",
    apartment: "101",
    role: "call_center",
    analyticsConsentGranted: true,
    analyticsConsentVersion: "admin_account_creation_test_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
  });

  try {
    const login = await request(baseUrl, actor, "POST", "/api/auth/login", {
      phone: staff.phone,
      pin: "1234",
    });
    assertStatus(login, 200, "staff login");
    actor.token = String(login.data?.token || "");

    const denied = await request(
      baseUrl,
      actor,
      "POST",
      "/api/admin/accounts/store",
      {
        phone: makePhone("078"),
        pin: "1234",
        merchantName: "متجر مرفوض",
        merchantActivityType: "furnishings",
        merchantDescription: "يجب أن يُرفض",
      }
    );
    assertStatus(denied, 403, "store creation denied without permission");
  } finally {
    await stopLocalServer(server);
    await cleanupUsers([Number(staff.id)]);
  }
});
