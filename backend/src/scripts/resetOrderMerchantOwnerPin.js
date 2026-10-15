import "dotenv/config";
import { randomInt } from "node:crypto";
import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";
import { hashPin, verifyPin } from "../shared/utils/hash.js";
import { invalidateSessionAccessCacheForUser, markSessionRevoked, markUserSessionsRevokedAfter }
  from "../shared/middleware/access-auth.js";

const orderId = Number(process.argv[2]);
const execute = process.argv.includes("--execute");
const expectedMerchantId = Number(process.env.RESET_EXPECTED_MERCHANT_ID);
const expectedOwnerId = Number(process.env.RESET_EXPECTED_OWNER_ID);
let client;
try {
  if (!Number.isSafeInteger(orderId) || orderId <= 0) throw new Error("ORDER_ID_REQUIRED");
  client = await pool.connect();
  await client.query("BEGIN");
  const result = await client.query(`SELECT o.id AS order_id, o.status AS order_status,
    m.id AS merchant_id, m.name AS merchant_name, m.owner_user_id,
    u.phone, u.role, u.is_account_disabled, u.is_super_admin,
    u.failed_login_attempts, u.locked_until, u.must_change_pin,
    (SELECT COUNT(*)::int FROM merchant other WHERE other.owner_user_id=u.id) AS linked_merchants
    FROM customer_order o JOIN merchant m ON m.id=o.merchant_id
    JOIN app_user u ON u.id=m.owner_user_id WHERE o.id=$1 FOR UPDATE OF u, m`, [orderId]);
  const target = result.rows[0];
  if (!target) throw new Error("ORDER_OWNER_NOT_FOUND");
  console.log(JSON.stringify({ execute, target }));
  if (!execute) {
    await client.query("ROLLBACK");
  } else {
    if (Number(target.merchant_id) !== expectedMerchantId || Number(target.owner_user_id) !== expectedOwnerId) {
      throw new Error("EXPECTED_OWNER_MISMATCH");
    }
    if (target.role !== "owner" || target.is_account_disabled === true || target.is_super_admin === true) {
      throw new Error("OWNER_NOT_ELIGIBLE_FOR_PIN_RESET");
    }
    const pin = String(randomInt(100000, 1000000));
    const hash = await hashPin(pin);
    const updated = await client.query(`UPDATE app_user SET pin_hash=$2, must_change_pin=TRUE,
      failed_login_attempts=0, locked_until=NULL, last_failed_login_at=NULL, updated_at=NOW()
      WHERE id=$1 RETURNING id, pin_hash`, [expectedOwnerId, hash]);
    if (updated.rowCount !== 1 || !await verifyPin(pin, updated.rows[0].pin_hash)) {
      throw new Error("PIN_VERIFICATION_FAILED");
    }
    const revoked = await client.query(`UPDATE user_session SET is_revoked=TRUE, revoked_at=NOW(),
      revoked_reason='merchant_owner_pin_reset', updated_at=NOW()
      WHERE user_id=$1 AND is_revoked=FALSE RETURNING id`, [expectedOwnerId]);
    await client.query("COMMIT");
    invalidateSessionAccessCacheForUser({ userId: expectedOwnerId });
    await markUserSessionsRevokedAfter(expectedOwnerId);
    for (const session of revoked.rows) await markSessionRevoked(Number(session.id));
    console.log(JSON.stringify({ updatedOwnerId: expectedOwnerId, temporaryPin: pin,
      pinVerified: true, mustChangePin: true, revokedSessions: revoked.rowCount }));
  }
} catch (error) {
  if (client) await client.query("ROLLBACK").catch(() => {});
  console.error(error.code || "RESET_FAILED", error.message);
  process.exitCode = 1;
} finally {
  client?.release();
  await closeRedisClient().catch(() => {});
  await pool.end();
}
