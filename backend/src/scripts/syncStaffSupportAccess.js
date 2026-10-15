import "dotenv/config";

import { pool, q } from "../config/db.js";
import { grantUserPermission } from "../modules/security/permissions.service.js";
import { getEffectivePermissionsResponse } from "../modules/security/permissions.service.js";
import { upsertAgentPresence } from "../modules/support/support.repo.js";

const REQUIRED_SUPPORT_PERMISSIONS = [
  "support.tickets.read",
  "support.tickets.reply",
  "support.tickets.resolve",
];

const FULL_COVERAGE_DOMAINS = [
  "SHOPPING",
  "DELIVERY",
  "TAXI",
  "SERVICES",
  "REAL_ESTATE",
  "CARS",
  "JOBS",
  "COMMUNITY",
  "ACCOUNT",
  "PAYMENTS",
  "OTHER",
];

const PHONE_ROUTING = Object.freeze({
  "07701111111": { team: "account", domains: ["ACCOUNT"] },
  "07702111111": { team: "delivery", domains: ["DELIVERY"] },
  "07703111111": { team: "orders", domains: ["SHOPPING"] },
  "07710111111": { team: "community", domains: ["COMMUNITY"] },
  "077010111111": { team: "finance", domains: ["PAYMENTS"] },
});

const ROLE_ROUTING = Object.freeze({
  orders_support: { team: "orders", domains: ["SHOPPING"] },
  taxi_monitoring: { team: "taxi", domains: ["TAXI"] },
  jobs_monitoring: { team: "jobs", domains: ["JOBS"] },
  services_monitoring: { team: "services", domains: ["SERVICES"] },
  marketplace_monitoring: { team: "marketplace", domains: ["REAL_ESTATE", "CARS"] },
  social_media_moderator: { team: "community", domains: ["COMMUNITY"] },
  ads_manager: { team: "general", domains: ["OTHER", "ACCOUNT"] },
  staff_monitoring: { team: "general", domains: FULL_COVERAGE_DOMAINS },
  order_monitoring: { team: "orders", domains: ["SHOPPING", "DELIVERY", "ACCOUNT", "PAYMENTS"] },
  delivery_monitoring: { team: "delivery", domains: ["DELIVERY"] },
  service_monitoring: { team: "services", domains: ["SERVICES", "REAL_ESTATE", "CARS", "JOBS"] },
  community_moderator: { team: "community", domains: ["COMMUNITY"] },
  call_center_agent: { team: "general", domains: FULL_COVERAGE_DOMAINS },
  call_center_supervisor: { team: "general", domains: FULL_COVERAGE_DOMAINS },
  sales_agent: { team: "orders", domains: ["SHOPPING", "PAYMENTS", "ACCOUNT"] },
  marketing_agent: { team: "general", domains: ["OTHER", "COMMUNITY", "ACCOUNT"] },
  subscriptions_monitor: { team: "finance", domains: ["PAYMENTS", "ACCOUNT", "TAXI", "SHOPPING"] },
  residents_moderator: { team: "community", domains: ["COMMUNITY", "ACCOUNT"] },
  hr: { team: "general", domains: ["ACCOUNT", "OTHER"] },
  payroll_officer: { team: "finance", domains: ["PAYMENTS", "ACCOUNT"] },
});

function routingFor(user) {
  const phone = String(user.phone || "").trim();
  const roleKey = String(user.admin_role_key || "").trim();
  return PHONE_ROUTING[phone] || ROLE_ROUTING[roleKey] || {
    team: "general",
    domains: FULL_COVERAGE_DOMAINS,
  };
}

async function staffUsers() {
  const result = await q(
    `SELECT u.id, u.phone, u.full_name, u.role, u.admin_role_key,
            u.is_account_disabled, u.locked_until,
            e.department, e.job_title
       FROM app_user u
       LEFT JOIN company_employee_profile e ON e.user_id = u.id
      WHERE u.role = 'staff'
         OR u.is_internal_staff IS TRUE
      ORDER BY u.id`
  );
  return result.rows;
}

async function superAdminActorId() {
  const result = await q(
    `SELECT id
       FROM app_user
      WHERE is_super_admin IS TRUE
         OR role = 'admin'
      ORDER BY is_super_admin DESC, id ASC
      LIMIT 1`
  );
  return Number(result.rows[0]?.id || 0) || null;
}

async function grantMissingSupport(userId, actorUserId) {
  const before = await getEffectivePermissionsResponse(userId);
  const granted = [];
  if (before.wildcard === true) return granted;
  for (const permissionKey of REQUIRED_SUPPORT_PERMISSIONS) {
    await grantUserPermission({
      targetUserId: userId,
      actorUserId,
      permissionKey,
      effect: "grant",
      scope: "all",
      reason: "ensure every staff account can receive and answer support tickets",
    });
    granted.push(permissionKey);
  }
  return granted;
}

async function main() {
  const actorUserId = await superAdminActorId();
  if (!actorUserId) {
    throw new Error("NO_SUPER_ADMIN_ACTOR_FOUND");
  }
  const users = await staffUsers();
  const rows = [];
  for (const user of users) {
    const userId = Number(user.id);
    const routing = routingFor(user);
    const granted = await grantMissingSupport(userId, actorUserId);
    const presence = await upsertAgentPresence({
      agentUserId: userId,
      status: "available",
      team: routing.team,
      skillDomains: routing.domains,
      currentTicketId: null,
    });
    const effective = await getEffectivePermissionsResponse(userId);
    const supportPermissions = effective.permissions.filter((permission) =>
      String(permission.key || "").startsWith("support.tickets.")
    );
    rows.push({
      id: userId,
      phone: user.phone,
      fullName: user.full_name,
      adminRoleKey: user.admin_role_key,
      disabled: user.is_account_disabled === true,
      lockedUntil: user.locked_until,
      team: presence.team,
      skillDomains: presence.skill_domains,
      granted,
      supportPermissions,
    });
  }
  console.log(JSON.stringify({ ok: true, actorUserId, count: rows.length, users: rows }, null, 2));
}

main()
  .catch((error) => {
    console.error("[sync-staff-support-access] failed:", error?.message || error);
    process.exitCode = 1;
  })
  .finally(() => pool.end().catch(() => {}));
