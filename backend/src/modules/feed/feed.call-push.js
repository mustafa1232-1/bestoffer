import crypto from "node:crypto";

import { env } from "../../config/env.js";
import {
  createNotification,
  deactivatePushTokensByValue,
  listActiveVoipTargets,
  sendTransientPush,
} from "../notifications/notifications.repo.js";
import { sendVoipCallPush } from "../notifications/apns-voip.js";

/**
 * Push side of in-app calls (social threads).
 *
 * - Invite: a high-priority, DATA-ONLY push (Android) + PushKit VoIP push (iOS)
 *   so the callee's phone rings with the native Answer / Decline UI even when
 *   the app is in the background or fully closed. Not stored in the inbox.
 * - Dismiss: when the call is answered, declined, cancelled or times out, the
 *   callee's ringing UI is told to stop (`social.call.ended`).
 * - Missed: the callee gets a stored "missed call from X" notification.
 * - Decline from the lock screen: the push carries a short-lived signed
 *   `callActionToken`; the native layer posts it to
 *   POST /api/feed/chats/calls/decline (no session needed) so the caller sees
 *   "declined" even if the app never starts.
 */

const CALL_ACTION_PURPOSE = "maslaki-call-decline:v1";
export const CALL_ACTION_TOKEN_TTL_SECONDS = 120;

function actionKey() {
  return crypto
    .createHash("sha256")
    .update(`${CALL_ACTION_PURPOSE}:${env.jwtSecret || ""}`)
    .digest();
}

function signPart(value) {
  return crypto.createHmac("sha256", actionKey()).update(value).digest("base64url");
}

export function signCallActionToken({
  sessionId,
  calleeUserId,
  ttlSeconds = CALL_ACTION_TOKEN_TTL_SECONDS,
  now = Date.now(),
}) {
  const exp = Math.floor(now / 1000) + Math.max(10, Number(ttlSeconds) || 0);
  const body = `${Number(sessionId)}.${Number(calleeUserId)}.${exp}`;
  return `${body}.${signPart(body)}`;
}

export function verifyCallActionToken(token, { now = Date.now() } = {}) {
  const parts = String(token || "").trim().split(".");
  if (parts.length !== 4) return null;
  const [sessionRaw, calleeRaw, expRaw, signature] = parts;
  const body = `${sessionRaw}.${calleeRaw}.${expRaw}`;
  const expected = Buffer.from(signPart(body));
  const given = Buffer.from(String(signature));
  if (expected.length !== given.length || !crypto.timingSafeEqual(expected, given)) {
    return null;
  }
  const sessionId = Number.parseInt(sessionRaw, 10);
  const calleeUserId = Number.parseInt(calleeRaw, 10);
  const exp = Number.parseInt(expRaw, 10);
  if (!(sessionId > 0) || !(calleeUserId > 0) || !(exp > 0)) return null;
  if (exp * 1000 < now) return null;
  return { sessionId, calleeUserId, exp };
}

/**
 * Deterministic CallKit UUID for a call session so the invite, the dismissal
 * and the app all address the same native call.
 */
export function callUuidForSession(sessionId) {
  const hex = Number(sessionId).toString(16).padStart(12, "0").slice(-12);
  return `5a17ca11-0000-4000-8000-${hex}`;
}

function callerCopy(callerName) {
  const name = String(callerName || "").trim() || "مستخدم";
  const nameEn = String(callerName || "").trim() || "Someone";
  return {
    title: `مكالمة واردة من ${name}`,
    body: "مكالمة صوتية عبر مسلكي — رد أو ارفض.",
    textEn: { title: `Incoming call from ${nameEn}`, body: "Maslaki voice call — answer or decline." },
  };
}

export async function sendIncomingCallPush({
  calleeUserId,
  callerUserId,
  callerName,
  callerAvatarUrl = null,
  threadId,
  sessionId,
  ringTimeoutSeconds = 35,
}) {
  const callUuid = callUuidForSession(sessionId);
  const callActionToken = signCallActionToken({
    sessionId,
    calleeUserId,
    ttlSeconds: Math.max(ringTimeoutSeconds + 30, CALL_ACTION_TOKEN_TTL_SECONDS),
  });
  const callExpiresAt = new Date(Date.now() + ringTimeoutSeconds * 1000).toISOString();
  const copy = callerCopy(callerName);

  // iOS: PushKit → CallKit (the only way to ring a closed iPhone app).
  let voip = { configured: false, accepted: 0 };
  try {
    const voipTargets = await listActiveVoipTargets(calleeUserId);
    if (voipTargets.length) {
      voip = await sendVoipCallPush({
        tokens: voipTargets.map((target) => target.token),
        expiresInSec: ringTimeoutSeconds,
        callPayload: {
          id: callUuid,
          nameCaller: String(callerName || "").trim() || "مسلكي",
          handle: "مكالمة مسلكي",
          type: 0,
          duration: ringTimeoutSeconds * 1000,
          extra: {
            threadId: Number(threadId),
            sessionId: Number(sessionId),
            senderUserId: Number(callerUserId),
            callActionToken,
            callExpiresAt,
          },
        },
      });
      if (voip.deadTokens?.length) {
        await deactivatePushTokensByValue(voip.deadTokens).catch(() => {});
      }
    }
  } catch (error) {
    console.warn("[social-call] voip push failed", error?.message || error);
  }

  // Android (+ iOS fallback when PushKit is not configured): data-only FCM.
  const delivery = await sendTransientPush({
    userId: calleeUserId,
    type: "social.call.incoming",
    title: copy.title,
    body: copy.body,
    textEn: copy.textEn,
    excludePlatforms: voip.accepted > 0 ? ["ios"] : [],
    payload: {
      threadId: Number(threadId),
      sessionId: Number(sessionId),
      senderUserId: Number(callerUserId),
      remoteDisplayName: callerName || undefined,
      callerName: callerName || undefined,
      callerAvatarUrl: callerAvatarUrl || undefined,
      callUuid,
      callActionToken,
      callExpiresAt,
      target: "social_call",
      targetEntity: "social_thread",
      entityId: Number(threadId),
      requiresAction: true,
    },
  }).catch((error) => {
    console.warn("[social-call] invite push failed", error?.message || error);
    return null;
  });
  return { callUuid, voip, delivery };
}

/** Stops the callee's ringing UI on every device (answered elsewhere, cancelled, ...). */
export async function sendCallEndedPush({ calleeUserId, threadId, sessionId, reason }) {
  return sendTransientPush({
    userId: calleeUserId,
    type: "social.call.ended",
    title: "انتهت المكالمة",
    body: "",
    textEn: { title: "Call ended", body: "" },
    payload: {
      threadId: Number(threadId),
      sessionId: Number(sessionId),
      callUuid: callUuidForSession(sessionId),
      target: "social_call",
      reason: reason || null,
    },
  }).catch((error) => {
    console.warn("[social-call] dismiss push failed", error?.message || error);
    return null;
  });
}

/** Stored "missed call" for the callee (shown in the inbox, opens the chat). */
export async function notifyCalleeMissedCall({ calleeUserId, callerUserId, callerName, threadId, sessionId }) {
  const name = String(callerName || "").trim() || "مستخدم";
  const nameEn = String(callerName || "").trim() || "someone";
  return createNotification({
    userId: Number(calleeUserId),
    type: "social.call.missed",
    title: `مكالمة فائتة من ${name}`,
    body: "اضغط لفتح المحادثة ومعاودة الاتصال.",
    textEn: { title: `Missed call from ${nameEn}`, body: "Tap to open the chat and call back." },
    payload: {
      threadId: Number(threadId),
      sessionId: Number(sessionId),
      senderUserId: Number(callerUserId),
      remoteDisplayName: callerName || undefined,
      target: "social_chat",
      targetEntity: "social_thread",
      entityId: Number(threadId),
    },
  }).catch((error) => {
    console.warn("[social-call] missed-call notification failed", error?.message || error);
    return null;
  });
}
