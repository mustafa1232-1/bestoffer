import admin from "firebase-admin";

import { q } from "../../config/db.js";
import { emitToUser } from "../../shared/realtime/live-events.js";

let firebaseInitAttempted = false;
let firebaseMessaging = null;
const PUSH_MAX_RETRIES = 3;
const PUSH_RETRY_BASE_DELAY_MS = 500;

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

function buildMulticastMessage(notification, tokens, orderId) {
  return {
    tokens,
    notification: {
      title: String(notification.title || "BestOffer"),
      body: String(notification.body || "لديك إشعار جديد"),
    },
    data: {
      notificationId: String(notification.id || ""),
      type: String(notification.type || ""),
      orderId: orderId == null ? "" : String(orderId),
    },
    android: {
      priority: "high",
      notification: {
        channelId: "bestoffer_live_updates",
        sound: "default",
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
    },
    apns: {
      headers: { "apns-priority": "10" },
      payload: {
        aps: {
          sound: "default",
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

async function dispatchPushNotification(notification) {
  const messaging = getFirebaseMessaging();
  if (!messaging) return;

  const userId = Number(notification.user_id ?? notification.userId);
  if (!Number.isFinite(userId) || userId <= 0) return;

  const tokens = await listActivePushTokens(userId);
  if (!tokens.length) return;

  const orderId =
    notification.order_id ??
    notification.orderId ??
    notification.payload?.orderId ??
    null;

  let pendingTokens = [...tokens];
  const staleTokens = new Set();

  for (
    let attempt = 1;
    attempt <= PUSH_MAX_RETRIES && pendingTokens.length > 0;
    attempt += 1
  ) {
    let response;
    try {
      response = await messaging.sendEachForMulticast(
        buildMulticastMessage(notification, pendingTokens, orderId)
      );
    } catch (error) {
      const code = error?.code;
      if (attempt >= PUSH_MAX_RETRIES || !isRetryablePushError(code)) {
        throw error;
      }
      await sleep(PUSH_RETRY_BASE_DELAY_MS * 2 ** (attempt - 1));
      continue;
    }

    if (response.failureCount <= 0) break;

    const retryTokens = [];
    for (let i = 0; i < response.responses.length; i += 1) {
      const result = response.responses[i];
      if (result.success) continue;

      const code = result.error?.code;
      const token = pendingTokens[i];
      if (!token) continue;

      if (isDeadTokenError(code)) {
        staleTokens.add(token);
        continue;
      }

      if (attempt < PUSH_MAX_RETRIES && isRetryablePushError(code)) {
        retryTokens.push(token);
      }
    }

    pendingTokens = retryTokens;
    if (pendingTokens.length && attempt < PUSH_MAX_RETRIES) {
      await sleep(PUSH_RETRY_BASE_DELAY_MS * 2 ** (attempt - 1));
    }
  }

  if (staleTokens.size > 0) {
    await deactivatePushTokensByValue([...staleTokens]);
  }
}

function queuePushNotification(notification) {
  dispatchPushNotification(notification).catch((e) => {
    console.error("Failed to send push notification", e);
  });
}

export async function createNotification({
  userId,
  type,
  title,
  body,
  orderId,
  merchantId,
  payload,
}) {
  if (!userId) return null;

  const r = await q(
    `INSERT INTO app_notification
      (user_id, order_id, merchant_id, type, title, body, payload)
     VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb)
     RETURNING *`,
    [
      Number(userId),
      orderId ? Number(orderId) : null,
      merchantId ? Number(merchantId) : null,
      type,
      title,
      body || null,
      payload ? JSON.stringify(payload) : null,
    ]
  );

  const notification = toNotificationRow(r.rows[0]);
  if (notification) {
    emitToUser(Number(userId), "notification", { notification });
    queuePushNotification(notification);
  }
  return notification;
}

export async function createManyNotifications(rows) {
  for (const row of rows) {
    try {
      await createNotification(row);
    } catch (e) {
      console.error("Failed to create notification", e);
    }
  }
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
    emitToUser(Number(userId), "notification_read", {
      notificationId: Number(notificationId),
    });
  }
  return ok;
}

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
    emitToUser(Number(userId), "notification_read_all", out);
  }

  return out;
}

export async function upsertPushToken({
  userId,
  token,
  platform = null,
  appVersion = null,
  deviceModel = null,
}) {
  const cleanToken = String(token || "").trim();
  if (!cleanToken) return null;

  const r = await q(
    `INSERT INTO user_push_token
      (user_id, push_token, platform, app_version, device_model, is_active, last_seen_at)
     VALUES ($1,$2,$3,$4,$5,TRUE,NOW())
     ON CONFLICT (push_token)
     DO UPDATE
       SET user_id = EXCLUDED.user_id,
           platform = COALESCE(EXCLUDED.platform, user_push_token.platform),
           app_version = COALESCE(EXCLUDED.app_version, user_push_token.app_version),
           device_model = COALESCE(EXCLUDED.device_model, user_push_token.device_model),
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
    `SELECT push_token
     FROM user_push_token
     WHERE user_id = $1
       AND is_active = TRUE
     ORDER BY last_seen_at DESC`,
    [Number(userId)]
  );

  return r.rows
    .map((row) => String(row.push_token || "").trim())
    .filter(Boolean);
}

