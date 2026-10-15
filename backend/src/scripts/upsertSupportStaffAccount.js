import "dotenv/config";

import { pool, ensureSchema } from "../config/db.js";
import { runSqlMigrations } from "../config/sqlMigrations.js";
import { allocateRegistrationUsername } from "../modules/auth/auth.service.js";
import { getEffectivePermissionsResponse } from "../modules/security/permissions.service.js";
import { hashPin } from "../shared/utils/hash.js";

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    phone: String(process.env.SEED_SUPPORT_STAFF_PHONE || "").trim(),
    pin: String(process.env.SEED_SUPPORT_STAFF_PIN || "").trim(),
    name: String(process.env.SEED_SUPPORT_STAFF_NAME || "Support Staff").trim(),
    roleKey: String(process.env.SEED_SUPPORT_STAFF_ROLE_KEY || "orders_support").trim(),
    skipMigrations: ["1", "true", "yes", "on"].includes(
      String(process.env.SEED_SUPPORT_STAFF_SKIP_MIGRATIONS || "")
        .trim()
        .toLowerCase()
    ),
  };

  const positional = [];
  for (let index = 0; index < args.length; index += 1) {
    const key = String(args[index] || "").trim();
    const next = String(args[index + 1] || "").trim();
    if (key === "--phone" && next) {
      out.phone = next;
      index += 1;
      continue;
    }
    if (key === "--pin" && next) {
      out.pin = next;
      index += 1;
      continue;
    }
    if (key === "--name" && next) {
      out.name = next;
      index += 1;
      continue;
    }
    if (key === "--role-key" && next) {
      out.roleKey = next;
      index += 1;
      continue;
    }
    if (key === "--skip-migrations") {
      out.skipMigrations = true;
      continue;
    }
    if (!key.startsWith("--")) positional.push(key);
  }

  if (!out.phone && positional[0]) out.phone = positional[0];
  if (!out.pin && positional[1]) out.pin = positional[1];
  if ((!out.name || out.name === "Support Staff") && positional[2]) {
    out.name = positional.slice(2).join(" ");
  }

  out.phone = out.phone.replace(/[^\d]/g, "");
  out.pin = out.pin.replace(/[^\d]/g, "");
  out.name = out.name || "Support Staff";
  out.roleKey = out.roleKey || "orders_support";
  return out;
}

function validate({ phone, pin, roleKey }) {
  if (!/^\d{6,15}$/.test(phone)) {
    console.error(
      "Usage: node src/scripts/upsertSupportStaffAccount.js <PHONE> <PIN> [NAME]"
    );
    process.exit(1);
  }
  if (!/^\d{4,8}$/.test(pin)) {
    console.error("PIN must be 4 to 8 digits.");
    process.exit(1);
  }
  if (!/^[a-z][a-z0-9_]{1,63}$/.test(roleKey)) {
    console.error("Role key has an invalid format.");
    process.exit(1);
  }
}

async function upsertSupportStaff({ phone, pin, name, roleKey }) {
  const pinHash = await hashPin(pin);
  const username = await allocateRegistrationUsername({ fullName: name, phone });
  const client = await pool.connect();

  try {
    await client.query("BEGIN");
    const existing = await client.query(
      `SELECT id, role, is_super_admin
         FROM app_user
        WHERE phone = $1
        FOR UPDATE`,
      [phone]
    );
    const row = existing.rows[0] || null;

    if (row && row.is_super_admin === true) {
      throw new Error(`PHONE_BELONGS_TO_SUPER_ADMIN:user_id=${row.id}`);
    }

    let userId;
    if (row) {
      const updated = await client.query(
        `UPDATE app_user
            SET full_name = $2,
                pin_hash = $3,
                role = 'staff',
                admin_role_key = $4,
                is_internal_staff = TRUE,
                is_account_disabled = FALSE,
                account_disabled_note = NULL,
                must_change_pin = FALSE,
                failed_login_attempts = 0,
                locked_until = NULL,
                last_failed_login_at = NULL,
                permission_version = permission_version + 1,
                updated_at = NOW()
          WHERE id = $1
          RETURNING id`,
        [Number(row.id), name, pinHash, roleKey]
      );
      userId = Number(updated.rows[0].id);
    } else {
      const created = await client.query(
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
            is_internal_staff,
            admin_role_key,
            is_account_disabled,
            must_change_pin,
            analytics_consent_granted,
            analytics_consent_version,
            analytics_consent_granted_at
          )
         VALUES ($1,$2,$3,$4,'HQ','1','1','staff',TRUE,$5,FALSE,FALSE,TRUE,'employee_created_v1',NOW())
         RETURNING id`,
        [name, username, phone, pinHash, roleKey]
      );
      userId = Number(created.rows[0].id);
    }

    await client.query(
      `INSERT INTO company_employee_profile
         (user_id, department, job_title, employment_type, status, start_date, notes)
       VALUES ($1,'customer_service','Support Staff','full_time','active',CURRENT_DATE,$2)
       ON CONFLICT (user_id) DO UPDATE SET
         department = 'customer_service',
         job_title = 'Support Staff',
         employment_type = 'full_time',
         status = 'active',
         notes = EXCLUDED.notes,
         updated_at = NOW()`,
      [userId, `Support account role=${roleKey} upserted by upsertSupportStaffAccount.js`]
    );

    await client.query(
      `INSERT INTO admin_permission_change_log
         (target_user_id, actor_user_id, action, role_key, after_value, reason)
       VALUES ($1, NULL, 'role_assign', $2, $3, $4)`,
      [
        userId,
        roleKey,
        JSON.stringify({ admin_role_key: roleKey, support: true }),
        "support staff account upsert",
      ]
    );

    await client.query("COMMIT");
    return { userId, created: !row };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function main() {
  const cfg = parseArgs();
  validate(cfg);
  if (!cfg.skipMigrations) {
    await runSqlMigrations({ force: true });
    await ensureSchema();
  }
  const result = await upsertSupportStaff(cfg);
  const effective = await getEffectivePermissionsResponse(result.userId);
  const supportPermissions = effective.permissions
    .filter((permission) => String(permission.key || "").startsWith("support.tickets."))
    .map((permission) => ({ key: permission.key, scope: permission.scope }));

  console.log(
    JSON.stringify(
      {
        ok: true,
        userId: result.userId,
        phone: cfg.phone,
        role: "staff",
        roleKey: cfg.roleKey,
        created: result.created,
        supportPermissions,
      },
      null,
      2
    )
  );
}

main().catch((error) => {
  console.error("[seed] support staff failed:", error?.message || error);
  process.exit(1);
});
