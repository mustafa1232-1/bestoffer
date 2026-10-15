import "dotenv/config";

import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";
import {
  invalidateSessionAccessCacheForUser,
  markSessionRevoked,
  markUserSessionsRevokedAfter,
} from "../shared/middleware/access-auth.js";
import { hashPin, verifyPin } from "../shared/utils/hash.js";

const CONFIRM_TOKEN = "RESET_ONE_MERCHANT_OWNER_PIN";

function readArg(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? String(process.argv[index + 1] || "").trim() : "";
}

const merchantId = Number(readArg("--merchant-id"));
const ownerId = Number(readArg("--owner-id"));
const pin = readArg("--pin").replace(/\D+/g, "");
const execute = process.argv.includes("--execute");
const confirm = readArg("--confirm");

if (!Number.isSafeInteger(merchantId) || merchantId <= 0) {
  throw new Error("MERCHANT_ID_REQUIRED");
}
if (!Number.isSafeInteger(ownerId) || ownerId <= 0) {
  throw new Error("OWNER_ID_REQUIRED");
}
if (!/^\d{4,8}$/.test(pin)) {
  throw new Error("PIN_MUST_BE_4_TO_8_DIGITS");
}

const client = await pool.connect();
let revokedSessionIds = [];
try {
  await client.query("BEGIN");
  const targetResult = await client.query(
    `SELECT
       m.id AS merchant_id,
       m.name AS merchant_name,
       m.owner_user_id,
       u.full_name,
       u.phone,
       u.role,
       COALESCE(u.is_account_disabled, FALSE) AS is_account_disabled,
       COALESCE(u.is_super_admin, FALSE) AS is_super_admin
     FROM merchant m
     JOIN app_user u ON u.id = m.owner_user_id
     WHERE m.id = $1
       AND u.id = $2
     FOR UPDATE OF m, u`,
    [merchantId, ownerId],
  );
  const target = targetResult.rows[0] || null;
  if (!target) throw new Error("MERCHANT_OWNER_PAIR_NOT_FOUND");
  if (
    target.role !== "owner" ||
    target.is_account_disabled === true ||
    target.is_super_admin === true
  ) {
    throw new Error("OWNER_NOT_ELIGIBLE_FOR_PIN_RESET");
  }

  console.log(
    JSON.stringify({
      execute,
      target: {
        merchantId: Number(target.merchant_id),
        merchantName: target.merchant_name,
        ownerId: Number(target.owner_user_id),
        ownerName: target.full_name,
        phone: target.phone,
      },
    }),
  );

  if (!execute) {
    await client.query("ROLLBACK");
  } else {
    if (confirm !== CONFIRM_TOKEN) {
      throw new Error(`MISSING_CONFIRM_${CONFIRM_TOKEN}`);
    }
    const pinHash = await hashPin(pin);
    const updated = await client.query(
      `UPDATE app_user
       SET pin_hash = $2,
           must_change_pin = FALSE,
           failed_login_attempts = 0,
           locked_until = NULL,
           last_failed_login_at = NULL,
           updated_at = NOW()
       WHERE id = $1
       RETURNING id, pin_hash`,
      [ownerId, pinHash],
    );
    if (
      updated.rowCount !== 1 ||
      !(await verifyPin(pin, updated.rows[0].pin_hash))
    ) {
      throw new Error("PIN_VERIFICATION_FAILED");
    }

    const revoked = await client.query(
      `UPDATE user_session
       SET is_revoked = TRUE,
           revoked_at = NOW(),
           revoked_reason = 'merchant_owner_pin_reset',
           updated_at = NOW()
       WHERE user_id = $1
         AND is_revoked = FALSE
       RETURNING id`,
      [ownerId],
    );
    revokedSessionIds = revoked.rows
      .map((row) => Number(row.id))
      .filter((id) => id > 0);
    await client.query("COMMIT");

    invalidateSessionAccessCacheForUser({ userId: ownerId });
    await markUserSessionsRevokedAfter(ownerId);
    for (const sessionId of revokedSessionIds) {
      await markSessionRevoked(sessionId);
    }

    console.log(
      JSON.stringify({
        updatedOwnerId: ownerId,
        pinVerified: true,
        mustChangePin: false,
        revokedSessions: revokedSessionIds.length,
      }),
    );
  }
} catch (error) {
  await client.query("ROLLBACK").catch(() => {});
  console.error(error?.code || "RESET_FAILED", error?.message || error);
  process.exitCode = 1;
} finally {
  client.release();
  await closeRedisClient().catch(() => {});
  await pool.end().catch(() => {});
}
