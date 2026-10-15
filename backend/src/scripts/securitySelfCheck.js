import "dotenv/config";

import { ensureSchema, pool, q } from "../config/db.js";
import { env, validateRuntimeEnv } from "../config/env.js";

async function run() {
  validateRuntimeEnv();
  await ensureSchema();

  const findings = [];

  if (env.isProduction) {
    if (!/^\d{8,20}$/.test(env.superAdminPhone)) {
      findings.push("SUPER_ADMIN_PHONE is missing or invalid.");
    }
    if (!/^\d{8}$/.test(env.superAdminPin)) {
      findings.push("SUPER_ADMIN_PIN must be an 8-digit deployment secret.");
    }
    if (!/^\d{8,20}$/.test(env.servicesOperatorPhone)) {
      findings.push("SERVICES_OPERATOR_PHONE is missing or invalid.");
    }
    if (!/^\d{8}$/.test(env.servicesOperatorPin)) {
      findings.push("SERVICES_OPERATOR_PIN must be an 8-digit deployment secret.");
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

run()
  .catch((error) => {
    console.error("[security-check] failed:", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    // CLI checks must release the pool so CI and release verification can exit.
    await pool.end();
  });
