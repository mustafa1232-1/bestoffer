import admin from "firebase-admin";

import { q } from "../../config/db.js";
import { emitRealtimeToUser } from "../../shared/realtime/realtime-gateway.js";
import {
  normalizeAppSurface,
  resolveRoleAppSurface,
} from "../../shared/utils/app-surface.js";
import { attachNotificationI18n } from "./notification.i18n.js";
import {
  normalizeNotificationLocale,
  renderNotificationTextForLocale,
} from "./notification.render.js";

/**
 * Purpose:
 * طبقة الوصول إلى بيانات الإشعارات والـ push fan-out.
 *
 * Used by:
 * - `notifications.service.js`
 * - modules أخرى تنشئ إشعارات مباشرة مثل taxi/delivery/feed/company
 *
 * Critical notes:
 * - هذا الملف مسؤول عن الإدخال في DB، البث اللحظي، ومحاولة push delivery.
 * - أي تغيير في shape payload أو target resolution يجب أن يبقى متوافقاً مع
 *   Flutter `NotificationNavigation`.
 */
let firebaseInitAttempted = false;
let firebaseMessaging = null;
const PUSH_MAX_RETRIES = 3;
const PUSH_RETRY_BASE_DELAY_MS = 500;
const PUSH_ANOMALY_ALERT_THRESHOLD = 5;

function pushDebug(message, details = null) {
  if (process.env.NODE_ENV !== "development") return;
  if (details == null) console.info(`[push] ${message}`);
  else console.info(`[push] ${message}`, details);
}

function sleep(ms) {
  return new Promise((resolve) =>
    setTimeout(resolve, Math.max(0, Number(ms) || 0))
  );
}

function toNotificationRow(row) {
  if (!row) return null;
  return {
    ...row,
    payload: row.payload || null,
  };
}

function normalizeServiceAccount(parsed, source) {
  if (!parsed || typeof parsed !== "object") return null;
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    return null;
  }

  return {
    projectId: String(parsed.project_id).trim(),
    clientEmail: String(parsed.client_email).trim(),
    privateKey: String(parsed.private_key).replace(/\\n/g, "\n"),
    source,
  };
}

function parseServiceAccountJson(raw, source, { silent = false } = {}) {
  if (!raw || !raw.trim()) return null;
  try {
    const parsed = JSON.parse(raw);
    const normalized = normalizeServiceAccount(parsed, source);
    if (normalized) return normalized;
    if (!silent) {
      console.error(`Firebase service account JSON missing required keys (${source}).`);
    }
    return null;
  } catch (e) {
    if (!silent) {
      console.error(`Invalid Firebase service account JSON (${source})`, e);
    }
    return null;
  }
}

function readFirebaseServiceAccount({ silent = false } = {}) {
  const jsonRaw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  const fromJson = parseServiceAccountJson(jsonRaw, "json", { silent });
  if (fromJson) return fromJson;

  const base64Raw = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64;
  if (base64Raw && base64Raw.trim()) {
    try {
      const decoded = Buffer.from(base64Raw.trim(), "base64").toString("utf8");
      const fromBase64 = parseServiceAccountJson(decoded, "base64", { silent });
      if (fromBase64) return fromBase64;
    } catch (e) {
      if (!silent) {
        console.error("Invalid FIREBASE_SERVICE_ACCOUNT_BASE64", e);
      }
    }
  }

  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY
    ? String(process.env.FIREBASE_PRIVATE_KEY).replace(/\\n/g, "\n")
    : null;

  if (!projectId || !clientEmail || !privateKey) return null;
  return {
    projectId: String(projectId).trim(),
    clientEmail: String(clientEmail).trim(),
    privateKey,
    source: "split",
  };
}

function currentConfiguredSource() {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim()) return "json";
  if (process.env.FIREBASE_SERVICE_ACCOUNT_BASE64?.trim()) return "base64";
  if (
    process.env.FIREBASE_PROJECT_ID?.trim() ||
    process.env.FIREBASE_CLIENT_EMAIL?.trim() ||
    process.env.FIREBASE_PRIVATE_KEY?.trim()
  ) {
    return "split";
  }
  return null;
}

function splitEnvMissingKeys() {
  const missing = [];
  if (!process.env.FIREBASE_PROJECT_ID?.trim()) missing.push("FIREBASE_PROJECT_ID");
  if (!process.env.FIREBASE_CLIENT_EMAIL?.trim()) missing.push("FIREBASE_CLIENT_EMAIL");
  if (!process.env.FIREBASE_PRIVATE_KEY?.trim()) missing.push("FIREBASE_PRIVATE_KEY");
  return missing;
}

/**
 * يعرض حالة تهيئة Firebase push الحالية لصفحات الدعم والـ health tooling.
 */
export function getPushConfigStatus() {
  const serviceAccount = readFirebaseServiceAccount({ silent: true });
  const source = serviceAccount?.source || currentConfiguredSource();
  return {
    configured: !!serviceAccount,
    source,
    firebaseInitAttempted,
    firebaseInitialized: !!firebaseMessaging,
    missingSplitKeys:
      source === "split" || source === null ? splitEnvMissingKeys() : [],
  };
}

function getFirebaseMessaging() {
  if (firebaseMessaging) return firebaseMessaging;
  if (firebaseInitAttempted) return null;
  firebaseInitAttempted = true;

  const serviceAccount = readFirebaseServiceAccount();
  if (!serviceAccount) return null;

  try {
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: serviceAccount.projectId,
          clientEmail: serviceAccount.clientEmail,
          privateKey: serviceAccount.privateKey,
        }),
      });
    }
    firebaseMessaging = admin.messaging();
  } catch (e) {
    console.error("Failed to initialize Firebase Admin", e);
    firebaseMessaging = null;
  }

  return firebaseMessaging;
}

// Test seam: inject a fake Firebase messaging (with sendEachForMulticast) or
// null to simulate "Firebase not configured". Never used in production paths.
export function __setFirebaseMessagingForTests(mock) {
  firebaseMessaging = mock || null;
  firebaseInitAttempted = true;
}

function isDeadTokenError(code) {
  return (
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token"
  );
}

function isRetryablePushError(code) {
  return (
    code === "messaging/internal-error" ||
    code === "messaging/server-unavailable" ||
    code === "messaging/unknown-error" ||
    code === "app/network-error" ||
    code === "messaging/quota-exceeded" ||
    code === "messaging/device-message-rate-exceeded" ||
    code === "messaging/topics-message-rate-exceeded"
  );
}

async function createOpsAlertSafe({
  source,
  eventType,
  severity = "medium",
  title,
  details = {},
  dedupeKey = null,
  affectedUserId = null,
  affectedRole = null,
  entityType = null,
  entityId = null,
}) {
  try {
    await q(
      `INSERT INTO ops_alert
        (source, event_type, severity, title, details, dedupe_key, affected_user_id, affected_role, entity_type, entity_id)
       VALUES ($1,$2,$3,$4,$5::jsonb,$6,$7,$8,$9,$10)`,
      [
        String(source || "notifications"),
        String(eventType || "unknown"),
        String(severity || "medium"),
        String(title || "Operational alert"),
        JSON.stringify(details && typeof details === "object" ? details : {}),
        dedupeKey ? String(dedupeKey).slice(0, 160) : null,
        affectedUserId ? Number(affectedUserId) : null,
        affectedRole ? String(affectedRole).trim().toLowerCase() : null,
        entityType ? String(entityType).trim().toLowerCase() : null,
        entityId ? Number(entityId) : null,
      ]
    );
  } catch (_) {
    // Ops tables may not be migrated in all environments yet.
  }
}

async function insertNotificationDeliveryEvents(rows = []) {
  const list = Array.isArray(rows) ? rows.filter(Boolean) : [];
  if (list.length <= 0) return;

  const values = [];
  const params = [];
  let i = 1;
  for (const row of list) {
    values.push(
      `($${i},$${i + 1},$${i + 2},$${i + 3},$${i + 4},$${i + 5},$${i + 6},$${i + 7},$${i + 8},$${i + 9},$${i + 10}::jsonb)`
    );
    params.push(
      row.notificationId ? Number(row.notificationId) : null,
      row.userId ? Number(row.userId) : null,
      row.pushToken ? String(row.pushToken) : null,
      row.platform ? String(row.platform) : null,
      row.channelId ? String(row.channelId) : null,
      row.target ? String(row.target) : null,
      String(row.eventStatus || "failed"),
      row.errorCode ? String(row.errorCode) : null,
      row.errorMessage ? String(row.errorMessage).slice(0, 800) : null,
      Number.isFinite(Number(row.latencyMs)) ? Number(row.latencyMs) : null,
      JSON.stringify(row.payload && typeof row.payload === "object" ? row.payload : {})
    );
    i += 11;
  }

  try {
    await q(
      `INSERT INTO notification_delivery_event
        (notification_id, user_id, push_token, platform, channel_id, target, event_status, error_code, error_message, latency_ms, payload)
       VALUES ${values.join(",")}`,
      params
    );
  } catch (_) {
    // Optional ops table path.
  }
}

async function upsertDevicePushHealth({
  pushToken,
  userId,
  platform = null,
  status = null,
  errorCode = null,
  successDelta = 0,
  failureDelta = 0,
}) {
  if (!pushToken) return;
  try {
    await q(
      `INSERT INTO device_push_health
        (push_token, user_id, platform, last_status, last_error_code, success_count, failure_count, last_seen_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,NOW(),NOW())
       ON CONFLICT (push_token)
       DO UPDATE SET
         user_id = COALESCE(EXCLUDED.user_id, device_push_health.user_id),
         platform = COALESCE(EXCLUDED.platform, device_push_health.platform),
         last_status = COALESCE(EXCLUDED.last_status, device_push_health.last_status),
         last_error_code = COALESCE(EXCLUDED.last_error_code, device_push_health.last_error_code),
         success_count = device_push_health.success_count + $6,
         failure_count = device_push_health.failure_count + $7,
         last_seen_at = NOW(),
         updated_at = NOW()`,
      [
        String(pushToken),
        userId ? Number(userId) : null,
        platform ? String(platform) : null,
        status ? String(status) : null,
        errorCode ? String(errorCode) : null,
        Math.max(0, Number(successDelta) || 0),
        Math.max(0, Number(failureDelta) || 0),
      ]
    );
  } catch (_) {
    // Optional ops table path.
  }
}


function resolveNotificationTarget(notification, orderId) {
  const type = String(notification?.type || "").trim().toLowerCase();
  const directTarget = String(notification?.payload?.target || "")
    .trim()
    .toLowerCase();
  if (directTarget) return directTarget;
  if (!type) {
    return orderId == null ? "notifications" : "order_tracking";
  }

  if (type.includes("admin_delivery_pending")) return "admin_merchants_pending";
  if (type.includes("pending_approval") && type.includes("admin")) {
    return "admin_merchants_pending";
  }
  if (type.includes("admin_pending_merchant")) return "admin_merchants_pending";
  if (type.includes("settlement")) return "admin_settlements";
  if (type.startsWith("residence.change.")) {
    if (type.includes("request_submitted")) return "admin_residence_requests";
    return "residence_change_request";
  }
  if (type.startsWith("social.capability.")) {
    return type.includes("restricted")
      ? "social_restriction_notice"
      : "social_profile";
  }
  if (type.startsWith("paid_upgrade.")) {
    if (
      type.includes("request_submitted") ||
      type.includes("approved") ||
      type.includes("rejected") ||
      type.includes("activated") ||
      type.includes("cancelled")
    ) {
      return "paid_upgrades_home";
    }
    return "paid_upgrades_home";
  }
  if (type === "car_listing" || type.startsWith("car_listing.")) {
    return "car_listing";
  }
  if (type === "real_estate_listing" || type.startsWith("real_estate_listing.")) {
    return "real_estate_listing";
  }
  if (type.startsWith("real_estate.")) {
    if (type.includes("pending_admin_review")) {
      return "admin_real_estate_pending";
    }
    if (
      type.includes("approved") ||
      type.includes("rejected") ||
      type.includes("hidden_due_subscription_expiry")
    ) {
      return "real_estate_workspace";
    }
    return "real_estate_marketplace";
  }
  if (type === "taxi.captain.subscription.cash_payment_requested") {
    return "admin_taxi_payments_pending";
  }
  if (type === "taxi.captain.profile_edit.requested") {
    return "admin_taxi_profile_edits_pending";
  }

  if (type.startsWith("taxi.")) return "taxi_live";
  if (type.startsWith("social.community.") || type.startsWith("social_community.")) {
    return "social_community";
  }
  if (
    type.startsWith("social.call.") ||
    type.startsWith("social_call.") ||
    type === "social_call_message"
  ) {
    return "social_call";
  }
  if (
    type.startsWith("social.chat.") ||
    type.startsWith("social_chat.") ||
    type === "social_chat_message"
  ) {
    return "social_chat";
  }
  if (type.startsWith("social.story.")) return "social_story";
  if (type.startsWith("social.reel.")) return "social_reel";
  if (type.startsWith("social.post.")) return "social_post";
  if (type.startsWith("social.relation.")) return "social_profile";
  if (type.startsWith("social.")) return "social_activity";
  if (type.startsWith("jobs.")) return "jobs_applications";
  if (type.startsWith("owner_")) return "owner_orders";
  if (type.startsWith("delivery_")) return "delivery_orders";
  if (type.includes("order")) return "order_tracking";

  return orderId == null ? "notifications" : "order_tracking";
}

function resolveRideId(notification) {
  const payload = notification?.payload;
  const rideId =
    notification?.ride_id ??
    notification?.rideId ??
    payload?.rideId ??
    payload?.ride_id ??
    null;
  if (rideId == null) return null;
  const n = Number(rideId);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.floor(n);
}

function stringifyDataValue(value) {
  if (value == null) return "";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  try {
    return JSON.stringify(value);
  } catch {
    return "";
  }
}

function buildMulticastMessage(
  notification,
  tokens,
  orderId,
  localizedText,
  appSurface
) {
  const target = resolveNotificationTarget(notification, orderId);
  const rideId = resolveRideId(notification);
  const payload = notification?.payload || {};
  const requiresAction = payload.requiresAction === true;
  const actionableExpiresAt =
    payload.actionableExpiresAt ||
    payload.expiresAt ||
    (requiresAction ? new Date(Date.now() + 120 * 1000).toISOString() : "");
  const androidChannelId = resolveEventChannelId(notification);
  const isUrgentChannel = URGENT_CHANNEL_ALLOWLIST.has(androidChannelId);
  const reminderTag =
    requiresAction && orderId != null
      ? `${String(payload.reminderKind || notification?.type || "order_action")}:${orderId}`
      : null;
  const postId =
    payload.postId == null ? null : Number.parseInt(String(payload.postId), 10);
  const storyId =
    payload.storyId == null
      ? null
      : Number.parseInt(String(payload.storyId), 10);
  const threadId =
    payload.threadId == null ? null : Number.parseInt(String(payload.threadId), 10);
  const sessionId =
    payload.sessionId == null ? null : Number.parseInt(String(payload.sessionId), 10);
  const jobId =
    payload.jobId == null ? null : Number.parseInt(String(payload.jobId), 10);
  const applicationId =
    payload.applicationId == null
      ? null
      : Number.parseInt(String(payload.applicationId), 10);
  const senderUserId =
    payload.senderUserId == null
      ? null
      : Number.parseInt(String(payload.senderUserId), 10);
  const remoteDisplayName =
    payload.remoteDisplayName == null ? "" : String(payload.remoteDisplayName);
  const scopeType =
    payload.scopeType == null ? "" : String(payload.scopeType).trim().toLowerCase();
  const scopeCode =
    payload.scopeCode == null ? "" : String(payload.scopeCode).trim().toUpperCase();
  const titleText =
    String(localizedText?.title || notification.title || "مَسْلَكي").trim() ||
    "مَسْلَكي";
  const bodyText =
    localizedText?.body == null
      ? String(notification.body || "").trim()
      : String(localizedText.body || "").trim();
  // Incoming-call pushes are sent DATA-ONLY (no top-level or android notification
  // block) so the Android background handler can build the full-screen "ringing"
  // call UI (fullScreenIntent + call category + ringtone). A notification block
  // would make the OS render a plain tap-to-answer notification instead and
  // suppress the ring. (Android focus; iOS incoming calls need CallKit/VoIP push.)
  const isCallPush = String(notification?.type || "")
    .toLowerCase()
    .startsWith("social.call");
  return {
    tokens,
    ...(isCallPush
      ? {}
      : {
          notification: {
            title: titleText,
            body: bodyText || "لديك إشعار جديد",
          },
        }),
    data: {
      payloadVersion: "2",
      notificationId: String(notification.id || ""),
      type: String(notification.type || ""),
      appSurface: String(appSurface || ""),
      roleScope: payload.roleScope == null ? "" : String(payload.roleScope),
      targetModule:
        payload.targetModule == null ? "" : String(payload.targetModule),
      orderId: orderId == null ? "" : String(orderId),
      target,
      deepLinkTarget: target,
      actionable: requiresAction ? "true" : "false",
      actionableExpiresAt: actionableExpiresAt ? String(actionableExpiresAt) : "",
      requiresAction: requiresAction ? "true" : "false",
      rideId: rideId == null ? "" : String(rideId),
      postId: Number.isFinite(postId) && postId > 0 ? String(postId) : "",
      storyId: Number.isFinite(storyId) && storyId > 0 ? String(storyId) : "",
      threadId: Number.isFinite(threadId) && threadId > 0 ? String(threadId) : "",
      sessionId: Number.isFinite(sessionId) && sessionId > 0 ? String(sessionId) : "",
      jobId: Number.isFinite(jobId) && jobId > 0 ? String(jobId) : "",
      applicationId:
        Number.isFinite(applicationId) && applicationId > 0
          ? String(applicationId)
          : "",
      scopeType,
      scopeCode,
      remoteDisplayName,
      i18nTitleKey:
        payload.i18nTitleKey == null ? "" : String(payload.i18nTitleKey),
      i18nBodyKey:
        payload.i18nBodyKey == null ? "" : String(payload.i18nBodyKey),
      i18nTitleArgs: stringifyDataValue(payload.i18nTitleArgs),
      i18nBodyArgs: stringifyDataValue(payload.i18nBodyArgs),
      title: titleText,
      body: bodyText,
      reminderKind:
        payload.reminderKind == null ? "" : String(payload.reminderKind),
      targetEntity:
        payload.targetEntity == null ? "" : String(payload.targetEntity),
      entityId: payload.entityId == null ? "" : String(payload.entityId),
      senderUserId:
        Number.isFinite(senderUserId) && senderUserId > 0
          ? String(senderUserId)
          : "",
      // §4 grouped-assignment urgent event contract (strings — FCM data must be
      // string-valued). Empty when not applicable.
      eventId: payload.eventId == null ? "" : String(payload.eventId),
      eventType: payload.eventType == null ? "" : String(payload.eventType),
      schemaVersion:
        payload.schemaVersion == null ? "" : String(payload.schemaVersion),
      deliveryJobId:
        payload.deliveryJobId == null ? "" : String(payload.deliveryJobId),
      orderGroupId:
        payload.orderGroupId == null ? "" : String(payload.orderGroupId),
      assignmentId:
        payload.assignmentId == null ? "" : String(payload.assignmentId),
      numberOfStores:
        payload.numberOfStores == null ? "" : String(payload.numberOfStores),
      route: payload.route == null ? "" : String(payload.route),
      createdAt: payload.createdAt == null ? "" : String(payload.createdAt),
      urgentChannelId: isUrgentChannel ? androidChannelId : "",
    },
    android: {
      priority: "high",
      ttl: 60 * 60 * 1000,
      ...(isCallPush
        ? {}
        : {
            notification: {
              channelId: androidChannelId,
              // Urgent operational channels carry a distinctive sound; the OS honors
              // the channel's own sound/vibration for the final presentation.
              sound:
                isUrgentChannel || requiresAction
                  ? "maslaki_attention"
                  : "default",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
              // Distinct assignment events must NOT collapse into each other.
              tag: isUrgentChannel ? undefined : reminderTag || undefined,
            },
          }),
    },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-push-type": "alert",
        ...(reminderTag && !isUrgentChannel
          ? { "apns-collapse-id": reminderTag }
          : {}),
      },
      payload: {
        aps: {
          sound: isUrgentChannel ? "maslaki_attention.caf" : "default",
          ...(isUrgentChannel ? {} : { contentAvailable: true }),
          ...(reminderTag && !isUrgentChannel ? { threadId: reminderTag } : {}),
        },
      },
    },
  };
}

async function deactivatePushTokensByValue(tokens = []) {
  if (!Array.isArray(tokens) || tokens.length === 0) return;
  await q(
    `UPDATE user_push_token
     SET is_active = FALSE,
         updated_at = NOW()
     WHERE push_token = ANY($1::text[])`,
    [tokens]
  );
}

function emptyDeliveryResult(overrides = {}) {
  return {
    firebaseConfigured: true,
    intendedSurface: null,
    totalTokens: 0,
    acceptedTokens: 0,
    failedTokens: 0,
    deadTokens: 0,
    retryableFailures: 0,
    permanentFailures: 0,
    providerMessageIds: [],
    ...overrides,
  };
}

async function dispatchPushNotification(notification) {
  const messaging = getFirebaseMessaging();
  // §3: Firebase not configured is NOT acceptance — report it truthfully and
  // let the caller decide to retry (config may appear later) vs. fail.
  if (!messaging) return emptyDeliveryResult({ firebaseConfigured: false });

  const userId = Number(notification.user_id ?? notification.userId);
  if (!Number.isFinite(userId) || userId <= 0) {
    return emptyDeliveryResult({ invalidUser: true });
  }

  const intendedSurface = normalizeAppSurface(
    notification?.payload?.appSurface || notification?.payload?.app_surface
  );
  const targets = (await listActivePushTargets(userId)).filter(
    (target) => !intendedSurface || target.appSurface === intendedSurface
  );
  // §5: no token matching the intended surface → suppressed (not accepted).
  if (!targets.length) {
    return emptyDeliveryResult({ intendedSurface, noTokens: true });
  }

  const deliveryResult = emptyDeliveryResult({ intendedSurface });

  const orderId =
    notification.order_id ??
    notification.orderId ??
    notification.payload?.orderId ??
    null;

  const byDeliveryContext = new Map();
  for (const target of targets) {
    const token = String(target?.token || "").trim();
    if (!token) continue;
    const locale = normalizeNotificationLocale(target?.locale);
    const appSurface = normalizeAppSurface(target?.appSurface);
    if (!appSurface) continue;
    const key = `${locale}:${appSurface}`;
    if (!byDeliveryContext.has(key)) {
      byDeliveryContext.set(key, { locale, appSurface, tokens: [] });
    }
    byDeliveryContext.get(key).tokens.push(token);
    deliveryResult.totalTokens += 1;
  }

  const staleTokens = new Set();
  const acceptedSet = new Set();
  const retryableSet = new Set();
  const permanentSet = new Set();
  let totalFailedEvents = 0;
  const resolvedTarget = resolveNotificationTarget(notification, orderId);
  for (const context of byDeliveryContext.values()) {
    const { locale, appSurface } = context;
    let pendingTokens = [...context.tokens];
    const localizedText = renderNotificationTextForLocale({
      locale,
      title: notification.title,
      body: notification.body,
      payload: notification.payload || null,
    });

    for (
      let attempt = 1;
      attempt <= PUSH_MAX_RETRIES && pendingTokens.length > 0;
      attempt += 1
    ) {
      const attemptStartedAt = Date.now();
      let response;
      try {
        response = await messaging.sendEachForMulticast(
          buildMulticastMessage(
            notification,
            pendingTokens,
            orderId,
            localizedText,
            appSurface
          )
        );
      } catch (error) {
        const code = error?.code;
        const latency = Date.now() - attemptStartedAt;
        const status = attempt < PUSH_MAX_RETRIES && isRetryablePushError(code)
          ? "retry"
          : "failed";
        for (const token of pendingTokens) {
          if (status === "retry") retryableSet.add(token);
          else permanentSet.add(token);
        }
        const errorRows = pendingTokens.map((token) => ({
          notificationId: notification.id,
          userId,
          pushToken: token,
          platform: "fcm",
          channelId: resolveEventChannelId(notification),
          target: resolvedTarget,
          eventStatus: status,
          errorCode: code || "messaging/send-exception",
          errorMessage: error?.message || null,
          latencyMs: latency,
          payload: { attempt, locale },
        }));
        await insertNotificationDeliveryEvents(errorRows);
        await Promise.all(
          errorRows.map((row) =>
            upsertDevicePushHealth({
              pushToken: row.pushToken,
              userId,
              platform: "fcm",
              status: row.eventStatus,
              errorCode: row.errorCode,
              failureDelta: 1,
            })
          )
        );
        totalFailedEvents += errorRows.length;

        if (attempt >= PUSH_MAX_RETRIES || !isRetryablePushError(code)) {
          throw error;
        }
        await sleep(PUSH_RETRY_BASE_DELAY_MS * 2 ** (attempt - 1));
        continue;
      }

      const retryTokens = [];
      const eventRows = [];
      const latency = Date.now() - attemptStartedAt;
      for (let i = 0; i < response.responses.length; i += 1) {
        const result = response.responses[i];
        const token = pendingTokens[i];
        if (!token) continue;

        if (result.success) {
          acceptedSet.add(token);
          retryableSet.delete(token);
          permanentSet.delete(token);
          if (result.messageId) {
            deliveryResult.providerMessageIds.push(String(result.messageId));
          }
          eventRows.push({
            notificationId: notification.id,
            userId,
            pushToken: token,
            platform: "fcm",
            channelId: resolveEventChannelId(notification),
            target: resolvedTarget,
            eventStatus: "sent",
            errorCode: null,
            errorMessage: null,
            latencyMs: latency,
            payload: { attempt, locale },
          });
          continue;
        }

        const code = result.error?.code;
        let eventStatus = "failed";

        if (isDeadTokenError(code)) {
          staleTokens.add(token);
          retryableSet.delete(token);
          permanentSet.delete(token);
          eventStatus = "dead_token";
        } else if (attempt < PUSH_MAX_RETRIES && isRetryablePushError(code)) {
          retryTokens.push(token);
          retryableSet.add(token);
          eventStatus = "retry";
        } else if (isRetryablePushError(code)) {
          // Retryable code but no internal attempts remain → defer to the
          // outbox-level retry (transient failure stays retryable, §3).
          retryableSet.add(token);
          permanentSet.delete(token);
          eventStatus = "retry";
        } else {
          permanentSet.add(token);
          retryableSet.delete(token);
        }

        eventRows.push({
          notificationId: notification.id,
          userId,
          pushToken: token,
          platform: "fcm",
          channelId: resolveEventChannelId(notification),
          target: resolvedTarget,
          eventStatus,
          errorCode: code || null,
          errorMessage: result.error?.message || null,
          latencyMs: latency,
          payload: { attempt, locale },
        });
      }

      await insertNotificationDeliveryEvents(eventRows);
      await Promise.all(
        eventRows.map((row) =>
          upsertDevicePushHealth({
            pushToken: row.pushToken,
            userId,
            platform: "fcm",
            status: row.eventStatus,
            errorCode: row.errorCode,
            successDelta: row.eventStatus === "sent" ? 1 : 0,
            failureDelta: row.eventStatus === "sent" ? 0 : 1,
          })
        )
      );
      totalFailedEvents += eventRows.filter((row) => row.eventStatus !== "sent").length;

      if (response.failureCount <= 0) break;

      pendingTokens = retryTokens;
      if (pendingTokens.length && attempt < PUSH_MAX_RETRIES) {
        await sleep(PUSH_RETRY_BASE_DELAY_MS * 2 ** (attempt - 1));
      }
    }
  }

  if (staleTokens.size > 0) {
    await deactivatePushTokensByValue([...staleTokens]);
    await createOpsAlertSafe({
      source: "notifications",
      eventType: "push_dead_tokens_detected",
      severity: "high",
      title: "Push tokens became invalid",
      details: {
        count: staleTokens.size,
        sampleTokens: [...staleTokens].slice(0, 5),
      },
      dedupeKey: `push_dead_tokens:${new Date().toISOString().slice(0, 16)}`,
      affectedUserId: userId,
      entityType: "notification",
      entityId: notification.id,
    });
  }

  if (totalFailedEvents >= PUSH_ANOMALY_ALERT_THRESHOLD) {
    await createOpsAlertSafe({
      source: "notifications",
      eventType: "push_delivery_anomaly",
      severity: "critical",
      title: "High push delivery failure rate detected",
      details: {
        notificationId: notification.id,
        userId,
        failedEvents: totalFailedEvents,
      },
      dedupeKey: `push_delivery_anomaly:${notification.id}:${new Date()
        .toISOString()
        .slice(0, 16)}`,
      affectedUserId: userId,
      entityType: "notification",
      entityId: notification.id,
    });
  }
  pushDebug("dispatch completed", {
    notificationId: notification.id,
    userId,
    target: resolvedTarget,
    failedEvents: totalFailedEvents,
  });

  // Finalize the truthful per-token disposition. accepted/dead win over
  // retryable/permanent; whatever remains unaccounted is a permanent failure.
  for (const t of acceptedSet) {
    retryableSet.delete(t);
    permanentSet.delete(t);
  }
  for (const t of staleTokens) {
    retryableSet.delete(t);
    permanentSet.delete(t);
  }
  deliveryResult.acceptedTokens = acceptedSet.size;
  deliveryResult.deadTokens = staleTokens.size;
  deliveryResult.retryableFailures = retryableSet.size;
  deliveryResult.permanentFailures = permanentSet.size;
  deliveryResult.failedTokens = permanentSet.size + staleTokens.size;
  return deliveryResult;
}

// §4: allow-listed urgent Android channels. The generic mapper must NOT replace
// a critical operational event's channel with maslaki_live_updates /
// maslaki_action_required_v2. Only these authoritative channel IDs are honored
// from the event contract; arbitrary client-provided IDs are ignored.
const URGENT_CHANNEL_ALLOWLIST = new Set([
  "maslaki_courier_assignments_urgent_v2",
  "maslaki_store_orders_urgent_v2",
]);

function resolveEventChannelId(notification) {
  const requested = String(notification?.payload?.urgentChannelId || "").trim();
  if (URGENT_CHANNEL_ALLOWLIST.has(requested)) return requested;
  return notification?.payload?.requiresAction
    ? "maslaki_action_required_v2"
    : "maslaki_live_updates";
}

/**
 * §3: awaited push delivery. Sends `notification` and RETURNS a structured,
 * truthful provider result. Unlike queuePushNotification (fire-and-forget), the
 * caller can record an accurate outbox state from the result.
 */
export async function dispatchNotificationWithResult(notification) {
  try {
    const result = await dispatchPushNotification(notification);
    return result || emptyDeliveryResult();
  } catch (error) {
    // A total exception is a retryable failure, not acceptance.
    return emptyDeliveryResult({
      totalTokens: 0,
      retryableFailures: 1,
      exception: true,
      errorCode: String(error?.code || error?.message || "dispatch_exception").slice(0, 64),
    });
  }
}

function queuePushNotification(notification) {
  dispatchPushNotification(notification).catch((e) => {
    pushDebug("dispatch failed", {
      notificationId: notification?.id || null,
      error: e?.message || String(e),
    });
  });
}

function prepareNotificationInsertRow({
  userId,
  type,
  title,
  body,
  orderId,
  merchantId,
  payload,
}) {
  const normalizedUserId = Number(userId);
  if (!Number.isInteger(normalizedUserId) || normalizedUserId <= 0) {
    return null;
  }

  const basePayload =
    payload && typeof payload === "object" && !Array.isArray(payload)
      ? { ...payload }
      : {};
  const localizedPayload = attachNotificationI18n({
    type,
    payload: basePayload,
  });
  const derivedTarget = resolveNotificationTarget(
    { type, payload: localizedPayload },
    orderId
  );
  const derivedRideId = resolveRideId({ payload: localizedPayload });

  if (
    localizedPayload.target == null ||
    String(localizedPayload.target).trim() === ""
  ) {
    localizedPayload.target = derivedTarget;
  }
  if (orderId != null && localizedPayload.orderId == null) {
    localizedPayload.orderId = Number(orderId);
  }
  if (derivedRideId != null && localizedPayload.rideId == null) {
    localizedPayload.rideId = derivedRideId;
  }

  return {
    userId: normalizedUserId,
    orderId: orderId ? Number(orderId) : null,
    merchantId: merchantId ? Number(merchantId) : null,
    type,
    title,
    body: body || null,
    payloadJson:
      Object.keys(localizedPayload).length > 0
        ? JSON.stringify(localizedPayload)
        : null,
  };
}

export function buildNotificationAudienceMetadata(role) {
  const appSurface = resolveRoleAppSurface(role);
  if (!appSurface) return null;
  return {
    appSurface,
    roleScope: {
      user: "customer",
      store: "merchant",
      delivery: "courier",
      taxi: "taxi_captain",
      company: "admin",
    }[appSurface],
    targetModule: {
      user: "customer",
      store: "merchant",
      delivery: "courier",
      taxi: "taxi",
      company: "admin",
    }[appSurface],
  };
}

async function enrichPreparedNotificationAudiences(rows) {
  if (!Array.isArray(rows) || rows.length === 0) return rows;
  const userIds = [...new Set(rows.map((row) => Number(row.userId)).filter(Boolean))];
  const result = await q(
    `SELECT id, role FROM app_user WHERE id = ANY($1::bigint[])`,
    [userIds]
  );
  const metadataByUserId = new Map(
    result.rows.map((row) => [Number(row.id), buildNotificationAudienceMetadata(row.role)])
  );
  return rows.map((row) => {
    const metadata = metadataByUserId.get(Number(row.userId));
    if (!metadata) return row;
    const payload = row.payloadJson ? JSON.parse(row.payloadJson) : {};
    payload.appSurface = metadata.appSurface;
    payload.roleScope ||= metadata.roleScope;
    payload.targetModule ||= metadata.targetModule;
    return { ...row, payloadJson: JSON.stringify(payload) };
  });
}

function finalizeCreatedNotification(notification) {
  if (!notification) return null;
  void emitRealtimeToUser(Number(notification.user_id), "notification", { notification });
  queuePushNotification(notification);
  return notification;
}

async function insertPreparedNotifications(rows) {
  if (!Array.isArray(rows) || rows.length <= 0) return [];
  const params = [];
  const values = rows.map((row, index) => {
    const offset = index * 7;
    params.push(
      Number(row.userId),
      row.orderId == null ? null : Number(row.orderId),
      row.merchantId == null ? null : Number(row.merchantId),
      row.type,
      row.title,
      row.body,
      row.payloadJson
    );
    return `($${offset + 1},$${offset + 2},$${offset + 3},$${offset + 4},$${offset + 5},$${offset + 6},$${offset + 7}::jsonb)`;
  });
  const result = await q(
    `INSERT INTO app_notification
      (user_id, order_id, merchant_id, type, title, body, payload)
     VALUES ${values.join(", ")}
     RETURNING *`,
    params
  );
  return result.rows.map(toNotificationRow).filter(Boolean);
}

/**
 * ينشئ إشعاراً واحداً ويطبّق enrichment موحداً للعنوان/النص/الـ i18n payload.
 */
export async function createNotification({
  userId,
  type,
  title,
  body,
  orderId,
  merchantId,
  payload,
}) {
  const prepared = prepareNotificationInsertRow({
    userId,
    type,
    title,
    body,
    orderId,
    merchantId,
    payload,
  });
  if (!prepared) return null;
  const enriched = await enrichPreparedNotificationAudiences([prepared]);
  const inserted = await insertPreparedNotifications(enriched);
  return finalizeCreatedNotification(inserted[0] || null);
}

/**
 * §2 + §3: idempotently create ONE app_notification keyed by `eventId`, then
 * await push delivery and return the app_notification id together with the
 * truthful provider result. Safe to call again after a crash: the unique
 * `event_id` index guarantees at most one notification row per event; a retry
 * re-sends push (bounded by the outbox attempt policy) but never duplicates the
 * in-app notification.
 */
export async function createNotificationAndAwaitDelivery({
  userId,
  type,
  title,
  body,
  orderId,
  merchantId,
  payload,
  eventId,
}) {
  if (!eventId) {
    throw new Error("createNotificationAndAwaitDelivery requires eventId");
  }
  const prepared = prepareNotificationInsertRow({
    userId,
    type,
    title,
    body,
    orderId,
    merchantId,
    payload: { ...(payload || {}), eventId },
  });
  if (!prepared) {
    return { notificationId: null, created: false, delivery: emptyDeliveryResult() };
  }
  const [enriched] = await enrichPreparedNotificationAudiences([prepared]);

  // Idempotent insert. If the row already exists (crash-retry), fetch it.
  let row = (
    await q(
      `INSERT INTO app_notification
        (user_id, order_id, merchant_id, type, title, body, payload, event_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8)
       ON CONFLICT (event_id) WHERE event_id IS NOT NULL DO NOTHING
       RETURNING *`,
      [
        Number(enriched.userId),
        enriched.orderId == null ? null : Number(enriched.orderId),
        enriched.merchantId == null ? null : Number(enriched.merchantId),
        enriched.type,
        enriched.title,
        enriched.body,
        enriched.payloadJson,
        String(eventId),
      ]
    )
  ).rows[0];
  const created = Boolean(row);
  if (!row) {
    row = (
      await q(`SELECT * FROM app_notification WHERE event_id=$1 LIMIT 1`, [
        String(eventId),
      ])
    ).rows[0];
  }
  const notification = toNotificationRow(row);
  if (created && notification) {
    void emitRealtimeToUser(Number(notification.user_id), "notification", {
      notification,
    });
  }
  const delivery = await dispatchNotificationWithResult(notification);
  return {
    notificationId: notification ? Number(notification.id) : null,
    created,
    delivery,
  };
}

/**
 * ينشئ عدة إشعارات على دفعات مع fallback إلى insertion فردي عند فشل batch.
 *
 * Maintenance notes:
 * - عند ظهور فقدان جزئي في fan-out راجع logs هذه الدالة أولاً.
 */
export async function createManyNotifications(rows) {
  let preparedRows = Array.isArray(rows)
    ? rows.map((row) => prepareNotificationInsertRow(row)).filter(Boolean)
    : [];
  if (preparedRows.length <= 0) return [];
  preparedRows = await enrichPreparedNotificationAudiences(preparedRows);

  const created = [];
  const chunkSize = 100;
  for (let index = 0; index < preparedRows.length; index += chunkSize) {
    const chunk = preparedRows.slice(index, index + chunkSize);
    try {
      const inserted = await insertPreparedNotifications(chunk);
      for (const notification of inserted) {
        const finalized = finalizeCreatedNotification(notification);
        if (finalized) created.push(finalized);
      }
      continue;
    } catch (e) {
      console.error("Failed to batch create notifications", e);
    }

    for (const prepared of chunk) {
      try {
        const inserted = await insertPreparedNotifications([prepared]);
        const finalized = finalizeCreatedNotification(inserted[0] || null);
        if (finalized) created.push(finalized);
      } catch (e) {
        console.error("Failed to create notification", e);
      }
    }
  }
  return created;
}

export async function listUserNotifications(
  userId,
  { limit = 50, unreadOnly = false } = {}
) {
  const safeLimit = Math.max(1, Math.min(100, Number(limit) || 50));
  const r = await q(
    `SELECT *
     FROM app_notification
     WHERE user_id = $1
       ${unreadOnly ? "AND is_read = FALSE" : ""}
     ORDER BY created_at DESC, id DESC
     LIMIT $2`,
    [Number(userId), safeLimit]
  );

  return r.rows.map(toNotificationRow);
}

export async function countUnreadNotifications(userId) {
  const r = await q(
    `SELECT COUNT(*)::int AS unread_count
     FROM app_notification
     WHERE user_id = $1
       AND is_read = FALSE`,
    [Number(userId)]
  );

  return Number(r.rows[0]?.unread_count || 0);
}

/**
 * يعلّم إشعاراً واحداً كمقروء ويبث event حي إلى المستخدم نفسه لتحديث inbox.
 */
export async function markNotificationRead(userId, notificationId) {
  const r = await q(
    `UPDATE app_notification
     SET is_read = TRUE,
         read_at = COALESCE(read_at, NOW())
     WHERE id = $1
       AND user_id = $2
     RETURNING id`,
    [Number(notificationId), Number(userId)]
  );

  const ok = !!r.rows[0];
  if (ok) {
    void emitRealtimeToUser(Number(userId), "notification_read", {
      notificationId: Number(notificationId),
    });
  }
  return ok;
}

/**
 * يعلّم كل إشعارات المستخدم كمقروءة مع event موحد للواجهة.
 */
export async function markAllNotificationsRead(userId) {
  const r = await q(
    `UPDATE app_notification
     SET is_read = TRUE,
         read_at = COALESCE(read_at, NOW())
     WHERE user_id = $1
       AND is_read = FALSE
     RETURNING id`,
    [Number(userId)]
  );

  const out = {
    updatedCount: r.rowCount || 0,
  };

  if (out.updatedCount > 0) {
    void emitRealtimeToUser(Number(userId), "notification_read_all", out);
  }

  return out;
}

export async function createNotificationActionEvent({
  notificationId = null,
  userId,
  actionId,
  target = null,
  entityType = null,
  entityId = null,
  requestState = "opened",
  payload = {},
}) {
  const safeUserId = Number(userId);
  if (!Number.isInteger(safeUserId) || safeUserId <= 0) return null;

  const status = String(requestState || "opened").trim().toLowerCase();
  const safeStatus = [
    "accepted",
    "rejected",
    "stale",
    "failed",
    "ignored",
    "opened",
  ].includes(status)
    ? status
    : "opened";

  const r = await q(
    `INSERT INTO notification_action_event
      (notification_id, user_id, action_id, target, entity_type, entity_id, request_state, payload)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb)
     RETURNING *`,
    [
      notificationId ? Number(notificationId) : null,
      safeUserId,
      String(actionId || "open"),
      target ? String(target) : null,
      entityType ? String(entityType) : null,
      entityId ? Number(entityId) : null,
      safeStatus,
      JSON.stringify(payload && typeof payload === "object" ? payload : {}),
    ]
  );

  if (safeStatus === "stale" || safeStatus === "failed") {
    await createOpsAlertSafe({
      source: "notifications",
      eventType: "notification_action_failed",
      severity: safeStatus === "stale" ? "medium" : "high",
      title: "Notification action failed or stale",
      details: {
        notificationId: notificationId || null,
        actionId: String(actionId || "open"),
        requestState: safeStatus,
      },
      dedupeKey: notificationId
        ? `notification_action_failed:${notificationId}:${safeStatus}`
        : null,
      affectedUserId: safeUserId,
      entityType: "notification",
      entityId: notificationId ? Number(notificationId) : null,
    });
  }

  return r.rows[0] || null;
}

export async function upsertPushToken({
  userId,
  token,
  authSessionId = null,
  appSurface = null,
  deviceFingerprint = null,
  platform = null,
  appVersion = null,
  deviceModel = null,
  locale = null,
}) {
  const cleanToken = String(token || "").trim();
  if (!cleanToken) return null;

  const r = await q(
    `INSERT INTO user_push_token
      (user_id, push_token, platform, app_version, device_model, locale,
       auth_session_id, app_surface, device_fingerprint, is_active, last_seen_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,TRUE,NOW())
     ON CONFLICT (push_token)
     DO UPDATE
       SET user_id = EXCLUDED.user_id,
           platform = COALESCE(EXCLUDED.platform, user_push_token.platform),
           app_version = COALESCE(EXCLUDED.app_version, user_push_token.app_version),
           device_model = COALESCE(EXCLUDED.device_model, user_push_token.device_model),
           locale = COALESCE(EXCLUDED.locale, user_push_token.locale),
           auth_session_id = EXCLUDED.auth_session_id,
           app_surface = EXCLUDED.app_surface,
           device_fingerprint = EXCLUDED.device_fingerprint,
           is_active = TRUE,
           last_seen_at = NOW(),
           updated_at = NOW()
     RETURNING *`,
    [
      Number(userId),
      cleanToken,
      platform ? String(platform).trim().slice(0, 24) : null,
      appVersion ? String(appVersion).trim().slice(0, 48) : null,
      deviceModel ? String(deviceModel).trim().slice(0, 120) : null,
      locale ? normalizeNotificationLocale(locale).slice(0, 8) : null,
      authSessionId ? Number(authSessionId) : null,
      normalizeAppSurface(appSurface),
      deviceFingerprint ? String(deviceFingerprint).trim().slice(0, 160) : null,
    ]
  );

  return r.rows[0] || null;
}

export async function deactivatePushToken(userId, token) {
  const cleanToken = String(token || "").trim();
  if (!cleanToken) return false;

  const r = await q(
    `UPDATE user_push_token
     SET is_active = FALSE,
         updated_at = NOW()
     WHERE user_id = $1
       AND push_token = $2`,
    [Number(userId), cleanToken]
  );
  return (r.rowCount || 0) > 0;
}

export async function listActivePushTokens(userId) {
  const r = await q(
    `SELECT upt.push_token
     FROM user_push_token upt
     JOIN user_session us
       ON us.id = upt.auth_session_id
      AND us.user_id = upt.user_id
      AND us.revoked_at IS NULL
      AND us.expires_at > NOW()
     WHERE upt.user_id = $1
       AND upt.is_active = TRUE
     ORDER BY upt.last_seen_at DESC`,
    [Number(userId)]
  );

  return r.rows
    .map((row) => String(row.push_token || "").trim())
    .filter(Boolean);
}

async function listActivePushTargets(userId) {
  const r = await q(
    `SELECT upt.push_token, upt.locale, upt.app_surface
     FROM user_push_token upt
     JOIN user_session us
       ON us.id = upt.auth_session_id
      AND us.user_id = upt.user_id
      AND us.revoked_at IS NULL
      AND us.expires_at > NOW()
     WHERE upt.user_id = $1
       AND upt.is_active = TRUE
     ORDER BY upt.last_seen_at DESC`,
    [Number(userId)]
  );

  return r.rows
    .map((row) => ({
      token: String(row.push_token || "").trim(),
      locale: normalizeNotificationLocale(row.locale),
      appSurface: normalizeAppSurface(row.app_surface),
    }))
    .filter((row) => row.token && row.appSurface);
}

export async function deactivatePushTokensForSession(userId, sessionId) {
  const r = await q(
    `UPDATE user_push_token
     SET is_active = FALSE, updated_at = NOW()
     WHERE user_id = $1 AND auth_session_id = $2`,
    [Number(userId), Number(sessionId)]
  );
  return r.rowCount || 0;
}

export async function deactivatePushTokensForUser(userId) {
  const r = await q(
    `UPDATE user_push_token
     SET is_active = FALSE, updated_at = NOW()
     WHERE user_id = $1`,
    [Number(userId)]
  );
  return r.rowCount || 0;
}

export const __notificationsRepoTestables = {
  buildMulticastMessage,
  buildNotificationAudienceMetadata,
};


