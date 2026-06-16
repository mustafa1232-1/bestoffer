import pg from "pg";

import { env } from "./env.js";

const poolBaseOptions = {
  max: 18,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 10_000,
  ssl: env.isProduction ? { rejectUnauthorized: false } : false,
};

function createPool(connectionString) {
  return new pg.Pool({
    connectionString,
    ...poolBaseOptions,
  });
}

const aiPrimaryPool = env.aiDatabaseUrl ? createPool(env.aiDatabaseUrl) : null;
const aiStandbyPool = env.aiDatabaseStandbyUrl
  ? createPool(env.aiDatabaseStandbyUrl)
  : null;
let activePoolLabel = "primary";
let lastFailoverAt = null;
let lastFailoverError = null;

const failoverPgCodes = new Set([
  "08000",
  "08001",
  "08003",
  "08004",
  "08006",
  "08007",
  "08P01",
  "57P01",
  "57P02",
  "57P03",
  "53300",
  "53400",
  "53200",
]);

const failoverNodeCodes = new Set([
  "ECONNRESET",
  "ECONNREFUSED",
  "ETIMEDOUT",
  "EHOSTUNREACH",
  "ENETUNREACH",
  "EPIPE",
]);

function isFailoverError(error) {
  const code = String(error?.code || "").toUpperCase();
  if (failoverPgCodes.has(code) || failoverNodeCodes.has(code)) return true;
  const message = String(error?.message || "").toLowerCase();
  return (
    message.includes("terminating connection") ||
    message.includes("connection reset") ||
    message.includes("connection refused") ||
    message.includes("timed out") ||
    message.includes("the database system is starting up")
  );
}

function currentPool() {
  if (!aiPrimaryPool) return null;
  if (activePoolLabel === "standby" && aiStandbyPool) return aiStandbyPool;
  return aiPrimaryPool;
}

function fallbackPool() {
  if (activePoolLabel === "primary" && aiStandbyPool) {
    return { label: "standby", pool: aiStandbyPool };
  }
  if (activePoolLabel === "standby" && aiPrimaryPool) {
    return { label: "primary", pool: aiPrimaryPool };
  }
  return null;
}

async function withFailover(execute) {
  const selected = currentPool();
  if (!selected) {
    throw new Error("AI_DB_NOT_CONFIGURED");
  }

  const firstLabel = activePoolLabel;
  try {
    return await execute(selected, firstLabel);
  } catch (error) {
    if (!env.aiDbFailoverEnabled || !isFailoverError(error)) throw error;
    const fallback = fallbackPool();
    if (!fallback) throw error;

    activePoolLabel = fallback.label;
    lastFailoverAt = new Date().toISOString();
    lastFailoverError = {
      code: String(error?.code || ""),
      message: String(error?.message || "AI_DB_FAILOVER_TRIGGERED"),
      from: firstLabel,
      to: fallback.label,
      at: lastFailoverAt,
    };

    return execute(fallback.pool, fallback.label);
  }
}

export function isAiDbConfigured() {
  return Boolean(aiPrimaryPool);
}

export async function aiQ(text, params) {
  return withFailover((targetPool) => targetPool.query(text, params));
}

export async function aiConnect() {
  return withFailover(async (targetPool, label) => {
    const client = await targetPool.connect();
    client.__poolLabel = label;
    return client;
  });
}

export async function closeAiDbPools() {
  if (!aiPrimaryPool) return;
  const tasks = [aiPrimaryPool.end()];
  if (aiStandbyPool) tasks.push(aiStandbyPool.end());
  await Promise.allSettled(tasks);
}

export async function aiDbHealthSnapshot() {
  if (!aiPrimaryPool) {
    return {
      configured: false,
      activePool: null,
      failoverEnabled: false,
      primary: null,
      standby: null,
      lastFailoverAt: null,
    };
  }

  const primary = {
    configured: true,
    ok: false,
    responseMs: null,
    error: null,
  };
  const standby = {
    configured: Boolean(aiStandbyPool),
    ok: false,
    responseMs: null,
    error: null,
  };

  const pStart = Date.now();
  try {
    await aiPrimaryPool.query("SELECT 1");
    primary.ok = true;
    primary.responseMs = Date.now() - pStart;
  } catch (error) {
    primary.error = String(error?.code || error?.message || "AI_PRIMARY_DB_FAILED");
    primary.responseMs = Date.now() - pStart;
  }

  if (aiStandbyPool) {
    const sStart = Date.now();
    try {
      await aiStandbyPool.query("SELECT 1");
      standby.ok = true;
      standby.responseMs = Date.now() - sStart;
    } catch (error) {
      standby.error = String(error?.code || error?.message || "AI_STANDBY_DB_FAILED");
      standby.responseMs = Date.now() - sStart;
    }
  }

  return {
    configured: true,
    activePool: activePoolLabel,
    failoverEnabled: env.aiDbFailoverEnabled,
    primary,
    standby,
    lastFailoverAt,
    lastFailoverError,
  };
}

export function getAiDbFailoverState() {
  return {
    configured: Boolean(aiPrimaryPool),
    activePool: aiPrimaryPool ? activePoolLabel : null,
    standbyConfigured: Boolean(aiStandbyPool),
    failoverEnabled: env.aiDbFailoverEnabled,
    lastFailoverAt,
    lastFailoverError,
  };
}
