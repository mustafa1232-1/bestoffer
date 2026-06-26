import { q } from "../../config/db.js";
import { env } from "../../config/env.js";
import {
  getSupabaseAdminClient,
  getSupabaseRealtimeStatus,
} from "../../config/supabase.js";
import {
  REALTIME_METRICS,
  incMetric,
  isRetryableError,
  runWithCircuit,
  sanitizeErrorForLog,
  supabaseCircuit,
  withRetry,
  withTimeout,
} from "./realtime-resilience.js";

const CHANNEL_MEMBER_TABLE = "realtime_channel_member";

const dependencies = {
  query: (text, params) => q(text, params),
  getAdminClient: () => getSupabaseAdminClient(),
  getStatus: () => getSupabaseRealtimeStatus(),
  circuit: supabaseCircuit,
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  logger: console,
};

function membershipConfig() {
  return {
    timeoutMs: Number(env.supabaseRealtimeMembershipTimeoutMs) || 6000,
    retries: Number.isFinite(Number(env.supabaseRealtimeMembershipRetries))
      ? Number(env.supabaseRealtimeMembershipRetries)
      : 2,
  };
}

function normalizeChannel(channel) {
  return String(channel || "").trim();
}

function normalizeUserIds(userIds = []) {
  return [...new Set(
    (Array.isArray(userIds) ? userIds : [userIds])
      .map((value) => Number(value))
      .filter((value) => Number.isInteger(value) && value > 0)
  )];
}

function getSupabaseTableClient() {
  const status = dependencies.getStatus();
  if (!status.canUseSupabase) return null;
  return dependencies.getAdminClient();
}

/**
 * Run a Supabase membership operation with: circuit breaker + bounded timeout +
 * exponential-backoff retry on transient (5xx/network/timeout) failures.
 * Throws the (last) error if it ultimately fails so callers can degrade.
 */
async function runMembershipSupabaseOp(label, op) {
  const { timeoutMs, retries } = membershipConfig();
  return withRetry(
    () =>
      runWithCircuit(dependencies.circuit, () =>
        withTimeout(Promise.resolve().then(op), timeoutMs, label)
      ),
    {
      retries,
      baseDelayMs: 200,
      maxDelayMs: 2000,
      shouldRetry: isRetryableError,
      sleep: dependencies.sleep,
      onRetry: () => incMetric(REALTIME_METRICS.MEMBERSHIP_RETRY),
    }
  );
}

/**
 * Supabase-js returns `{ data, error }` rather than throwing. Normalise that
 * into a throw so retry/circuit logic sees the failure, attaching any status.
 */
function throwIfSupabaseError(error, label) {
  if (!error) return;
  const wrapped =
    error instanceof Error ? error : new Error(error?.message || String(error));
  if (error?.status != null) wrapped.status = error.status;
  if (error?.code != null && wrapped.code == null) wrapped.code = error.code;
  wrapped.details = { ...(error?.details || {}), label };
  throw wrapped;
}

/**
 * Build a structured, secret-free failure descriptor and emit a single compact
 * log line. Never prints HTML, JWTs, api keys or Authorization headers.
 */
function logMembershipFailure(event, { channel, userCount, error, requestId }) {
  incMetric(REALTIME_METRICS.MEMBERSHIP_FAILURE);
  const safe = sanitizeErrorForLog(error);
  const descriptor = {
    event,
    channel,
    userCount: Number(userCount) || 0,
    provider: "supabase",
    statusCode: safe?.statusCode ?? null,
    retryable: safe?.retryable ?? false,
    fallback: "polling",
    requestId: requestId || null,
    error: safe?.message || null,
  };
  dependencies.logger.warn?.("[realtime-membership] failed", descriptor);
  return descriptor;
}

async function fetchExistingChannelUserIds(channel) {
  const client = getSupabaseTableClient();
  if (!client) return [];
  const data = await runMembershipSupabaseOp("membership_fetch", async () => {
    const res = await client
      .from(CHANNEL_MEMBER_TABLE)
      .select("user_id")
      .eq("channel", channel);
    throwIfSupabaseError(res.error, "membership_fetch");
    return res.data;
  });
  return normalizeUserIds((data || []).map((item) => item.user_id));
}

async function pruneChannelMembers(channel, keepUserIds = []) {
  const client = getSupabaseTableClient();
  if (!client) return { ok: false, skipped: true, reason: "supabase_unavailable" };
  const existingIds = await fetchExistingChannelUserIds(channel);
  const keepSet = new Set(normalizeUserIds(keepUserIds));
  const removedIds = existingIds.filter((userId) => !keepSet.has(userId));
  if (removedIds.length <= 0) {
    return { ok: true, removedCount: 0 };
  }
  await runMembershipSupabaseOp("membership_prune", async () => {
    const res = await client
      .from(CHANNEL_MEMBER_TABLE)
      .delete()
      .eq("channel", channel)
      .in("user_id", removedIds);
    throwIfSupabaseError(res.error, "membership_prune");
    return true;
  });
  return { ok: true, removedCount: removedIds.length };
}

export async function allowUsersOnChannel(
  userIds,
  channel,
  { role = "member", expiresAt = null, replace = false, requestId = null } = {}
) {
  const safeChannel = normalizeChannel(channel);
  const safeUserIds = normalizeUserIds(userIds);
  if (!safeChannel || safeUserIds.length <= 0) {
    return { ok: false, skipped: true, reason: "invalid_membership_input" };
  }

  const client = getSupabaseTableClient();
  if (!client) {
    return { ok: false, skipped: true, reason: "supabase_unavailable" };
  }

  try {
    await runMembershipSupabaseOp("membership_allow", async () => {
      const payload = safeUserIds.map((userId) => ({
        channel: safeChannel,
        user_id: userId,
        role: String(role || "member").trim() || "member",
        expires_at: expiresAt || null,
      }));
      const res = await client.from(CHANNEL_MEMBER_TABLE).upsert(payload, {
        onConflict: "channel,user_id",
        ignoreDuplicates: false,
      });
      throwIfSupabaseError(res.error, "membership_allow");
      return true;
    });
    if (replace) {
      // Pruning is best-effort: failing to remove stale members must not turn a
      // successful authorization into a failure.
      try {
        await pruneChannelMembers(safeChannel, safeUserIds);
      } catch (pruneError) {
        logMembershipFailure("realtime_membership_prune_failed", {
          channel: safeChannel,
          userCount: safeUserIds.length,
          error: pruneError,
          requestId,
        });
      }
    }
    return {
      ok: true,
      channel: safeChannel,
      count: safeUserIds.length,
      replaced: replace === true,
    };
  } catch (error) {
    const descriptor = logMembershipFailure("realtime_membership_failed", {
      channel: safeChannel,
      userCount: safeUserIds.length,
      error,
      requestId,
    });
    return {
      ok: false,
      channel: safeChannel,
      userCount: safeUserIds.length,
      provider: "supabase",
      statusCode: descriptor.statusCode,
      retryable: descriptor.retryable,
      fallback: "polling",
      reason: "membership_supabase_failed",
      error: descriptor.error,
    };
  }
}

export async function allowUserOnChannel(userId, channel, options = {}) {
  return allowUsersOnChannel([userId], channel, options);
}

export async function revokeUserFromChannel(userId, channel, { requestId = null } = {}) {
  const safeChannel = normalizeChannel(channel);
  const safeUserId = normalizeUserIds([userId])[0] || 0;
  if (!safeChannel || safeUserId <= 0) {
    return { ok: false, skipped: true, reason: "invalid_membership_input" };
  }
  const client = getSupabaseTableClient();
  if (!client) {
    return { ok: false, skipped: true, reason: "supabase_unavailable" };
  }

  try {
    await runMembershipSupabaseOp("membership_revoke", async () => {
      const res = await client
        .from(CHANNEL_MEMBER_TABLE)
        .delete()
        .eq("channel", safeChannel)
        .eq("user_id", safeUserId);
      throwIfSupabaseError(res.error, "membership_revoke");
      return true;
    });
    return { ok: true, channel: safeChannel, userId: safeUserId };
  } catch (error) {
    const descriptor = logMembershipFailure("realtime_membership_revoke_failed", {
      channel: safeChannel,
      userCount: 1,
      error,
      requestId,
    });
    return {
      ok: false,
      channel: safeChannel,
      userId: safeUserId,
      statusCode: descriptor.statusCode,
      retryable: descriptor.retryable,
      reason: "membership_supabase_failed",
      error: descriptor.error,
    };
  }
}

async function listChatThreadMemberUserIds(threadId) {
  const result = await dependencies.query(
    `SELECT DISTINCT user_id
     FROM social_chat_thread_member
     WHERE thread_id = $1`,
    [Number(threadId)]
  );
  return normalizeUserIds(result.rows.map((row) => row.user_id));
}

async function listTaxiRideMemberUserIds(rideId) {
  const result = await dependencies.query(
    `WITH member_ids AS (
       SELECT customer_user_id AS user_id
       FROM taxi_ride_request
       WHERE id = $1
       UNION
       SELECT assigned_captain_user_id AS user_id
       FROM taxi_ride_request
       WHERE id = $1
       UNION
       SELECT captain_user_id AS user_id
       FROM taxi_ride_bid
       WHERE ride_request_id = $1
       UNION
       SELECT friend_user_id AS user_id
       FROM taxi_ride_friend_share
       WHERE ride_request_id = $1
     )
     SELECT DISTINCT user_id
     FROM member_ids
     WHERE user_id IS NOT NULL`,
    [Number(rideId)]
  );
  return normalizeUserIds(result.rows.map((row) => row.user_id));
}

async function listOrderMemberUserIds(orderId) {
  const result = await dependencies.query(
    `SELECT DISTINCT member.user_id
     FROM (
       SELECT o.customer_user_id AS user_id
       FROM customer_order o
       WHERE o.id = $1
       UNION
       SELECT o.delivery_user_id AS user_id
       FROM customer_order o
       WHERE o.id = $1
       UNION
       SELECT m.owner_user_id AS user_id
       FROM customer_order o
       LEFT JOIN merchant m ON m.id = o.merchant_id
       WHERE o.id = $1
     ) AS member
     WHERE member.user_id IS NOT NULL`,
    [Number(orderId)]
  );
  return normalizeUserIds(result.rows.map((row) => row.user_id));
}

export async function syncChatThreadMembers(threadId, options = {}) {
  const safeThreadId = Number(threadId);
  if (!Number.isInteger(safeThreadId) || safeThreadId <= 0) {
    return { ok: false, skipped: true, reason: "invalid_thread_id" };
  }
  const userIds = await listChatThreadMemberUserIds(safeThreadId);
  return allowUsersOnChannel(userIds, `chat:thread:${safeThreadId}`, {
    replace: true,
    ...options,
  });
}

export async function syncTaxiRideMembers(rideId, options = {}) {
  const safeRideId = Number(rideId);
  if (!Number.isInteger(safeRideId) || safeRideId <= 0) {
    return { ok: false, skipped: true, reason: "invalid_ride_id" };
  }
  const userIds = await listTaxiRideMemberUserIds(safeRideId);
  return allowUsersOnChannel(userIds, `taxi:ride:${safeRideId}`, {
    replace: true,
    ...options,
  });
}

export async function syncOrderMembers(orderId, options = {}) {
  const safeOrderId = Number(orderId);
  if (!Number.isInteger(safeOrderId) || safeOrderId <= 0) {
    return { ok: false, skipped: true, reason: "invalid_order_id" };
  }
  const userIds = await listOrderMemberUserIds(safeOrderId);
  return allowUsersOnChannel(userIds, `order:${safeOrderId}`, {
    replace: true,
    ...options,
  });
}

export const __realtimeMembershipTestApi = {
  normalizeUserIds,
  setQuery(fn) {
    dependencies.query = fn;
  },
  setAdminClientFactory(fn) {
    dependencies.getAdminClient = fn;
  },
  setStatusResolver(fn) {
    dependencies.getStatus = fn;
  },
  setSleeper(fn) {
    dependencies.sleep = fn;
  },
  setCircuit(circuit) {
    dependencies.circuit = circuit;
  },
  setLogger(logger) {
    dependencies.logger = logger;
  },
  reset() {
    dependencies.query = (text, params) => q(text, params);
    dependencies.getAdminClient = () => getSupabaseAdminClient();
    dependencies.getStatus = () => getSupabaseRealtimeStatus();
    dependencies.circuit = supabaseCircuit;
    dependencies.sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    dependencies.logger = console;
    supabaseCircuit.reset();
  },
};
