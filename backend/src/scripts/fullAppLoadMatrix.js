/* eslint-disable no-console */
import "dotenv/config";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";
const DEFAULT_TIMEOUT_MS = 20000;
const DEFAULT_RETRIES = 2;
const DEFAULT_RUN_SEED = Date.now();
const DEFAULT_STAGE_STEP = 20;
const DEFAULT_STAGE_MAX = 400;
const DEFAULT_MAX_CONCURRENCY = 160;
const DEFAULT_STOP_FAIL_RATE = 0.45;

function toInt(value, fallback, { min = 1, max = 1_000_000 } = {}) {
  const n = Number(value);
  if (!Number.isInteger(n)) return fallback;
  if (n < min || n > max) return fallback;
  return n;
}

function toFloat(value, fallback, { min = 0, max = 1 } = {}) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  if (n < min || n > max) return fallback;
  return n;
}

function parseStages(raw, fallbackStep, fallbackMax) {
  const value = String(raw || "").trim();
  if (value) {
    const explicit = value
      .split(",")
      .map((item) => Number(String(item || "").trim()))
      .filter((n) => Number.isInteger(n) && n > 0)
      .sort((a, b) => a - b);
    if (explicit.length > 0) return explicit;
  }
  const out = [];
  for (let n = fallbackStep; n <= fallbackMax; n += fallbackStep) {
    out.push(n);
  }
  if (out.length === 0) out.push(fallbackStep);
  return out;
}

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    baseUrl:
      String(process.env.LOAD_BASE_URL || DEFAULT_BASE_URL).trim().replace(/\/+$/, ""),
    timeoutMs: toInt(process.env.LOAD_TIMEOUT_MS, DEFAULT_TIMEOUT_MS, {
      min: 5000,
      max: 120000,
    }),
    retries: toInt(process.env.LOAD_RETRIES, DEFAULT_RETRIES, { min: 0, max: 6 }),
    runSeed: toInt(process.env.LOAD_RUN_SEED, DEFAULT_RUN_SEED, {
      min: 1,
      max: 9_999_999_999_999,
    }),
    stageStep: toInt(process.env.LOAD_STAGE_STEP, DEFAULT_STAGE_STEP, {
      min: 1,
      max: 200,
    }),
    stageMax: toInt(process.env.LOAD_STAGE_MAX, DEFAULT_STAGE_MAX, {
      min: 20,
      max: 5000,
    }),
    maxConcurrency: toInt(process.env.LOAD_MAX_CONCURRENCY, DEFAULT_MAX_CONCURRENCY, {
      min: 1,
      max: 5000,
    }),
    stopFailRate: toFloat(process.env.LOAD_STOP_FAIL_RATE, DEFAULT_STOP_FAIL_RATE, {
      min: 0.05,
      max: 1,
    }),
    skipWrites:
      String(process.env.LOAD_SKIP_WRITES || "").trim().toLowerCase() === "true",
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
    if (key === "--timeout-ms") {
      out.timeoutMs = toInt(next, out.timeoutMs, { min: 5000, max: 120000 });
      i += 1;
      continue;
    }
    if (key === "--retries") {
      out.retries = toInt(next, out.retries, { min: 0, max: 6 });
      i += 1;
      continue;
    }
    if (key === "--run-seed") {
      out.runSeed = toInt(next, out.runSeed, { min: 1, max: 9_999_999_999_999 });
      i += 1;
      continue;
    }
    if (key === "--stage-step") {
      out.stageStep = toInt(next, out.stageStep, { min: 1, max: 200 });
      i += 1;
      continue;
    }
    if (key === "--stage-max") {
      out.stageMax = toInt(next, out.stageMax, { min: 20, max: 5000 });
      i += 1;
      continue;
    }
    if (key === "--stages") {
      out.stagesRaw = next;
      i += 1;
      continue;
    }
    if (key === "--max-concurrency") {
      out.maxConcurrency = toInt(next, out.maxConcurrency, { min: 1, max: 5000 });
      i += 1;
      continue;
    }
    if (key === "--stop-fail-rate") {
      out.stopFailRate = toFloat(next, out.stopFailRate, { min: 0.05, max: 1 });
      i += 1;
      continue;
    }
    if (key === "--skip-writes") {
      out.skipWrites = true;
    }
  }

  out.stages = parseStages(out.stagesRaw, out.stageStep, out.stageMax);
  return out;
}

function endpointKey(method, path) {
  return `${String(method || "").toUpperCase()} ${path}`;
}

function bump(map, key, value = 1) {
  map.set(key, Number(map.get(key) || 0) + value);
}

function serializeMap(map) {
  const out = {};
  for (const [k, v] of map.entries()) out[k] = v;
  return out;
}

function buildPhone(runSeed, index) {
  const seedPart = (runSeed + index) % 100000000;
  return `079${String(seedPart).padStart(8, "0")}`;
}

function buildUserAddress(index) {
  const block = "A1";
  const building = `A1${String((index % 12) + 1).padStart(2, "0")}`;
  const apartment = `${String((index % 9) + 1)}${String((index % 12) + 1).padStart(
    2,
    "0"
  )}`;
  return { block, buildingNumber: building, apartment };
}

function parseItems(data, fallbackKey = "items") {
  if (Array.isArray(data)) return data;
  if (Array.isArray(data?.[fallbackKey])) return data[fallbackKey];
  if (Array.isArray(data?.data)) return data.data;
  return [];
}

function extractRideId(payload) {
  const direct = Number(payload?.ride?.id || payload?.id || 0);
  if (direct > 0) return direct;
  const nested = Number(payload?.ride?.ride?.id || 0);
  return nested > 0 ? nested : null;
}

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function apiRequest({
  baseUrl,
  method,
  path,
  token = null,
  body = undefined,
  timeoutMs,
  retries,
  stats,
  deviceId,
}) {
  const key = endpointKey(method, path.split("?")[0]);
  let last = null;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    const startedAt = Date.now();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const headers = {
        "Content-Type": "application/json",
        "X-Device-Id": deviceId || `matrix-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
        "X-Client-Platform": "load-matrix",
        "X-App-Version": "load-matrix/1",
        "X-Device-Model": "load-matrix-runner",
        "User-Agent": "load-matrix/1",
      };
      if (token) headers.Authorization = `Bearer ${token}`;

      const response = await fetch(`${baseUrl}${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: controller.signal,
      });

      clearTimeout(timeout);
      const elapsed = Date.now() - startedAt;
      const text = await response.text();
      let data = null;
      if (text) {
        try {
          data = JSON.parse(text);
        } catch {
          data = text;
        }
      }

      bump(stats.requestsByEndpoint, key, 1);
      bump(stats.requestsByStatus, String(response.status), 1);
      bump(stats.latencyByEndpointMs, key, elapsed);
      if (!response.ok) {
        if (stats.failureSamples.length < 120) {
          stats.failureSamples.push({
            endpoint: key,
            status: response.status,
            body:
              typeof data === "string"
                ? data.slice(0, 300)
                : JSON.stringify(data || {}).slice(0, 300),
          });
        }
      }

      last = {
        ok: response.ok,
        status: response.status,
        elapsed,
        data,
      };

      if (response.status === 429 && attempt < retries) {
        const retryAfterSec = Number(response.headers.get("retry-after") || 1);
        await sleep(Math.max(1, retryAfterSec) * 1000);
        continue;
      }
      return last;
    } catch (error) {
      clearTimeout(timeout);
      const elapsed = Date.now() - startedAt;
      bump(stats.requestsByEndpoint, key, 1);
      bump(stats.requestsByStatus, "network_error", 1);
      bump(stats.latencyByEndpointMs, key, elapsed);
      if (stats.failureSamples.length < 120) {
        stats.failureSamples.push({
          endpoint: key,
          status: "network_error",
          body: String(error?.message || error).slice(0, 300),
        });
      }
      last = {
        ok: false,
        status: 0,
        elapsed,
        data: String(error?.message || error),
      };
      if (attempt < retries) {
        await sleep((attempt + 1) * 250);
        continue;
      }
      return last;
    }
  }
  return last;
}

async function discoverCatalog({ cfg, stats }) {
  const merchantsRes = await apiRequest({
    baseUrl: cfg.baseUrl,
    method: "GET",
    path: "/api/merchants",
    timeoutMs: cfg.timeoutMs,
    retries: cfg.retries,
    stats,
    deviceId: "catalog-probe",
  });
  const merchants = parseItems(merchantsRes?.data);
  const orderCandidates = [];
  const merchantCandidates = merchants
    .filter((item) => Number(item?.id || 0) > 0)
    .slice(0, 12);
  for (const merchant of merchantCandidates) {
    const merchantId = Number(merchant.id || 0);
    if (!merchantId) continue;
    const productsRes = await apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: `/api/merchants/${merchantId}/products`,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId: "catalog-probe",
    });
    const products = parseItems(productsRes?.data);
    const productId = Number(products?.[0]?.id || 0);
    if (productId > 0) {
      orderCandidates.push({ merchantId, productId });
    }
  }

  const probeAuth = await registerOrLoginUser({
    cfg,
    stats,
    userIndex: 99999,
    stageUsers: 1,
    knownUsers: cfg.knownUsers,
  });
  let posts = [];
  let stories = [];
  let reels = [];
  if (probeAuth.token) {
    const probeToken = probeAuth.token;
    const probeDeviceId = probeAuth.deviceId;

    const publicPostsRes = await apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/feed/posts?limit=20",
      token: probeToken,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId: probeDeviceId,
    });
    posts = parseItems(publicPostsRes?.data);

    const storiesRes = await apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/feed/stories",
      token: probeToken,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId: probeDeviceId,
    });
    stories = parseItems(storiesRes?.data, "stories");

    const reelsRes = await apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/feed/reels/explore?limit=20",
      token: probeToken,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId: probeDeviceId,
    });
    reels = parseItems(reelsRes?.data);
  }

  return {
    merchantId: Number(orderCandidates?.[0]?.merchantId || 0) || null,
    productId: Number(orderCandidates?.[0]?.productId || 0) || null,
    orderCandidates,
    postId: Number(posts?.[0]?.id || 0) || null,
    storyId: Number(stories?.[0]?.id || 0) || null,
    reelId: Number(reels?.[0]?.id || 0) || null,
  };
}

async function registerOrLoginUser({
  cfg,
  stats,
  userIndex,
  stageUsers,
  knownUsers,
}) {
  const phone = buildPhone(cfg.runSeed, userIndex);
  const pin = "1234";
  const fullName = `Load Matrix ${stageUsers}-${userIndex}`;
  const address = buildUserAddress(userIndex);
  const deviceId = `matrix-${cfg.runSeed}-${stageUsers}-${userIndex}`;

  if (knownUsers.has(phone)) {
    const loginRes = await apiRequest({
      baseUrl: cfg.baseUrl,
      method: "POST",
      path: "/api/auth/login",
      body: { phone, pin },
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId,
    });
    let token = String(loginRes?.data?.token || "").trim();
    if (token) {
      return { token, phone, pin, deviceId };
    }
    knownUsers.delete(phone);
  }

  const registerRes = await apiRequest({
    baseUrl: cfg.baseUrl,
    method: "POST",
    path: "/api/auth/register",
    body: {
      fullName,
      phone,
      pin,
      block: address.block,
      buildingNumber: address.buildingNumber,
      apartment: address.apartment,
      analyticsConsentAccepted: true,
      analyticsConsentVersion: "analytics_v1",
    },
    timeoutMs: cfg.timeoutMs,
    retries: cfg.retries,
    stats,
    deviceId,
  });
  let token = String(registerRes?.data?.token || "").trim();
  if (token) {
    knownUsers.add(phone);
    return { token, phone, pin, deviceId };
  }

  const fallbackLoginRes = await apiRequest({
    baseUrl: cfg.baseUrl,
    method: "POST",
    path: "/api/auth/login",
    body: { phone, pin },
    timeoutMs: cfg.timeoutMs,
    retries: cfg.retries,
    stats,
    deviceId,
  });
  token = String(fallbackLoginRes?.data?.token || "").trim();
  if (token) knownUsers.add(phone);
  return { token, phone, pin, deviceId };
}

async function runUserScenario({
  cfg,
  stats,
  catalog,
  stageUsers,
  userIndex,
  sharedPosts,
}) {
  const auth = await registerOrLoginUser({
    cfg,
    stats,
    userIndex,
    stageUsers,
    knownUsers: cfg.knownUsers,
  });
  if (!auth.token) {
    bump(stats.userAuthFailures, "count", 1);
    return;
  }

  bump(stats.userAuthSuccess, "count", 1);

  const token = auth.token;
  const deviceId = auth.deviceId;

  const reads = [
    apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/feed/posts?limit=20",
      token,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId,
    }),
    apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/feed/stories",
      token,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId,
    }),
    apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/feed/reels/explore?limit=20",
      token,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId,
    }),
    apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/merchants?limit=30",
      token,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId,
    }),
    apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/orders/my",
      token,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId,
    }),
    apiRequest({
      baseUrl: cfg.baseUrl,
      method: "GET",
      path: "/api/taxi/rides/current",
      token,
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId,
    }),
  ];
  await Promise.allSettled(reads);

  const postCreate = await apiRequest({
    baseUrl: cfg.baseUrl,
    method: "POST",
    path: "/api/feed/posts",
    token,
    body: {
      caption: `load-matrix post ${cfg.runSeed}-${stageUsers}-${userIndex}`,
      postKind: "text",
    },
    timeoutMs: cfg.timeoutMs,
    retries: cfg.retries,
    stats,
    deviceId,
  });
  const ownPostId = Number(postCreate?.data?.post?.id || 0) || null;
  if (ownPostId) {
    sharedPosts.push(ownPostId);
  }

  const targetPostId =
    sharedPosts.length > 0
      ? sharedPosts[Math.floor(Math.random() * sharedPosts.length)]
      : catalog.postId;

  if (targetPostId) {
    await Promise.allSettled([
      apiRequest({
        baseUrl: cfg.baseUrl,
        method: "POST",
        path: `/api/feed/posts/${targetPostId}/like`,
        token,
        timeoutMs: cfg.timeoutMs,
        retries: cfg.retries,
        stats,
        deviceId,
      }),
      apiRequest({
        baseUrl: cfg.baseUrl,
        method: "POST",
        path: `/api/feed/posts/${targetPostId}/comments`,
        token,
        body: {
          body: `load-matrix comment ${cfg.runSeed}-${stageUsers}-${userIndex}`,
        },
        timeoutMs: cfg.timeoutMs,
        retries: cfg.retries,
        stats,
        deviceId,
      }),
    ]);
  }

  if (catalog.storyId) {
    await Promise.allSettled([
      apiRequest({
        baseUrl: cfg.baseUrl,
        method: "POST",
        path: `/api/feed/stories/${catalog.storyId}/view`,
        token,
        timeoutMs: cfg.timeoutMs,
        retries: cfg.retries,
        stats,
        deviceId,
      }),
      apiRequest({
        baseUrl: cfg.baseUrl,
        method: "POST",
        path: `/api/feed/stories/${catalog.storyId}/like`,
        token,
        timeoutMs: cfg.timeoutMs,
        retries: cfg.retries,
        stats,
        deviceId,
      }),
      apiRequest({
        baseUrl: cfg.baseUrl,
        method: "POST",
        path: `/api/feed/stories/${catalog.storyId}/comments`,
        token,
        body: {
          body: `load-matrix story comment ${cfg.runSeed}-${stageUsers}-${userIndex}`,
        },
        timeoutMs: cfg.timeoutMs,
        retries: cfg.retries,
        stats,
        deviceId,
      }),
    ]);
  }

  if (catalog.reelId) {
    await Promise.allSettled([
      apiRequest({
        baseUrl: cfg.baseUrl,
        method: "POST",
        path: `/api/feed/reels/${catalog.reelId}/view`,
        token,
        timeoutMs: cfg.timeoutMs,
        retries: cfg.retries,
        stats,
        deviceId,
      }),
      apiRequest({
        baseUrl: cfg.baseUrl,
        method: "GET",
        path: `/api/feed/reels/${catalog.reelId}`,
        token,
        timeoutMs: cfg.timeoutMs,
        retries: cfg.retries,
        stats,
        deviceId,
      }),
    ]);
  }

  if (!cfg.skipWrites) {
    const candidates = Array.isArray(catalog.orderCandidates)
      ? catalog.orderCandidates
      : [];
    if (candidates.length > 0) {
      let orderCreated = false;
      const shuffled = [...candidates].sort(() => Math.random() - 0.5).slice(0, 3);
      for (const candidate of shuffled) {
        const orderRes = await apiRequest({
          baseUrl: cfg.baseUrl,
          method: "POST",
          path: "/api/orders",
          token,
          body: {
            merchantId: Number(candidate.merchantId),
            items: [{ productId: Number(candidate.productId), quantity: 1 }],
            note: `load-matrix order ${cfg.runSeed}-${stageUsers}-${userIndex}`,
          },
          timeoutMs: cfg.timeoutMs,
          retries: cfg.retries,
          stats,
          deviceId,
        });
        if (orderRes.ok) {
          orderCreated = true;
          break;
        }
      }
      if (!orderCreated) {
        bump(stats.orderWriteFailures, "count", 1);
      }
    }

    const taxiRes = await apiRequest({
      baseUrl: cfg.baseUrl,
      method: "POST",
      path: "/api/taxi/rides",
      token,
      body: {
        pickupLatitude: 33.2977,
        pickupLongitude: 44.3922,
        dropoffLatitude: 33.3152,
        dropoffLongitude: 44.3661,
        pickupLabel: "Bismayah Gate",
        dropoffLabel: "Bismayah Center",
        proposedFareIqd: 6000 + (userIndex % 7) * 1000,
        searchRadiusM: 3000,
      },
      timeoutMs: cfg.timeoutMs,
      retries: cfg.retries,
      stats,
      deviceId,
    });
    const rideId = extractRideId(taxiRes?.data);
    if (taxiRes.ok && rideId) {
      await apiRequest({
        baseUrl: cfg.baseUrl,
        method: "POST",
        path: `/api/taxi/rides/${rideId}/cancel`,
        token,
        timeoutMs: cfg.timeoutMs,
        retries: cfg.retries,
        stats,
        deviceId,
      });
    }
  }
}

async function runPool({ totalUsers, concurrency, runner }) {
  let next = 0;
  const workers = Array.from({ length: Math.min(totalUsers, concurrency) }).map(async () => {
    for (;;) {
      const current = next;
      next += 1;
      if (current >= totalUsers) return;
      await runner(current + 1);
    }
  });
  await Promise.all(workers);
}

function buildStageSummary({ stageUsers, startedAt, stats, concurrency }) {
  const durationSec = Number(((Date.now() - startedAt) / 1000).toFixed(2));
  const successUsers = Number(stats.userAuthSuccess.get("count") || 0);
  const failedUsers = Number(stats.userAuthFailures.get("count") || 0);
  const statusMap = serializeMap(stats.requestsByStatus);
  const totalRequests = Object.values(statusMap).reduce((sum, value) => sum + Number(value || 0), 0);
  const failedRequests =
    Number(statusMap.network_error || 0) +
    Object.entries(statusMap)
      .filter(([code]) => /^[45]\d\d$/.test(code))
      .reduce((sum, [, value]) => sum + Number(value || 0), 0);
  const failRate = totalRequests > 0 ? failedRequests / totalRequests : 1;

  return {
    stageUsers,
    concurrency,
    durationSec,
    authenticatedUsers: successUsers,
    failedAuthUsers: failedUsers,
    orderWriteFailures: Number(stats.orderWriteFailures.get("count") || 0),
    totalRequests,
    failedRequests,
    failRate: Number(failRate.toFixed(4)),
    requestsByStatus: statusMap,
    requestsByEndpoint: serializeMap(stats.requestsByEndpoint),
    latencyByEndpointMs: serializeMap(stats.latencyByEndpointMs),
    failureSamples: stats.failureSamples,
  };
}

async function runStage({ cfg, stageUsers }) {
  const startedAt = Date.now();
  const stats = {
    userAuthSuccess: new Map(),
    userAuthFailures: new Map(),
    requestsByStatus: new Map(),
    requestsByEndpoint: new Map(),
    latencyByEndpointMs: new Map(),
    orderWriteFailures: new Map(),
    failureSamples: [],
  };
  const sharedPosts = [];

  const concurrency = Math.min(cfg.maxConcurrency, Math.max(1, Math.floor(stageUsers * 0.45)));
  const catalog = await discoverCatalog({ cfg, stats });
  console.log(
    `[matrix] stage=${stageUsers} users concurrency=${concurrency} catalog merchant=${catalog.merchantId || "none"} product=${catalog.productId || "none"} post=${catalog.postId || "none"} story=${catalog.storyId || "none"} reel=${catalog.reelId || "none"}`
  );

  await runPool({
    totalUsers: stageUsers,
    concurrency,
    runner: async (userIndex) => {
      await runUserScenario({
        cfg,
        stats,
        catalog,
        stageUsers,
        userIndex,
        sharedPosts,
      });
      if (userIndex % 10 === 0 || userIndex === stageUsers) {
        console.log(`[matrix] stage=${stageUsers} progress=${userIndex}/${stageUsers}`);
      }
    },
  });

  return buildStageSummary({
    stageUsers,
    startedAt,
    stats,
    concurrency,
  });
}

async function main() {
  const cfg = parseArgs();
  cfg.knownUsers = new Set();
  const startedAt = Date.now();
  const results = [];
  let aborted = false;

  console.log(
    `[matrix] start baseUrl=${cfg.baseUrl} stages=${cfg.stages.join(",")} timeoutMs=${cfg.timeoutMs} retries=${cfg.retries} runSeed=${cfg.runSeed} maxConcurrency=${cfg.maxConcurrency} stopFailRate=${cfg.stopFailRate} skipWrites=${cfg.skipWrites}`
  );

  for (const stageUsers of cfg.stages) {
    const stageResult = await runStage({ cfg, stageUsers });
    results.push(stageResult);
    console.log(
      `[matrix] stage=${stageUsers} done failRate=${stageResult.failRate} totalRequests=${stageResult.totalRequests} failedRequests=${stageResult.failedRequests}`
    );
    if (stageResult.failRate >= cfg.stopFailRate) {
      aborted = true;
      console.log(
        `[matrix] stop condition reached at stage=${stageUsers} failRate=${stageResult.failRate}`
      );
      break;
    }
  }

  const totalDurationSec = Number(((Date.now() - startedAt) / 1000).toFixed(2));
  const output = {
    baseUrl: cfg.baseUrl,
    runSeed: cfg.runSeed,
    skipWrites: cfg.skipWrites === true,
    timeoutMs: cfg.timeoutMs,
    retries: cfg.retries,
    maxConcurrency: cfg.maxConcurrency,
    stopFailRate: cfg.stopFailRate,
    stagesPlanned: cfg.stages,
    stagesCompleted: results.map((r) => r.stageUsers),
    aborted,
    totalDurationSec,
    results,
  };

  console.log("[matrix] completed");
  console.log(JSON.stringify(output, null, 2));
}

main().catch((error) => {
  console.error("[matrix] failed", error);
  process.exitCode = 1;
});
