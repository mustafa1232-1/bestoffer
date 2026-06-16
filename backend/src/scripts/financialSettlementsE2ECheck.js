/* eslint-disable no-console */

const BASE_URL = (process.env.API_BASE_URL || "http://127.0.0.1:3000").replace(
  /\/+$/,
  ""
);

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

function assertStatus(response, allowed, label) {
  if (!allowed.includes(response.status)) {
    throw new Error(
      `${label} expected=[${allowed.join(",")}] got=${response.status} body=${JSON.stringify(
        response.payload
      )}`
    );
  }
}

async function runStorePaysAppFlow(ownerToken, adminToken) {
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
      note: "E2E store pays app",
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

async function runAppPaysStoreFlow(ownerToken, adminToken) {
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
      note: "E2E app pays store",
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
  const ownerPhone = String(process.env.ROLE_OWNER_PHONE || "").trim();
  const ownerPin = String(process.env.ROLE_OWNER_PIN || "").trim();
  const adminPhone = String(
    process.env.ROLE_ADMIN_PHONE || process.env.SUPER_ADMIN_PHONE || ""
  ).trim();
  const adminPin = String(
    process.env.ROLE_ADMIN_PIN || process.env.SUPER_ADMIN_PIN || ""
  ).trim();

  if (!ownerPhone || !ownerPin || !adminPhone || !adminPin) {
    console.error(
      "[financial:e2e] Missing env vars: ROLE_OWNER_PHONE, ROLE_OWNER_PIN, ROLE_ADMIN_PHONE/SUPER_ADMIN_PHONE, ROLE_ADMIN_PIN/SUPER_ADMIN_PIN"
    );
    process.exitCode = 1;
    return;
  }

  console.log(`[financial:e2e] base_url=${BASE_URL}`);
  const ownerToken = await login(ownerPhone, ownerPin);
  const adminToken = await login(adminPhone, adminPin);

  await runStorePaysAppFlow(ownerToken, adminToken);
  await runAppPaysStoreFlow(ownerToken, adminToken);

  console.log("[financial:e2e] done");
}

run().catch((error) => {
  console.error("[financial:e2e] failed:", error.message);
  process.exitCode = 1;
});
