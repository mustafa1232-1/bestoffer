import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as employees from "../modules/employees/employees.service.js";
import * as perms from "../modules/security/permissions.service.js";
import * as support from "../modules/support/support.service.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let seq = 0;
const makePhone = () => `07${String(Date.now() + (seq += 1) + phoneSalt).slice(-9)}`;
const tag = () => `wr${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

const userIds = [];
const ticketIds = [];

async function makeUser({ adminRoleKey = null } = {}) {
  const user = await createUser({
    fullName: `WR ${tag()}`, username: tag().slice(0, 32), phone: makePhone(),
    pinHash: await hashPin("1234"), block: "A", buildingNumber: "1", apartment: "1",
    imageUrl: null, role: "user", analyticsConsentGranted: true,
    analyticsConsentVersion: "wr_v1", analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  userIds.push(id);
  if (adminRoleKey) {
    await q(`UPDATE app_user SET admin_role_key = $2 WHERE id = $1`, [id, adminRoleKey]);
  }
  return id;
}

function hasKey(effective, key) {
  return effective.permissions.some((p) => p.key === key);
}

test.after(async () => {
  if (ticketIds.length) await q(`DELETE FROM support_ticket WHERE id = ANY($1::bigint[])`, [ticketIds]);
  if (userIds.length) {
    await q(`DELETE FROM admin_user_permission WHERE user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM company_employee_profile WHERE user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM company_salary_contract WHERE employee_user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});

test("admin can create an employee AND grant role + permission in one call", async () => {
  const admin = await makeUser({ adminRoleKey: "super_admin" }); // can manage permissions
  const emp = await makeUser();

  await employees.saveEmployee({
    actorUserId: admin,
    dto: {
      userId: emp,
      department: "customer_service",
      jobTitle: "Agent",
      adminRoleKey: "call_center_agent",
      permissions: [
        { permissionKey: "support.tickets.escalate", scope: "all" },
      ],
    },
  });

  const eff = await perms.getEffectivePermissionsResponse(emp);
  // from the call_center_agent template:
  assert.ok(hasKey(eff, "support.tickets.read"), "template permission present");
  assert.ok(hasKey(eff, "support.tickets.reply"));
  // from the explicit per-user grant:
  assert.ok(hasKey(eff, "support.tickets.escalate"), "extra grant present");

  const profile = await employees.getEmployeeProfile(emp);
  assert.equal(profile.employee.admin_role_key, "call_center_agent");
});

test("admin can edit an employee's permissions later (role change + revoke)", async () => {
  const admin = await makeUser({ adminRoleKey: "super_admin" });
  const emp = await makeUser();
  await employees.saveEmployee({
    actorUserId: admin,
    dto: { userId: emp, department: "monitoring", adminRoleKey: "call_center_agent" },
  });

  // promote to supervisor
  await perms.assignAdminRole({ actorUserId: admin, targetUserId: emp, roleKey: "call_center_supervisor" });
  let eff = await perms.getEffectivePermissionsResponse(emp);
  assert.ok(hasKey(eff, "support.tickets.assign"), "supervisor gains assign");

  // revoke a specific capability
  await perms.grantUserPermission({
    actorUserId: admin, targetUserId: emp,
    permissionKey: "support.tickets.assign", scope: "all", effect: "revoke",
  });
  eff = await perms.getEffectivePermissionsResponse(emp);
  assert.ok(!hasKey(eff, "support.tickets.assign"), "revoke removes it immediately");
});

test("agent image attachment is saved and respects customer/internal visibility", async () => {
  const customer = await makeUser();
  const agent = await makeUser({ adminRoleKey: "super_admin" });

  const ticket = await support.createTicket({
    userId: customer, domain: "TAXI", type: "PROBLEM", priority: "normal",
    subject: "photo evidence",
  });
  ticketIds.push(Number(ticket.id));
  await support.assignTicket({ ticketId: ticket.id, actorUserId: agent, actorRole: "admin", assigneeUserId: agent });

  // agent sends a customer-visible reply WITH an image attachment
  await support.agentReply({
    ticketId: ticket.id, agentUserId: agent, agentRole: "admin",
    body: "here is the photo",
    attachments: [
      { fileUrl: "https://cdn.example.test/support/a.png", mimeType: "image/png", visibility: "customer" },
    ],
  });

  // agent adds an internal note WITH an internal-only attachment
  await support.addInternalNote({
    ticketId: ticket.id, agentUserId: agent, agentRole: "admin",
    body: "internal photo",
    attachments: [
      { fileUrl: "https://cdn.example.test/support/internal.png", mimeType: "image/png", visibility: "internal" },
    ],
  });

  const customerView = await support.getTicketForViewer({
    ticketId: ticket.id,
    viewer: { userId: customer, isAgent: false, canReadInternal: false },
  });
  // customer sees the customer image, and NO internal attachment / internal note
  assert.ok(
    customerView.attachments.some((a) => a.file_url.endsWith("a.png")),
    "customer sees the shared image"
  );
  assert.ok(
    customerView.attachments.every((a) => a.visibility === "customer"),
    "customer never sees internal attachments"
  );
  assert.equal(customerView.internalNotes.length, 0);

  const agentView = await support.getTicketForViewer({
    ticketId: ticket.id,
    viewer: { userId: agent, isAgent: true, canReadInternal: true, permissionScope: "all" },
  });
  assert.ok(
    agentView.attachments.some((a) => a.visibility === "internal"),
    "agent sees the internal image"
  );
  assert.equal(agentView.internalNotes.length, 1);
});
