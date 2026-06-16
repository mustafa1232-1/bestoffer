import pg from "pg";

import { env } from "./env.js";

const PRIMARY_LABEL = "primary";
const DEFAULT_DB_RETRIES = 1;
const PRIMARY_RETRY_DELAY_MS = 250;

const poolBaseOptions = {
  max: 20,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 10_000,
  keepAlive: true,
  query_timeout: 15_000,
  statement_timeout: 20_000,
  ssl: env.isProduction ? { rejectUnauthorized: false } : false,
};

const transientPgCodes = new Set([
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

const transientNodeCodes = new Set([
  "ECONNRESET",
  "ECONNREFUSED",
  "ETIMEDOUT",
  "EHOSTUNREACH",
  "ENETUNREACH",
  "EPIPE",
]);

let lastPrimaryFailureAt = null;
let lastPrimaryFailureError = null;
let lastPrimaryRecoveryAt = null;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function safeErrorCode(error) {
  return String(error?.code || error?.message || "DB_ERROR");
}

function safeErrorMessage(error) {
  return String(error?.message || error?.code || "DB_ERROR");
}

function isTransientDbConnectionError(error) {
  const code = String(error?.code || "").toUpperCase();
  if (transientPgCodes.has(code) || transientNodeCodes.has(code)) return true;

  const message = String(error?.message || "").toLowerCase();
  return (
    message.includes("terminating connection") ||
    message.includes("connection reset") ||
    message.includes("connection refused") ||
    message.includes("timed out") ||
    message.includes("the database system is starting up") ||
    message.includes("server closed the connection") ||
    message.includes("failed to connect")
  );
}

function createPool(connectionString, label) {
  if (!connectionString) return null;
  const targetPool = new pg.Pool({
    connectionString,
    application_name: `maslaki-api-${label}`,
    ...poolBaseOptions,
  });

  targetPool.on("error", (error) => {
    console.error(`[db:${label}] pool error: ${safeErrorMessage(error)}`);
  });

  return targetPool;
}

const primaryPool = createPool(env.databaseUrl, PRIMARY_LABEL);

function notePrimaryFailure(error) {
  lastPrimaryFailureAt = new Date().toISOString();
  lastPrimaryFailureError = {
    at: lastPrimaryFailureAt,
    code: safeErrorCode(error),
    message: safeErrorMessage(error),
  };
}

function notePrimaryRecovery() {
  if (!lastPrimaryFailureAt) return;
  lastPrimaryRecoveryAt = new Date().toISOString();
}

async function executeOnPrimary(operation, { kind = "query", retries = DEFAULT_DB_RETRIES } = {}) {
  if (!primaryPool) {
    throw new Error("PRIMARY_DB_NOT_CONFIGURED");
  }

  let attempt = 0;
  while (attempt <= retries) {
    attempt += 1;
    try {
      const result = await operation(primaryPool);
      notePrimaryRecovery();
      return result;
    } catch (error) {
      notePrimaryFailure(error);
      const canRetry = isTransientDbConnectionError(error) && attempt <= retries;
      console.error(
        `[db:${PRIMARY_LABEL}] ${kind} failed on attempt ${attempt}/${retries + 1}: ${safeErrorMessage(error)}`
      );
      if (!canRetry) {
        throw error;
      }
      await sleep(PRIMARY_RETRY_DELAY_MS * attempt);
    }
  }

  throw new Error("PRIMARY_DB_RETRY_EXHAUSTED");
}

async function probePrimary() {
  if (!primaryPool) {
    return {
      configured: false,
      ok: false,
      responseMs: null,
      role: PRIMARY_LABEL,
      error: null,
      inRecovery: null,
    };
  }

  const startedAt = Date.now();
  try {
    const result = await primaryPool.query(
      "SELECT pg_is_in_recovery() AS in_recovery, NOW() AS current_time"
    );
    return {
      configured: true,
      ok: true,
      responseMs: Date.now() - startedAt,
      role: PRIMARY_LABEL,
      error: null,
      inRecovery: result.rows[0]?.in_recovery === true,
      checkedAt: result.rows[0]?.current_time || new Date().toISOString(),
    };
  } catch (error) {
    return {
      configured: true,
      ok: false,
      responseMs: Date.now() - startedAt,
      role: PRIMARY_LABEL,
      error: safeErrorCode(error),
      inRecovery: null,
    };
  }
}

export async function dbHealthSnapshot() {
  const startedAt = Date.now();
  const primary = await probePrimary();

  return {
    mode: "single_primary",
    automaticFailover: false,
    totalMs: Date.now() - startedAt,
    primary,
    lastPrimaryFailureAt,
    lastPrimaryFailureError,
    lastPrimaryRecoveryAt,
  };
}

export function getDbFailoverState() {
  return {
    strategy: "single_primary_no_failover",
    automaticFailover: false,
    writeTarget: PRIMARY_LABEL,
    readTarget: PRIMARY_LABEL,
    primaryEnvVar: "DATABASE_URL",
    failoverEnabled: false,
    standbyConfigured: false,
    lastPrimaryFailureAt,
    lastPrimaryFailureError,
    lastPrimaryRecoveryAt,
    operatorAction:
      "Restore or replace the primary database, update DATABASE_URL if needed, then restart or redeploy the app.",
  };
}

export async function ensurePrimaryDbReady() {
  await executeOnPrimary((targetPool) => targetPool.query("SELECT 1"), {
    kind: "readiness",
    retries: 0,
  });
}

export const pool = {
  async query(text, params) {
    return executeOnPrimary((targetPool) => targetPool.query(text, params), {
      kind: "query",
      retries: DEFAULT_DB_RETRIES,
    });
  },
  async connect() {
    return executeOnPrimary(
      async (targetPool) => {
        const client = await targetPool.connect();
        client.__poolLabel = PRIMARY_LABEL;
        return client;
      },
      {
        kind: "connect",
        retries: 0,
      }
    );
  },
  async end() {
    if (primaryPool) {
      await primaryPool.end();
    }
  },
};

export async function q(text, params) {
  return pool.query(text, params);
}
