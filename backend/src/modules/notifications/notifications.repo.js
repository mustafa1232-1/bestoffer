import { q } from "../../config/db.js";
import { emitToUser } from "../../shared/realtime/live-events.js";

function toNotificationRow(row) {
  if (!row) return null;
  return {
    ...row,
    payload: row.payload || null,
  };
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
