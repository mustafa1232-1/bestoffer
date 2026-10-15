import admin from "firebase-admin";
import pg from "pg";

const args = new Set(process.argv.slice(2));
const shouldSend = args.has("--send");
const releaseVersion = String(
  process.env.WEB_RELEASE_VERSION || "1.0.11+57-web-20261011-1830",
).trim();
const updateUrl = "https://maslaki-app.web.app/";
const title = "تحديث إجباري لتطبيق مسلكي";
const body =
  "تم نشر تحسينات وإصلاحات جديدة. افتح مسلكي واضغط «تحديث الآن» لاستخدام أحدث نسخة.";

function loadFirebaseCredential() {
  const raw = String(process.env.FIREBASE_SERVICE_ACCOUNT_JSON || "").trim();
  if (raw) {
    const parsed = JSON.parse(raw);
    parsed.private_key = String(parsed.private_key || "").replace(/\\n/g, "\n");
    return admin.credential.cert(parsed);
  }

  const projectId = String(process.env.FIREBASE_PROJECT_ID || "").trim();
  const clientEmail = String(process.env.FIREBASE_CLIENT_EMAIL || "").trim();
  const privateKey = String(process.env.FIREBASE_PRIVATE_KEY || "")
    .replace(/\\n/g, "\n")
    .trim();
  if (!projectId || !clientEmail || !privateKey) return null;
  return admin.credential.cert({ projectId, clientEmail, privateKey });
}

function chunk(items, size) {
  const chunks = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

const databaseUrl = String(process.env.DATABASE_URL || "").trim();
if (!databaseUrl) throw new Error("DATABASE_URL is required");

const pool = new pg.Pool({
  connectionString: databaseUrl,
  ssl: { rejectUnauthorized: false },
  max: 3,
});

try {
  const distributionResult = await pool.query(`
    SELECT
      COALESCE(NULLIF(LOWER(upt.platform), ''), 'unknown') AS platform,
      COALESCE(NULLIF(LOWER(upt.app_surface), ''), 'unknown') AS app_surface,
      CASE
        WHEN COALESCE(us.user_agent, '') ~* '(iphone|ipad|ipod)' THEN 'apple_mobile'
        WHEN COALESCE(us.user_agent, '') ~* 'android' THEN 'android'
        ELSE 'other'
      END AS client_family,
      COUNT(*)::int AS tokens,
      COUNT(DISTINCT upt.user_id)::int AS users
    FROM user_push_token upt
    JOIN app_user u ON u.id = upt.user_id
    JOIN user_session us
      ON us.id = upt.auth_session_id
     AND us.user_id = upt.user_id
    WHERE upt.is_active = TRUE
      AND us.revoked_at IS NULL
      AND us.expires_at > NOW()
      AND u.role = 'user'
      AND COALESCE(u.account_deleted, FALSE) = FALSE
      AND COALESCE(u.is_account_disabled, FALSE) = FALSE
    GROUP BY 1,2,3
    ORDER BY 1,2,3
  `);

  const targetResult = await pool.query(`
    SELECT DISTINCT ON (upt.push_token)
      upt.id AS token_id,
      upt.user_id,
      upt.push_token,
      LOWER(COALESCE(upt.platform, '')) AS platform
    FROM user_push_token upt
    JOIN app_user u ON u.id = upt.user_id
    JOIN user_session us
      ON us.id = upt.auth_session_id
     AND us.user_id = upt.user_id
    WHERE upt.is_active = TRUE
      AND us.revoked_at IS NULL
      AND us.expires_at > NOW()
      AND u.role = 'user'
      AND COALESCE(u.account_deleted, FALSE) = FALSE
      AND COALESCE(u.is_account_disabled, FALSE) = FALSE
      AND COALESCE(NULLIF(LOWER(upt.app_surface), ''), LOWER(us.app_surface), 'user') = 'user'
      AND (
        LOWER(COALESCE(upt.platform, '')) IN ('ios', 'iphone', 'ipad')
        OR COALESCE(us.user_agent, '') ~* '(iphone|ipad|ipod)'
      )
    ORDER BY upt.push_token, upt.last_seen_at DESC
  `);

  const iosUserResult = await pool.query(`
    SELECT DISTINCT u.id AS user_id
    FROM user_session us
    JOIN app_user u ON u.id = us.user_id
    WHERE us.revoked_at IS NULL
      AND us.expires_at > NOW()
      AND u.role = 'user'
      AND COALESCE(u.account_deleted, FALSE) = FALSE
      AND COALESCE(u.is_account_disabled, FALSE) = FALSE
      AND COALESCE(us.user_agent, '') ~* '(iphone|ipad|ipod)'
    ORDER BY u.id
  `);

  const targets = targetResult.rows;
  const userIds = iosUserResult.rows.map((row) => Number(row.user_id));
  const inboxAuditResult = await pool.query(
    `SELECT COUNT(*)::int AS notifications,
            COUNT(DISTINCT user_id)::int AS users
     FROM app_notification
     WHERE type = 'system.app_update.required'
       AND payload->>'releaseVersion' = $1`,
    [releaseVersion],
  );
  const inboxAudit = inboxAuditResult.rows[0] || {};
  console.log(
    JSON.stringify(
      {
        releaseVersion,
        mode: shouldSend ? "send" : "dry-run",
        distribution: distributionResult.rows,
        targetUsers: userIds.length,
        targetTokens: targets.length,
        existingInboxNotifications: Number(inboxAudit.notifications || 0),
        existingInboxUsers: Number(inboxAudit.users || 0),
      },
      null,
      2,
    ),
  );

  if (!shouldSend || userIds.length === 0) process.exitCode = 0;
  else {
    let messaging = null;
    if (targets.length > 0) {
      const credential = loadFirebaseCredential();
      if (!credential) throw new Error("Firebase service account is not configured");
      if (!admin.apps.length) admin.initializeApp({ credential });
      messaging = admin.messaging();
    }

    const hasEventId = Boolean(
      (
        await pool.query(`
          SELECT 1
          FROM information_schema.columns
          WHERE table_schema = current_schema()
            AND table_name = 'app_notification'
            AND column_name = 'event_id'
          LIMIT 1
        `)
      ).rowCount,
    );

    let inboxCreated = 0;
    for (const userId of userIds) {
      const eventId = `mandatory_ios_web_update:${releaseVersion}:${userId}`;
      const payload = {
        target: "notifications",
        targetModule: "customer",
        appSurface: "user",
        roleScope: "customer",
        updateUrl,
        releaseVersion,
        mandatory: true,
        requiresAction: true,
        actionable: true,
        eventId,
      };
      const insertResult = hasEventId
        ? await pool.query(
            `INSERT INTO app_notification
              (user_id, type, title, body, payload, event_id)
             VALUES ($1,$2,$3,$4,$5::jsonb,$6)
             ON CONFLICT (event_id) WHERE event_id IS NOT NULL DO NOTHING
             RETURNING id`,
            [
              userId,
              "system.app_update.required",
              title,
              body,
              JSON.stringify(payload),
              eventId,
            ],
          )
        : await pool.query(
            `INSERT INTO app_notification (user_id, type, title, body, payload)
             SELECT $1,$2,$3,$4,$5::jsonb
             WHERE NOT EXISTS (
               SELECT 1 FROM app_notification
               WHERE user_id = $1
                 AND type = $2
                 AND payload->>'releaseVersion' = $6
             )
             RETURNING id`,
            [
              userId,
              "system.app_update.required",
              title,
              body,
              JSON.stringify(payload),
              releaseVersion,
            ],
          );
      inboxCreated += insertResult.rowCount || 0;
    }

    let accepted = 0;
    let failed = 0;
    let dead = 0;
    const deadTokens = [];
    for (const targetChunk of chunk(targets, 500)) {
      const response = await messaging.sendEachForMulticast({
        tokens: targetChunk.map((row) => row.push_token),
        notification: { title, body },
        data: {
          type: "system.app_update.required",
          target: "notifications",
          targetModule: "customer",
          appSurface: "user",
          roleScope: "customer",
          updateUrl,
          releaseVersion,
          mandatory: "true",
          requiresAction: "true",
          actionable: "true",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "maslaki_action_required_v2",
            sound: "default",
          },
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { sound: "default", "content-available": 1 } },
        },
        webpush: {
          headers: { Urgency: "high" },
          notification: {
            icon: "/icons/Icon-192.png",
            badge: "/icons/Icon-192.png",
            requireInteraction: true,
            tag: `mandatory-update-${releaseVersion}`,
          },
          fcmOptions: { link: updateUrl },
        },
      });

      accepted += response.successCount;
      failed += response.failureCount;
      response.responses.forEach((result, index) => {
        if (result.success) return;
        const code = String(result.error?.code || "");
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          dead += 1;
          deadTokens.push(targetChunk[index].push_token);
        }
      });
    }

    if (deadTokens.length) {
      await pool.query(
        `UPDATE user_push_token
         SET is_active = FALSE, updated_at = NOW()
         WHERE push_token = ANY($1::text[])`,
        [deadTokens],
      );
    }

    console.log(
      JSON.stringify(
        {
          sent: true,
          releaseVersion,
          inboxCreated,
          targetedUsers: userIds.length,
          targetedTokens: targets.length,
          accepted,
          failed,
          deadTokensDeactivated: dead,
        },
        null,
        2,
      ),
    );
  }
} finally {
  await pool.end();
}
