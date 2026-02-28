import "dotenv/config";
import os from "os";

import { app } from "./app.js";
import { ensureSchema, pool, q } from "./config/db.js";
import { env, validateRuntimeEnv } from "./config/env.js";
import { runSqlMigrations } from "./config/sqlMigrations.js";
import { startTaxiLifecycleWorker } from "./modules/taxi/taxi.service.js";
import { hashPin } from "./shared/utils/hash.js";

const port = env.port;
const host = env.host;

async function ensureSuperAdminAccount() {
  const superPhone = String(env.superAdminPhone || "").trim();
  const superPin = String(env.superAdminPin || "").trim();
  const superName = String(env.superAdminName || "Super Admin").trim();

  if (!/^\d{8,20}$/.test(superPhone) || !/^\d{4,8}$/.test(superPin)) {
    console.warn("[seed] skipped super admin seeding due to invalid phone/pin.");
    return;
  }

  const pinHash = await hashPin(superPin);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `UPDATE app_user
       SET is_super_admin = FALSE
       WHERE is_super_admin = TRUE`
    );

    await client.query(
      `INSERT INTO app_user
        (
          full_name,
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
       VALUES ($1,$2,$3,'A','1','1','admin',TRUE,TRUE,'system_seed_v1',NOW())
       ON CONFLICT (phone)
       DO UPDATE SET
         full_name = EXCLUDED.full_name,
         pin_hash = EXCLUDED.pin_hash,
         role = 'admin',
         is_super_admin = TRUE,
         analytics_consent_granted = TRUE,
         analytics_consent_version = 'system_seed_v1',
         analytics_consent_granted_at = COALESCE(
           app_user.analytics_consent_granted_at,
           NOW()
         )`,
      [superName, superPhone, pinHash]
    );

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }

  const seeded = await q(
    `SELECT id
     FROM app_user
     WHERE phone = $1
     LIMIT 1`,
    [superPhone]
  );

  const superAdminUserId = seeded.rows[0]?.id;
  if (superAdminUserId) {
    console.log(
      `[seed] Super admin ready -> phone: ${superPhone}, userId: ${superAdminUserId}`
    );
  }
}

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
  validateRuntimeEnv();
  await runSqlMigrations();
  await ensureSchema();
  await ensureSuperAdminAccount();
  await ensureDevAdmin();
  startTaxiLifecycleWorker();

  const server = app.listen(port, host, () => {
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

  server.requestTimeout = env.requestTimeoutMs;
  server.headersTimeout = env.requestTimeoutMs + 1000;
}

start().catch((err) => {
  console.error("Failed to start server:", err);
  process.exit(1);
});
