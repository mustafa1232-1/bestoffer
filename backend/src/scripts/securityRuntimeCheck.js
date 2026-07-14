/* eslint-disable no-console */
import "dotenv/config";

import {
  assertStatus,
  buildPhone,
  buildRunTag,
  createActor,
  readId,
  request,
} from "./e2eTestUtils.js";
import { assertSafeE2EDatabaseTarget } from "./e2eDbSafety.js";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    baseUrl: String(process.env.E2E_BASE_URL || DEFAULT_BASE_URL).trim().replace(/\/+$/, ""),
    runTag: String(process.env.SECURITY_RUN_TAG || "").trim() || buildRunTag("security"),
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

async function rawRequest(baseUrl, method, path, { headers = {}, body } = {}) {
  let response = null;
  let lastError = null;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      response = await fetch(`${baseUrl}${path}`, {
        method,
        headers:
          body === undefined
            ? headers
            : { "Content-Type": "application/json", ...headers },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(20000),
      });
      lastError = null;
      break;
    } catch (error) {
      lastError = error;
      if (attempt >= 2) {
        throw error;
      }
      await new Promise((resolve) => setTimeout(resolve, (attempt + 1) * 1000));
    }
  }
  if (!response) {
    throw lastError || new Error("RAW_REQUEST_FAILED");
  }
  const text = await response.text();
  let data = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch (_) {
      data = text;
    }
  }
  return { response, status: response.status, data };
}

async function registerCustomer(baseUrl, runTag) {
  const actor = createActor("security-customer", runTag, "security-check/1");
  actor.appFlavor = "user";
  const phone = buildPhone("079", Number(String(Date.now()).slice(-8)));
  const out = await request(baseUrl, actor, "POST", "/api/auth/register", {
    fullName: `Security Customer ${runTag}`,
    phone,
    pin: "1234",
    block: "A1",
    buildingNumber: "A101",
    apartment: "101",
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "security_check_v1",
  });
  assertStatus(out, 201, "register customer");
  actor.token = String(out.data?.token || "");
  return { actor, phone, userId: readId(out.data?.user) };
}

async function registerOwner(baseUrl, runTag) {
  const actor = createActor("security-owner", runTag, "security-check/1");
  actor.appFlavor = "store";
  const phone = buildPhone("078", Number(String(Date.now() + 19).slice(-8)));
  const out = await request(baseUrl, actor, "POST", "/api/owner/register", {
    phone,
    pin: "1234",
    block: "A2",
    buildingNumber: "A202",
    apartment: "202",
    merchantName: `Security Merchant ${runTag}`,
    merchantType: "restaurant",
    merchantActivityType: "restaurant",
    merchantDiscoverySubcategory: "eastern",
    merchantDescription: `security-merchant-${runTag}`,
    merchantTagline: `security-tagline-${runTag}`,
    merchantWorkingHours: "09:00-23:00",
    merchantServiceAreaNote: `security-service-area-${runTag}`,
    merchantSupportsChat: true,
    merchantSupportsAttachments: true,
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "security_check_v1",
  });
  assertStatus(out, 201, "register owner");
  actor.token = String(out.data?.token || "");
  return {
    actor,
    phone,
    ownerUserId: readId(out.data?.user),
    merchantId: readId(out.data?.merchant),
  };
}

async function approveOwnerMerchant(baseUrl, admin, ownerActor, merchantId) {
  const approve = await request(
    baseUrl,
    admin,
    "PATCH",
    `/api/admin/merchants/${merchantId}/approve`,
    {
      commissionType: "percentage",
      commissionValue: 10,
      serviceFeeType: "fixed",
      serviceFeeValue: 500,
      deliveryFeeMode: "dynamic",
      appDeliveryFeeValue: 1000,
      storeDeliveryFeeValue: 0,
      appDeliveryEnabled: true,
      merchantDeliveryEnabled: true,
      settlementCycle: "weekly",
      distributionPolicy: "commission_service_delivery",
      effectiveFrom: new Date().toISOString(),
    }
  );
  assertStatus(approve, 204, "approve owner merchant");

  const accept = await request(
    baseUrl,
    ownerActor,
    "POST",
    "/api/owner/merchant/financial-terms/accept"
  );
  assertStatus(accept, 200, "accept merchant financial terms");
}

async function createDeliveryAgent(baseUrl, ownerActor, runTag) {
  const phone = buildPhone("076", Number(String(Date.now() + 37).slice(-8)));
  const created = await request(
    baseUrl,
    ownerActor,
    "POST",
    "/api/owner/delivery-agents",
    {
      fullName: `Security Delivery ${runTag}`,
      phone,
      pin: "1234",
    }
  );
  assertStatus(created, 201, "create delivery agent");
  return { phone, userId: readId(created.data?.user) };
}

async function createManagedBackofficeUser(baseUrl, superAdmin, runTag, role, seedOffset) {
  const phone = buildPhone("075", Number(String(Date.now() + seedOffset).slice(-8)));
  const created = await request(baseUrl, superAdmin, "POST", "/api/admin/users", {
    fullName: `Security ${role} ${runTag}`,
    phone,
    pin: "1234",
    block: "A3",
    buildingNumber: "A303",
    apartment: "303",
    role,
  });
  assertStatus(created, 201, `create temp ${role}`);
  return { phone, userId: readId(created.data?.user) };
}

async function createAccountant(baseUrl, ownerActor, runTag) {
  const phone = buildPhone("074", Number(String(Date.now() + 67).slice(-8)));
  const created = await request(
    baseUrl,
    ownerActor,
    "POST",
    "/api/owner/accountants",
    {
      fullName: `Security Accountant ${runTag}`,
      phone,
      pin: "1234",
    }
  );
  assertStatus(created, 201, "create accountant");
  return { phone, userId: readId(created.data?.user) };
}

async function createHrStaff(baseUrl, ownerActor, runTag) {
  const phone = buildPhone("073", Number(String(Date.now() + 83).slice(-8)));
  const created = await request(baseUrl, ownerActor, "POST", "/api/owner/hr-staff", {
    fullName: `Security HR ${runTag}`,
    phone,
    pin: "1234",
  });
  assertStatus(created, 201, "create hr staff");
  return { phone, userId: readId(created.data?.user) };
}

function expectHeader(response, headerName) {
  const value = response.headers.get(headerName);
  if (!value) {
    throw new Error(`MISSING_HEADER:${headerName}`);
  }
  return value;
}

async function cleanup(baseUrl, superAdmin, runTag) {
  const out = await request(
    baseUrl,
    superAdmin,
    "POST",
    "/api/admin/ops/test-artifacts/cleanup",
    { runTag }
  );
  assertStatus(out, 200, "cleanup security artifacts");
}

async function main() {
  const cfg = parseArgs();
  assertSafeE2EDatabaseTarget({
    scriptName: "security-runtime-check",
    databaseUrl: process.env.DATABASE_URL || "",
  });
  const superAdminPhone = String(process.env.SUPER_ADMIN_PHONE || "").trim();
  const superAdminPin = String(process.env.SUPER_ADMIN_PIN || "").trim();
  if (!superAdminPhone || !superAdminPin) {
    throw new Error("SUPER_ADMIN_CREDENTIALS_REQUIRED");
  }

  const anonymousProtected = await rawRequest(cfg.baseUrl, "GET", "/api/admin/analytics");
  if (anonymousProtected.status !== 401) {
    throw new Error(`ANON_PROTECTED_EXPECTED_401:${anonymousProtected.status}`);
  }

  const ready = await rawRequest(cfg.baseUrl, "GET", "/ready");
  if (ready.status !== 200) {
    throw new Error(`READY_FAILED:${ready.status}`);
  }
  expectHeader(ready.response, "x-content-type-options");
  expectHeader(ready.response, "x-frame-options");
  expectHeader(ready.response, "content-security-policy");
  expectHeader(ready.response, "permissions-policy");
  expectHeader(ready.response, "cross-origin-opener-policy");
  expectHeader(ready.response, "cross-origin-resource-policy");

  const uploadsFallback = await rawRequest(cfg.baseUrl, "GET", "/uploads/security-check.jpg");
  if (uploadsFallback.status !== 200) {
    throw new Error(`UPLOAD_FALLBACK_EXPECTED_200:${uploadsFallback.status}`);
  }
  expectHeader(uploadsFallback.response, "x-content-type-options");
  expectHeader(uploadsFallback.response, "cross-origin-resource-policy");

  const firewallBadUa = await rawRequest(cfg.baseUrl, "GET", "/ready", {
    headers: {
      "User-Agent": "sqlmap/1.8 security-check",
      "X-Forwarded-For": "198.51.100.10",
    },
  });
  if (firewallBadUa.status !== 403) {
    throw new Error(`FIREWALL_BAD_UA_EXPECTED_403:${firewallBadUa.status}`);
  }

  const firewallTraversal = await rawRequest(
    cfg.baseUrl,
    "GET",
    "/ready?file=../../etc/passwd",
    {
      headers: {
        "X-Forwarded-For": "198.51.100.11",
      },
    }
  );
  if (firewallTraversal.status !== 403) {
    throw new Error(`FIREWALL_TRAVERSAL_EXPECTED_403:${firewallTraversal.status}`);
  }

  const superAdmin = createActor("security-super-admin", cfg.runTag, "security-check/1");
  superAdmin.appFlavor = "company";
  const superLogin = await request(cfg.baseUrl, superAdmin, "POST", "/api/auth/login", {
    phone: superAdminPhone,
    pin: superAdminPin,
  });
  assertStatus(superLogin, 200, "super admin login");
  superAdmin.token = String(superLogin.data?.token || "");
  if (!superLogin.data?.user?.isSuperAdmin) {
    throw new Error("SUPER_ADMIN_LOGIN_DID_NOT_RETURN_SUPER_ADMIN_USER");
  }

  const superAdminUserSurface = createActor(
    "security-super-admin-user-surface",
    cfg.runTag,
    "security-check/1"
  );
  superAdminUserSurface.appFlavor = "user";
  const superUserSurfaceLogin = await request(
    cfg.baseUrl,
    superAdminUserSurface,
    "POST",
    "/api/auth/login",
    {
      phone: superAdminPhone,
      pin: superAdminPin,
    }
  );
  assertStatus(superUserSurfaceLogin, 200, "super admin user-surface login");
  if (!superUserSurfaceLogin.data?.user?.isSuperAdmin) {
    throw new Error(
      "SUPER_ADMIN_USER_SURFACE_LOGIN_DID_NOT_RETURN_SUPER_ADMIN_USER"
    );
  }
  superAdminUserSurface.token = String(superUserSurfaceLogin.data?.token || "");
  const superUserSurfaceAdminAnalytics = await request(
    cfg.baseUrl,
    superAdminUserSurface,
    "GET",
    "/api/admin/analytics"
  );
  assertStatus(
    superUserSurfaceAdminAnalytics,
    200,
    "super admin user-surface admin analytics"
  );

  const superAdminBlockedSurface = createActor(
    "security-super-admin-blocked-surface",
    cfg.runTag,
    "security-check/1"
  );
  superAdminBlockedSurface.appFlavor = "store";
  const superBlockedSurfaceLogin = await request(
    cfg.baseUrl,
    superAdminBlockedSurface,
    "POST",
    "/api/auth/login",
    {
      phone: superAdminPhone,
      pin: superAdminPin,
    }
  );
  if (superBlockedSurfaceLogin.status !== 403) {
    throw new Error(
      `SUPER_ADMIN_BLOCKED_SURFACE_EXPECTED_403:${superBlockedSurfaceLogin.status}`
    );
  }
  if (String(superBlockedSurfaceLogin.data?.message || "").trim() !== "FORBIDDEN_APP_SURFACE") {
    throw new Error(
      `SUPER_ADMIN_BLOCKED_SURFACE_EXPECTED_FORBIDDEN_APP_SURFACE:${
        superBlockedSurfaceLogin.data?.message || "missing"
      }`
    );
  }

  await cleanup(cfg.baseUrl, superAdmin, cfg.runTag);

  const customer = await registerCustomer(cfg.baseUrl, cfg.runTag);
  customer.actor.token = null;
  const customerLogin = await request(
    cfg.baseUrl,
    customer.actor,
    "POST",
    "/api/auth/login",
    {
      phone: customer.phone,
      pin: "1234",
    }
  );
  assertStatus(customerLogin, 200, "customer login");
  customer.actor.token = String(customerLogin.data?.token || "");
  const owner = await registerOwner(cfg.baseUrl, cfg.runTag);
  owner.actor.token = null;
  const ownerLogin = await request(
    cfg.baseUrl,
    owner.actor,
    "POST",
    "/api/auth/login",
    {
      phone: owner.phone,
      pin: "1234",
    }
  );
  assertStatus(ownerLogin, 200, "owner login");
  owner.actor.token = String(ownerLogin.data?.token || "");
  await approveOwnerMerchant(cfg.baseUrl, superAdmin, owner.actor, owner.merchantId);
  const delivery = await createDeliveryAgent(cfg.baseUrl, owner.actor, cfg.runTag);
  const accountantUser = await createAccountant(cfg.baseUrl, owner.actor, cfg.runTag);
  const hrUser = await createHrStaff(cfg.baseUrl, owner.actor, cfg.runTag);
  const adminUser = await createManagedBackofficeUser(
    cfg.baseUrl,
    superAdmin,
    cfg.runTag,
    "admin",
    53
  );
  const deputyAdminUser = await createManagedBackofficeUser(
    cfg.baseUrl,
    superAdmin,
    cfg.runTag,
    "deputy_admin",
    97
  );
  const callCenterUser = await createManagedBackofficeUser(
    cfg.baseUrl,
    superAdmin,
    cfg.runTag,
    "call_center",
    111
  );

  const adminActor = createActor("security-admin", cfg.runTag, "security-check/1");
  adminActor.appFlavor = "company";
  const adminLogin = await request(cfg.baseUrl, adminActor, "POST", "/api/auth/login", {
    phone: adminUser.phone,
    pin: "1234",
  });
  assertStatus(adminLogin, 200, "temp admin login");
  adminActor.token = String(adminLogin.data?.token || "");

  const deputyAdminActor = createActor(
    "security-deputy-admin",
    cfg.runTag,
    "security-check/1"
  );
  deputyAdminActor.appFlavor = "company";
  const deputyAdminLogin = await request(
    cfg.baseUrl,
    deputyAdminActor,
    "POST",
    "/api/auth/login",
    {
      phone: deputyAdminUser.phone,
      pin: "1234",
    }
  );
  assertStatus(deputyAdminLogin, 200, "deputy admin login");
  deputyAdminActor.token = String(deputyAdminLogin.data?.token || "");

  const callCenterActor = createActor(
    "security-call-center",
    cfg.runTag,
    "security-check/1"
  );
  callCenterActor.appFlavor = "company";
  const callCenterLogin = await request(
    cfg.baseUrl,
    callCenterActor,
    "POST",
    "/api/auth/login",
    {
      phone: callCenterUser.phone,
      pin: "1234",
    }
  );
  assertStatus(callCenterLogin, 200, "call center login");
  callCenterActor.token = String(callCenterLogin.data?.token || "");

  const deliveryActor = createActor("security-delivery", cfg.runTag, "security-check/1");
  deliveryActor.appFlavor = "delivery";
  const deliveryLogin = await request(cfg.baseUrl, deliveryActor, "POST", "/api/auth/login", {
    phone: delivery.phone,
    pin: "1234",
  });
  assertStatus(deliveryLogin, 200, "delivery login");
  deliveryActor.token = String(deliveryLogin.data?.token || "");

  const accountantActor = createActor(
    "security-accountant",
    cfg.runTag,
    "security-check/1"
  );
  accountantActor.appFlavor = "company";
  const accountantLogin = await request(
    cfg.baseUrl,
    accountantActor,
    "POST",
    "/api/auth/login",
    {
      phone: accountantUser.phone,
      pin: "1234",
    }
  );
  assertStatus(accountantLogin, 200, "accountant login");
  accountantActor.token = String(accountantLogin.data?.token || "");

  const hrActor = createActor("security-hr", cfg.runTag, "security-check/1");
  hrActor.appFlavor = "company";
  const hrLogin = await request(cfg.baseUrl, hrActor, "POST", "/api/auth/login", {
    phone: hrUser.phone,
    pin: "1234",
  });
  assertStatus(hrLogin, 200, "hr login");
  hrActor.token = String(hrLogin.data?.token || "");

  const customerSessions = await request(
    cfg.baseUrl,
    customer.actor,
    "GET",
    "/api/auth/sessions"
  );
  assertStatus(customerSessions, 200, "customer own sessions");

  const stolenTokenProbe = await rawRequest(cfg.baseUrl, "GET", "/api/auth/sessions", {
    headers: {
      Authorization: `Bearer ${customer.actor.token}`,
      "X-Device-Id": `${cfg.runTag}-stolen-device`,
      "X-Client-Platform": "security-check",
      "X-App-Version": "security-check/1",
      "X-Device-Model": "stolen-device",
      "User-Agent": "security-check/stolen",
    },
  });
  if (stolenTokenProbe.status !== 401) {
    throw new Error(`DEVICE_BINDING_EXPECTED_401:${stolenTokenProbe.status}`);
  }

  const customerOnAdmin = await request(
    cfg.baseUrl,
    customer.actor,
    "GET",
    "/api/admin/analytics"
  );
  if (customerOnAdmin.status !== 403) {
    throw new Error(`CUSTOMER_ADMIN_EXPECTED_403:${customerOnAdmin.status}`);
  }

  const ownerOnDelivery = await request(
    cfg.baseUrl,
    owner.actor,
    "GET",
    "/api/delivery/orders/current"
  );
  if (ownerOnDelivery.status !== 403) {
    throw new Error(`OWNER_DELIVERY_EXPECTED_403:${ownerOnDelivery.status}`);
  }

  const deliveryOnOwner = await request(
    cfg.baseUrl,
    deliveryActor,
    "GET",
    "/api/owner/merchant"
  );
  if (deliveryOnOwner.status !== 403) {
    throw new Error(`DELIVERY_OWNER_EXPECTED_403:${deliveryOnOwner.status}`);
  }

  const deliveryOnCustomerRoute = await request(
    cfg.baseUrl,
    deliveryActor,
    "GET",
    "/api/orders/favorites/ids"
  );
  if (deliveryOnCustomerRoute.status !== 403) {
    throw new Error(
      `DELIVERY_CUSTOMER_ROUTE_EXPECTED_403:${deliveryOnCustomerRoute.status}`
    );
  }

  const deliveryOnCaptainRoute = await request(
    cfg.baseUrl,
    deliveryActor,
    "GET",
    "/api/taxi/captain/dashboard"
  );
  if (deliveryOnCaptainRoute.status !== 403) {
    throw new Error(
      `DELIVERY_CAPTAIN_ROUTE_EXPECTED_403:${deliveryOnCaptainRoute.status}`
    );
  }

  const adminOnSuperRoute = await request(
    cfg.baseUrl,
    adminActor,
    "GET",
    "/api/admin/customers/insights?limit=1"
  );
  if (adminOnSuperRoute.status !== 403) {
    throw new Error(`ADMIN_SUPER_ONLY_EXPECTED_403:${adminOnSuperRoute.status}`);
  }

  const deputyOnAnalytics = await request(
    cfg.baseUrl,
    deputyAdminActor,
    "GET",
    "/api/admin/analytics"
  );
  assertStatus(deputyOnAnalytics, 200, "deputy admin analytics");

  const deputyOnAdminOnly = await request(
    cfg.baseUrl,
    deputyAdminActor,
    "GET",
    "/api/admin/ad-board/items"
  );
  if (deputyOnAdminOnly.status !== 403) {
    throw new Error(`DEPUTY_ADMIN_ONLY_EXPECTED_403:${deputyOnAdminOnly.status}`);
  }

  const callCenterOnBackoffice = await request(
    cfg.baseUrl,
    callCenterActor,
    "GET",
    "/api/admin/analytics"
  );
  if (callCenterOnBackoffice.status !== 403) {
    throw new Error(`CALL_CENTER_BACKOFFICE_EXPECTED_403:${callCenterOnBackoffice.status}`);
  }

  const accountantSummary = await request(
    cfg.baseUrl,
    accountantActor,
    "GET",
    "/api/accountant/summary"
  );
  assertStatus(accountantSummary, 200, "accountant summary");

  const accountantOnHr = await request(
    cfg.baseUrl,
    accountantActor,
    "GET",
    `/api/hr/dashboard?merchantId=${owner.merchantId}`
  );
  if (accountantOnHr.status !== 403) {
    throw new Error(`ACCOUNTANT_HR_EXPECTED_403:${accountantOnHr.status}`);
  }

  const hrDashboard = await request(
    cfg.baseUrl,
    hrActor,
    "GET",
    `/api/hr/dashboard?merchantId=${owner.merchantId}`
  );
  assertStatus(hrDashboard, 200, "hr dashboard");

  const hrOnAccountant = await request(
    cfg.baseUrl,
    hrActor,
    "GET",
    "/api/accountant/summary"
  );
  if (hrOnAccountant.status !== 403) {
    throw new Error(`HR_ACCOUNTANT_EXPECTED_403:${hrOnAccountant.status}`);
  }

  const superOnSuperRoute = await request(
    cfg.baseUrl,
    superAdmin,
    "GET",
    "/api/admin/customers/insights?limit=1"
  );
  assertStatus(superOnSuperRoute, 200, "super admin insight route");

  const logoutCustomer = await registerCustomer(cfg.baseUrl, `${cfg.runTag}-logout`);
  logoutCustomer.actor.token = null;
  const logoutCustomerLogin = await request(
    cfg.baseUrl,
    logoutCustomer.actor,
    "POST",
    "/api/auth/login",
    {
      phone: logoutCustomer.phone,
      pin: "1234",
    }
  );
  assertStatus(logoutCustomerLogin, 200, "logout probe customer login");
  logoutCustomer.actor.token = String(logoutCustomerLogin.data?.token || "");

  const logout = await request(cfg.baseUrl, logoutCustomer.actor, "POST", "/api/auth/logout");
  assertStatus(logout, 200, "customer logout");

  let postLogoutProbe = null;
  const logoutProbeDelaysMs = [0, 500, 1500, 3000, 5000];
  for (const delayMs of logoutProbeDelaysMs) {
    if (delayMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
    postLogoutProbe = await rawRequest(cfg.baseUrl, "GET", "/api/auth/sessions", {
      headers: {
        Authorization: `Bearer ${logoutCustomer.actor.token}`,
        "X-Device-Id": logoutCustomer.actor.deviceId,
        "X-Client-Platform": `flutter:${logoutCustomer.actor.appFlavor}`,
        "X-App-Flavor": logoutCustomer.actor.appFlavor,
        "X-App-Version": logoutCustomer.actor.appVersion,
        "X-Device-Model": logoutCustomer.actor.model,
        "User-Agent": logoutCustomer.actor.userAgent,
        "Cache-Control": "no-cache, no-store, max-age=0",
        Pragma: "no-cache",
      },
    });
    if (postLogoutProbe.status === 401) {
      break;
    }
  }
  if (postLogoutProbe?.status !== 401) {
    throw new Error(`POST_LOGOUT_EXPECTED_401:${postLogoutProbe?.status}`);
  }

  await cleanup(cfg.baseUrl, superAdmin, cfg.runTag);

  console.log(
    JSON.stringify({
      ok: true,
      runTag: cfg.runTag,
      userId: customer.userId,
      ownerUserId: owner.ownerUserId,
      deliveryUserId: delivery.userId,
      accountantUserId: accountantUser.userId,
      hrUserId: hrUser.userId,
      adminUserId: adminUser.userId,
      deputyAdminUserId: deputyAdminUser.userId,
      callCenterUserId: callCenterUser.userId,
      checks: [
        "security_headers",
        "uploads_security_headers",
        "firewall_bad_user_agent_403",
        "firewall_traversal_403",
        "anonymous_protected_401",
        "device_binding_401",
        "customer_admin_403",
        "owner_delivery_403",
        "delivery_owner_403",
        "delivery_customer_route_403",
        "delivery_captain_route_403",
        "accountant_summary_200",
        "accountant_hr_403",
        "hr_dashboard_200",
        "hr_accountant_403",
        "deputy_admin_backoffice_200",
        "deputy_admin_admin_only_403",
        "call_center_backoffice_403",
        "admin_super_admin_route_403",
        "super_admin_super_route_200",
        "post_logout_token_revoked_401",
      ],
    })
  );
}

main().catch((error) => {
  console.error("[security-runtime-check] failed:", error);
  process.exitCode = 1;
});
