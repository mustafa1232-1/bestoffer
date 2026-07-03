import * as repo from "./notifications.repo.js";
import {
  normalizeAppSurface,
  resolveRoleAppSurface,
} from "../../shared/utils/app-surface.js";

/**
 * Purpose:
 * منطق الخدمة الخفيف لطبقة الإشعارات. يبقي controllers نظيفة ويعزل
 * parsing/query normalization عن repository.
 *
 * Critical notes:
 * - source of truth للسياسات البسيطة مثل unreadOnly/limit والتحقق من token.
 * - الارسال الفعلي وتخزين الإشعارات يحصل في `notifications.repo.js`.
 */
export async function listUserNotifications(userId, query) {
  const unreadOnly =
    query?.unreadOnly === true ||
    query?.unreadOnly === "true" ||
    query?.unreadOnly === "1";
  const limit = Number(query?.limit || 50);

  return repo.listUserNotifications(userId, {
    unreadOnly,
    limit,
  });
}

/**
 * يعيد unread badge count كما تستهلكه الواجهة والـ pollers.
 */
export async function unreadCount(userId) {
  const unreadCount = await repo.countUnreadNotifications(userId);
  return { unreadCount };
}

/**
 * يعلم إشعاراً واحداً كمقروء ويتأكد من ملكية المستخدم له.
 */
export async function markRead(userId, notificationId) {
  const ok = await repo.markNotificationRead(userId, notificationId);
  if (!ok) {
    const err = new Error("NOTIFICATION_NOT_FOUND");
    err.status = 404;
    throw err;
  }
}

export async function markAllRead(userId) {
  return repo.markAllNotificationsRead(userId);
}

/**
 * يسجل push token الحالي للجهاز كي يمكن fan-out عبر FCM/APNs لاحقاً.
 */
export function validatePushTokenContext(authContext, body = {}) {
  const userId = Number(authContext?.userId);
  const sessionId = Number(authContext?.sessionId);
  const appSurface = resolveRoleAppSurface(authContext?.role);
  const hintedUserId = body?.userId == null ? null : Number(body.userId);
  const hintedSessionId = body?.sessionId == null ? null : Number(body.sessionId);
  const hintedSurface = body?.appFlavor == null
    ? null
    : normalizeAppSurface(body.appFlavor);

  const mismatch =
    !Number.isInteger(userId) ||
    userId <= 0 ||
    !Number.isInteger(sessionId) ||
    sessionId <= 0 ||
    !appSurface ||
    (hintedUserId != null && hintedUserId !== userId) ||
    (hintedSessionId != null && hintedSessionId !== sessionId) ||
    (body?.appFlavor != null && hintedSurface !== appSurface);
  if (mismatch) {
    const err = new Error("PUSH_TOKEN_CONTEXT_MISMATCH");
    err.status = 409;
    throw err;
  }

  return {
    userId,
    sessionId,
    appSurface,
    deviceFingerprint:
      String(authContext?.deviceContext?.deviceFingerprint || "").trim() || null,
  };
}

export async function registerPushToken(authContext, body) {
  const token = String(body?.token || "").trim();
  if (!token) {
    const err = new Error("PUSH_TOKEN_REQUIRED");
    err.status = 400;
    throw err;
  }

  const context = validatePushTokenContext(authContext, body);
  await repo.upsertPushToken({
    userId: context.userId,
    authSessionId: context.sessionId,
    appSurface: context.appSurface,
    deviceFingerprint: context.deviceFingerprint,
    token,
    platform: body?.platform || null,
    appVersion: body?.appVersion || null,
    deviceModel: body?.deviceModel || null,
    locale: body?.locale || null,
  });
}

/**
 * يلغي تفعيل token على الجهاز الحالي عند logout أو تبديل الجهاز.
 */
export async function unregisterPushToken(userId, body) {
  const token = String(body?.token || "").trim();
  if (!token) {
    const err = new Error("PUSH_TOKEN_REQUIRED");
    err.status = 400;
    throw err;
  }

  await repo.deactivatePushToken(userId, token);
}

/**
 * يعرض status مختصر يفيد شاشة الدعم أو التشخيص لمعرفة هل push مهيأ.
 */
export async function pushStatus(userId) {
  const base = repo.getPushConfigStatus();
  const activeTokens = await repo.listActivePushTokens(userId);
  return {
    ...base,
    activeTokens: activeTokens.length,
  };
}

export async function trackAction(userId, body) {
  const actionId = String(body?.actionId || body?.action || "").trim();
  if (!actionId) {
    const err = new Error("ACTION_ID_REQUIRED");
    err.status = 400;
    throw err;
  }

  const notificationId =
    body?.notificationId == null
      ? null
      : Number.parseInt(String(body.notificationId), 10);
  const entityId =
    body?.entityId == null ? null : Number.parseInt(String(body.entityId), 10);
  const requestState = String(body?.requestState || "opened")
    .trim()
    .toLowerCase();

  return repo.createNotificationActionEvent({
    notificationId:
      Number.isInteger(notificationId) && notificationId > 0
        ? notificationId
        : null,
    userId,
    actionId,
    target: body?.target || null,
    entityType: body?.entityType || null,
    entityId: Number.isInteger(entityId) && entityId > 0 ? entityId : null,
    requestState,
    payload: body?.payload && typeof body.payload === "object" ? body.payload : {},
  });
}
