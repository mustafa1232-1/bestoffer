const userStreams = new Map();

function encodeSseChunk({ event, data }) {
  const chunks = [];
  if (event) chunks.push(`event: ${event}`);
  const payload = JSON.stringify(data ?? {});
  for (const line of payload.split("\n")) {
    chunks.push(`data: ${line}`);
  }
  chunks.push("");
  chunks.push("");
  return chunks.join("\n");
}

export function addUserStream(userId, res) {
  const key = String(Number(userId));
  const set = userStreams.get(key) || new Set();
  set.add(res);
  userStreams.set(key, set);
}

export function removeUserStream(userId, res) {
  const key = String(Number(userId));
  const set = userStreams.get(key);
  if (!set) return;
  set.delete(res);
  if (set.size === 0) {
    userStreams.delete(key);
  }
}

export function emitToUser(userId, event, data) {
  const key = String(Number(userId));
  const set = userStreams.get(key);
  if (!set || set.size === 0) return;

  const payload = encodeSseChunk({ event, data });
  const dropped = [];

  for (const res of set) {
    try {
      res.write(payload);
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
