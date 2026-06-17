import jwt from "jsonwebtoken";
import { createClient } from "@supabase/supabase-js";
import NodeWebSocket from "ws";

import { q } from "./db.js";
import { env } from "./env.js";

const VALID_REALTIME_MODES = new Set(["dual", "supabase_only", "sse_only"]);
const DEFAULT_REALTIME_TOKEN_TTL_SEC = 15 * 60;
const LOCAL_REALTIME_READINESS_OBJECTS = Object.freeze(["realtime_outbox"]);
const SUPABASE_SHARED_TOPIC_READINESS_OBJECTS = Object.freeze([
  "realtime_channel_member",
  "realtime_channel_audit",
]);
const SUPABASE_SQL_PROBE_TTL_MS = 30 * 1000;

let supabaseAdminClient = null;
let supabaseSqlProbeCache = {
  expiresAt: 0,
  promise: null,
};
const dependencies = {
  getEnv: () => env,
  query: (text, params) => q(text, params),
  getAdminClient: () => getSupabaseAdminClient(),
};

function normalizeRealtimeMode(value) {
  const normalized = String(value || "")
    .trim()
    .toLowerCase();
  if (VALID_REALTIME_MODES.has(normalized)) return normalized;
  return "dual";
}

function resolveMissingRealtimeKeys() {
  const runtimeEnv = dependencies.getEnv();
  const missing = [];
  if (!runtimeEnv.supabaseUrl) missing.push("SUPABASE_URL");
  if (!runtimeEnv.supabaseAnonKey) missing.push("SUPABASE_ANON_KEY");
  if (!runtimeEnv.supabaseServiceRoleKey) missing.push("SUPABASE_SERVICE_ROLE_KEY");
  if (!runtimeEnv.supabaseJwtSecret) missing.push("SUPABASE_JWT_SECRET");
  return missing;
}

export function getSupabaseRealtimeStatus() {
  const runtimeEnv = dependencies.getEnv();
  const requestedMode = normalizeRealtimeMode(runtimeEnv.supabaseRealtimeMode);
  const enabled = runtimeEnv.supabaseRealtimeEnabled === true;
  const missingKeys = resolveMissingRealtimeKeys();
  const configured = missingKeys.length === 0;
  const canUseSupabase =
    enabled === true && requestedMode !== "sse_only" && configured;

  let reason = "enabled";
  if (!enabled) reason = "disabled";
  else if (requestedMode === "sse_only") reason = "sse_only_mode";
  else if (!configured) reason = "missing_config";

  return {
    enabled,
    configured,
    requestedMode,
    effectiveMode: canUseSupabase ? requestedMode : "sse_only",
    canUseSupabase,
    missingKeys,
    reason,
    hasAnonKey: !!runtimeEnv.supabaseAnonKey,
    hasServiceRoleKey: !!runtimeEnv.supabaseServiceRoleKey,
    hasJwtSecret: !!runtimeEnv.supabaseJwtSecret,
  };
}

export function getSupabaseRealtimeMode() {
  return getSupabaseRealtimeStatus().effectiveMode;
}

export function getSupabaseRealtimePublicConfig() {
  const runtimeEnv = dependencies.getEnv();
  return {
    supabaseUrl: runtimeEnv.supabaseUrl || "",
    supabaseAnonKey: runtimeEnv.supabaseAnonKey || "",
  };
}

export function getSupabaseAdminClient() {
  const status = getSupabaseRealtimeStatus();
  if (!status.canUseSupabase) return null;
  if (supabaseAdminClient) return supabaseAdminClient;
  const runtimeEnv = dependencies.getEnv();

  supabaseAdminClient = createClient(
    runtimeEnv.supabaseUrl,
    runtimeEnv.supabaseServiceRoleKey,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
      global: {
        headers: {
          "X-Client-Info": "maslaki-backend-realtime",
        },
      },
      realtime: {
        transport: NodeWebSocket,
      },
    }
  );
  return supabaseAdminClient;
}

export function getSupabaseBroadcastEndpoint() {
  const status = getSupabaseRealtimeStatus();
  if (!status.canUseSupabase) return null;
  const runtimeEnv = dependencies.getEnv();
  return `${String(runtimeEnv.supabaseUrl).replace(/\/+$/g, "")}/realtime/v1/api/broadcast`;
}

export function getSupabaseBroadcastHeaders() {
  const status = getSupabaseRealtimeStatus();
  if (!status.canUseSupabase) return null;
  const runtimeEnv = dependencies.getEnv();
  return {
    apikey: runtimeEnv.supabaseServiceRoleKey,
    Authorization: `Bearer ${runtimeEnv.supabaseServiceRoleKey}`,
    "Content-Type": "application/json",
  };
}

async function checkRailwayRealtimeSchema() {
  const result = await dependencies.query(
    `SELECT table_name
     FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_name = ANY($1::text[])`,
    [LOCAL_REALTIME_READINESS_OBJECTS]
  );
  const existing = new Set((result.rows || []).map((row) => row.table_name));
  const missingObjects = LOCAL_REALTIME_READINESS_OBJECTS.filter(
    (tableName) => !existing.has(tableName)
  );
  return {
    ok: missingObjects.length === 0,
    missingObjects,
  };
}

async function checkSupabaseRealtimeAuthorizationTables() {
  const now = Date.now();
  if (
    supabaseSqlProbeCache.promise &&
    Number(supabaseSqlProbeCache.expiresAt) > now
  ) {
    return supabaseSqlProbeCache.promise;
  }

  const promise = checkSupabaseRealtimeAuthorizationTablesUncached();
  supabaseSqlProbeCache = {
    expiresAt: now + SUPABASE_SQL_PROBE_TTL_MS,
    promise,
  };
  try {
    return await promise;
  } finally {
    if (supabaseSqlProbeCache.promise === promise) {
      supabaseSqlProbeCache.promise = null;
    }
  }
}

async function checkSupabaseRealtimeAuthorizationTablesUncached() {
  const client = dependencies.getAdminClient();
  if (!client) {
    return {
      ok: false,
      reason: "supabase_unavailable",
      missingObjects: [...SUPABASE_SHARED_TOPIC_READINESS_OBJECTS],
    };
  }

  const missingObjects = [];
  for (const tableName of SUPABASE_SHARED_TOPIC_READINESS_OBJECTS) {
    const { error } = await client
      .from(tableName)
      .select("*", { head: true, count: "exact" })
      .limit(1);
    if (error) {
      missingObjects.push(tableName);
    }
  }

  if (missingObjects.length > 0) {
    return {
      ok: false,
      reason: "missing_sql_objects",
      missingObjects,
    };
  }

  const membershipProbeChannel = `readiness:probe:${Date.now()}`;
  const membershipProbeUserId = 1;
  const membershipWrite = await client
    .from("realtime_channel_member")
    .upsert(
      [
        {
          channel: membershipProbeChannel,
          user_id: membershipProbeUserId,
          role: "member",
          expires_at: null,
        },
      ],
      {
        onConflict: "channel,user_id",
        ignoreDuplicates: false,
      }
    );
  if (membershipWrite.error) {
    return {
      ok: false,
      reason: "membership_write_probe_failed",
      missingObjects: ["realtime_channel_member"],
      error: membershipWrite.error.message,
    };
  }

  const membershipCleanup = await client
    .from("realtime_channel_member")
    .delete()
    .eq("channel", membershipProbeChannel)
    .eq("user_id", membershipProbeUserId);
  if (membershipCleanup.error) {
    return {
      ok: false,
      reason: "membership_cleanup_failed",
      missingObjects: ["realtime_channel_member"],
      error: membershipCleanup.error.message,
    };
  }

  const auditInsert = await client
    .from("realtime_channel_audit")
    .insert({
      channel: membershipProbeChannel,
      event: "readiness_probe",
      user_id: membershipProbeUserId,
      entity_type: "readiness_probe",
      entity_id: null,
    })
    .select("id")
    .single();
  if (auditInsert.error) {
    return {
      ok: false,
      reason: "audit_write_probe_failed",
      missingObjects: ["realtime_channel_audit"],
      error: auditInsert.error.message,
    };
  }

  const auditId = Number(auditInsert.data?.id || 0);
  if (auditId > 0) {
    const auditCleanup = await client
      .from("realtime_channel_audit")
      .delete()
      .eq("id", auditId);
    if (auditCleanup.error) {
      return {
        ok: false,
        reason: "audit_cleanup_failed",
        missingObjects: ["realtime_channel_audit"],
        error: auditCleanup.error.message,
      };
    }
  }

  return {
    ok: true,
    reason: "ok",
    missingObjects: [],
  };
}

async function verifyTokenIssuanceCapability() {
  try {
    const issued = issueSupabaseRealtimeToken({
      userId: 1,
      appRole: "user",
      expiresInSec: 60,
    });
    return {
      ok: typeof issued?.token === "string" && issued.token.length > 20,
    };
  } catch (error) {
    return {
      ok: false,
      reason: error?.code || error?.message || "token_issue_failed",
    };
  }
}

export async function getSupabaseRealtimeReadiness() {
  const status = getSupabaseRealtimeStatus();
  const runtimeEnv = dependencies.getEnv();
  const dualModeRequested =
    status.enabled === true && status.requestedMode === "dual";
  const supabaseModeRequested =
    status.enabled === true && status.requestedMode !== "sse_only";

  if (!supabaseModeRequested) {
    return {
      ok: true,
      status,
      releaseBlocking: false,
      reason: status.reason,
      railwaySchemaReady: true,
      sharedTopicsReady: true,
      tokenReady: true,
      missingKeys: [],
      missingObjects: [],
      checks: {
        dualModeRequested,
        hasSupabaseEnv: status.configured,
        railwayOutboxTable: true,
        sharedTopicAuthorizationTables: true,
        realtimeTokenIssuance: true,
        outboxPumpEnabled: false,
      },
    };
  }

  const missingKeys = [...status.missingKeys];
  const railwaySchemaStatus = await checkRailwayRealtimeSchema();
  const sharedTopicStatus = await checkSupabaseRealtimeAuthorizationTables();
  const tokenStatus = await verifyTokenIssuanceCapability();
  const outboxPumpEnabled = runtimeEnv.supabaseRealtimeEnabled === true;
  const releaseBlocking =
    dualModeRequested &&
    (!status.configured ||
      railwaySchemaStatus.ok !== true ||
      sharedTopicStatus.ok !== true ||
      tokenStatus.ok !== true ||
      outboxPumpEnabled !== true);
  const coreReady =
    status.configured &&
    railwaySchemaStatus.ok === true &&
    sharedTopicStatus.ok === true &&
    tokenStatus.ok === true &&
    outboxPumpEnabled === true;

  return {
    ok: coreReady,
    status,
    releaseBlocking,
    reason:
      missingKeys.length > 0
        ? "missing_config"
        : railwaySchemaStatus.ok !== true
          ? "missing_outbox_table"
          : tokenStatus.ok !== true
              ? tokenStatus.reason
              : outboxPumpEnabled !== true
                ? "outbox_disabled"
                : sharedTopicStatus.ok !== true
                  ? "shared_topics_degraded"
                  : "ok",
    railwaySchemaReady: railwaySchemaStatus.ok === true,
    sharedTopicsReady: sharedTopicStatus.ok === true,
    tokenReady: tokenStatus.ok === true,
    missingKeys,
    missingObjects: [
      ...(railwaySchemaStatus.missingObjects || []),
      ...(sharedTopicStatus.missingObjects || []),
    ],
    checks: {
      dualModeRequested,
      hasSupabaseEnv: status.configured,
      railwayOutboxTable: railwaySchemaStatus.ok === true,
      sharedTopicAuthorizationTables: sharedTopicStatus.ok === true,
      realtimeTokenIssuance: tokenStatus.ok === true,
      outboxPumpEnabled,
    },
  };
}

export async function getSupabaseSharedTopicReadiness() {
  const status = getSupabaseRealtimeStatus();
  if (!status.canUseSupabase || status.requestedMode === "sse_only") {
    return {
      ok: false,
      skipped: true,
      reason: status.reason,
      missingObjects: [],
    };
  }
  return checkSupabaseRealtimeAuthorizationTables();
}

export function issueSupabaseRealtimeToken({
  userId,
  appRole,
  expiresInSec = DEFAULT_REALTIME_TOKEN_TTL_SEC,
} = {}) {
  const status = getSupabaseRealtimeStatus();
  if (status.enabled !== true) {
    const error = new Error("REALTIME_DISABLED");
    error.code = "REALTIME_DISABLED";
    throw error;
  }
  const runtimeEnv = dependencies.getEnv();
  if (
    !runtimeEnv.supabaseUrl ||
    !runtimeEnv.supabaseAnonKey ||
    !runtimeEnv.supabaseJwtSecret
  ) {
    const error = new Error("REALTIME_NOT_CONFIGURED");
    error.code = "REALTIME_NOT_CONFIGURED";
    error.details = { missingKeys: resolveMissingRealtimeKeys() };
    throw error;
  }

  const safeUserId = Number(userId);
  if (!Number.isInteger(safeUserId) || safeUserId <= 0) {
    const error = new Error("REALTIME_TOKEN_INVALID_USER");
    error.code = "REALTIME_TOKEN_INVALID_USER";
    throw error;
  }

  const safeRole = String(appRole || "").trim().toLowerCase() || "user";
  const ttlSec = Math.max(60, Math.min(30 * 60, Number(expiresInSec) || 900));

  return {
    token: jwt.sign(
      {
        sub: String(safeUserId),
        role: "authenticated",
        app_user_id: safeUserId,
        app_role: safeRole,
      },
      runtimeEnv.supabaseJwtSecret,
      {
        algorithm: "HS256",
        expiresIn: `${ttlSec}s`,
      }
    ),
    expiresIn: ttlSec,
  };
}

export const __supabaseConfigTestApi = {
  reset() {
    supabaseAdminClient = null;
    supabaseSqlProbeCache = {
      expiresAt: 0,
      promise: null,
    };
    dependencies.getEnv = () => env;
    dependencies.query = (text, params) => q(text, params);
    dependencies.getAdminClient = () => getSupabaseAdminClient();
  },
  setEnv(nextEnv) {
    supabaseAdminClient = null;
    dependencies.getEnv = () => nextEnv;
  },
  setQuery(fn) {
    dependencies.query = fn;
  },
  setAdminClientFactory(fn) {
    dependencies.getAdminClient = fn;
  },
  normalizeRealtimeMode,
  resolveMissingRealtimeKeys,
  DEFAULT_REALTIME_TOKEN_TTL_SEC,
  resetReadinessCache() {
    supabaseSqlProbeCache = {
      expiresAt: 0,
      promise: null,
    };
  },
};
