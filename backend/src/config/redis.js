import { env } from "./env.js";

let RedisCtor = null;
let redisClient = null;
let redisInitPromise = null;

function safeErrorCode(error) {
  return String(error?.code || error?.message || "REDIS_ERROR");
}

async function ensureRedisCtor() {
  if (RedisCtor) return RedisCtor;
  try {
    const mod = await import("ioredis");
    RedisCtor = mod?.default || mod?.Redis || null;
    return RedisCtor;
  } catch (_) {
    RedisCtor = null;
    return null;
  }
}

export function isRedisConfigured() {
  return Boolean(env.redisUrl);
}

function buildRedisOptions(role = "default") {
  return {
    lazyConnect: true,
    maxRetriesPerRequest: 1,
    enableReadyCheck: true,
    enableAutoPipelining: env.redisEnableAutoPipelining === true,
    connectionName: `maslaki:${role}:w${env.appWorkerSlot || 0}:pid${process.pid}`,
  };
}

export async function createRedisIsolatedClient(role = "isolated") {
  if (!env.redisUrl) return null;
  const Ctor = await ensureRedisCtor();
  if (!Ctor) return null;
  return new Ctor(env.redisUrl, buildRedisOptions(role));
}

export async function getRedisClient() {
  if (!env.redisUrl) return null;
  if (redisClient) return redisClient;
  if (redisInitPromise) return redisInitPromise;

  redisInitPromise = (async () => {
    const client = await createRedisIsolatedClient("cache");
    if (!client) return null;
    try {
      if (client.status !== "ready") {
        await client.connect();
      }
      redisClient = client;
      return redisClient;
    } catch (_) {
      try {
        client.disconnect();
      } catch (_) {
        // ignore disconnect errors
      }
      return null;
    }
  })();

  try {
    return await redisInitPromise;
  } finally {
    redisInitPromise = null;
  }
}

export async function redisHealthSnapshot() {
  if (!env.redisUrl) {
    return {
      configured: false,
      ok: false,
      error: "REDIS_NOT_CONFIGURED",
    };
  }

  const startedAt = Date.now();
  const client = await getRedisClient();
  if (!client) {
    return {
      configured: true,
      ok: false,
      responseMs: Date.now() - startedAt,
      error: "REDIS_CLIENT_UNAVAILABLE",
    };
  }

  try {
    const pong = await client.ping();
    return {
      configured: true,
      ok: String(pong || "").toUpperCase() === "PONG",
      responseMs: Date.now() - startedAt,
      status: client.status,
    };
  } catch (error) {
    return {
      configured: true,
      ok: false,
      responseMs: Date.now() - startedAt,
      error: safeErrorCode(error),
      status: client.status,
    };
  }
}

export async function closeRedisClient() {
  if (!redisClient) return;
  try {
    await redisClient.quit();
  } catch (_) {
    try {
      redisClient.disconnect();
    } catch (_) {
      // ignore
    }
  } finally {
    redisClient = null;
  }
}
