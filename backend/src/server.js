import "dotenv/config";
import os from "os";

import { app } from "./app.js";
import { ensureSchema, q } from "./config/db.js";
import { runSqlMigrations } from "./config/sqlMigrations.js";
import { hashPin } from "./shared/utils/hash.js";

const port = process.env.PORT || 3000;
const host = process.env.HOST || "0.0.0.0";

async function ensureDevAdmin() {
  if (process.env.NODE_ENV === "production") return;
  if (process.env.DEV_SEED_ADMIN === "false") return;

  const adminPhone = String(
    process.env.DEV_ADMIN_PHONE || "07701234567"
  ).trim();
  const adminPin = String(process.env.DEV_ADMIN_PIN || "1234").trim();
  const adminName = String(process.env.DEV_ADMIN_NAME || "Admin").trim();

  if (!/^\d{4,20}$/.test(adminPhone) || !/^\d{4,8}$/.test(adminPin)) {
    console.warn("[seed] skipped DEV admin seeding due to invalid phone/pin.");
    return;
  }

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

  console.log(`[seed] Dev admin ready -> phone: ${adminPhone}, pin: ${adminPin}`);
}

async function start() {
  await runSqlMigrations();
  await ensureSchema();
  await ensureDevAdmin();

  app.listen(port, host, () => {
    console.log(`Server running on http://${host}:${port}`);

    const ifaces = os.networkInterfaces();
    const ipv4 = [];
    for (const entries of Object.values(ifaces)) {
      for (const entry of entries || []) {
        if (entry.family === "IPv4" && !entry.internal) {
          ipv4.push(entry.address);
        }
      }
    }
    if (ipv4.length) {
      console.log(`[net] LAN IPv4: ${ipv4.join(", ")}`);
    }
  });
}

start().catch((err) => {
  console.error("Failed to start server:", err);
  process.exit(1);
});
