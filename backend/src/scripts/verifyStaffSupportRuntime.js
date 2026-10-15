import "dotenv/config";

import { pool, q } from "../config/db.js";
import { getEffectivePermissionsResponse } from "../modules/security/permissions.service.js";
import { findBestAvailableAgent } from "../modules/support/support.repo.js";

const DOMAIN_TEAM = Object.freeze({
  SHOPPING: "orders",
  DELIVERY: "delivery",
  TAXI: "taxi",
  SERVICES: "services",
  REAL_ESTATE: "marketplace",
  CARS: "marketplace",
  JOBS: "jobs",
  COMMUNITY: "community",
  ACCOUNT: "account",
  PAYMENTS: "finance",
  OTHER: "general",
});

const REQUIRED = [
  "support.tickets.read",
  "support.tickets.reply",
  "support.tickets.resolve",
];

async function staffRows() {
  const result = await q(
    `SELECT u.id, u.phone, u.full_name, u.role, u.admin_role_key,
            u.is_account_disabled, u.locked_until,
            p.status AS support_status, p.team, p.skill_domains
       FROM app_user u
       LEFT JOIN support_agent_presence p ON p.agent_user_id = u.id
      WHERE u.role = 'staff'
         OR u.is_internal_staff IS TRUE
      ORDER BY u.id`
  );
  return result.rows;
}

async function main() {
  const staff = [];
  for (const user of await staffRows()) {
    const effective = await getEffectivePermissionsResponse(Number(user.id));
    const permissionKeys = new Set(
      effective.wildcard
        ? REQUIRED
        : effective.permissions.map((permission) => String(permission.key || ""))
    );
    staff.push({
      id: Number(user.id),
      phone: user.phone,
      fullName: user.full_name,
      adminRoleKey: user.admin_role_key,
      disabled: user.is_account_disabled === true,
      locked: Boolean(user.locked_until && new Date(user.locked_until) > new Date()),
      supportStatus: user.support_status,
      team: user.team,
      skillDomains: user.skill_domains || [],
      hasRequiredSupport: REQUIRED.every((key) => permissionKeys.has(key)),
    });
  }

  const routing = [];
  for (const [domain, team] of Object.entries(DOMAIN_TEAM)) {
    const agent = await findBestAvailableAgent({ domain, team });
    routing.push({
      domain,
      team,
      availableAgent: agent
        ? {
            userId: Number(agent.agent_user_id),
            team: agent.team,
            skillDomains: agent.skill_domains || [],
          }
        : null,
    });
  }

  console.log(
    JSON.stringify(
      {
        ok:
          staff.every((user) => !user.disabled && !user.locked && user.hasRequiredSupport) &&
          routing.every((row) => row.availableAgent),
        staff,
        routing,
      },
      null,
      2
    )
  );
}

main()
  .catch((error) => {
    console.error("[verify-staff-support-runtime] failed:", error?.message || error);
    process.exitCode = 1;
  })
  .finally(() => pool.end().catch(() => {}));
