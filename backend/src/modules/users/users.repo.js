import { listUserActiveSessions, revokeAllUserSessions, revokeUserSession } from "../auth/auth.repo.js";
import {
  invalidateSessionAccessCacheForSession,
  invalidateSessionAccessCacheForUser,
  markSessionRevoked,
  markUserSessionsRevokedAfter,
} from "../../shared/middleware/access-auth.js";
import { findUserAddressMeta, setUserAccountDisabled } from "../feed/feed.repo.js";
import {
  deactivatePushTokensForSession,
  deactivatePushTokensForUser,
} from "../notifications/notifications.repo.js";

export async function findMyAccountMeta(userId) {
  return findUserAddressMeta(Number(userId));
}

export async function disableMyAccount({ userId, note = null }) {
  return setUserAccountDisabled({
    userId: Number(userId),
    disabled: true,
    note: note || null,
    actedByUserId: Number(userId),
  });
}

export async function revokeAllMySessions(userId, reason = "account_self_disabled") {
  const revoked = await revokeAllUserSessions({
    userId: Number(userId),
    reason,
  });
  await markUserSessionsRevokedAfter(Number(userId));
  await deactivatePushTokensForUser(Number(userId));
  invalidateSessionAccessCacheForUser({
    userId: Number(userId),
  });
  return revoked;
}

export async function listMySessions(userId) {
  return listUserActiveSessions(Number(userId));
}

export async function revokeMySession({ userId, sessionId }) {
  const revoked = await revokeUserSession({
    userId: Number(userId),
    sessionId: Number(sessionId),
    reason: "session_revoked_by_owner",
  });
  if (revoked) {
    await deactivatePushTokensForSession(Number(userId), Number(sessionId));
    await markSessionRevoked(Number(sessionId));
    invalidateSessionAccessCacheForSession({
      userId: Number(userId),
      sessionId: Number(sessionId),
    });
  }
  return revoked;
}
