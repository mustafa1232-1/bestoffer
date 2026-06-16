import { AppError } from "../../shared/utils/errors.js";
import * as feedService from "../feed/feed.service.js";
import * as repo from "./users.repo.js";

function withLegacyUserAlias(payload) {
  if (!payload || typeof payload !== "object" || !payload.profile) return payload;
  const profile = payload.profile;
  return {
    ...payload,
    user: {
      id: profile.id,
      username: profile.username ?? null,
      fullName: profile.fullName ?? "",
      full_name: profile.fullName ?? "",
      imageUrl: profile.imageUrl ?? null,
      image_url: profile.imageUrl ?? null,
      bio: profile.bio ?? "",
      workTitle: profile.workTitle ?? null,
      work_title: profile.workTitle ?? null,
      workCompany: profile.workCompany ?? null,
      work_company: profile.workCompany ?? null,
      age: profile.age ?? null,
      phone: profile.phone ?? "",
      preferredLocale: profile.preferredLocale ?? "ar",
      preferred_locale: profile.preferredLocale ?? "ar",
      role: profile.role ?? "user",
      isSuperAdmin: profile.isSuperAdmin === true,
      is_super_admin: profile.isSuperAdmin === true,
      accountDisabled: profile.accountDisabled === true,
      is_account_disabled: profile.accountDisabled === true,
      joinedAt: profile.joinedAt ?? null,
      joined_at: profile.joinedAt ?? null,
    },
  };
}

function mapSession(row) {
  return {
    id: Number(row.id),
    userAgent: row.user_agent || null,
    ipAddress: row.ip || null,
    deviceFingerprint: row.device_fingerprint || null,
    createdAt: row.created_at,
    lastSeenAt: row.last_seen_at,
    expiresAt: row.expires_at,
    accessExpiresAt: row.access_expires_at,
  };
}

export async function getMyProfile(userId) {
  const profile = await feedService.getUserProfile(Number(userId), Number(userId));
  return withLegacyUserAlias(profile);
}

export async function updateMyProfile(userId, dto) {
  const profile = await feedService.updateMyProfile(Number(userId), dto || {});
  return withLegacyUserAlias(profile);
}

export async function deleteMyAccount(userId, { note = null } = {}) {
  const me = await repo.findMyAccountMeta(Number(userId));
  if (!me) throw new AppError("USER_NOT_FOUND", { status: 404 });
  if (me.is_super_admin === true) {
    throw new AppError("SUPER_ADMIN_SELF_DISABLE_NOT_ALLOWED", { status: 403 });
  }

  await repo.disableMyAccount({
    userId: Number(userId),
    note: note || "حساب معطل بطلب المستخدم",
  });
  await repo.revokeAllMySessions(Number(userId), "account_self_disabled");
  return { success: true };
}

export async function getMySessions(userId, currentSessionId = null) {
  const rows = await repo.listMySessions(Number(userId));
  return {
    sessions: rows.map(mapSession),
    currentSessionId: Number(currentSessionId) > 0 ? Number(currentSessionId) : null,
  };
}

export async function revokeMySession({ userId, sessionId, currentSessionId = null }) {
  const targetSessionId = Number(sessionId);
  if (
    Number(currentSessionId) > 0 &&
    Number(currentSessionId) === targetSessionId
  ) {
    throw new AppError("CURRENT_SESSION_REVOKE_NOT_ALLOWED", {
      status: 409,
      details: { sessionId: targetSessionId },
    });
  }

  const revoked = await repo.revokeMySession({
    userId: Number(userId),
    sessionId: targetSessionId,
  });
  if (!revoked) {
    throw new AppError("SESSION_NOT_FOUND", { status: 404 });
  }
  return { success: true, revokedSessionId: targetSessionId };
}
