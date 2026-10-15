import "dotenv/config";

import { q } from "../config/db.js";
import { getEffectivePermissionsResponse } from "../modules/security/permissions.service.js";

const phone = String(process.argv[2] || "").trim();
if (!phone) {
  console.error("Usage: node src/scripts/diagnoseLoginAccount.js <phone>");
  process.exit(2);
}

const exact = await q(
  `SELECT id, phone, full_name, role, admin_role_key, is_super_admin,
          is_internal_staff, is_account_disabled, must_change_pin,
          permission_version
     FROM app_user
    WHERE phone = $1
    LIMIT 1`,
  [phone]
);

const nearby = await q(
  `SELECT id, phone, full_name, role, admin_role_key, is_super_admin,
          is_internal_staff, is_account_disabled, must_change_pin
     FROM app_user
    WHERE phone LIKE $1
    ORDER BY phone
    LIMIT 20`,
  [`%${phone.slice(-7)}%`]
);

const out = {
  exactFound: exact.rows.length === 1,
  exact: exact.rows[0] || null,
  nearby: nearby.rows,
  effective: null,
};

if (exact.rows[0]) {
  const effective = await getEffectivePermissionsResponse(Number(exact.rows[0].id));
  out.effective = {
    roleKey: effective.roleKey,
    wildcard: effective.wildcard === true,
    permissions: effective.permissions
      .filter((permission) =>
        ["support.tickets.read", "support.tickets.reply", "ads.manage"].includes(
          permission.key
        )
      )
      .map((permission) => ({ key: permission.key, scope: permission.scope })),
  };
}

console.log(JSON.stringify(out, null, 2));
process.exit(0);
