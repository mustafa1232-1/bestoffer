/* eslint-disable no-console */

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";

function readEnv(name, fallback = "") {
  return String(process.env[name] || fallback).trim();
}

function fail(message) {
  console.error(`[review-validation] FAIL: ${message}`);
  process.exitCode = 1;
}

function isPrivateHost(hostname) {
  const host = String(hostname || "").toLowerCase();
  return (
    host === "localhost" ||
    host === "127.0.0.1" ||
    host === "::1" ||
    /^10\./.test(host) ||
    /^192\.168\./.test(host) ||
    /^172\.(1[6-9]|2\d|3[0-1])\./.test(host)
  );
}

function assertPublicHttpsBaseUrl(baseUrl) {
  let parsed;
  try {
    parsed = new URL(baseUrl);
  } catch {
    throw new Error("MASLAKI_API_BASE_URL is not a valid URL");
  }
  if (parsed.protocol !== "https:") {
    throw new Error("MASLAKI_API_BASE_URL must use HTTPS");
  }
  if (isPrivateHost(parsed.hostname)) {
    throw new Error("MASLAKI_API_BASE_URL must not point to localhost/private LAN");
  }
  return parsed.origin;
}

async function request(baseUrl, method, path, { token = "", body } = {}) {
  const headers = {
    "User-Agent": "maslaki-review-validation/1",
    "X-Client-Platform": "flutter:user",
    "X-App-Flavor": "user",
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  const raw = await response.text();
  let data = null;
  if (raw) {
    try {
      data = JSON.parse(raw);
    } catch {
      data = raw;
    }
  }
  return { status: response.status, ok: response.ok, data };
}

function assertNoRawRequestUuid(data, label) {
  const text =
    typeof data === "string"
      ? data
      : [
          data?.message,
          data?.error,
          data?.detail,
          data?.title,
          data?.description,
        ]
          .filter(Boolean)
          .join(" ");
  if (/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i.test(text)) {
    throw new Error(`${label} exposed a raw request UUID`);
  }
}

async function login(baseUrl, label, phone, pin) {
  if (!phone || !pin) throw new Error(`${label} credentials are missing`);
  const response = await request(baseUrl, "POST", "/api/auth/login", {
    body: { phone, pin },
  });
  if (response.status !== 200) {
    throw new Error(`${label} login failed with HTTP ${response.status}`);
  }
  const token = String(response.data?.token || "");
  if (!token) throw new Error(`${label} login did not return an access token`);
  return {
    token,
    user: response.data?.user || {},
  };
}

async function main() {
  const baseUrl = assertPublicHttpsBaseUrl(
    readEnv("MASLAKI_API_BASE_URL", DEFAULT_BASE_URL)
  );
  const customerPhone = readEnv(
    "MASLAKI_CUSTOMER_REVIEW_PHONE",
    readEnv("MASLAKI_REVIEW_PHONE")
  );
  const customerPin = readEnv(
    "MASLAKI_CUSTOMER_REVIEW_PIN",
    readEnv("MASLAKI_REVIEW_PIN")
  );
  const providerPhone = readEnv("MASLAKI_PROVIDER_REVIEW_PHONE");
  const providerPin = readEnv("MASLAKI_PROVIDER_REVIEW_PIN");

  console.log(`[review-validation] baseUrl=${baseUrl}`);

  const health = await request(baseUrl, "GET", "/health");
  if (health.status !== 200) throw new Error(`/health returned ${health.status}`);
  console.log("[review-validation] /health ok");

  const ready = await request(baseUrl, "GET", "/ready");
  if (ready.status >= 500) throw new Error(`/ready returned ${ready.status}`);
  console.log(`[review-validation] /ready status=${ready.status}`);

  const invalid = await request(baseUrl, "POST", "/api/auth/login", {
    body: { phone: customerPhone || "0790000000", pin: "0000" },
  });
  if (![400, 401, 403, 429].includes(invalid.status)) {
    throw new Error(`invalid login returned unexpected HTTP ${invalid.status}`);
  }
  assertNoRawRequestUuid(invalid.data, "invalid login");
  console.log("[review-validation] invalid login returns safe error");

  const customer = await login(baseUrl, "customer review", customerPhone, customerPin);
  if (String(customer.user?.role || "user") !== "user") {
    throw new Error("customer review account is not a customer/user role");
  }
  const customerMe = await request(baseUrl, "GET", "/api/me", {
    token: customer.token,
  });
  if (customerMe.status !== 200) {
    throw new Error(`customer features probe failed with HTTP ${customerMe.status}`);
  }
  console.log("[review-validation] customer review account ok");

  const provider = await login(baseUrl, "provider review", providerPhone, providerPin);
  if (String(provider.user?.role || "") !== "service_provider") {
    throw new Error("provider review account is not service_provider");
  }
  const providerStatus = await request(
    baseUrl,
    "POST",
    "/api/services/provider/application/status",
    {
      body: { phone: providerPhone, pin: providerPin },
    }
  );
  if (providerStatus.status !== 200) {
    throw new Error(`provider status probe failed with HTTP ${providerStatus.status}`);
  }
  if (
    providerStatus.data?.status !== "approved" ||
    providerStatus.data?.canLogin !== true
  ) {
    throw new Error("provider review account is not approved before review");
  }
  const workspace = await request(
    baseUrl,
    "GET",
    "/api/services/provider/workspace",
    { token: provider.token }
  );
  if (workspace.status !== 200) {
    throw new Error(`provider workspace probe failed with HTTP ${workspace.status}`);
  }
  if (workspace.data?.provider?.acceptsElectronic === true) {
    throw new Error("provider review account unexpectedly enables electronic payment");
  }
  if (workspace.data?.provider?.acceptsCash !== true) {
    throw new Error("provider review account does not clearly support cash payment");
  }
  console.log("[review-validation] provider review account ok");

  console.log("[review-validation] credentials were accepted without OTP, electronic payment, or manual approval during validation");
}

main().catch((error) => {
  fail(error?.message || String(error));
});
