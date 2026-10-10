import { AccessToken, RoomServiceClient, TrackSource } from "livekit-server-sdk";

import { env } from "../../config/env.js";

function clean(value) {
  return String(value || "").trim();
}

export function teamCodeVoiceConfigured() {
  return Boolean(
    clean(env.livekitUrl) &&
      clean(env.livekitApiKey) &&
      clean(env.livekitApiSecret),
  );
}

export function teamCodeVoiceRoomName(roomId) {
  return `maslaki-team-code-${Number(roomId)}`;
}

export function teamCodeVoiceIdentity(roomId, userId) {
  return `team-code:${Number(roomId)}:user:${Number(userId)}`;
}

function serviceUrl() {
  return clean(env.livekitUrl)
    .replace(/^wss:/i, "https:")
    .replace(/^ws:/i, "http:");
}

function roomService() {
  if (!teamCodeVoiceConfigured()) return null;
  return new RoomServiceClient(
    serviceUrl(),
    env.livekitApiKey,
    env.livekitApiSecret,
  );
}

function participantIsOffline(error) {
  const code = String(error?.code ?? "").toLowerCase();
  const message = String(error?.message || error || "").toLowerCase();
  return (
    code === "5" ||
    code.includes("not_found") ||
    /participant.*not.?found|not.?found.*participant/.test(message)
  );
}

export function teamCodeVoicePermissions(room) {
  const enabled =
    String(room?.mode || "") === "cooperative" &&
    !["abandoned"].includes(String(room?.status || ""));
  return {
    roomJoin: enabled,
    room: teamCodeVoiceRoomName(room?.id),
    canPublish: enabled,
    canSubscribe: enabled,
    canPublishData: enabled,
    canPublishSources: enabled ? [TrackSource.MICROPHONE] : [],
  };
}

async function ensureTeamCodeVoiceRoom(room) {
  const service = roomService();
  if (!service) return { enabled: false };
  const name = teamCodeVoiceRoomName(room.id);
  try {
    await service.createRoom({
      name,
      maxParticipants: 4,
      emptyTimeout: 10 * 60,
      departureTimeout: 3 * 60,
      metadata: JSON.stringify({
        kind: "maslaki_team_code",
        roomId: Number(room.id),
      }),
    });
  } catch (error) {
    if (!/exist|already/i.test(String(error?.message || error))) throw error;
  }
  return { enabled: true, roomName: name };
}

export async function issueTeamCodeVoiceToken({
  room,
  membership,
  displayName,
}) {
  if (!teamCodeVoiceConfigured()) {
    return { enabled: false, reason: "LIVEKIT_NOT_CONFIGURED" };
  }
  const permissions = teamCodeVoicePermissions(room);
  if (!permissions.roomJoin) {
    return { enabled: false, reason: "TEAM_CODE_VOICE_UNAVAILABLE" };
  }
  await ensureTeamCodeVoiceRoom(room);
  const identity = teamCodeVoiceIdentity(room.id, membership.user_id);
  const token = new AccessToken(env.livekitApiKey, env.livekitApiSecret, {
    identity,
    name: clean(displayName) || `Player ${membership.seat_number}`,
    ttl: Number(env.livekitTokenTtlSec || 900),
    metadata: JSON.stringify({
      roomId: Number(room.id),
      membershipId: Number(membership.id),
      seatNumber: Number(membership.seat_number),
    }),
  });
  token.addGrant(permissions);
  return {
    enabled: true,
    url: env.livekitUrl,
    roomName: permissions.room,
    identity,
    token: await token.toJwt(),
    permissions: {
      canPublish: permissions.canPublish,
      canSubscribe: permissions.canSubscribe,
    },
    expiresInSeconds: Number(env.livekitTokenTtlSec || 900),
  };
}

export async function removeTeamCodeVoiceParticipant(roomId, userId) {
  const service = roomService();
  if (!service) return { enabled: false, removed: false };
  try {
    await service.removeParticipant(
      teamCodeVoiceRoomName(roomId),
      teamCodeVoiceIdentity(roomId, userId),
    );
    return { enabled: true, removed: true };
  } catch (error) {
    if (!participantIsOffline(error)) throw error;
    return { enabled: true, removed: false };
  }
}
