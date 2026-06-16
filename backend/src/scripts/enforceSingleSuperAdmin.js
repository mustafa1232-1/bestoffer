import "dotenv/config";

import { ensureSchema, pool } from "../config/db.js";
import { hashPin } from "../shared/utils/hash.js";

function normalizeDigits(value) {
  return String(value || "")
    .replace(/[\u0660-\u0669]/g, (digit) =>
      String(digit.charCodeAt(0) - 0x0660)
    )
    .replace(/[\u06F0-\u06F9]/g, (digit) =>
      String(digit.charCodeAt(0) - 0x06f0)
    );
}

function normalizePhone(value) {
  return normalizeDigits(value).replace(/[^\d]/g, "");
}

function normalizePin(value) {
  return normalizeDigits(value).replace(/[^\d]/g, "");
}

function buildSeedUsername(prefix, phone) {
  const digits = String(phone || "").replace(/\D+/g, "");
  const suffix = digits.slice(-6) || "000000";
  let username = `${prefix}.${suffix}`
    .toLowerCase()
    .replace(/[^a-z0-9._]+/g, ".")
    .replace(/[._]{2,}/g, ".")
    .replace(/^[._]+|[._]+$/g, "");

  if (username.length < 4) username = `user.${suffix}`.slice(0, 24);
  if (username.length > 24) {
    username = username.slice(0, 24).replace(/[._]+$/g, "");
  }
  if (!/^[a-z0-9]/.test(username)) username = `u${username}`.slice(0, 24);
  if (!/[a-z0-9]$/.test(username)) username = `${username}0`.slice(0, 24);
  if (username.length < 4) username = username.padEnd(4, "0");
  return username;
}

async function run() {
  const targetPhone = normalizePhone(
    process.argv[2] || process.env.SUPER_ADMIN_PHONE || "07746515247"
  );
  const targetPin = normalizePin(
    process.argv[3] || process.env.SUPER_ADMIN_PIN || "1998"
  );
  const targetName = String(
    process.argv[4] || process.env.SUPER_ADMIN_NAME || "Super Admin"
  ).trim() || "Super Admin";
  const targetUsername = buildSeedUsername("maslaki.admin", targetPhone);

  if (!/^\d{8,20}$/.test(targetPhone)) {
    throw new Error("TARGET_SUPER_ADMIN_PHONE_INVALID");
  }
  if (!/^\d{4,8}$/.test(targetPin)) {
    throw new Error("TARGET_SUPER_ADMIN_PIN_INVALID");
  }

  await ensureSchema();
  const pinHash = await hashPin(targetPin);

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const before = await client.query(
      `SELECT id, phone, role, is_super_admin
       FROM app_user
       WHERE is_super_admin = TRUE OR role::text = 'super_admin'
       ORDER BY id ASC`
    );

    const demotedRows = await client.query(
      `UPDATE app_user
       SET is_super_admin = FALSE,
           role = CASE
             WHEN role::text = 'super_admin' THEN 'admin'::user_role
             ELSE role
           END
       WHERE phone <> $1
         AND (is_super_admin = TRUE OR role::text = 'super_admin')
       RETURNING id`,
      [targetPhone]
    );

    await client.query(
      `INSERT INTO app_user
        (
          full_name,
          username,
          phone,
          pin_hash,
          block,
          building_number,
          apartment,
          role,
          is_super_admin,
          analytics_consent_granted,
          analytics_consent_version,
          analytics_consent_granted_at,
          is_account_disabled
        )
       VALUES ($1,$2,$3,$4,'A','1','1','admin',TRUE,TRUE,'system_seed_v1',NOW(),FALSE)
       ON CONFLICT (phone)
       DO UPDATE SET
         full_name = EXCLUDED.full_name,
         username = COALESCE(NULLIF(app_user.username, ''), EXCLUDED.username),
         pin_hash = EXCLUDED.pin_hash,
         role = 'admin',
         is_super_admin = TRUE,
         is_account_disabled = FALSE,
         analytics_consent_granted = TRUE,
         analytics_consent_version = 'system_seed_v1',
         analytics_consent_granted_at = COALESCE(
           app_user.analytics_consent_granted_at,
           NOW()
         )`,
      [targetName, targetUsername, targetPhone, pinHash]
    );

    const demotedIds = demotedRows.rows
      .map((row) => Number(row.id))
      .filter((id) => Number.isFinite(id) && id > 0);
    if (demotedIds.length > 0) {
      await client.query(
        `UPDATE user_session
         SET is_revoked = TRUE,
             revoked_reason = COALESCE(revoked_reason, 'single_super_admin_enforced'),
             revoked_at = COALESCE(revoked_at, NOW()),
             updated_at = NOW()
         WHERE is_revoked = FALSE
           AND user_id = ANY($1::bigint[])`,
        [demotedIds]
      );
    }

    const after = await client.query(
      `SELECT id, phone, role, is_super_admin
       FROM app_user
       WHERE is_super_admin = TRUE OR role::text = 'super_admin'
       ORDER BY id ASC`
    );

    await client.query("COMMIT");

    console.log(
      `[single-super-admin] targetPhone=${targetPhone} before=${before.rowCount} after=${after.rowCount} demoted=${demotedIds.length}`
    );
    for (const row of after.rows) {
      console.log(
        `[single-super-admin] active id=${row.id} phone=${row.phone} role=${row.role} is_super_admin=${row.is_super_admin}`
      );
    }
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

run().catch((error) => {
  console.error("[single-super-admin] failed:", error);
  process.exit(1);
});
