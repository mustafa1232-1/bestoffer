/* eslint-disable no-console */
import "dotenv/config";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";
const DEFAULT_USERS = 1000;
const DEFAULT_CONCURRENCY = 1000;
const DEFAULT_TIMEOUT_MS = 20000;
const DEFAULT_RETRIES = 2;
const DEFAULT_RUN_SEED = Date.now();
let RUN_SEED = DEFAULT_RUN_SEED;

function toInt(value, fallback, { min = 1, max = 1_000_000 } = {}) {
  const n = Number(value);
  if (!Number.isInteger(n)) return fallback;
  if (n < min || n > max) return fallback;
  return n;
}

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    baseUrl:
      String(process.env.STRESS_BASE_URL || DEFAULT_BASE_URL).trim().replace(/\/+$/, ""),
    users: toInt(process.env.STRESS_USERS, DEFAULT_USERS, { min: 1, max: 20000 }),
    concurrency: toInt(process.env.STRESS_CONCURRENCY, DEFAULT_CONCURRENCY, {
      min: 1,
      max: 5000,
    }),
    timeoutMs: toInt(process.env.STRESS_TIMEOUT_MS, DEFAULT_TIMEOUT_MS, {
      min: 5000,
      max: 120000,
    }),
    retries: toInt(process.env.STRESS_RETRIES, DEFAULT_RETRIES, {
      min: 0,
      max: 5,
    }),
    runSeed: toInt(process.env.STRESS_RUN_SEED, DEFAULT_RUN_SEED, {
      min: 1,
      max: 9_999_999_999_999,
    }),
    skipWrites:
      String(process.env.STRESS_SKIP_WRITES || "").trim().toLowerCase() === "true",
  };

  for (let i = 0; i < args.length; i += 1) {
    const key = String(args[i] || "").trim();
    const next = String(args[i + 1] || "").trim();
    if (!key.startsWith("--")) continue;
    if (key === "--base-url") {
      out.baseUrl = next.replace(/\/+$/, "");
      i += 1;
      continue;
    }
    if (key === "--users") {
      out.users = toInt(next, out.users, { min: 1, max: 20000 });
      i += 1;
      continue;
    }
    if (key === "--concurrency") {
      out.concurrency = toInt(next, out.concurrency, { min: 1, max: 5000 });
      i += 1;
      continue;
    }
    if (key === "--timeout-ms") {
      out.timeoutMs = toInt(next, out.timeoutMs, { min: 5000, max: 120000 });
      i += 1;
      continue;
    }
    if (key === "--retries") {
      out.retries = toInt(next, out.retries, { min: 0, max: 5 });
      i += 1;
      continue;
    }
    if (key === "--run-seed") {
      out.runSeed = toInt(next, out.runSeed, {
        min: 1,
        max: 9_999_999_999_999,
      });
      i += 1;
      continue;
    }
    if (key === "--skip-writes") {
      out.skipWrites = true;
    }
  }
  return out;
}

function buildPhone(index) {
  const suffix = String((RUN_SEED + index) % 100000000).padStart(8, "0");
  return `079${suffix}`;
}

function buildAddress(index) {
  const block = index % 2 === 0 ? "A1" : "B1";
  const buildingPrefix = block.startsWith("A") ? "A1" : "B1";
  const maxBuildingNo = block.startsWith("A") ? 12 : 22;
  const building = `${buildingPrefix}${String((index % maxBuildingNo) + 1).padStart(2, "0")}`;
  const floor = String((index % 9) + 1);
  const apartmentNo = String((index % 12) + 1).padStart(2, "0");
  const apartment = `${floor}${apartmentNo}`;
  return { block, building, apartment };
}

function buildForwardedFor(index) {
  const second = ((Math.floor(index / 255) % 254) + 1).toString();
  const third = ((index % 255) + 1).toString();
  return `10.42.${second}.${third}`;
}

function endpointKey(method, path) {
  return `${String(method || "").toUpperCase()} ${path}`;
}

function bump(map, key, value = 1) {
  map.set(key, Number(map.get(key) || 0) + value);
}

async function apiRequest({
  baseUrl,
  method,
  path,
  token = null,
  body = undefined,
  device = null,
  timeoutMs,
  retries,
  stats,
}) {
  const key = endpointKey(method, path.split("?")[0]);
  let last = null;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    const started = Date.now();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const headers = {
        "Content-Type": "application/json",
        "X-Device-Id":
          device?.deviceId || `stress-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
        "X-Client-Platform": device?.platform || "stress",
        "X-App-Version": device?.appVersion || "stress/1",
        "X-Device-Model": device?.model || "stress-runner",
        "User-Agent": device?.userAgent || "stress-runner/1",
        "X-Forwarded-For": device?.forwardedFor || "10.42.1.1",
      };
      if (token) headers.Authorization = `Bearer ${token}`;

      const res = await fetch(`${baseUrl}${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: controller.signal,
      });
      clearTimeout(timer);
      const elapsed = Date.now() - started;
      const text = await res.text();
      let data = null;
      if (text) {
        try {
          data = JSON.parse(text);
        } catch {
          data = text;
        }
      }

      bump(stats.requestsByEndpoint, key, 1);
      bump(stats.requestsByStatus, String(res.status), 1);
      bump(stats.endpointLatencyMs, key, elapsed);

      last = { ok: res.ok, status: res.status, data, elapsed };
      if (res.status === 429 && attempt < retries) {
        await new Promise((r) => setTimeout(r, 300 * (attempt + 1)));
        continue;
      }
      return last;
    } catch (error) {
      clearTimeout(timer);
      const elapsed = Date.now() - started;
      bump(stats.requestsByEndpoint, key, 1);
      bump(stats.requestsByStatus, "network_error", 1);
      bump(stats.endpointLatencyMs, key, elapsed);
      last = { ok: false, status: 0, data: String(error?.message || error), elapsed };
      if (attempt < retries) {
        await new Promise((r) => setTimeout(r, 300 * (attempt + 1)));
        continue;
      }
      return last;
    }
  }
  return last;
}

async function discoverCatalog({ baseUrl, timeoutMs, retries, stats }) {
  const merchants = await apiRequest({
    baseUrl,
    method: "GET",
    path: "/api/merchants",
    timeoutMs,
    retries,
    stats,
  });
  if (!Array.isArray(merchants?.data) || merchants.data.length === 0) {
    return { merchantId: null, productId: null };
  }

  const merchantId = Number(merchants.data[0]?.id || 0) || null;
  if (!merchantId) return { merchantId: null, productId: null };

  const products = await apiRequest({
    baseUrl,
    method: "GET",
    path: `/api/merchants/${merchantId}/products`,
    timeoutMs,
    retries,
    stats,
  });
  const productId = Array.isArray(products?.data)
    ? Number(products.data[0]?.id || 0) || null
    : null;

  return { merchantId, productId };
}

async function runVirtualUser({ index, cfg, catalog, stats }) {
  const phone = buildPhone(index);
  const pin = "1234";
  const fullName = `Stress User ${index}`;
  const address = buildAddress(index);
  const device = {
    deviceId: `stress-user-${RUN_SEED}-${index}`,
    platform: "stress",
    appVersion: "stress/1",
    model: "stress-runner",
    userAgent: `stress-runner/${index}`,
    forwardedFor: buildForwardedFor(index),
  };

  const registerRes = await apiRequest({
    baseUrl: cfg.baseUrl,
    method: "POST",
    path: "/api/auth/register",
    device,
    body: {
      fullName,
      phone,
      pin,
      block: address.block,
      buildingNumber: address.building,
      apartment: address.apartment,
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "analytics_v1",
    },
    timeoutMs: cfg.timeoutMs,
    retries: cfg.retries,
    stats,
  });

  let token = String(registerRes?.data?.token || "").trim();
  if (!token) {
    const loginRes = await apiRequest({
      baseUrl: cfg.baseUrl,
      method: "POST",
      path: "/api/auth/login",
      device,
      body: { phone, pin },
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
    });
    token = String(loginRes?.data?.token || "").trim();
  }
  if (!token) {
    bump(stats.usersFailedAuth, "count", 1);
    return;
  }

  bump(stats.usersAuthenticated, "count", 1);

  const ops = [
    apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/feed/posts?limit=20",
      token,
      device,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
    }),
    apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/jobs?limit=20",
      token,
      device,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
    }),
    apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/merchants/discovery?limit=20",
      token,
      device,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
    }),
    apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/orders/my",
      token,
      device,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
    }),
  ];

  if (!cfg.skipWrites) {
    ops.push(
      apiRequest({
        baseUrl: cfg.baseUrl,
        method: "POST",
        path: "/api/taxi/rides",
        token,
        device,
        body: {
          pickupLatitude: 33.2977,
          pickupLongitude: 44.3922,
          dropoffLatitude: 33.3152,
          dropoffLongitude: 44.3661,
          pickupLabel: "Bismayah Gate",
          dropoffLabel: "Bismayah Center",
          proposedFareIqd: 7000 + (index % 5) * 1000,
          searchRadiusM: 3000,
        },
        timeoutMs: cfg.timeoutMs,
        retries: cfg.retries,
        stats,
      })
    );
  }

  if (!cfg.skipWrites && catalog.merchantId && catalog.productId) {
    ops.push(
      apiRequest({
        baseUrl: cfg.baseUrl,
        method: "POST",
        path: "/api/orders",
        token,
        body: {
          merchantId: Number(catalog.merchantId),
          items: [{ productId: Number(catalog.productId), quantity: 1 }],
          note: "stress order",
        },
        timeoutMs: cfg.timeoutMs,
        retries: cfg.retries,
        stats,
      })
    );
  }

  await Promise.allSettled(ops);
}

async function runPool({ total, concurrency, runner }) {
  let next = 0;
  const workers = Array.from({ length: Math.min(total, concurrency) }).map(async () => {
    for (;;) {
      const i = next;
      next += 1;
      if (i >= total) return;
      await runner(i + 1);
    }
  });
  await Promise.all(workers);
}

function serializeCounterMap(map) {
  const out = {};
  for (const [k, v] of map.entries()) out[k] = v;
  return out;
}

async function main() {
  const cfg = parseArgs();
  RUN_SEED = cfg.runSeed;
  const startedAt = Date.now();
  const stats = {
    usersAuthenticated: new Map(),
    usersFailedAuth: new Map(),
    requestsByEndpoint: new Map(),
    requestsByStatus: new Map(),
    endpointLatencyMs: new Map(),
  };

  console.log(
    `[stress] start baseUrl=${cfg.baseUrl} users=${cfg.users} concurrency=${cfg.concurrency} timeoutMs=${cfg.timeoutMs} retries=${cfg.retries} runSeed=${cfg.runSeed} skipWrites=${cfg.skipWrites}`
  );

  const catalog = await discoverCatalog({
    baseUrl: cfg.baseUrl,
    timeoutMs: cfg.timeoutMs,
    retries: cfg.retries,
    stats,
  });
  console.log(
    `[stress] catalog merchantId=${catalog.merchantId || "none"} productId=${catalog.productId || "none"}`
  );

  await runPool({
    total: cfg.users,
    concurrency: cfg.concurrency,
    runner: async (index) => {
      await runVirtualUser({ index, cfg, catalog, stats });
      if (index % 25 === 0) {
        console.log(`[stress] progress usersProcessed=${index}/${cfg.users}`);
      }
    },
  });

  const durationSec = ((Date.now() - startedAt) / 1000).toFixed(2);
  console.log("[stress] completed");
  console.log(
    JSON.stringify(
      {
        baseUrl: cfg.baseUrl,
        usersTarget: cfg.users,
        concurrency: cfg.concurrency,
        runSeed: cfg.runSeed,
        skipWrites: cfg.skipWrites === true,
        durationSec: Number(durationSec),
        usersAuthenticated: Number(stats.usersAuthenticated.get("count") || 0),
        usersFailedAuth: Number(stats.usersFailedAuth.get("count") || 0),
        requestsByEndpoint: serializeCounterMap(stats.requestsByEndpoint),
        requestsByStatus: serializeCounterMap(stats.requestsByStatus),
        endpointLatencyMs: serializeCounterMap(stats.endpointLatencyMs),
      },
      null,
      2
    )
  );
}

main().catch((error) => {
  console.error("[stress] failed", error);
  process.exitCode = 1;
});
