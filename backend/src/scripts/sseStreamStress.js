/* eslint-disable no-console */
import "dotenv/config";
import fs from "node:fs";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";
const DEFAULT_USERS = 50;
const DEFAULT_TIMEOUT_MS = 15000;
const DEFAULT_OBSERVE_MS = 8000;

function toInt(value, fallback, { min = 1, max = 10000 } = {}) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return fallback;
  if (parsed < min || parsed > max) return fallback;
  return parsed;
}

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    baseUrl: String(process.env.STRESS_BASE_URL || DEFAULT_BASE_URL).trim().replace(/\/+$/, ""),
    users: toInt(process.env.STRESS_USERS, DEFAULT_USERS, { min: 1, max: 5000 }),
    timeoutMs: toInt(process.env.STRESS_TIMEOUT_MS, DEFAULT_TIMEOUT_MS, {
      min: 1000,
      max: 120000,
    }),
    observeMs: toInt(process.env.STRESS_OBSERVE_MS, DEFAULT_OBSERVE_MS, {
      min: 2000,
      max: 120000,
    }),
    runTag: String(process.env.LOAD_RUN_TAG || "").trim(),
  };
  for (let i = 0; i < args.length; i += 1) {
    const key = String(args[i] || "").trim();
    const next = String(args[i + 1] || "").trim();
    if (key === "--base-url" && next) {
      out.baseUrl = next.replace(/\/+$/, "");
      i += 1;
      continue;
    }
    if (key === "--users" && next) {
      out.users = toInt(next, out.users, { min: 1, max: 5000 });
      i += 1;
      continue;
    }
    if (key === "--timeout-ms" && next) {
      out.timeoutMs = toInt(next, out.timeoutMs, { min: 1000, max: 120000 });
      i += 1;
      continue;
    }
    if (key === "--observe-ms" && next) {
      out.observeMs = toInt(next, out.observeMs, { min: 2000, max: 120000 });
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

function parseTokenPool() {
  const filePath = String(
    process.env.AUTH_TOKENS_FILE || process.env.STRESS_AUTH_TOKENS_FILE || ""
  ).trim();
  let raw = "";
  if (filePath) {
    try {
      raw = fs.readFileSync(filePath, "utf8");
    } catch {
      raw = "";
    }
  }
  if (!raw) {
    raw = String(
      process.env.AUTH_TOKENS_JSON || process.env.STRESS_AUTH_TOKENS_JSON || ""
    ).trim();
  }
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .map((item, index) => ({
        token: String(item?.token || "").trim(),
        label: String(item?.phone || item?.userId || index + 1),
        deviceId: String(item?.deviceId || "").trim(),
        platform: String(item?.platform || "").trim(),
        appVersion: String(item?.appVersion || "").trim(),
        model: String(item?.model || "").trim(),
        userAgent: String(item?.userAgent || "").trim(),
      }))
      .filter((item) => item.token.length > 0);
  } catch {
    return [];
  }
}

function bucketStatus(summary, status) {
  const key = String(status || 0);
  summary[key] = (summary[key] || 0) + 1;
}

function resolveRideId(payload) {
  return Number(payload?.ride?.id || payload?.id || 0);
}

function buildAuthHeaders(auth, extra = {}) {
  return {
    Authorization: `Bearer ${auth.token}`,
    "X-Device-Id": auth.deviceId || `sse-device-${auth.label}`,
    "X-Client-Platform": auth.platform || "sse-stress",
    "X-App-Version": auth.appVersion || "sse-stress/1",
    "X-Device-Model": auth.model || "sse-runner",
    "User-Agent": auth.userAgent || `sse-stress/1/${auth.label}`,
    ...extra,
  };
}

async function jsonRequest({ baseUrl, path, method = "GET", auth, body, timeoutMs }) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: buildAuthHeaders(auth, { "Content-Type": "application/json" }),
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: controller.signal,
    });
    const text = await response.text();
    let data = null;
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = text;
      }
    }
    return { ok: response.ok, status: response.status, data };
  } finally {
    clearTimeout(timer);
  }
}

async function openSse({ baseUrl, path, auth, timeoutMs, observeMs }) {
  const controller = new AbortController();
  const hardTimer = setTimeout(() => controller.abort(), timeoutMs + observeMs + 1000);
  const observeTimer = setTimeout(() => controller.abort(), observeMs);
  const startedAt = Date.now();
  let eventCount = 0;
  let heartbeatCount = 0;
  try {
    const response = await fetch(`${baseUrl}${path}`, {
      headers: buildAuthHeaders(auth, {
        Accept: "text/event-stream",
        "Cache-Control": "no-cache",
      }),
      signal: controller.signal,
    });
    if (!response.ok || !response.body) {
      return {
        ok: false,
        status: response.status,
        elapsedMs: Date.now() - startedAt,
        eventCount,
        heartbeatCount,
      };
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() ?? "";
      for (const line of lines) {
        if (line.startsWith(":")) heartbeatCount += 1;
        if (line.startsWith("event:")) eventCount += 1;
      }
    }
    return {
      ok: true,
      status: response.status,
      elapsedMs: Date.now() - startedAt,
      eventCount,
      heartbeatCount,
    };
  } catch (error) {
    const aborted = error?.name === "AbortError";
    return {
      ok: aborted,
      status: aborted ? 200 : 0,
      elapsedMs: Date.now() - startedAt,
      eventCount,
      heartbeatCount,
      error: aborted ? null : String(error?.message || error),
    };
  } finally {
    clearTimeout(hardTimer);
    clearTimeout(observeTimer);
  }
}

async function runOne(index, cfg, auth) {
  const authEntry = auth[index % auth.length];
  if (!authEntry?.token) {
    return {
      notifications: { ok: false, status: 0, elapsedMs: 0, eventCount: 0, heartbeatCount: 0 },
      taxi: {
        ok: false,
        status: 0,
        elapsedMs: 0,
        eventCount: 0,
        heartbeatCount: 0,
        phase: "missing-auth",
      },
    };
  }

  const notifications = await openSse({
    baseUrl: cfg.baseUrl,
    path: "/api/notifications/stream",
    auth: authEntry,
    timeoutMs: cfg.timeoutMs,
    observeMs: cfg.observeMs,
  });

  let taxi = {
    ok: true,
    status: 204,
    elapsedMs: 0,
    eventCount: 0,
    heartbeatCount: 0,
    phase: "skipped",
  };
  const shouldDriveTaxi = index % 2 === 0 && index < auth.length;
  if (shouldDriveTaxi) {
    let createRide = await jsonRequest({
      baseUrl: cfg.baseUrl,
      path: "/api/taxi/rides",
      method: "POST",
      auth: authEntry,
      timeoutMs: cfg.timeoutMs,
      body: {
        pickupLatitude: 33.2977,
        pickupLongitude: 44.3922,
        dropoffLatitude: 33.3152,
        dropoffLongitude: 44.3661,
        pickupLabel: `SSE pickup ${cfg.runTag || index}`,
        dropoffLabel: `SSE dropoff ${cfg.runTag || index}`,
        proposedFareIqd: 7000,
        searchRadiusM: 3000,
      },
    });
    if (createRide.status === 409) {
      const currentRide = await jsonRequest({
        baseUrl: cfg.baseUrl,
        path: "/api/taxi/rides/current",
        method: "GET",
        auth: authEntry,
        timeoutMs: cfg.timeoutMs,
      });
      const currentRideId = resolveRideId(currentRide.data);
      if (currentRideId > 0) {
        await jsonRequest({
          baseUrl: cfg.baseUrl,
          path: `/api/taxi/rides/${currentRideId}/cancel`,
          method: "POST",
          auth: authEntry,
          timeoutMs: cfg.timeoutMs,
        });
      }
      createRide = await jsonRequest({
        baseUrl: cfg.baseUrl,
        path: "/api/taxi/rides",
        method: "POST",
        auth: authEntry,
        timeoutMs: cfg.timeoutMs,
        body: {
          pickupLatitude: 33.2977,
          pickupLongitude: 44.3922,
          dropoffLatitude: 33.3152,
          dropoffLongitude: 44.3661,
          pickupLabel: `SSE pickup ${cfg.runTag || index}`,
          dropoffLabel: `SSE dropoff ${cfg.runTag || index}`,
          proposedFareIqd: 7000,
          searchRadiusM: 3000,
        },
      });
    }
    if (createRide.ok) {
      taxi = await openSse({
        baseUrl: cfg.baseUrl,
        path: "/api/taxi/stream",
        auth: authEntry,
        timeoutMs: cfg.timeoutMs,
        observeMs: Math.max(3000, Math.floor(cfg.observeMs / 2)),
      });
      taxi.phase = taxi.ok ? "stream-opened" : "stream-failed";
      const rideId = resolveRideId(createRide.data);
      if (rideId > 0) {
        await jsonRequest({
          baseUrl: cfg.baseUrl,
          path: `/api/taxi/rides/${rideId}/cancel`,
          method: "POST",
          auth: authEntry,
          timeoutMs: cfg.timeoutMs,
        });
      }
    } else {
      taxi = {
        ok: false,
        status: createRide.status,
        elapsedMs: 0,
        eventCount: 0,
        heartbeatCount: 0,
        phase: "ride-create-failed",
      };
    }
  } else if (index % 2 === 0) {
    taxi.phase = "pooled-skip";
  }

  return { notifications, taxi };
}

async function main() {
  const cfg = parseArgs();
  const auth = parseTokenPool();
  if (auth.length === 0) {
    throw new Error("AUTH_TOKENS_JSON_REQUIRED");
  }

  const results = [];
  for (let i = 0; i < cfg.users; i += 1) {
    results.push(runOne(i, cfg, auth));
  }
  const settled = await Promise.all(results);

  const summary = {
    users: cfg.users,
    notifications: {
      ok: settled.filter((item) => item.notifications.ok).length,
      failed: settled.filter((item) => !item.notifications.ok).length,
      totalEvents: settled.reduce((sum, item) => sum + item.notifications.eventCount, 0),
      totalHeartbeats: settled.reduce(
        (sum, item) => sum + item.notifications.heartbeatCount,
        0
      ),
      statusBreakdown: settled.reduce((acc, item) => {
        bucketStatus(acc, item.notifications.status);
        return acc;
      }, {}),
    },
    taxi: {
      ok: settled.filter((item) => item.taxi.ok).length,
      failed: settled.filter((item) => !item.taxi.ok).length,
      totalEvents: settled.reduce((sum, item) => sum + item.taxi.eventCount, 0),
      totalHeartbeats: settled.reduce((sum, item) => sum + item.taxi.heartbeatCount, 0),
      statusBreakdown: settled.reduce((acc, item) => {
        bucketStatus(acc, item.taxi.status);
        return acc;
      }, {}),
      phaseBreakdown: settled.reduce((acc, item) => {
        const key = String(item.taxi.phase || "unknown");
        acc[key] = (acc[key] || 0) + 1;
        return acc;
      }, {}),
    },
  };

  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error("[sse-stream-stress] failed:", error);
  process.exitCode = 1;
});
