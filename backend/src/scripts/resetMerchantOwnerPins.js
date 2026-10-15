/* eslint-disable no-console */
import "dotenv/config";

import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";
import {
  invalidateSessionAccessCacheForUser,
  markSessionRevoked,
  markUserSessionsRevokedAfter,
} from "../shared/middleware/access-auth.js";
import { hashPin, verifyPin } from "../shared/utils/hash.js";

const CONFIRM_TOKEN = "RESET_MERCHANT_OWNER_PINS";

function parseArgs() {
  const args = process.argv.slice(2);
  const positional = [];
  const out = {
    pin: String(process.env.MERCHANT_OWNER_RESET_PIN || "").trim(),
    execute: args.includes("--execute"),
    confirm: "",
    mustChangePin: args.includes("--must-change-pin"),
    verifyOnly: args.includes("--verify-only"),
  };

  for (let i = 0; i < args.length; i += 1) {
    const key = String(args[i] || "").trim();
    const next = String(args[i + 1] || "").trim();
    if (key === "--pin" && next) {
      out.pin = next;
      i += 1;
      continue;
    }
    if (key === "--confirm" && next) {
      out.confirm = next;
      i += 1;
      continue;
    }
    if (!key.startsWith("--")) {
      positional.push(key);
    }
  }

  if (!out.pin && positional[0]) out.pin = positional[0];
  out.pin = out.pin.replace(/[^\d]/g, "");
  if (!/^\d{4,8}$/.test(out.pin)) {
    throw new Error("PIN must be 4 to 8 digits.");
  }

  return out;
}

async function listTargetOwners(client) {
  const result = await client.query(
    `SELECT DISTINCT
        u.id AS user_id,
        u.phone,
        u.full_name,
        u.pin_hash,
        u.role,
        COALESCE(u.is_super_admin, FALSE) AS is_super_admin,
        COUNT(m.id) OVER (PARTITION BY u.id) AS merchant_count
      FROM merchant m
      JOIN app_user u ON u.id = m.owner_user_id
      WHERE m.owner_user_id IS NOT NULL
        AND COALESCE(u.is_account_disabled, FALSE) = FALSE
        AND COALESCE(u.is_super_admin, FALSE) = FALSE
      ORDER BY u.id ASC`
  );
  return result.rows;
}

async function main() {
  const options = parseArgs();
  const client = await pool.connect();
  let targets = [];
  let revokedSessionIds = [];

  try {
    targets = await listTargetOwners(client);
    if (options.verifyOnly) {
      let pinOk = 0;
      for (const row of targets) {
        if (await verifyPin(options.pin, row.pin_hash)) pinOk += 1;
      }
      const activeSessions = await client.query(
        `SELECT COUNT(*)::int AS count
         FROM user_session
         WHERE is_revoked = FALSE
           AND user_id = ANY($1::bigint[])`,
        [targets.map((row) => Number(row.user_id)).filter((id) => id > 0)]
      );
      console.log(
        `[merchant-pin-reset] verify_owner_accounts=${targets.length} pin_ok=${pinOk} active_sessions=${activeSessions.rows[0]?.count ?? 0}`
      );
      return;
    }

    const pinHash = await hashPin(options.pin);
    const merchantCount = targets.reduce(
      (sum, row) => sum + Number(row.merchant_count || 0),
      0
    );
    console.log(
      `[merchant-pin-reset] target_owner_accounts=${targets.length} linked_merchants=${merchantCount} must_change_pin=${options.mustChangePin}`
    );
    for (const row of targets.slice(0, 25)) {
      console.log(
        `[merchant-pin-reset] owner=${row.user_id} phone=${row.phone || ""} name="${row.full_name || ""}" merchants=${row.merchant_count}`
      );
    }
    if (targets.length > 25) {
      console.log(`[merchant-pin-reset] showing first 25 of ${targets.length}`);
    }

    if (!options.execute) {
      console.log(
        "[merchant-pin-reset] dry-run only. Add --execute --confirm RESET_MERCHANT_OWNER_PINS to update."
      );
      return;
    }
    if (options.confirm !== CONFIRM_TOKEN) {
      throw new Error(`Missing --confirm ${CONFIRM_TOKEN}`);
    }
    if (targets.length === 0) {
      console.log("[merchant-pin-reset] no target owner accounts found.");
      return;
    }

    const userIds = targets.map((row) => Number(row.user_id)).filter((id) => id > 0);

    await client.query("BEGIN");
    const updated = await client.query(
      `UPDATE app_user
       SET pin_hash = $2,
           must_change_pin = $3,
           failed_login_attempts = 0,
           locked_until = NULL,
           last_failed_login_at = NULL,
           updated_at = NOW()
       WHERE id = ANY($1::bigint[])
       RETURNING id`,
      [userIds, pinHash, options.mustChangePin === true]
    );
    const revoked = await client.query(
      `UPDATE user_session
       SET is_revoked = TRUE,
           revoked_at = NOW(),
           revoked_reason = 'merchant_owner_pin_reset',
           updated_at = NOW()
       WHERE user_id = ANY($1::bigint[])
         AND is_revoked = FALSE
       RETURNING id, user_id`,
      [userIds]
    );
    revokedSessionIds = revoked.rows
      .map((row) => Number(row.id))
      .filter((id) => id > 0);
    await client.query("COMMIT");

    await Promise.all(
      userIds.map(async (userId) => {
        invalidateSessionAccessCacheForUser({ userId });
        await markUserSessionsRevokedAfter(userId);
      })
    );
    await Promise.all(revokedSessionIds.map((sessionId) => markSessionRevoked(sessionId)));

    console.log(
      `[merchant-pin-reset] updated_owner_accounts=${updated.rowCount || 0} revoked_sessions=${revokedSessionIds.length}`
    );
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

main()
  .catch((error) => {
    console.error(`[merchant-pin-reset] failed: ${error?.message || error}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closeRedisClient().catch(() => {});
    await pool.end().catch(() => {});
  });
