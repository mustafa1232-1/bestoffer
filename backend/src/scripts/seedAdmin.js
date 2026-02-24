import "dotenv/config";

import { ensureSchema, q } from "../config/db.js";
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
  await q(
    `INSERT INTO app_user
      (full_name, phone, pin_hash, block, building_number, apartment, role)
     VALUES ($1,$2,$3,'A','1','1','admin')
     ON CONFLICT (phone)
     DO UPDATE
       SET full_name = EXCLUDED.full_name,
           pin_hash = EXCLUDED.pin_hash,
           role = 'admin'`,
    [adminName, adminPhone, pinHash]
  );

  console.log(`[seed] Admin ready -> phone: ${adminPhone}`);
}

run().catch((error) => {
  console.error("[seed] failed:", error);
  process.exit(1);
});
