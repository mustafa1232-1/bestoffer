import { AccessToken, RoomServiceClient, TrackSource } from "livekit-server-sdk";
import { env } from "../../config/env.js";
import { q } from "../../config/db.js";
import { AppError } from "../../shared/utils/errors.js";

export const socialCallRoomName = (sessionId) => `maslaki-social-call-${Number(sessionId)}`;
export const socialCallIdentity = (sessionId, userId) => `social-call:${Number(sessionId)}:user:${Number(userId)}`;
export function socialCallVoiceConfigured() {
  return Boolean(env.livekitUrl && env.livekitApiKey && env.livekitApiSecret);
}

export function assertSocialCallVoiceAccess(session, userId) {
  if (!session || ![session.callerUserId, session.calleeUserId].some((id) => Number(id) === Number(userId))) {
    throw new AppError("SOCIAL_CALL_FORBIDDEN", { status: 403 });
  }
  if (session.status !== "active" || session.voiceTransport !== "livekit") {
    throw new AppError("SOCIAL_CALL_NOT_ACTIVE", { status: 409 });
  }
}

export async function issueSocialCallVoiceToken({ session, userId, displayName }) {
  assertSocialCallVoiceAccess(session, userId);
  if (!socialCallVoiceConfigured()) throw new AppError("SOCIAL_VOICE_UNAVAILABLE", { status: 503 });
  const roomName = socialCallRoomName(session.id);
  const token = new AccessToken(env.livekitApiKey, env.livekitApiSecret, {
    identity: socialCallIdentity(session.id, userId), name: displayName || "Maslaki", ttl: 60,
  });
  token.addGrant({ roomJoin: true, room: roomName, canPublish: true,
    canPublishSources: [TrackSource.MICROPHONE], canSubscribe: true, canPublishData: false });
  // Token issuance is local: no provider round trip on the connection path.
  return { url: env.livekitUrl, roomName, token: await token.toJwt() };
}

let service;
function missing(error) {
  return ["5", "not_found"].includes(String(error?.code)) || /not.?found/i.test(error?.message || "");
}

export async function processSocialCallVoiceCleanup() {
  if (!socialCallVoiceConfigured()) return;
  service ??= new RoomServiceClient(env.livekitUrl.replace(/^ws/, "http"),
    env.livekitApiKey, env.livekitApiSecret, { requestTimeout: 3 });
  // Durable lease: a failed provider request survives both restart and retry.
  const jobs = await q(`WITH due AS (
    SELECT session_id FROM social_call_voice_cleanup WHERE next_attempt_at <= NOW()
    ORDER BY next_attempt_at LIMIT 4 FOR UPDATE SKIP LOCKED
  ) UPDATE social_call_voice_cleanup j SET next_attempt_at = NOW() + INTERVAL '30 seconds'
    FROM due WHERE j.session_id = due.session_id RETURNING j.session_id`);
  await Promise.allSettled(jobs.rows.map(async ({ session_id: id }) => {
    try {
      const result = await q(`SELECT caller_user_id, callee_user_id, ended_at FROM social_call_session WHERE id = $1`, [id]);
      const session = result.rows[0];
      for (const userId of [session.caller_user_id, session.callee_user_id]) {
        try { await service.removeParticipant(socialCallRoomName(id), socialCallIdentity(id, userId)); }
        catch (error) { if (!missing(error)) throw error; }
      }
      try { await service.deleteRoom(socialCallRoomName(id)); }
      catch (error) { if (!missing(error)) throw error; }
      // Repeat across the token TTL to close any token-issued/room-join race.
      if (Date.now() - new Date(session.ended_at).getTime() > 90_000) {
        await q(`DELETE FROM social_call_voice_cleanup WHERE session_id = $1`, [id]);
      }
    } catch (error) {
      console.warn("[social] voice cleanup retry", id, error.code || error.name);
    }
  }));
}
