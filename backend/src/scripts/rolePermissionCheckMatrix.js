/* eslint-disable no-console */

import "dotenv/config";

import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";

import { env } from "../config/env.js";
import {
  createActor,
  readId,
  request,
} from "./e2eTestUtils.js";

const DEFAULT_BASE_URL = (
  process.env.API_BASE_URL ||
  process.env.E2E_BASE_URL ||
  "http://127.0.0.1:3000"
)
  .trim()
  .replace(/\/+$/, "");

const DEFAULT_MATRIX_FILE = path.join(
  process.cwd(),
  "qa_artifacts",
  "phase_3d_android_rc",
  "qa-role-matrix.json"
);

const FORBIDDEN_STATUSES = [401, 403];

const ROLE_CONFIG = [
  {
    role: "user",
    label: "user",
    appFlavor: "user",
    phoneEnv: "ROLE_USER_PHONE",
    pinEnv: "ROLE_USER_PIN",
  },
  {
    role: "owner",
    label: "owner",
    appFlavor: "store",
    phoneEnv: "ROLE_OWNER_PHONE",
    pinEnv: "ROLE_OWNER_PIN",
  },
  {
    role: "delivery",
    label: "delivery",
    appFlavor: "delivery",
    phoneEnv: "ROLE_DELIVERY_PHONE",
    pinEnv: "ROLE_DELIVERY_PIN",
  },
  {
    role: "admin",
    label: "admin",
    appFlavor: "company",
    phoneEnv: "ROLE_ADMIN_PHONE",
    pinEnv: "ROLE_ADMIN_PIN",
    fallbackPhoneEnv: "DEV_ADMIN_PHONE",
    fallbackPinEnv: "DEV_ADMIN_PIN",
  },
  {
    role: "super_admin",
    label: "super_admin",
    appFlavor: "user",
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
  },
  {
    id: "orders_favorites_ids",
    method: "GET",
    path: "/api/orders/favorites/ids",
    allowedRoles: ["user"],
  },
  {
    id: "cars_brands",
    method: "GET",
    path: "/api/cars/brands",
    allowedRoles: ["user", "owner", "delivery", "admin", "super_admin"],
  },
  {
    id: "owner_merchant",
    method: "GET",
    path: "/api/owner/merchant",
    allowedRoles: ["owner"],
  },
  {
    id: "delivery_current_orders",
    method: "GET",
    path: "/api/delivery/orders/current",
    allowedRoles: ["delivery"],
  },
  {
    id: "admin_analytics",
    method: "GET",
    path: "/api/admin/analytics",
    allowedRoles: ["admin", "super_admin"],
  },
  {
    id: "company_admin_list",
    method: "GET",
    path: "/api/company/admin/companies?limit=1",
    allowedRoles: ["admin", "super_admin"],
  },
  {
    id: "super_admin_customer_insights",
    method: "GET",
    path: "/api/admin/customers/insights?limit=1",
    allowedRoles: ["super_admin"],
  },
  {
    id: "feed_scopes_me",
    method: "GET",
    path: "/api/feed/communities/scopes/me",
    allowedRoles: ["user", "owner", "delivery", "admin", "super_admin"],
  },
];

function readString(value) {
  return String(value ?? "").trim();
}

function buildDeviceContext(role) {
  const normalized = readString(role)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 32);

  return {
    deviceId: `perm-${normalized || "actor"}-device`,
    platform: "permissions-check",
    appVersion: "permissions-check/1",
    model: `${normalized || "actor"}-simulator`,
    userAgent: `permissions-check/${normalized || "actor"}`,
  };
}

function appendCacheBust(requestPath, seed) {
  if (typeof requestPath !== "string" || !requestPath.startsWith("/")) {
    return requestPath;
  }
  const url = new URL(requestPath, "http://local.test");
  url.searchParams.set("_permBust", `${Date.now()}-${seed}`);
  return `${url.pathname}${url.search}`;
}

function normalizeMatrixAccount(entry) {
  const role = readString(entry?.role || entry?.authRole || entry?.label).toLowerCase();
  const appFlavor = readString(entry?.appFlavor || entry?.surface || "").toLowerCase();
  return {
    label: readString(entry?.label || role || "account") || "account",
    role: role || "user",
    appFlavor: appFlavor || (role === "owner" ? "store" : role === "delivery" ? "delivery" : role === "admin" ? "company" : "user"),
    phone: readString(entry?.phone),
    pin: readString(entry?.pin),
    isSuperAdmin: entry?.isSuperAdmin === true,
    companyRole: readString(entry?.companyRole || ""),
    companyId: entry?.companyId == null ? null : Number(entry.companyId),
    loginPath: readString(entry?.loginPath || ""),
  };
}

async function loadMatrixAccounts(filePath) {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    const parsed = JSON.parse(raw);
    const accounts = Array.isArray(parsed?.accounts) ? parsed.accounts.map(normalizeMatrixAccount) : [];
    return {
      exists: true,
      accounts,
      source: filePath,
      createdAt: readString(parsed?.createdAt || ""),
      runTag: readString(parsed?.runTag || ""),
    };
  } catch (error) {
    if (error?.code === "ENOENT") {
      return {
        exists: false,
        accounts: [],
        source: filePath,
        createdAt: "",
        runTag: "",
      };
    }
    throw error;
  }
}

async function requestJson(
  baseUrl,
  actor,
  method,
  requestPath,
  { body = null, companyId = null } = {}
) {
  const headers = {
    "Content-Type": "application/json",
    "Cache-Control": "no-cache",
    Pragma: "no-cache",
  };
  if (actor?.appFlavor) {
    headers["X-Client-Platform"] = `flutter:${actor.appFlavor}`;
    headers["X-App-Flavor"] = actor.appFlavor;
  } else {
    headers["X-Client-Platform"] = "permissions-check";
  }
  if (actor?.deviceId) {
    headers["X-Device-Id"] = actor.deviceId;
    headers["X-App-Version"] = actor.appVersion;
    headers["X-Device-Model"] = actor.model;
    headers["User-Agent"] = actor.userAgent;
  }
  if (actor?.token) {
    headers.Authorization = `Bearer ${actor.token}`;
  }
  const effectiveCompanyId = companyId ?? actor?.companyId ?? null;
  if (effectiveCompanyId != null && /\/api\/company(?:\/|$)/.test(requestPath)) {
    headers["X-Company-Id"] = String(effectiveCompanyId);
  }

  const response = await fetch(`${baseUrl}${requestPath}`, {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });

  const text = await response.text();
  let payload = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch (_) {
      payload = text;
    }
  }

  return {
    status: response.status,
    ok: response.ok,
    data: payload,
  };
}

async function loginAccount(baseUrl, account) {
  const role = readString(account.role).toLowerCase();
  const label = readString(account.label || role || "account");
  const appFlavor = readString(account.appFlavor || "user").toLowerCase();
  const loginPath =
    readString(account.loginPath) ||
    (appFlavor === "company" ? "/api/company/auth/login" : "/api/auth/login");
  const actor = createActor(label, buildRunTag("perm"), "permissions-check/1");
  actor.appFlavor = appFlavor;
  const phone = readString(account.phone);
  const pin = readString(account.pin);
  if (!phone || !pin) {
    throw new Error(`MATRIX_ACCOUNT_MISSING_CREDENTIALS role=${role} label=${label}`);
  }

  const response = await requestJson(baseUrl, actor, "POST", loginPath, { phone, pin });
  assert.equal(
    response.status,
    200,
    `${label} login -> expected 200, received ${response.status}, body=${JSON.stringify(response.data)}`
  );

  const token = readString(response.data?.token);
  assert.ok(token, `${label} login -> missing token`);
  actor.token = token;
  actor.sessionId = Number(response.data?.sessionId || 0) || null;
  actor.userId = readId(response.data?.user);
  actor.isSuperAdmin = response.data?.user?.isSuperAdmin === true || account.isSuperAdmin === true;
  actor.companyId = account.companyId;
  actor.companyRole = readString(account.companyRole);
  const memberships = Array.isArray(response.data?.memberships) ? response.data.memberships : [];
  if (memberships.length > 0) {
    actor.companyId =
      actor.companyId || readId(memberships[0]?.company) || readId(memberships[0]?.companyId);
    actor.companyRole =
      actor.companyRole || readString(memberships[0]?.role || memberships[0]?.companyRole || "");
  }
  actor.permissionsRole = actor.isSuperAdmin
    ? "super_admin"
    : actor.companyRole || role || readString(response.data?.user?.role || "");
  actor.authRole = readString(response.data?.user?.role || role || "");
  assert.ok(actor.userId, `${label} login -> missing user id`);
  return actor;
}

function isAllowedRole(check, session) {
  if (session.isSuperAdmin && check.allowedRoles.includes("super_admin")) {
    return true;
  }

  const candidates = new Set(
    [session.permissionsRole, session.authRole, session.role]
      .map((value) => readString(value).toLowerCase())
      .filter(Boolean)
  );

  for (const candidate of candidates) {
    if (check.allowedRoles.includes(candidate)) {
      return true;
    }
  }
  return false;
}

function buildFallbackAccounts() {
  const out = [];
  for (const roleConfig of ROLE_CONFIG) {
    const phone = String(
      process.env[roleConfig.phoneEnv] ||
        (roleConfig.fallbackPhoneEnv ? process.env[roleConfig.fallbackPhoneEnv] : "") ||
        roleConfig.fallbackPhone ||
        ""
    ).trim();
    const pin = String(
      process.env[roleConfig.pinEnv] ||
        (roleConfig.fallbackPinEnv ? process.env[roleConfig.fallbackPinEnv] : "") ||
        roleConfig.fallbackPin ||
        ""
    ).trim();
    if (!phone || !pin) continue;
    out.push({
      label: roleConfig.label,
      role: roleConfig.role,
      appFlavor: roleConfig.appFlavor,
      phone,
      pin,
      isSuperAdmin: roleConfig.role === "super_admin",
    });
  }
  return out;
}

function pickAccounts(matrixAccounts, fallbackAccounts) {
  if (matrixAccounts.length > 0) {
    return matrixAccounts;
  }
  return fallbackAccounts;
}

async function run() {
  const baseUrl = readString(DEFAULT_BASE_URL).replace(/\/+$/, "");
  const matrixFile = readString(
    process.env.QA_ROLE_MATRIX_FILE || DEFAULT_MATRIX_FILE
  );

  console.log(`[permissions] base_url=${baseUrl}`);
  console.log(`[permissions] matrix_file=${matrixFile}`);

  const matrix = await loadMatrixAccounts(matrixFile);
  const fallbackAccounts = buildFallbackAccounts();
  const accounts = pickAccounts(matrix.accounts, fallbackAccounts);

  if (matrix.exists) {
    console.log(
      `[permissions] loaded_matrix_accounts=${matrix.accounts.length} created_at=${matrix.createdAt || "(unknown)"} run_tag=${matrix.runTag || "(unknown)"}`
    );
  } else {
    console.log(
      `[permissions] matrix file missing, falling back to env credentials where available`
    );
  }

  if (accounts.length === 0) {
    console.error("[permissions] no QA accounts available.");
    console.error(
      "[permissions] bootstrap qa-role-matrix.json or export ROLE_* / SUPER_ADMIN_* credentials before rerunning."
    );
    process.exitCode = 1;
    return;
  }

  const sessions = [];
  for (const account of accounts) {
    try {
      const session = await loginAccount(baseUrl, account);
      sessions.push(session);
      console.log(
        `[permissions] login ok label=${account.label} role=${session.permissionsRole} authRole=${session.authRole} super=${session.isSuperAdmin} companyId=${session.companyId || "n/a"}`
      );
    } catch (error) {
      console.error(
        `[permissions] LOGIN_FAILED label=${account.label} role=${account.role} error=${String(
          error?.message || error
        )}`
      );
      process.exitCode = 1;
      return;
    }
  }

  let total = 0;
  let failures = 0;
  let skipped = 0;

  for (const session of sessions) {
    for (const check of CHECKS) {
      total += 1;
      const allowed = isAllowedRole(check, session);
      const expectedStatuses = allowed ? [200] : FORBIDDEN_STATUSES;
      const requestPath =
        check.method === "GET"
          ? appendCacheBust(check.path, `${session.label || session.authRole}-${check.id}`)
          : check.path;

      if (!allowed && check.allowedRoles.length > 0) {
        const deniedResponse = await requestJson(baseUrl, session, check.method, requestPath);
        const ok = expectedStatuses.includes(deniedResponse.status);
        if (!ok) failures += 1;
        console.log(
          `[${ok ? "PASS" : "FAIL"}] label=${session.label} role=${session.permissionsRole} check=${check.id} expect=deny status=${deniedResponse.status}`
        );
        if (!ok) {
          console.log(
            `[details] expected=${expectedStatuses.join(",")} body=${JSON.stringify(deniedResponse.data)}`
          );
        }
        continue;
      }

      if (!allowed) {
        skipped += 1;
        console.log(
          `[SKIP] label=${session.label} role=${session.permissionsRole} check=${check.id} reason=not-applicable`
        );
        continue;
      }

      const response = await requestJson(baseUrl, session, check.method, requestPath, {
        companyId: session.companyId,
      });
      const ok = expectedStatuses.includes(response.status);
      if (!ok) failures += 1;
      console.log(
        `[${ok ? "PASS" : "FAIL"}] label=${session.label} role=${session.permissionsRole} check=${check.id} expect=allow status=${response.status}`
      );
      if (!ok) {
        console.log(
          `[details] expected=${expectedStatuses.join(",")} body=${JSON.stringify(response.data)}`
        );
      }
    }
  }

  console.log(
    `[permissions] completed total=${total} failures=${failures} skipped=${skipped} passed=${total - failures - skipped}`
  );
  process.exitCode = failures > 0 ? 1 : 0;
}

run().catch((error) => {
  console.error(`[permissions] fatal=${error?.message || error}`);
  process.exitCode = 1;
});
