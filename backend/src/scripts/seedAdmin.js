import "dotenv/config";

import { ensureSchema, q } from "../config/db.js";
import { env } from "../config/env.js";
import { allocateRegistrationUsername } from "../modules/auth/auth.service.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";
import { hashPin } from "../shared/utils/hash.js";

function getArg(index, fallback = "") {
  return String(process.argv[index] ?? fallback).trim();
}

const adminPhone = getArg(2, process.env.SEED_ADMIN_PHONE);
const adminPin = getArg(3, process.env.SEED_ADMIN_PIN);
const adminName = getArg(4, process.env.SEED_ADMIN_NAME || "Admin");

if (!/^\d{4,20}$/.test(adminPhone)) {
  console.error("Usage: npm run seed:admin -- <PHONE> <PIN> [NAME]");
  process.exit(1);
}

if (!/^\d{4,8}$/.test(adminPin)) {
  console.error("PIN must be 4 to 8 digits.");
  process.exit(1);
}

async function run() {
  await runSqlMigrations({ force: true });
  await ensureSchema();

  const pinHash = await hashPin(adminPin);
  const username = await allocateRegistrationUsername({
    fullName: adminName,
    phone: adminPhone,
  });
  const normalizedSeedPhone = String(adminPhone).replace(/[^\d]/g, "");
  const normalizedSuperPhone = String(env.superAdminPhone || "").replace(/[^\d]/g, "");
  const isConfiguredSuperAdmin =
    normalizedSeedPhone.length > 0 && normalizedSeedPhone === normalizedSuperPhone;

  await q(
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
        analytics_consent_granted_at
      )
     VALUES ($1,$2,$3,$4,'A','1','1','admin',$5,TRUE,'system_seed_v1',NOW())
     ON CONFLICT (phone)
     DO UPDATE
       SET full_name = EXCLUDED.full_name,
           username = COALESCE(NULLIF(app_user.username, ''), EXCLUDED.username),
           pin_hash = EXCLUDED.pin_hash,
           role = 'admin',
           is_super_admin = app_user.is_super_admin OR EXCLUDED.is_super_admin,
           analytics_consent_granted = TRUE,
           analytics_consent_version = 'system_seed_v1',
           analytics_consent_granted_at = COALESCE(
             app_user.analytics_consent_granted_at,
             NOW()
           )`,
    [adminName, username, adminPhone, pinHash, isConfiguredSuperAdmin]
  );

  console.log(
    `[seed] Admin ready -> phone: ${adminPhone}, isSuperAdmin: ${isConfiguredSuperAdmin}`
  );
}

run().catch((error) => {
  console.error("[seed] failed:", error);
  process.exit(1);
});
