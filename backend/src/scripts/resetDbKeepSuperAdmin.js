import "dotenv/config";

import { ensureSchema, pool, q } from "../config/db.js";
import { env } from "../config/env.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";
import { hashPin } from "../shared/utils/hash.js";

function quoteIdent(identifier) {
  const normalized = String(identifier || "").trim();
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(normalized)) {
    throw new Error(`INVALID_SQL_IDENTIFIER: ${normalized}`);
  }
  return `"${normalized.replace(/"/g, "\"\"")}"`;
}

function normalizeText(value, fallback) {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function normalizeUsername(value, fallback = "super.admin") {
  const text = String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._]+/g, ".")
    .replace(/[.]{2,}/g, ".")
    .replace(/^[_\.]+|[_\.]+$/g, "");
  const candidate = text || fallback;
  return candidate.length > 24 ? candidate.slice(0, 24).replace(/^[_\.]+|[_\.]+$/g, "") : candidate;
}

function asBool(value, fallback = false) {
  if (value === true || value === false) return value;
  if (value === 1 || value === "1" || value === "true") return true;
  if (value === 0 || value === "0" || value === "false") return false;
  return fallback;
}

async function resolveSuperAdminSeed() {
  const existing = await q(
    `SELECT
       full_name,
       phone,
       pin_hash,
       block,
       building_number,
       apartment,
       image_url,
       analytics_consent_granted,
       analytics_consent_version,
       analytics_consent_granted_at
     FROM app_user
     WHERE is_super_admin = TRUE
     ORDER BY id ASC
     LIMIT 1`
  );

  if (existing.rowCount > 0) {
    const row = existing.rows[0];
    return {
      source: "existing",
      fullName: normalizeText(row.full_name, "Super Admin"),
      username: normalizeUsername("super.admin"),
      phone: normalizeText(row.phone, env.superAdminPhone || "07746515247"),
      pinHash: normalizeText(row.pin_hash, ""),
      block: normalizeText(row.block, "A"),
      buildingNumber: normalizeText(row.building_number, "1"),
      apartment: normalizeText(row.apartment, "1"),
      imageUrl: String(row.image_url || "").trim() || null,
      analyticsConsentGranted: asBool(row.analytics_consent_granted, true),
      analyticsConsentVersion: normalizeText(
        row.analytics_consent_version,
        "system_seed_v1"
      ),
      analyticsConsentGrantedAt: row.analytics_consent_granted_at || null,
    };
  }

  const phone = normalizeText(env.superAdminPhone, "");
  const pin = normalizeText(env.superAdminPin, "");
  const fullName = normalizeText(env.superAdminName, "Super Admin");

  if (!/^\d{8,20}$/.test(phone)) {
    throw new Error(
      "SUPER_ADMIN_PHONE is invalid and there is no existing super admin row."
    );
  }
  if (!/^\d{4,8}$/.test(pin)) {
    throw new Error(
      "SUPER_ADMIN_PIN is invalid and there is no existing super admin row."
    );
  }

  return {
    source: "env",
    fullName,
    username: normalizeUsername(process.env.SUPER_ADMIN_USERNAME, "super.admin"),
    phone,
    pinHash: await hashPin(pin),
    block: "A",
    buildingNumber: "1",
    apartment: "1",
    imageUrl: null,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "system_seed_v1",
    analyticsConsentGrantedAt: null,
  };
}

async function run() {
  await runSqlMigrations({ force: true });
  await ensureSchema();

  const seed = await resolveSuperAdminSeed();
  if (!seed.pinHash) {
    throw new Error(
      "Super admin pin hash is empty. Refusing to continue to avoid lockout."
    );
  }

  const client = await pool.connect();
  let txStarted = false;
  try {
    const beforeUsersResult = await client.query(
      `SELECT COUNT(*)::INT AS total FROM app_user`
    );
    const beforeUsers = Number(beforeUsersResult.rows[0]?.total || 0);

    const tablesResult = await client.query(
      `SELECT tablename
       FROM pg_tables
       WHERE schemaname = 'public'
         AND tablename <> 'schema_migration'
       ORDER BY tablename ASC`
    );

    const tableNames = tablesResult.rows
      .map((row) => String(row.tablename || "").trim())
      .filter(Boolean);

    if (!tableNames.includes("app_user")) {
      throw new Error("Table app_user not found.");
    }

    await client.query("BEGIN");
    txStarted = true;

    const quotedTables = tableNames.map(quoteIdent).join(", ");
    await client.query(`TRUNCATE TABLE ${quotedTables} RESTART IDENTITY CASCADE`);

    const insertResult = await client.query(
      `INSERT INTO app_user (
         full_name,
         username,
         phone,
         pin_hash,
         block,
         building_number,
         apartment,
         image_url,
         role,
         is_super_admin,
         analytics_consent_granted,
         analytics_consent_version,
         analytics_consent_granted_at,
         is_account_disabled,
         delivery_account_approved
       )
       VALUES (
         $1, $2, $3, $4, $5, $6, $7, $8,
         'admin', TRUE, $9, $10, COALESCE($11, NOW()), FALSE, TRUE
       )
       RETURNING id`,
      [
        seed.fullName,
        seed.username,
        seed.phone,
        seed.pinHash,
        seed.block,
        seed.buildingNumber,
        seed.apartment,
        seed.imageUrl,
        seed.analyticsConsentGranted,
        seed.analyticsConsentVersion,
        seed.analyticsConsentGrantedAt,
      ]
    );

    const superAdminId = Number(insertResult.rows[0]?.id || 0);

    await client.query("COMMIT");
    txStarted = false;

    const afterUsersResult = await client.query(
      `SELECT COUNT(*)::INT AS total FROM app_user`
    );
    const afterUsers = Number(afterUsersResult.rows[0]?.total || 0);

    console.log(
      `[reset] done -> source=${seed.source}, phone=${seed.phone}, userId=${superAdminId}, usersBefore=${beforeUsers}, usersAfter=${afterUsers}, truncatedTables=${tableNames.length}`
    );
  } catch (error) {
    if (txStarted) {
      await client.query("ROLLBACK");
    }
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

run().catch((error) => {
  console.error("[reset] failed:", error);
  process.exit(1);
});
