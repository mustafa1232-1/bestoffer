import { q } from "../../config/db.js";
import {
  getSupabaseAdminClient,
  getSupabaseRealtimeStatus,
} from "../../config/supabase.js";

const CHANNEL_MEMBER_TABLE = "realtime_channel_member";

const dependencies = {
  query: (text, params) => q(text, params),
  getAdminClient: () => getSupabaseAdminClient(),
  getStatus: () => getSupabaseRealtimeStatus(),
  logger: console,
};

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

async function fetchExistingChannelUserIds(channel) {
  const client = getSupabaseTableClient();
  if (!client) return [];
  const { data, error } = await client
    .from(CHANNEL_MEMBER_TABLE)
    .select("user_id")
    .eq("channel", channel);
  if (error) throw error;
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
  const { error } = await client
    .from(CHANNEL_MEMBER_TABLE)
    .delete()
    .eq("channel", channel)
    .in("user_id", removedIds);
  if (error) throw error;
  return { ok: true, removedCount: removedIds.length };
}

export async function allowUsersOnChannel(
  userIds,
  channel,
  { role = "member", expiresAt = null, replace = false } = {}
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
    const payload = safeUserIds.map((userId) => ({
      channel: safeChannel,
      user_id: userId,
      role: String(role || "member").trim() || "member",
      expires_at: expiresAt || null,
    }));
    const { error } = await client.from(CHANNEL_MEMBER_TABLE).upsert(payload, {
      onConflict: "channel,user_id",
      ignoreDuplicates: false,
    });
    if (error) throw error;
    if (replace) {
      await pruneChannelMembers(safeChannel, safeUserIds);
    }
    return {
      ok: true,
      channel: safeChannel,
      count: safeUserIds.length,
      replaced: replace === true,
    };
  } catch (error) {
    dependencies.logger.warn?.(
      "[realtime-membership] allowUsersOnChannel failed",
      {
        channel: safeChannel,
        count: safeUserIds.length,
        error: error?.message || error,
      }
    );
    return { ok: false, channel: safeChannel, error };
  }
}

export async function allowUserOnChannel(userId, channel, options = {}) {
  return allowUsersOnChannel([userId], channel, options);
}

export async function revokeUserFromChannel(userId, channel) {
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
    const { error } = await client
      .from(CHANNEL_MEMBER_TABLE)
      .delete()
      .eq("channel", safeChannel)
      .eq("user_id", safeUserId);
    if (error) throw error;
    return { ok: true, channel: safeChannel, userId: safeUserId };
  } catch (error) {
    dependencies.logger.warn?.(
      "[realtime-membership] revokeUserFromChannel failed",
      {
        channel: safeChannel,
        userId: safeUserId,
        error: error?.message || error,
      }
    );
    return { ok: false, channel: safeChannel, userId: safeUserId, error };
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
  reset() {
    dependencies.query = (text, params) => q(text, params);
    dependencies.getAdminClient = () => getSupabaseAdminClient();
    dependencies.getStatus = () => getSupabaseRealtimeStatus();
    dependencies.logger = console;
  },
};
