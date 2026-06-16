/* eslint-disable no-console */
import "dotenv/config";

import { q } from "../config/db.js";

async function run() {
  const before = await q(
    `SELECT COUNT(*)::int AS total
     FROM user_session
     WHERE is_revoked = FALSE
       AND expires_at < NOW()`
  );

  const staleBefore = Number(before.rows[0]?.total || 0);
  if (staleBefore <= 0) {
    console.log("[session-cleanup] no expired active sessions found.");
    return;
  }

  const updated = await q(
    `UPDATE user_session
     SET is_revoked = TRUE,
         revoked_reason = COALESCE(revoked_reason, 'expired_cleanup'),
         revoked_at = COALESCE(revoked_at, NOW()),
         updated_at = NOW()
     WHERE is_revoked = FALSE
       AND expires_at < NOW()
     RETURNING id`
  );

  console.log(
    `[session-cleanup] revoked ${updated.rowCount} expired sessions (before=${staleBefore}).`
  );
}

run().catch((error) => {
  console.error("[session-cleanup] failed:", error);
  process.exit(1);
});
