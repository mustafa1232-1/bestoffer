/* eslint-disable no-console */

import "dotenv/config";
import { env } from "../config/env.js";

const BASE_URL = (
  process.env.API_BASE_URL ||
  process.env.E2E_BASE_URL ||
  "http://127.0.0.1:3000"
).replace(/\/+$/, "");

const IS_REMOTE_BASE = !/127\.0\.0\.1|localhost/i.test(BASE_URL);
const DISABLE_DEV_ADMIN_FALLBACK =
  String(process.env.PERMISSIONS_CHECK_DISABLE_DEV_ADMIN_FALLBACK || "")
    .trim()
    .toLowerCase() === "true" || IS_REMOTE_BASE;

const ROLE_CONFIG = [
  { role: "user", phoneEnv: "ROLE_USER_PHONE", pinEnv: "ROLE_USER_PIN" },
  { role: "owner", phoneEnv: "ROLE_OWNER_PHONE", pinEnv: "ROLE_OWNER_PIN" },
  {
    role: "delivery",
    phoneEnv: "ROLE_DELIVERY_PHONE",
    pinEnv: "ROLE_DELIVERY_PIN",
  },
  {
    role: "admin",
    phoneEnv: "ROLE_ADMIN_PHONE",
    pinEnv: "ROLE_ADMIN_PIN",
    fallbackPhoneEnv: "DEV_ADMIN_PHONE",
    fallbackPinEnv: "DEV_ADMIN_PIN",
  },
  {
    role: "super_admin",
    phoneEnv: "SUPER_ADMIN_PHONE",
    pinEnv: "SUPER_ADMIN_PIN",
    fallbackPhone: env.superAdminPhone,
    fallbackPin: env.superAdminPin,
  },
];

const CHECKS = [
  {
    id: "auth_sessions",
    method: "GET",
    path: "/api/auth/sessions",
    allowedRoles: ["user", "owner", "delivery", "admin", "super_admin"],
    allowedStatuses: [200],
  },
  {
    id: "orders_favorites_ids",
    method: "GET",
    path: "/api/orders/favorites/ids",
    allowedRoles: ["user"],
    allowedStatuses: [200],
  },
  {
    id: "cars_brands",
    method: "GET",
    path: "/api/cars/brands",
    allowedRoles: ["user", "owner", "delivery", "admin", "super_admin"],
    allowedStatuses: [200],
  },
  {
    id: "owner_merchant",
    method: "GET",
    path: "/api/owner/merchant",
    allowedRoles: ["owner"],
    allowedStatuses: [200],
  },
  {
    id: "delivery_current_orders",
    method: "GET",
    path: "/api/delivery/orders/current",
    allowedRoles: ["delivery"],
    allowedStatuses: [200],
  },
  {
    id: "admin_analytics",
    method: "GET",
    path: "/api/admin/analytics",
    allowedRoles: ["admin", "super_admin"],
    allowedStatuses: [200],
  },
  {
    id: "company_admin_list",
    method: "GET",
    path: "/api/company/admin/companies?limit=1",
    allowedRoles: ["admin", "super_admin"],
    allowedStatuses: [200],
  },
  {
    id: "super_admin_customer_insights",
    method: "GET",
    path: "/api/admin/customers/insights?limit=1",
    allowedRoles: ["super_admin"],
    allowedStatuses: [200],
  },
  {
    id: "feed_scopes_me",
    method: "GET",
    path: "/api/feed/communities/scopes/me",
    allowedRoles: ["user", "owner", "delivery", "admin", "super_admin"],
    allowedStatuses: [200],
  },
];

const FORBIDDEN_STATUSES = [401, 403];

function buildDeviceContext(role) {
  const normalized = String(role || "actor")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-");
  return {
    deviceId: `perm-${normalized}-device`,
    platform: "permissions-check",
    appVersion: "permissions-check/1",
    model: `${normalized}-simulator`,
    userAgent: `permissions-check/${normalized}`,
  };
}

function appendCacheBust(path, seed) {
  if (typeof path !== "string" || !path.startsWith("/")) return path;
  const url = new URL(path, "http://local.test");
  url.searchParams.set("_permBust", `${Date.now()}-${seed}`);
  return `${url.pathname}${url.search}`;
}

async function request(
  path,
  { method = "GET", token = null, body = null, device = null } = {}
) {
  const headers = {
    "Content-Type": "application/json",
    "Cache-Control": "no-cache",
    Pragma: "no-cache",
  };
  if (device) {
    headers["X-Device-Id"] = device.deviceId;
    headers["X-Client-Platform"] = device.platform;
    headers["X-App-Version"] = device.appVersion;
    headers["X-Device-Model"] = device.model;
    headers["User-Agent"] = device.userAgent;
  }
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });

  let payload = null;
  const text = await res.text();
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch (_) {
      payload = text;
    }
  }

  return { status: res.status, payload };
}

async function loginAs(roleConfig) {
  const allowFallback =
    !DISABLE_DEV_ADMIN_FALLBACK || roleConfig.role !== "admin";
  const phone = String(
    process.env[roleConfig.phoneEnv] ||
      (allowFallback && roleConfig.fallbackPhoneEnv
        ? process.env[roleConfig.fallbackPhoneEnv]
        : "") ||
      roleConfig.fallbackPhone ||
      ""
  ).trim();
  const pin = String(
    process.env[roleConfig.pinEnv] ||
      (allowFallback && roleConfig.fallbackPinEnv
        ? process.env[roleConfig.fallbackPinEnv]
        : "") ||
      roleConfig.fallbackPin ||
      ""
  ).trim();
  if (!phone || !pin) return null;
  const device = buildDeviceContext(roleConfig.role);

  const res = await request("/api/auth/login", {
    method: "POST",
    body: { phone, pin },
    device,
  });

  if (res.status !== 200 || !res.payload || typeof res.payload !== "object") {
    throw new Error(
      `LOGIN_FAILED role=${roleConfig.role} status=${res.status} body=${JSON.stringify(res.payload)}`
    );
  }

  const token = String(res.payload.token || "").trim();
  if (!token) {
    throw new Error(`LOGIN_NO_TOKEN role=${roleConfig.role}`);
  }

  return {
    role: roleConfig.role,
    token,
    device,
    userRole: String(res.payload.user?.role || "").trim().toLowerCase(),
    isSuperAdmin: res.payload.user?.isSuperAdmin === true,
    userId: Number(res.payload.user?.id || 0) || null,
  };
}

function isAllowedRole(check, session) {
  if (check.allowedRoles.includes("super_admin") && session.isSuperAdmin) {
    return true;
  }
  return check.allowedRoles.includes(session.role);
}

function formatStatus(ok) {
  return ok ? "PASS" : "FAIL";
}

async function run() {
  console.log(`[permissions] base_url=${BASE_URL}`);
  const sessions = [];

  for (const roleConfig of ROLE_CONFIG) {
    try {
      const session = await loginAs(roleConfig);
      if (!session) {
        console.log(`[permissions] skip role=${roleConfig.role} (missing credentials)`);
        continue;
      }
      sessions.push(session);
      console.log(
        `[permissions] login role=${roleConfig.role} ok userId=${session.userId} apiRole=${session.userRole} super=${session.isSuperAdmin}`
      );
    } catch (error) {
      console.error(`[permissions] ${error.message}`);
      process.exitCode = 1;
      return;
    }
  }

  if (sessions.length === 0) {
    console.error("[permissions] no role credentials provided.");
    console.error(
      "[permissions] set env vars like ROLE_USER_PHONE/ROLE_USER_PIN or SUPER_ADMIN_PHONE/SUPER_ADMIN_PIN then rerun."
    );
    process.exitCode = 1;
    return;
  }

  let failures = 0;
  let total = 0;

  for (const session of sessions) {
    for (const check of CHECKS) {
      total += 1;
      const allowed = isAllowedRole(check, session);
      const expectedStatuses = allowed ? check.allowedStatuses : FORBIDDEN_STATUSES;
      const requestPath =
        check.method === "GET"
          ? appendCacheBust(check.path, `${session.role}-${check.id}`)
          : check.path;
      let response;
      try {
        response = await request(requestPath, {
          method: check.method,
          token: session.token,
          device: session.device,
        });
      } catch (error) {
        failures += 1;
        console.error(
          `[${formatStatus(false)}] role=${session.role} check=${check.id} network_error=${error.message}`
        );
        continue;
      }

      const ok = expectedStatuses.includes(response.status);
      if (!ok) failures += 1;
      const expectation = allowed ? "allow" : "deny";
      console.log(
        `[${formatStatus(ok)}] role=${session.role} check=${check.id} expect=${expectation} status=${response.status}`
      );
      if (!ok) {
        console.log(
          `[details] expected=${expectedStatuses.join(",")} body=${JSON.stringify(response.payload)}`
        );
      }
    }
  }

  console.log(
    `[permissions] completed total=${total} failures=${failures} passed=${total - failures}`
  );
  process.exitCode = failures > 0 ? 1 : 0;
}

run().catch((error) => {
  console.error(`[permissions] fatal=${error?.message || error}`);
  process.exitCode = 1;
});
