import { env } from "../../config/env.js";
import {
  createRedisIsolatedClient,
  isRedisConfigured,
} from "../../config/redis.js";

const userStreams = new Map();
const userEventBacklog = new Map();

const EVENT_BACKLOG_LIMIT_PER_USER_CHANNEL = 1000;
const EVENT_ID_STRIDE = 100;
const workerSlot = Math.max(0, Math.min(99, Number(env.appWorkerSlot || 0)));
let nextEventId = Date.now() * EVENT_ID_STRIDE + workerSlot;
const instanceId = `w${workerSlot}:pid${process.pid}:${Date.now()}`;

let busPublisher = null;
let busSubscriber = null;
let busInitPromise = null;

function shouldUseCrossProcessBus() {
  if (!isRedisConfigured()) return false;
  if (env.realtimeCrossProcessBus === true) return true;
  return Math.max(1, Number(env.appWorkersTotal) || 1) > 1;
}

function normalizeUserKey(userId) {
  return String(Number(userId));
}

function normalizeChannel(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized === "social") return "social";
  if (normalized === "taxi") return "taxi";
  if (normalized === "general") return "general";
  return "notifications";
}

function deriveChannelFromEvent(event) {
  const normalized = String(event || "").trim().toLowerCase();
  if (normalized.startsWith("taxi_")) return "taxi";
  if (normalized.startsWith("social_")) return "social";
  if (normalized.startsWith("notification")) return "notifications";
  return "general";
}

function normalizeEventId(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return 0;
  return Math.floor(parsed);
}

function allocateEventId() {
  nextEventId += EVENT_ID_STRIDE;
  return nextEventId;
}

export function allocateLiveEventId() {
  return allocateEventId();
}

function encodeSseChunk({ id = null, event, data, retry = null }) {
  const chunks = [];
  if (retry != null) chunks.push(`retry: ${Number(retry) || 0}`);
  if (id != null) chunks.push(`id: ${id}`);
  if (event) chunks.push(`event: ${event}`);
  const payload = JSON.stringify(data ?? {});
  for (const line of payload.split("\n")) {
    chunks.push(`data: ${line}`);
  }
  chunks.push("");
  chunks.push("");
  return chunks.join("\n");
}

function writeChunk(res, record) {
  res.write(encodeSseChunk(record));
}

function getUserChannelStreams(userId, channel, { create = false } = {}) {
  const key = normalizeUserKey(userId);
  let channelMap = userStreams.get(key);
  if (!channelMap) {
    if (!create) return null;
    channelMap = new Map();
    userStreams.set(key, channelMap);
  }
  const normalizedChannel = normalizeChannel(channel);
  let set = channelMap.get(normalizedChannel);
  if (!set) {
    if (!create) return null;
    set = new Set();
    channelMap.set(normalizedChannel, set);
  }
  return set;
}

function getUserChannelBacklog(userId, channel, { create = false } = {}) {
  const key = normalizeUserKey(userId);
  let channelMap = userEventBacklog.get(key);
  if (!channelMap) {
    if (!create) return null;
    channelMap = new Map();
    userEventBacklog.set(key, channelMap);
  }
  const normalizedChannel = normalizeChannel(channel);
  let backlog = channelMap.get(normalizedChannel);
  if (!backlog) {
    if (!create) return null;
    backlog = [];
    channelMap.set(normalizedChannel, backlog);
  }
  return backlog;
}

function appendBacklog(userId, channel, record) {
  const backlog = getUserChannelBacklog(userId, channel, { create: true });
  backlog.push(record);
  if (backlog.length > EVENT_BACKLOG_LIMIT_PER_USER_CHANNEL) {
    backlog.splice(0, backlog.length - EVENT_BACKLOG_LIMIT_PER_USER_CHANNEL);
  }
}

function emitLocalRecord(userId, channel, record) {
  const set = getUserChannelStreams(userId, channel);
  if (!set || set.size === 0) return;

  const dropped = [];
  for (const res of set) {
    try {
      writeChunk(res, record);
    } catch (_) {
      dropped.push(res);
    }
  }

  for (const res of dropped) {
    set.delete(res);
  }

  if (set.size === 0) {
    const key = normalizeUserKey(userId);
    const channelMap = userStreams.get(key);
    channelMap?.delete(normalizeChannel(channel));
    if (channelMap && channelMap.size === 0) {
      userStreams.delete(key);
    }
  }
}

async function publishCrossProcess(userId, channel, record) {
  if (!shouldUseCrossProcessBus() || !busPublisher) return;
  try {
    await busPublisher.publish(
      env.realtimeRedisChannel,
      JSON.stringify({
        originInstanceId: instanceId,
        userId: Number(userId),
        channel: normalizeChannel(channel),
        record,
      })
    );
  } catch (_) {
    // best effort cross-worker fanout
  }
}

async function handleCrossProcessMessage(rawMessage) {
  let payload = null;
  try {
    payload = JSON.parse(rawMessage);
  } catch (_) {
    return;
  }
  if (!payload || payload.originInstanceId === instanceId) return;
  const userId = Number(payload.userId || 0);
  if (!Number.isInteger(userId) || userId <= 0) return;
  const channel = normalizeChannel(
    payload.channel || deriveChannelFromEvent(payload.record?.event)
  );
  const record = payload.record;
  if (!record || typeof record !== "object") return;
  appendBacklog(userId, channel, record);
  emitLocalRecord(userId, channel, record);
}

export async function initLiveEventBus() {
  if (!shouldUseCrossProcessBus()) return false;
  if (busPublisher && busSubscriber) return true;
  if (busInitPromise) return busInitPromise;

  busInitPromise = (async () => {
    const publisher = await createRedisIsolatedClient("live-events-pub");
    const subscriber = await createRedisIsolatedClient("live-events-sub");
    if (!publisher || !subscriber) return false;
    try {
      if (publisher.status !== "ready") await publisher.connect();
      if (subscriber.status !== "ready") await subscriber.connect();
      subscriber.on("message", (_, message) => {
        void handleCrossProcessMessage(message);
      });
      await subscriber.subscribe(env.realtimeRedisChannel);
      busPublisher = publisher;
      busSubscriber = subscriber;
      return true;
    } catch (_) {
      try {
        subscriber.disconnect();
      } catch (_) {
        // ignore
      }
      try {
        publisher.disconnect();
      } catch (_) {
        // ignore
      }
      return false;
    }
  })();

  try {
    return await busInitPromise;
  } finally {
    busInitPromise = null;
  }
}

export async function shutdownLiveEventBus() {
  if (!busPublisher && !busSubscriber) return;
  const closer = async (client) => {
    if (!client) return;
    try {
      await client.quit();
    } catch (_) {
      try {
        client.disconnect();
      } catch (_) {
        // ignore
      }
    }
  };
  await Promise.all([closer(busPublisher), closer(busSubscriber)]);
  busPublisher = null;
  busSubscriber = null;
}

export function addUserStream(userId, res, { channel = "notifications" } = {}) {
  if (shouldUseCrossProcessBus()) {
    void initLiveEventBus();
  }
  const set = getUserChannelStreams(userId, channel, { create: true });
  set.add(res);
}

export function removeUserStream(userId, res) {
  const key = normalizeUserKey(userId);
  const channelMap = userStreams.get(key);
  if (!channelMap) return;
  for (const [channel, set] of channelMap.entries()) {
    set.delete(res);
    if (set.size === 0) channelMap.delete(channel);
  }
  if (channelMap.size === 0) {
    userStreams.delete(key);
  }
}

export function replayUserEvents(
  userId,
  res,
  { afterEventId = 0, maxEvents = 120, channel = "notifications" } = {}
) {
  const normalizedChannel = normalizeChannel(channel);
  const minId = normalizeEventId(afterEventId);
  const limit = Math.max(1, Math.min(500, Number(maxEvents) || 120));
  const backlog = getUserChannelBacklog(userId, normalizedChannel) || [];

  if (backlog.length === 0) {
    return {
      replayed: 0,
      lastEventId: minId,
      resyncRequired: false,
    };
  }

  const oldestEventId = Number(backlog[0]?.id || 0);
  const latestEventId = Number(backlog[backlog.length - 1]?.id || 0);
  if (minId > 0 && oldestEventId > minId) {
    return {
      replayed: 0,
      lastEventId: minId,
      resyncRequired: true,
      reason: "backlog_pruned",
      oldestEventId,
      latestEventId,
    };
  }

  const missed = backlog.filter((record) => Number(record.id || 0) > minId);
  if (missed.length === 0) {
    return {
      replayed: 0,
      lastEventId: minId,
      resyncRequired: false,
    };
  }

  const chunk = missed.slice(-limit);
  for (const record of chunk) {
    writeChunk(res, record);
  }

  return {
    replayed: chunk.length,
    lastEventId: Number(chunk[chunk.length - 1]?.id || minId),
    resyncRequired: false,
  };
}

export function getLatestUserEventId(
  userId,
  { channel = "notifications" } = {}
) {
  const backlog = getUserChannelBacklog(userId, normalizeChannel(channel)) || [];
  return backlog[backlog.length - 1]?.id || null;
}

export function writeSseEvent(
  res,
  event,
  data,
  { id = null, retry = null } = {}
) {
  writeChunk(res, { id, event, data, retry });
}

export function emitToUser(userId, event, data, { channel = null, id = null } = {}) {
  const normalizedChannel = normalizeChannel(channel || deriveChannelFromEvent(event));
  const record = {
    id: normalizeEventId(id) || allocateEventId(),
    event,
    data,
  };

  appendBacklog(userId, normalizedChannel, record);
  emitLocalRecord(userId, normalizedChannel, record);
  void publishCrossProcess(userId, normalizedChannel, record);
}
