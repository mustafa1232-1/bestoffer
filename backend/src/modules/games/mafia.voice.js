import { AccessToken, RoomServiceClient, TrackSource } from "livekit-server-sdk";

import { env } from "../../config/env.js";

function clean(value) {
  return String(value || "").trim();
}

export function mafiaVoiceConfigured() {
  return Boolean(clean(env.livekitUrl) && clean(env.livekitApiKey) && clean(env.livekitApiSecret));
}

export function mafiaVoiceRoomName(roomId) {
  return `maslaki-mafia-${Number(roomId)}`;
}

export function mafiaVoiceIdentity(roomId, userId) {
  return `mafia:${Number(roomId)}:user:${Number(userId)}`;
}

export function mafiaDeadVoiceRoomName(roomId) {
  return `${mafiaVoiceRoomName(roomId)}-afterlife`;
}

// Night talk happens in its own LiveKit room that only alive mafia can join.
// Isolation by room (not by per-participant permission toggles inside the
// shared room) means a stale or replayed day token can never hear it.
export function mafiaNightVoiceRoomName(roomId) {
  return `${mafiaVoiceRoomName(roomId)}-night`;
}
export function mafiaNightVoiceIdentity(roomId, userId) {
  return `mafia:${Number(roomId)}:night:user:${Number(userId)}`;
}
export function mafiaDeadVoiceIdentity(roomId, userId) {
  return `mafia:${Number(roomId)}:dead:user:${Number(userId)}`;
}

function serviceUrl() {
  return clean(env.livekitUrl).replace(/^wss:/i, "https:").replace(/^ws:/i, "http:");
}

let cachedService;
function roomService() {
  if (!mafiaVoiceConfigured()) return null;
  return cachedService ??= new RoomServiceClient(serviceUrl(), env.livekitApiKey, env.livekitApiSecret, { requestTimeout: 3 });
}

function participantIsOffline(error) {
  const code = String(error?.code ?? "").toLowerCase();
  const message = String(error?.message || error || "").toLowerCase();
  return code === "5" ||
    code.includes("not_found") ||
    /participant.*not.?found|not.?found.*participant/.test(message);
}

export function mafiaVoicePermissions(room, player, candidates = []) {
  const allowed = player.life_status !== 'left' && room.status !== 'cancelled';
  const alive = player.life_status === "alive";
  const candidateIds = new Set((candidates || []).map(Number));
  let canPublish = false;
  let canSubscribe = true;

  switch (room.status) {
    case "lobby":
      canPublish = true;
      break;
    case "role_reveal":
      canPublish = false;
      break;
    case "night":
      // The shared table is silent at night; mafia speak in the night room.
      // Subscriptions stay on so morning audio resumes without renegotiation.
      canPublish = false;
      break;
    case "day_discussion":
      canPublish = alive;
      break;
    case "day_defense":
      canPublish = alive && candidateIds.has(Number(player.id));
      break;
    case "day_nomination":
    case "day_vote":
    case "day_revote":
      canPublish = false;
      break;
    case "completed":
      canPublish = true;
      break;
    default:
      canPublish = false;
  }

  return {
    roomJoin: allowed,
    room: room.voice_room_name,
    canPublish: allowed && canPublish,
    canSubscribe: allowed && canSubscribe,
    // Text and reactions use the authenticated, phase-aware backend routes.
    canPublishData: false,
    canPublishSources: allowed && canPublish ? [TrackSource.MICROPHONE] : [],
  };
}

export async function ensureMafiaVoiceRoom(room) {
  const service = roomService();
  if (!service) return { enabled: false };
  const name = room.voice_room_name || mafiaVoiceRoomName(room.id);
  try {
    await service.createRoom({
      name,
      maxParticipants: 14,
      emptyTimeout: 10 * 60,
      departureTimeout: 3 * 60,
      metadata: JSON.stringify({ kind: "maslaki_mafia", roomId: Number(room.id) }),
    });
  } catch (error) {
    // LiveKit returns an already-exists error when the first token created it.
    if (!/exist|already/i.test(String(error?.message || error))) throw error;
  }
  return { enabled: true, roomName: name };
}

async function ensureMafiaDeadVoiceRoom(room) {
  const service = roomService();
  if (!service) return { enabled: false };
  const name = mafiaDeadVoiceRoomName(room.id);
  try {
    await service.createRoom({
      name,
      maxParticipants: 14,
      emptyTimeout: 10 * 60,
      departureTimeout: 3 * 60,
      metadata: JSON.stringify({
        kind: "maslaki_mafia_afterlife",
        roomId: Number(room.id),
      }),
    });
  } catch (error) {
    if (!/exist|already/i.test(String(error?.message || error))) throw error;
  }
  return { enabled: true, roomName: name };
}

async function createVoiceToken({ identity, name, metadata, grant, ttl }) {
  const token = new AccessToken(env.livekitApiKey, env.livekitApiSecret, {
    identity,
    name,
    ttl: ttl ?? Number(env.livekitTokenTtlSec || 900),
    metadata: JSON.stringify(metadata),
  });
  token.addGrant(grant);
  return token.toJwt();
}

export async function issueMafiaVoiceToken(room, player, displayName, candidates = []) {
  if (!mafiaVoiceConfigured()) {
    return { enabled: false, reason: "LIVEKIT_NOT_CONFIGURED" };
  }
  // LiveKit creates rooms on first join; signing access never waits on its API.
  const permissions = mafiaVoicePermissions(room, player, candidates);
  const identity = mafiaVoiceIdentity(room.id, player.user_id);
  const playerName = clean(displayName) || `Player ${player.seat_number}`;
  const token = await createVoiceToken({
    identity,
    name: playerName,
    metadata: {
      roomId: Number(room.id),
      playerId: Number(player.id),
      seatNumber: Number(player.seat_number),
      lifeStatus: player.life_status,
    },
    grant: permissions,
  });
  const response = {
    enabled: true,
    url: env.livekitUrl,
    roomName: room.voice_room_name,
    identity,
    token,
    permissions: {
      canPublish: permissions.canPublish,
      canSubscribe: permissions.canSubscribe,
    },
    expiresInSeconds: Number(env.livekitTokenTtlSec || 900),
  };
  if (room.status === "night" && player.life_status === "alive" && player.team === "mafia") {
    // The token outlives the night by at most a minute; the worker also deletes
    // the night room as soon as the phase changes.
    const remaining = room.phase_ends_at
      ? Math.ceil((new Date(room.phase_ends_at).getTime() - Date.now()) / 1000)
      : 60;
    response.afterlife = {
      channel: "night",
      roomName: mafiaNightVoiceRoomName(room.id),
      identity: mafiaNightVoiceIdentity(room.id, player.user_id),
      token: await createVoiceToken({
        identity: mafiaNightVoiceIdentity(room.id, player.user_id),
        name: playerName,
        ttl: Math.max(30, remaining + 60),
        metadata: {
          roomId: Number(room.id),
          playerId: Number(player.id),
          seatNumber: Number(player.seat_number),
          channel: "night",
        },
        grant: {
          roomJoin: true,
          room: mafiaNightVoiceRoomName(room.id),
          canPublish: true,
          canSubscribe: true,
          canPublishData: false,
          canPublishSources: [TrackSource.MICROPHONE],
        },
      }),
      permissions: { canPublish: true, canSubscribe: true },
    };
  } else if (player.life_status === "dead" && !['completed', 'cancelled'].includes(room.status)) {
    const afterlifeGrant = {
      roomJoin: true,
      room: mafiaDeadVoiceRoomName(room.id),
      canPublish: true,
      canSubscribe: true,
      canPublishData: false,
      canPublishSources: [TrackSource.MICROPHONE],
    };
    response.afterlife = {
      channel: "afterlife",
      roomName: mafiaDeadVoiceRoomName(room.id),
      identity: mafiaDeadVoiceIdentity(room.id, player.user_id),
      token: await createVoiceToken({
        identity: mafiaDeadVoiceIdentity(room.id, player.user_id),
        name: playerName,
        metadata: {
          roomId: Number(room.id),
          playerId: Number(player.id),
          seatNumber: Number(player.seat_number),
          channel: "afterlife",
        },
        grant: afterlifeGrant,
      }),
      permissions: { canPublish: true, canSubscribe: true },
    };
  }
  return response;
}

export async function syncMafiaVoicePermissions(room, players, candidates = [], service = roomService(), { isCurrent = async () => true } = {}) {
  if (!service) return { enabled: false, updated: 0 };
  let updated = 0;
  const update = async player => {
    const grant = mafiaVoicePermissions(room, player, candidates);
    const { canPublish, canSubscribe, canPublishData, canPublishSources } = grant;
    try {
      await service.updateParticipant(
        room.voice_room_name,
        mafiaVoiceIdentity(room.id, player.user_id),
        { permission: { canPublish, canSubscribe, canPublishData, canPublishSources } },
      );
      updated += 1;
    } catch (error) {
      // Offline participants receive the correct permissions in their next token.
      if (!participantIsOffline(error)) throw error;
    }
  };
  // Revoke listeners/speakers before enabling the next phase's publishers.
  const groups = [(players || []).filter(p => !mafiaVoicePermissions(room,p,candidates).canPublish),
    (players || []).filter(p => mafiaVoicePermissions(room,p,candidates).canPublish)];
  for (const group of groups) {
    for (let i = 0; i < group.length; i += 4) {
      if (!await isCurrent()) throw Object.assign(new Error('MAFIA_VOICE_SUPERSEDED'), {code:'MAFIA_VOICE_SUPERSEDED'});
      const results = await Promise.allSettled(group.slice(i,i+4).map(update));
      const failure = results.find(r => r.status === 'rejected');
      if (failure) throw failure.reason;
    }
  }
  const deleteIfPresent = async (name) => {
    if (typeof service.deleteRoom !== 'function') return;
    try { await service.deleteRoom(name); }
    catch (error) { if (!participantIsOffline(error) && !/room.*not.?found|does not exist/i.test(String(error?.message))) throw error; }
  };
  // Night is over: disconnect every night-room participant immediately, so no
  // private mafia channel survives into the day.
  if (room.status !== 'night') await deleteIfPresent(mafiaNightVoiceRoomName(room.id));
  // The completed table is public again; obsolete secondary publishers leave.
  if (room.status === 'completed') await deleteIfPresent(mafiaDeadVoiceRoomName(room.id));
  return { enabled: true, updated };
}

export async function removeMafiaVoiceParticipant(room, userId) {
  const service = roomService();
  if (!service) return { enabled: false, removed: false };
  let removed = false;
  for (const [roomName, identity] of [
    [room.voice_room_name, mafiaVoiceIdentity(room.id, userId)],
    [mafiaDeadVoiceRoomName(room.id), mafiaDeadVoiceIdentity(room.id, userId)],
    [mafiaNightVoiceRoomName(room.id), mafiaNightVoiceIdentity(room.id, userId)],
  ]) {
    try {
      await service.removeParticipant(roomName, identity);
      removed = true;
    } catch (error) {
      if (!participantIsOffline(error)) throw error;
    }
  }
  return { enabled: true, removed };
}

export async function closeMafiaVoiceRoom(room) {
  const service = roomService();
  if (!service) return { enabled: false, closed: false };
  let closed = false;
  for (const roomName of [
    room.voice_room_name,
    mafiaDeadVoiceRoomName(room.id),
    mafiaNightVoiceRoomName(room.id),
  ]) {
    try {
      await service.deleteRoom(roomName);
      closed = true;
    } catch (error) {
      const message = String(error?.message || error).toLowerCase();
      if (!participantIsOffline(error) && !/room.*not.?found|not.?found.*room|does not exist/.test(message)) {
        throw error;
      }
    }
  }
  return { enabled: true, closed };
}
