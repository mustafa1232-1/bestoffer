import "dotenv/config";

import { ensureSchema, q } from "../config/db.js";
import { env, validateRuntimeEnv } from "../config/env.js";

async function run() {
  validateRuntimeEnv();
  await ensureSchema();

  const findings = [];

  if (env.isProduction) {
    if (env.superAdminPin === "1998") {
      findings.push("SUPER_ADMIN_PIN is using default value (1998).");
    }
    if (env.superAdminPhone === "07746515247") {
      findings.push("SUPER_ADMIN_PHONE is using default value.");
    }
  }

  const staleSessions = await q(
    `SELECT COUNT(*)::int AS total
     FROM user_session
     WHERE is_revoked = FALSE
       AND expires_at < NOW()`
  );
  const staleCount = Number(staleSessions.rows[0]?.total || 0);
  if (staleCount > 0) {
    findings.push(`Found ${staleCount} expired non-revoked sessions (cleanup recommended).`);
  }

  const lockedUsers = await q(
    `SELECT COUNT(*)::int AS total
     FROM app_user
     WHERE locked_until IS NOT NULL
       AND locked_until > NOW()`
  );

  console.log("[security-check] active_locked_users:", Number(lockedUsers.rows[0]?.total || 0));
  console.log("[security-check] findings:", findings.length);
  for (const item of findings) {
    console.log(" -", item);
  }

  if (findings.length > 0) {
    process.exitCode = 1;
  }
}

run().catch((error) => {
  console.error("[security-check] failed:", error);
  process.exit(1);
});
