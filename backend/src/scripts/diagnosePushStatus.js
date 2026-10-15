import {
  getPushConfigStatus,
  getPushTokenPresence,
} from "../modules/notifications/notifications.repo.js";
import { pool } from "../config/db.js";

async function main() {
  const config = getPushConfigStatus();
  const tokenPresence = await getPushTokenPresence();

  const bySurface = await pool.query(
    `SELECT
       COALESCE(NULLIF(upt.app_surface, ''), 'unknown') AS app_surface,
       COALESCE(NULLIF(upt.platform, ''), 'unknown') AS platform,
       COUNT(*) FILTER (WHERE is_active)::int AS active_tokens,
       COUNT(*) FILTER (
         WHERE upt.is_active = TRUE
           AND us.id IS NOT NULL
           AND us.revoked_at IS NULL
           AND us.expires_at > NOW()
       )::int AS sendable_tokens,
       MAX(upt.last_seen_at) AS last_seen_at
     FROM user_push_token upt
     LEFT JOIN user_session us
       ON us.id = upt.auth_session_id
      AND us.user_id = upt.user_id
     GROUP BY COALESCE(NULLIF(upt.app_surface, ''), 'unknown'),
              COALESCE(NULLIF(upt.platform, ''), 'unknown')
     ORDER BY app_surface, platform`
  );

  const recentDeliveryEvents = await pool.query(
    `SELECT
       event_status,
       COALESCE(NULLIF(platform, ''), 'unknown') AS platform,
       COUNT(*)::int AS count,
       MAX(created_at) AS latest_at
     FROM notification_delivery_event
     WHERE created_at >= NOW() - INTERVAL '24 hours'
     GROUP BY event_status, COALESCE(NULLIF(platform, ''), 'unknown')
     ORDER BY event_status, platform`
  ).catch(() => ({ rows: [] }));

  console.log(
    JSON.stringify(
      {
        config,
        tokenPresence,
        tokensBySurface: bySurface.rows,
        deliveryEvents24h: recentDeliveryEvents.rows,
      },
      null,
      2
    )
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
