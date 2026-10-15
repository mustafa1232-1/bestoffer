import "dotenv/config";

import { q } from "../config/db.js";
import { getEffectivePermissionsResponse } from "../modules/security/permissions.service.js";

const users = await q(
  `SELECT id, phone, full_name, role, admin_role_key, is_super_admin, permission_version
     FROM app_user
    WHERE role = 'staff' OR is_internal_staff IS TRUE
    ORDER BY id`
);

const rows = [];
for (const user of users.rows) {
  const effective = await getEffectivePermissionsResponse(Number(user.id));
  const supportPermissions = effective.permissions.filter((permission) =>
    String(permission.key || "").startsWith("support.tickets.")
  );
  rows.push({
    id: Number(user.id),
    phone: user.phone,
    fullName: user.full_name,
    role: user.role,
    adminRoleKey: user.admin_role_key,
    isSuperAdmin: user.is_super_admin === true,
    wildcard: effective.wildcard === true,
    supportPermissions,
  });
}

console.log(JSON.stringify({ count: rows.length, users: rows }, null, 2));
process.exit(0);
