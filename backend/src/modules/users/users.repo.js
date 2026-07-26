import { pool } from "../../config/db.js";
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

async function tableExists(client, tableName) {
  const r = await client.query(
    `SELECT to_regclass($1) AS table_name`,
    [`public.${String(tableName || "").trim()}`]
  );
  return r.rows[0]?.table_name != null;
}

async function existingColumns(client, tableName) {
  const r = await client.query(
    `SELECT column_name
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = $1`,
    [String(tableName || "").trim()]
  );
  return new Set(r.rows.map((row) => String(row.column_name)));
}

function pushSet(parts, columns, column, expression) {
  if (columns.has(column)) parts.push(`${column} = ${expression}`);
}

async function updateIfTable(client, tableName, sql, params = []) {
  if (!(await tableExists(client, tableName))) return { rowCount: 0 };
  return client.query(sql, params);
}

export async function deleteMyAccountData({
  userId,
  note = null,
  anonymizedPinHash,
}) {
  const normalizedUserId = Number(userId);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const userResult = await client.query(
      `SELECT *
       FROM app_user
       WHERE id = $1
       FOR UPDATE`,
      [normalizedUserId]
    );
    const user = userResult.rows[0] || null;
    if (!user) {
      await client.query("ROLLBACK");
      return null;
    }

    if (
      user.account_deleted === true ||
      user.account_deletion_completed_at != null
    ) {
      await client.query("COMMIT");
      return {
        user,
        alreadyDeleted: true,
        sessionsRevoked: 0,
        pushTokensInvalidated: 0,
      };
    }

    const columns = await existingColumns(client, "app_user");
    const deletedPhone = `deleted_${normalizedUserId}`;
    const deletedUsername = `deleted_${normalizedUserId}`.slice(0, 24);
    const disabledNote =
      String(note || "").trim() ||
      "Account permanently deleted by user request";
    const setParts = [
      "is_account_disabled = TRUE",
      "full_name = 'Deleted account'",
      "phone = $2",
      "pin_hash = $3",
      "block = 'deleted'",
      "building_number = 'deleted'",
      "apartment = 'deleted'",
      "updated_at = NOW()",
    ];
    pushSet(setParts, columns, "image_url", "NULL");
    pushSet(setParts, columns, "username", "$4");
    pushSet(setParts, columns, "social_bio", "''");
    pushSet(setParts, columns, "work_title", "NULL");
    pushSet(setParts, columns, "work_company", "NULL");
    pushSet(setParts, columns, "social_show_phone", "FALSE");
    pushSet(setParts, columns, "social_posts_public", "FALSE");
    pushSet(setParts, columns, "social_stories_public", "FALSE");
    pushSet(setParts, columns, "social_relations_public", "FALSE");
    pushSet(setParts, columns, "is_private_account", "TRUE");
    pushSet(setParts, columns, "account_disabled_note", "$5");
    pushSet(setParts, columns, "account_disabled_by_user_id", "$1");
    pushSet(setParts, columns, "account_disabled_at", "NOW()");
    pushSet(setParts, columns, "account_deleted", "TRUE");
    pushSet(setParts, columns, "account_deleted_at", "NOW()");
    pushSet(setParts, columns, "account_deletion_requested_at", "NOW()");
    pushSet(setParts, columns, "account_deletion_completed_at", "NOW()");
    pushSet(setParts, columns, "account_deletion_status", "'completed'");
    pushSet(setParts, columns, "account_deletion_note", "$5");
    pushSet(
      setParts,
      columns,
      "account_deletion_retention_policy_version",
      "'account_deletion_v1'"
    );

    const updatedUser = await client.query(
      `UPDATE app_user
       SET ${setParts.join(",\n           ")}
       WHERE id = $1
       RETURNING *`,
      [
        normalizedUserId,
        deletedPhone,
        anonymizedPinHash,
        deletedUsername,
        disabledNote,
      ]
    );

    const sessions = await client.query(
      `UPDATE user_session
       SET is_revoked = TRUE,
           revoked_reason = 'account_deleted',
           revoked_at = COALESCE(revoked_at, NOW()),
           updated_at = NOW()
       WHERE user_id = $1
         AND COALESCE(is_revoked, FALSE) = FALSE`,
      [normalizedUserId]
    );

    let pushTokensInvalidated = 0;
    if (await tableExists(client, "user_push_token")) {
      const pushColumns = await existingColumns(client, "user_push_token");
      const pushSet = ["is_active = FALSE", "updated_at = NOW()"];
      pushSet.push("last_seen_at = NOW()");
      if (pushColumns.has("auth_session_id")) pushSet.push("auth_session_id = NULL");
      if (pushColumns.has("device_model")) pushSet.push("device_model = NULL");
      if (pushColumns.has("app_version")) pushSet.push("app_version = NULL");
      if (pushColumns.has("locale")) pushSet.push("locale = NULL");
      if (pushColumns.has("push_token")) {
        pushSet.push("push_token = CONCAT('deleted:', id::text)");
      }
      const r = await client.query(
        `UPDATE user_push_token
         SET ${pushSet.join(", ")}
         WHERE user_id = $1`,
        [normalizedUserId]
      );
      pushTokensInvalidated = r.rowCount || 0;
    }

    await updateIfTable(
      client,
      "service_provider_profiles",
      `UPDATE service_provider_profiles
       SET is_active = FALSE,
           provider_approval_status = 'suspended',
           business_name = 'Deleted provider',
           bio = NULL,
           phone = 'deleted',
           whatsapp_phone = NULL,
           city = 'deleted',
           area = NULL,
           address_line = NULL,
           logo_url = NULL,
           cover_image_url = NULL,
           search_text = '',
           approval_note = 'Account deleted by user',
           is_temporarily_paused = TRUE,
           updated_at = NOW()
       WHERE user_id = $1`,
      [normalizedUserId]
    );
    await updateIfTable(
      client,
      "service_offerings",
      `UPDATE service_offerings o
       SET is_active = FALSE,
           moderation_status = CASE
             WHEN moderation_status IN ('pending', 'approved', 'rejected', 'changes_requested', 'hidden')
             THEN 'hidden'
             ELSE moderation_status
           END,
           search_text = '',
           updated_at = NOW()
       FROM service_provider_profiles p
       WHERE o.provider_id = p.id
         AND p.user_id = $1`,
      [normalizedUserId]
    );
    await updateIfTable(
      client,
      "service_provider_employee_profile",
      `UPDATE service_provider_employee_profile
       SET is_active = FALSE,
           archived_at = COALESCE(archived_at, NOW()),
           notes = COALESCE(notes, 'Archived because user account was deleted'),
           updated_at = NOW()
       WHERE employee_user_id = $1`,
      [normalizedUserId]
    );
    await updateIfTable(
      client,
      "taxi_captain_profile",
      `UPDATE taxi_captain_profile
       SET is_active = FALSE,
           profile_image_url = NULL,
           car_image_url = NULL,
           updated_at = NOW()
       WHERE user_id = $1`,
      [normalizedUserId]
    );
    await updateIfTable(
      client,
      "taxi_captain_presence",
      `UPDATE taxi_captain_presence
       SET is_online = FALSE,
           updated_at = NOW()
       WHERE captain_user_id = $1`,
      [normalizedUserId]
    );
    await updateIfTable(
      client,
      "courier_profile",
      `UPDATE courier_profile
       SET active_status = FALSE,
           availability_status = 'offline',
           updated_at = NOW()
       WHERE user_id = $1`,
      [normalizedUserId]
    );
    await updateIfTable(
      client,
      "merchant_delivery_agent",
      `UPDATE merchant_delivery_agent
       SET is_active = FALSE,
           updated_at = NOW()
       WHERE delivery_user_id = $1`,
      [normalizedUserId]
    );
    await updateIfTable(
      client,
      "merchant_employee_profile",
      `UPDATE merchant_employee_profile
       SET is_active = FALSE,
           notes = COALESCE(notes, 'Archived because user account was deleted'),
           updated_at = NOW()
       WHERE employee_user_id = $1`,
      [normalizedUserId]
    );
    await updateIfTable(
      client,
      "company_user",
      `UPDATE company_user
       SET is_active = FALSE,
           updated_at = NOW()
       WHERE user_id = $1`,
      [normalizedUserId]
    );

    await client.query("COMMIT");
    return {
      user: updatedUser.rows[0] || null,
      alreadyDeleted: false,
      sessionsRevoked: sessions.rowCount || 0,
      pushTokensInvalidated,
    };
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // ignore rollback errors
    }
    throw error;
  } finally {
    client.release();
  }
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
