/* eslint-disable no-console */
import "dotenv/config";

import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";

import { env } from "../config/env.js";
import { cleanupLoadArtifactsByRunTag } from "../shared/utils/testArtifactCleanup.js";
import { assertSafeE2EDatabaseTarget } from "./e2eDbSafety.js";
import {
  assertStatus,
  buildPhone,
  buildRunTag,
  createActor,
  readId,
  request,
} from "./e2eTestUtils.js";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";
const DEFAULT_OUTPUT_FILE = path.join(
  process.cwd(),
  "qa_artifacts",
  "phase_3d_android_rc",
  "qa-role-matrix.json"
);

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    baseUrl: String(
      process.env.QA_ROLE_MATRIX_BASE_URL ||
        process.env.LOAD_BASE_URL ||
        process.env.E2E_BASE_URL ||
        DEFAULT_BASE_URL
    )
      .trim()
      .replace(/\/+$/, ""),
    runTag: String(process.env.QA_ROLE_MATRIX_RUN_TAG || "").trim() || buildRunTag("qa-matrix"),
    outputFile: String(process.env.QA_ROLE_MATRIX_FILE || "").trim() || DEFAULT_OUTPUT_FILE,
    keepOnSuccess:
      ["1", "true", "yes", "on"].includes(
        String(process.env.QA_ROLE_MATRIX_KEEP || "").trim().toLowerCase()
      ),
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
      continue;
    }
    if (key === "--output-file" && next) {
      out.outputFile = next;
      i += 1;
      continue;
    }
    if (key === "--cleanup-on-success") {
      out.keepOnSuccess = false;
    }
  }

  return out;
}

function readString(value) {
  return String(value ?? "").trim();
}

function normalizeCode(value) {
  return readString(value)
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 32);
}

function makeActor(label, runTag, appFlavor) {
  const actor = createActor(label, runTag, "qa-matrix/1");
  actor.appFlavor = appFlavor;
  return actor;
}

async function loginWithPath(baseUrl, { label, appFlavor, phone, pin, loginPath }) {
  const actor = makeActor(label, "qa-matrix", appFlavor);
  const response = await request(baseUrl, actor, "POST", loginPath, { phone, pin });
  assertStatus(response, 200, `${label} login`);

  actor.token = readString(response.data?.token);
  actor.refreshToken = readString(response.data?.refreshToken);
  actor.sessionId = Number(response.data?.sessionId || 0) || null;
  actor.userId = readId(response.data?.user);
  actor.companyRoles = Array.isArray(response.data?.memberships)
    ? response.data.memberships
        .map((membership) => readString(membership?.role))
        .filter(Boolean)
    : [];
  actor.companyId = Array.isArray(response.data?.memberships)
    ? readId(response.data.memberships[0]?.company) || readId(response.data.memberships[0]?.companyId)
    : null;
  actor.isSuperAdmin = response.data?.user?.isSuperAdmin === true;

  assert.ok(actor.token, `${label} -> missing access token`);
  assert.ok(actor.refreshToken, `${label} -> missing refresh token`);
  assert.ok(actor.userId, `${label} -> missing user id`);
  return { actor, response };
}

async function loginAuth(baseUrl, { label, appFlavor, phone, pin }) {
  return loginWithPath(baseUrl, {
    label,
    appFlavor,
    phone,
    pin,
    loginPath: "/api/auth/login",
  });
}

async function loginCompany(baseUrl, { label, phone, pin }) {
  return loginWithPath(baseUrl, {
    label,
    appFlavor: "company",
    phone,
    pin,
    loginPath: "/api/company/auth/login",
  });
}

async function createCustomer(baseUrl, runTag, prefix, label) {
  const phone = buildPhone(prefix, Number(String(Date.now()).slice(-8)));
  const actor = makeActor(label, runTag, "user");
  const response = await request(baseUrl, actor, "POST", "/api/auth/register", {
    fullName: `${label} ${runTag}`,
    phone,
    pin: "1234",
    block: "A1",
    buildingNumber: "A101",
    apartment: "101",
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "phase3d_matrix_v1",
  });
  assertStatus(response, 201, `${label} register`);
  return {
    label,
    phone,
    pin: "1234",
    userId: readId(response.data?.user),
    role: String(response.data?.user?.role || "user"),
    appFlavor: "user",
  };
}

async function createOwner(baseUrl, runTag, prefix, label, merchantBody) {
  const phone = buildPhone(prefix, Number(String(Date.now()).slice(-8)));
  const actor = makeActor(label, runTag, "store");
  const response = await request(baseUrl, actor, "POST", "/api/owner/register", {
    phone,
    pin: "1234",
    block: merchantBody.block || "A2",
    buildingNumber: merchantBody.buildingNumber || "A201",
    apartment: merchantBody.apartment || "201",
    merchantName: merchantBody.merchantName,
    merchantType: merchantBody.merchantType || "restaurant",
    merchantActivityType: merchantBody.merchantActivityType || "restaurant",
    merchantDiscoverySelectAll: merchantBody.merchantDiscoverySelectAll !== false,
    merchantDiscoverySubcategory: merchantBody.merchantDiscoverySubcategory || null,
    merchantDescription: merchantBody.merchantDescription || `${label} description ${runTag}`,
    merchantTagline: merchantBody.merchantTagline || `${label} tagline ${runTag}`,
    merchantWorkingHours: merchantBody.merchantWorkingHours || "10:00-22:00",
    merchantServiceAreaNote: merchantBody.merchantServiceAreaNote || `${label} service area ${runTag}`,
    merchantSupportsChat: merchantBody.merchantSupportsChat !== false,
    merchantSupportsAttachments: merchantBody.merchantSupportsAttachments !== false,
    merchantSupportsPharmacyWorkflow:
      merchantBody.merchantSupportsPharmacyWorkflow === true,
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "phase3d_matrix_v1",
  });
  assertStatus(response, 201, `${label} register`);
  return {
    label,
    phone,
    pin: "1234",
    userId: readId(response.data?.user),
    merchantId: readId(response.data?.merchant),
    role: String(response.data?.user?.role || "owner"),
    appFlavor: "store",
  };
}

async function createStoreEmployee(baseUrl, runTag, ownerActor, ownerMerchantId, label) {
  const phone = buildPhone("072", Number(String(Date.now()).slice(-8)));
  const response = await request(baseUrl, ownerActor, "POST", "/api/hr/employees/invite", {
    merchantId: ownerMerchantId,
    fullName: `${label} ${runTag}`,
    phone,
    pin: "1234",
    roleTag: "staff",
    displayName: `${label} display ${runTag}`,
    contactEmail: `${normalizeCode(label)}-${runTag}@example.com`,
    employmentType: "full_time",
    baseSalary: 0,
    currency: "IQD",
    workDaysPerWeek: 6,
    shiftStartTime: "09:00",
    shiftEndTime: "18:00",
    permissions: ["view_orders", "manage_employees"],
    isActive: true,
    notes: `${label} invited for ${runTag}`,
  });
  assertStatus(response, 201, `${label} invite`);
  return {
    label,
    phone,
    pin: "1234",
    userId: readId(response.data?.user),
    role: String(response.data?.user?.role || "owner"),
    appFlavor: "store",
    merchantId: ownerMerchantId,
    employee: true,
  };
}

async function createDeliveryCourier(baseUrl, runTag, superAdminActor, label, approved) {
  const phone = buildPhone(approved ? "076" : "075", Number(String(Date.now()).slice(-8)));
  const createResponse = await request(baseUrl, superAdminActor, "POST", "/api/admin/users", {
    fullName: `${label} ${runTag}`,
    phone,
    pin: "1234",
    block: "B1",
    buildingNumber: "B101",
    apartment: "301",
    role: "delivery",
    driverType: "app_driver",
  });
  assertStatus(createResponse, 201, `${label} create`);
  const userId = readId(createResponse.data?.user);
  assert.ok(userId, `${label} -> missing user id`);

  if (approved) {
    const approveResponse = await request(
      baseUrl,
      superAdminActor,
      "PATCH",
      `/api/admin/delivery/${userId}/approve`
    );
    assertStatus(approveResponse, 200, `${label} approve`);
  }

  return {
    label,
    phone,
    pin: "1234",
    userId,
    role: "delivery",
    appFlavor: "delivery",
    deliveryAccountApproved: approved,
  };
}

async function createTaxiCaptain(baseUrl, runTag, superAdminActor, label) {
  const phone = buildPhone("077", Number(String(Date.now()).slice(-8)));
  const createResponse = await request(baseUrl, makeActor(label, runTag, "taxi"), "POST", "/api/taxi/captain/register", {
    fullName: `${label} ${runTag}`,
    phone,
    pin: "1234",
    block: "C1",
    buildingNumber: "C101",
    apartment: "401",
    vehicleType: "car",
    carMake: "Toyota",
    carModel: "Corolla",
    carYear: 2023,
    carColor: "White",
    plateNumber: `${normalizeCode(label).slice(0, 6).toUpperCase()}-${String(Date.now()).slice(-4)}`,
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "phase3d_matrix_v1",
  });
  assertStatus(createResponse, 201, `${label} register`);
  const userId = readId(createResponse.data?.user);
  assert.ok(userId, `${label} -> missing user id`);

  const approveResponse = await request(
    baseUrl,
    superAdminActor,
    "PATCH",
    `/api/admin/taxi-captains/${userId}/approve`
  );
  assertStatus(approveResponse, 200, `${label} approve`);

  return {
    label,
    phone,
    pin: "1234",
    userId,
    role: String(createResponse.data?.user?.role || "taxi_captain"),
    appFlavor: "taxi",
    isTaxiCaptain: true,
  };
}

async function createCompanyMatrix(baseUrl, runTag, superAdminActor) {
  const ownerPhone = buildPhone("071", Number(String(Date.now()).slice(-8)));
  const companyName = `Phase 3D Company ${runTag}`;
  const companyCode = normalizeCode(`phase-3d-${runTag}`);
  const createResponse = await request(baseUrl, superAdminActor, "POST", "/api/company/admin/companies", {
    name: companyName,
    code: companyCode,
    summary: `Phase 3D QA company ${runTag}`,
    businessType: "general",
    headquartersAddress: "Baghdad",
    contactPhone: ownerPhone,
    owner: {
      fullName: `Company Owner ${runTag}`,
      phone: ownerPhone,
      pin: "1234",
      workTitle: "Company Owner",
      workCompany: companyName,
    },
  });
  assertStatus(createResponse, 201, "company create");
  const companyId = readId(createResponse.data?.company);
  assert.ok(companyId, "company create -> missing company id");

  const ownerLogin = await loginCompany(baseUrl, {
    label: "company_owner",
    phone: ownerPhone,
    pin: "1234",
  });

  const companyUsers = [];
  const addCompanyUser = async (role, label, offsetPrefix) => {
    const phone = buildPhone(offsetPrefix, Number(String(Date.now() + companyUsers.length).slice(-8)));
    const response = await request(baseUrl, ownerLogin.actor, "POST", "/api/company/users", {
      fullName: `${label} ${runTag}`,
      phone,
      pin: "1234",
      role,
      workTitle: label,
      workCompany: companyName,
    });
    assertStatus(response, 201, `${label} create`);
    companyUsers.push({
      label,
      phone,
      pin: "1234",
      role: "company_portal",
      companyRole: role,
      appFlavor: "company",
      companyId,
    });
    return { phone, pin: "1234" };
  };

  await addCompanyUser("company_manager", "company_manager", "072");
  await addCompanyUser("finance_viewer", "company_finance", "073");
  await addCompanyUser("operations_viewer", "company_operations", "074");

  return {
    companyId,
    companyName,
    owner: {
      label: "company_owner",
      phone: ownerPhone,
      pin: "1234",
      role: "company_portal",
      companyRole: "company_owner",
      appFlavor: "company",
      companyId,
    },
    companyUsers,
  };
}

async function main() {
  const cfg = parseArgs();
  console.log(`[qa-role-matrix-bootstrap] baseUrl=${cfg.baseUrl}`);
  console.log(`[qa-role-matrix-bootstrap] runTag=${cfg.runTag}`);

  assertSafeE2EDatabaseTarget({
    scriptName: "qa-role-matrix-bootstrap",
    databaseUrl: env.databaseUrl,
    allowProductionOverride: process.env.ALLOW_QA_ROLE_MATRIX_PROD_OVERRIDE,
  });

  if (String(process.env.ALLOW_QA_ROLE_MATRIX_BOOTSTRAP || "").trim().toLowerCase() !== "true") {
    throw new Error(
      "ALLOW_QA_ROLE_MATRIX_BOOTSTRAP=true is required before generating the QA role matrix."
    );
  }

  const cleanupBefore = await cleanupLoadArtifactsByRunTag(cfg.runTag).catch((error) => {
    console.warn(
      `[qa-role-matrix-bootstrap] pre-cleanup skipped: ${String(error?.message || error)}`
    );
    return null;
  });
  if (cleanupBefore) {
    console.log(
      `[qa-role-matrix-bootstrap] pre-cleanup removed users=${cleanupBefore.removedUsers} merchants=${cleanupBefore.removedMerchants}`
    );
  }

  const generated = {
    baseUrl: cfg.baseUrl,
    runTag: cfg.runTag,
    createdAt: new Date().toISOString(),
    accounts: [],
    notes: [
      "Generated by backend/src/scripts/qaRoleMatrixBootstrap.js",
      "Company portal, service provider, and other extended roles are handled separately in the permissions matrix when fixture cleanup is available.",
    ],
  };

  const superAdminPhone = readString(env.superAdminPhone);
  const superAdminPin = readString(env.superAdminPin);
  if (!superAdminPhone || !superAdminPin) {
    throw new Error("SUPER_ADMIN_CREDENTIALS_REQUIRED");
  }

  const superAdminLogin = await loginAuth(cfg.baseUrl, {
    label: "super_admin",
    appFlavor: "user",
    phone: superAdminPhone,
    pin: superAdminPin,
  });
  generated.accounts.push({
    label: "super_admin_user_surface",
    role: "admin",
    appFlavor: "user",
    phone: superAdminPhone,
    pin: superAdminPin,
    userId: superAdminLogin.actor.userId,
    isSuperAdmin: true,
    surfaceNote: "QA-only super admin user-surface exception",
  });

  const adminPhone = buildPhone("070", Number(String(Date.now()).slice(-8)));
  const adminCreate = await request(cfg.baseUrl, superAdminLogin.actor, "POST", "/api/admin/users", {
    fullName: `Phase 3D Admin ${cfg.runTag}`,
    phone: adminPhone,
    pin: "1234",
    block: "HQ",
    buildingNumber: "1",
    apartment: "1",
    role: "admin",
  });
  assertStatus(adminCreate, 201, "create admin");
  const adminLogin = await loginAuth(cfg.baseUrl, {
    label: "admin",
    appFlavor: "company",
    phone: adminPhone,
    pin: "1234",
  });
  generated.accounts.push({
    label: "admin",
    role: "admin",
    appFlavor: "company",
    phone: adminPhone,
    pin: "1234",
    userId: adminLogin.actor.userId,
  });

  const customerA = await createCustomer(cfg.baseUrl, cfg.runTag, "079", "customer_a");
  const customerB = await createCustomer(cfg.baseUrl, cfg.runTag, "078", "customer_b");
  generated.accounts.push(customerA, customerB);

  const ownerA = await createOwner(cfg.baseUrl, cfg.runTag, "077", "store_owner_a", {
    merchantName: `Phase 3D Store ${cfg.runTag}`,
    merchantType: "restaurant",
    merchantActivityType: "restaurant",
    merchantDiscoverySelectAll: true,
    merchantDescription: `phase3d-store-${cfg.runTag}`,
    merchantTagline: `phase3d-store-tag-${cfg.runTag}`,
    merchantWorkingHours: "10:00-22:00",
    merchantServiceAreaNote: `phase3d-store-area-${cfg.runTag}`,
  });
  const ownerALogin = await loginAuth(cfg.baseUrl, {
    label: "store_owner_a",
    appFlavor: "store",
    phone: ownerA.phone,
    pin: ownerA.pin,
  });
  generated.accounts.push({ ...ownerA, userId: ownerALogin.actor.userId });

  const storeEmployee = await createStoreEmployee(
    cfg.baseUrl,
    cfg.runTag,
    ownerALogin.actor,
    ownerA.merchantId,
    "store_employee"
  );
  generated.accounts.push(storeEmployee);

  const ownerB = await createOwner(cfg.baseUrl, cfg.runTag, "076", "pharmacy_owner", {
    merchantName: `Phase 3D Pharmacy ${cfg.runTag}`,
    merchantType: "market",
    merchantActivityType: "pharmacy",
    merchantDiscoverySubcategory: "prescriptions",
    merchantDescription: `phase3d-pharmacy-${cfg.runTag}`,
    merchantTagline: `phase3d-pharmacy-tag-${cfg.runTag}`,
    merchantWorkingHours: "24h",
    merchantServiceAreaNote: `phase3d-pharmacy-area-${cfg.runTag}`,
    merchantSupportsPharmacyWorkflow: true,
    merchantSupportsChat: true,
    merchantSupportsAttachments: true,
  });
  const ownerBLogin = await loginAuth(cfg.baseUrl, {
    label: "pharmacy_owner",
    appFlavor: "store",
    phone: ownerB.phone,
    pin: ownerB.pin,
  });
  generated.accounts.push({ ...ownerB, userId: ownerBLogin.actor.userId });

  const deliveryA = await createDeliveryCourier(cfg.baseUrl, cfg.runTag, superAdminLogin.actor, "delivery_courier_a", true);
  const deliveryB = await createDeliveryCourier(cfg.baseUrl, cfg.runTag, superAdminLogin.actor, "delivery_courier_b", false);
  const deliveryALogin = await loginAuth(cfg.baseUrl, {
    label: "delivery_courier_a",
    appFlavor: "delivery",
    phone: deliveryA.phone,
    pin: deliveryA.pin,
  });
  generated.accounts.push({ ...deliveryA, userId: deliveryALogin.actor.userId });
  generated.accounts.push(deliveryB);

  const taxiCaptainA = await createTaxiCaptain(cfg.baseUrl, cfg.runTag, superAdminLogin.actor, "taxi_captain_a");
  const taxiCaptainB = await createTaxiCaptain(cfg.baseUrl, cfg.runTag, superAdminLogin.actor, "taxi_captain_b");
  const taxiCaptainALogin = await loginAuth(cfg.baseUrl, {
    label: "taxi_captain_a",
    appFlavor: "taxi",
    phone: taxiCaptainA.phone,
    pin: taxiCaptainA.pin,
  });
  const taxiCaptainBLogin = await loginAuth(cfg.baseUrl, {
    label: "taxi_captain_b",
    appFlavor: "taxi",
    phone: taxiCaptainB.phone,
    pin: taxiCaptainB.pin,
  });
  generated.accounts.push({ ...taxiCaptainA, userId: taxiCaptainALogin.actor.userId });
  generated.accounts.push({ ...taxiCaptainB, userId: taxiCaptainBLogin.actor.userId });

  const outputDir = path.dirname(cfg.outputFile);
  await fs.mkdir(outputDir, { recursive: true });
  await fs.writeFile(cfg.outputFile, `${JSON.stringify(generated, null, 2)}\n`, "utf8");
  await fs.chmod(cfg.outputFile, 0o600).catch(() => {});

  console.log(`[qa-role-matrix-bootstrap] wrote ${cfg.outputFile}`);
  console.log(
    `[qa-role-matrix-bootstrap] accounts=${generated.accounts.length} superAdmin=${generated.accounts.some((a) => a.label === "super_admin_user_surface")}`
  );

  if (cfg.keepOnSuccess) {
    console.log(
      `[qa-role-matrix-bootstrap] keeping generated QA accounts for follow-up permission checks`
    );
    return;
  }

  const cleanupAfter = await cleanupLoadArtifactsByRunTag(cfg.runTag).catch((error) => {
    console.warn(
      `[qa-role-matrix-bootstrap] post-cleanup skipped: ${String(error?.message || error)}`
    );
    return null;
  });
  if (cleanupAfter) {
    console.log(
      `[qa-role-matrix-bootstrap] post-cleanup removed users=${cleanupAfter.removedUsers} merchants=${cleanupAfter.removedMerchants}`
    );
  }
}

main().catch((error) => {
  console.error(`[qa-role-matrix-bootstrap] fatal=${error?.message || error}`);
  process.exitCode = 1;
});
