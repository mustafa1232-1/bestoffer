/* eslint-disable no-console */

import "dotenv/config";

import { env } from "../config/env.js";
import { cleanupLoadArtifactsByRunTag } from "../shared/utils/testArtifactCleanup.js";

const BASE_URL = (
  process.env.API_BASE_URL ||
  process.env.E2E_BASE_URL ||
  "https://bestoffer-production.up.railway.app"
).replace(
  /\/+$/,
  ""
);

function buildRunTag() {
  return String(process.env.FINANCIAL_E2E_RUN_TAG || "").trim() ||
    `financial-e2e-${Date.now().toString(36)}`;
}

function toNum(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

async function request(path, { method = "GET", token = null, body = null } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let payload = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch (_) {
      payload = text;
    }
  }
  return { status: res.status, payload };
}

async function login(phone, pin) {
  const res = await request("/api/auth/login", {
    method: "POST",
    body: { phone, pin },
  });
  if (res.status !== 200) {
    throw new Error(`LOGIN_FAILED status=${res.status} body=${JSON.stringify(res.payload)}`);
  }
  const token = String(res.payload?.token || "").trim();
  if (!token) throw new Error("LOGIN_NO_TOKEN");
  return token;
}

async function loginAny(candidates) {
  let lastError = null;
  for (const candidate of candidates) {
    if (!candidate.phone || !candidate.pin) continue;
    try {
      const token = await login(candidate.phone, candidate.pin);
      return { token, label: candidate.label };
    } catch (error) {
      lastError = error;
    }
  }
  if (lastError) throw lastError;
  throw new Error("LOGIN_CREDENTIALS_MISSING");
}

async function registerOwner(runTag) {
  const phone = `078${String(Date.now()).slice(-8)}`;
  const res = await request("/api/owner/register", {
    method: "POST",
    body: {
      fullName: `Financial E2E Owner ${runTag}`,
      phone,
      pin: "1234",
      block: "A2",
      buildingNumber: "A202",
      apartment: "202",
      merchantName: `Financial E2E Merchant ${runTag}`,
      merchantType: "restaurant",
      merchantActivityType: "restaurant",
      merchantDiscoverySubcategory: "eastern",
      merchantDescription: `financial-e2e-merchant-${runTag}`,
      merchantTagline: `financial-e2e-tagline-${runTag}`,
      merchantWorkingHours: "09:00-23:00",
      merchantServiceAreaNote: `financial-e2e-service-area-${runTag}`,
      merchantSupportsChat: true,
      merchantSupportsAttachments: true,
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "financial_e2e_v1",
    },
  });
  if (res.status !== 201) {
    throw new Error(`REGISTER_OWNER_FAILED status=${res.status} body=${JSON.stringify(res.payload)}`);
  }
  const token = String(res.payload?.token || "").trim();
  if (!token) throw new Error("REGISTER_OWNER_NO_TOKEN");
  return {
    token,
    phone,
    userId: Number(res.payload?.user?.id || 0) || null,
    merchantId: Number(res.payload?.merchant?.id || 0) || null,
  };
}

function assertStatus(response, allowed, label) {
  if (!allowed.includes(response.status)) {
    throw new Error(
      `${label} expected=[${allowed.join(",")}] got=${response.status} body=${JSON.stringify(
        response.payload
      )}`
    );
  }
}

async function runStorePaysAppFlow(ownerToken, adminToken, runTag) {
  const summary = await request("/api/merchant/receivables", { token: ownerToken });
  assertStatus(summary, [200], "owner_receivables");

  const outstanding = toNum(
    summary.payload?.storePaysApp?.outstanding ??
      summary.payload?.breakdown?.totals?.outstanding
  );
  if (outstanding <= 0) {
    console.log("[financial:e2e] store_pays_app skipped (no outstanding)");
    return;
  }

  const amount = Math.max(100, Math.min(outstanding, 1500));
  const create = await request("/api/merchant/payment-requests", {
    token: ownerToken,
    method: "POST",
    body: {
      requestType: "store_pays_app",
      paymentScope: "all",
      amount,
      note: `E2E store pays app ${runTag}`,
    },
  });
  assertStatus(create, [201], "create_store_pays_app");
  const id = Number(create.payload?.paymentRequest?.id || 0);
  if (!id) throw new Error("create_store_pays_app missing request id");

  const approve = await request(`/api/admin/payment-requests/${id}/approve`, {
    token: adminToken,
    method: "POST",
    body: { reviewNote: "E2E approve store payment" },
  });
  assertStatus(approve, [200], "approve_store_pays_app");
  console.log(`[financial:e2e] store_pays_app approved request_id=${id}`);
}

async function runAppPaysStoreFlow(ownerToken, adminToken, runTag) {
  const summary = await request("/api/merchant/receivables", { token: ownerToken });
  assertStatus(summary, [200], "owner_receivables_app_pays_store");

  const outstanding = toNum(summary.payload?.appPaysStore?.outstanding);
  if (outstanding <= 0) {
    console.log("[financial:e2e] app_pays_store skipped (no app payable outstanding)");
    return;
  }

  const amount = Math.max(100, Math.min(outstanding, 1000));
  const create = await request("/api/merchant/payment-requests", {
    token: ownerToken,
    method: "POST",
    body: {
      requestType: "app_pays_store",
      paymentScope: "all",
      amount,
      note: `E2E app pays store ${runTag}`,
    },
  });
  assertStatus(create, [201], "create_app_pays_store");
  const id = Number(create.payload?.paymentRequest?.id || 0);
  if (!id) throw new Error("create_app_pays_store missing request id");

  const approve = await request(`/api/admin/payment-requests/${id}/approve`, {
    token: adminToken,
    method: "POST",
    body: { reviewNote: "E2E approve payout request" },
  });
  assertStatus(approve, [200], "approve_app_pays_store");

  const assign = await request(`/api/admin/payment-requests/${id}/assign`, {
    token: adminToken,
    method: "POST",
    body: { assignedToName: "E2E Settlement Agent" },
  });
  assertStatus(assign, [200], "assign_app_pays_store");

  const markPaid = await request(`/api/admin/payment-requests/${id}/mark-paid`, {
    token: adminToken,
    method: "POST",
    body: {
      paidAmount: amount,
      paymentMethod: "cash",
      paymentActorName: "E2E Admin",
      reviewNote: "E2E marked paid",
    },
  });
  assertStatus(markPaid, [200], "mark_paid_app_pays_store");

  const confirm = await request(
    `/api/merchant/payment-requests/${id}/confirm-received`,
    {
      token: ownerToken,
      method: "POST",
      body: { note: "E2E confirmed receipt" },
    }
  );
  assertStatus(confirm, [200], "confirm_received_app_pays_store");
  console.log(`[financial:e2e] app_pays_store completed request_id=${id}`);
}

async function run() {
  const runTag = buildRunTag();
  const adminCandidates = [
    {
      label: "super_admin",
      phone: String(process.env.SUPER_ADMIN_PHONE || env.superAdminPhone || "").trim(),
      pin: String(process.env.SUPER_ADMIN_PIN || env.superAdminPin || "").trim(),
    },
    {
      label: "dev_admin",
      phone: String(process.env.DEV_ADMIN_PHONE || "").trim(),
      pin: String(process.env.DEV_ADMIN_PIN || "").trim(),
    },
    {
      label: "role_admin",
      phone: String(process.env.ROLE_ADMIN_PHONE || "").trim(),
      pin: String(process.env.ROLE_ADMIN_PIN || "").trim(),
    },
  ];

  if (!adminCandidates.some((candidate) => candidate.phone && candidate.pin)) {
    console.error(
      "[financial:e2e] Missing admin env vars: SUPER_ADMIN or DEV_ADMIN or ROLE_ADMIN credentials"
    );
    process.exitCode = 1;
    return;
  }

  console.log(`[financial:e2e] base_url=${BASE_URL}`);
  console.log(`[financial:e2e] run_tag=${runTag}`);
  const owner = await registerOwner(runTag);
  const ownerToken = owner.token;
  const admin = await loginAny(adminCandidates);
  console.log(`[financial:e2e] admin_login_label=${admin.label}`);
  const adminToken = admin.token;

  try {
    await runStorePaysAppFlow(ownerToken, adminToken, runTag);
    await runAppPaysStoreFlow(ownerToken, adminToken, runTag);
  } finally {
    try {
      const cleanup = await cleanupLoadArtifactsByRunTag(runTag);
      console.log(`[financial:e2e] cleanup=${JSON.stringify(cleanup)}`);
    } catch (cleanupError) {
      console.warn(`[financial:e2e] cleanup_failed=${cleanupError.message}`);
    }
  }

  console.log("[financial:e2e] done");
}

run().catch((error) => {
  console.error("[financial:e2e] failed:", error.message);
  process.exitCode = 1;
});
