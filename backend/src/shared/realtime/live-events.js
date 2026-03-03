const userStreams = new Map();
const userEventBacklog = new Map();

const EVENT_BACKLOG_LIMIT_PER_USER = 1000;
let nextEventId = Date.now();

function normalizeUserKey(userId) {
  return String(Number(userId));
}

function normalizeEventId(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return 0;
  return Math.floor(parsed);
}

function allocateEventId() {
  nextEventId += 1;
  return nextEventId;
}

function encodeSseChunk({ id = null, event, data }) {
  const chunks = [];
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

function appendBacklog(userId, record) {
  const key = normalizeUserKey(userId);
  const backlog = userEventBacklog.get(key) || [];
  backlog.push(record);
  if (backlog.length > EVENT_BACKLOG_LIMIT_PER_USER) {
    backlog.splice(0, backlog.length - EVENT_BACKLOG_LIMIT_PER_USER);
  }
  userEventBacklog.set(key, backlog);
}

export function addUserStream(userId, res) {
  const key = normalizeUserKey(userId);
  const set = userStreams.get(key) || new Set();
  set.add(res);
  userStreams.set(key, set);
}

export function removeUserStream(userId, res) {
  const key = normalizeUserKey(userId);
  const set = userStreams.get(key);
  if (!set) return;
  set.delete(res);
  if (set.size === 0) {
    userStreams.delete(key);
  }
}

export function replayUserEvents(
  userId,
  res,
  { afterEventId = 0, maxEvents = 120 } = {}
) {
  const key = normalizeUserKey(userId);
  const minId = normalizeEventId(afterEventId);
  const limit = Math.max(1, Math.min(500, Number(maxEvents) || 120));

  const backlog = userEventBacklog.get(key) || [];
  const missed = backlog.filter((record) => record.id > minId);
  if (missed.length === 0) {
    return {
      replayed: 0,
      lastEventId: minId,
    };
  }

  const chunk = missed.slice(-limit);
  for (const record of chunk) {
    writeChunk(res, record);
  }

  return {
    replayed: chunk.length,
    lastEventId: chunk[chunk.length - 1]?.id || minId,
  };
}

export function getLatestUserEventId(userId) {
  const key = normalizeUserKey(userId);
  const backlog = userEventBacklog.get(key) || [];
  return backlog[backlog.length - 1]?.id || null;
}

export function writeSseEvent(res, event, data, { id = null } = {}) {
  writeChunk(res, { id, event, data });
}

export function emitToUser(userId, event, data) {
  const key = normalizeUserKey(userId);
  const set = userStreams.get(key);

  const record = {
    id: allocateEventId(),
    event,
    data,
  };

  appendBacklog(userId, record);

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
    userStreams.delete(key);
  }
}
