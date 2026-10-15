import assert from "node:assert/strict";
import { randomInt, randomUUID } from "node:crypto";
import test from "node:test";

import { app } from "../app.js";
import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as supportService from "../modules/support/support.service.js";
import {
  assertStatus,
  createActor,
  request,
  startLocalServer,
  stopLocalServer,
} from "../scripts/e2eTestUtils.js";

function makePhone(prefix = "077") {
  return `${prefix}${String(randomInt(0, 10_000_000)).padStart(7, "0")}`;
}
function makeUsername(prefix) {
  return `${prefix}_${randomUUID().replace(/-/g, "").slice(0, 8)}`.slice(0, 24);
}

async function mkUser(role) {
  return createUser({
    fullName: `${role} ${randomUUID().slice(0, 8)}`,
    username: makeUsername(role.slice(0, 3)),
    phone: makePhone("078"),
    pinHash: await hashPin("1234"),
    block: "A1",
    buildingNumber: "A101",
    apartment: "101",
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "support_agent_create_test_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
  });
}

async function cleanup(userIds) {
  const ids = userIds.map(Number).filter((id) => id > 0);
  if (!ids.length) return;
  await q(`DELETE FROM support_ticket WHERE user_id = ANY($1::bigint[]) OR created_by_user_id = ANY($1::bigint[])`, [ids]).catch(() => {});
  await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [ids]).catch(() => {});
}

test("agent opens a phone ticket on behalf of a customer (by phone), owns it, IN_PROGRESS", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `agent-ticket-${Date.now().toString(36)}`;
  const adminActor = createActor("admin", runTag);
  adminActor.appFlavor = "admin";
  const admin = await mkUser("admin");
  const customer = await mkUser("user");

  try {
    const adminLogin = await request(baseUrl, adminActor, "POST", "/api/auth/login", {
      phone: admin.phone,
      pin: "1234",
    });
    assertStatus(adminLogin, 200, "admin login");
    adminActor.token = String(adminLogin.data?.token || "");

    const created = await request(baseUrl, adminActor, "POST", "/api/admin/support/tickets", {
      customerPhone: customer.phone,
      domain: "TAXI",
      type: "COMPLAINT",
      priority: "high",
      subject: "الزبون اتصل يشتكي من تأخر الكابتن",
      description: "بلاغ هاتفي",
      channel: "phone",
      callOutcome: "needs_follow_up",
      internalNote: "اتصل الساعة 3، وعد بمعاودة الاتصال",
    });
    assertStatus(created, 201, "agent creates ticket for customer");
    const ticket = created.data?.ticket;
    assert.equal(Number(ticket?.user_id), Number(customer.id), "ticket owned by customer");
    assert.equal(Number(ticket?.created_by_user_id), Number(admin.id), "created_by is the agent");
    assert.equal(ticket?.channel, "phone");
    assert.equal(Number(ticket?.assigned_user_id), Number(admin.id), "agent owns it");
    assert.equal(ticket?.status, "IN_PROGRESS", "moves to in progress");
  } finally {
    await stopLocalServer(server);
    await cleanup([Number(customer.id), Number(admin.id)]);
  }
});

test("resolved_on_call closes the ticket immediately as RESOLVED", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `agent-ticket-res-${Date.now().toString(36)}`;
  const adminActor = createActor("admin", runTag);
  adminActor.appFlavor = "admin";
  const admin = await mkUser("admin");
  const customer = await mkUser("user");

  try {
    const adminLogin = await request(baseUrl, adminActor, "POST", "/api/auth/login", {
      phone: admin.phone,
      pin: "1234",
    });
    assertStatus(adminLogin, 200, "admin login");
    adminActor.token = String(adminLogin.data?.token || "");

    const created = await request(baseUrl, adminActor, "POST", "/api/admin/support/tickets", {
      customerUserId: Number(customer.id),
      domain: "ACCOUNT",
      type: "QUESTION",
      subject: "استفسار عن كيفية تغيير الرقم",
      channel: "phone",
      callOutcome: "resolved_on_call",
    });
    assertStatus(created, 201, "agent creates + resolves on call");
    assert.equal(created.data?.ticket?.status, "RESOLVED", "resolved on the call");
    assert.ok(created.data?.ticket?.resolved_at, "resolved_at set");
  } finally {
    await stopLocalServer(server);
    await cleanup([Number(customer.id), Number(admin.id)]);
  }
});

test("unknown customer phone is rejected with 404", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `agent-ticket-404-${Date.now().toString(36)}`;
  const adminActor = createActor("admin", runTag);
  adminActor.appFlavor = "admin";
  const admin = await mkUser("admin");

  try {
    const adminLogin = await request(baseUrl, adminActor, "POST", "/api/auth/login", {
      phone: admin.phone,
      pin: "1234",
    });
    assertStatus(adminLogin, 200, "admin login");
    adminActor.token = String(adminLogin.data?.token || "");

    const created = await request(baseUrl, adminActor, "POST", "/api/admin/support/tickets", {
      customerPhone: "07000000000",
      domain: "OTHER",
      type: "QUESTION",
      subject: "لا يوجد عميل بهذا الرقم",
      channel: "phone",
    });
    assertStatus(created, 404, "unknown customer rejected");
  } finally {
    await stopLocalServer(server);
    await cleanup([Number(admin.id)]);
  }
});

test("staff support account sees incoming customer tickets through public tickets route", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `staff-support-compat-${Date.now().toString(36)}`;
  const staffActor = createActor("staff", runTag);
  staffActor.appFlavor = "user";
  const staff = await mkUser("staff");
  const customer = await mkUser("user");

  try {
    await q(`UPDATE app_user SET admin_role_key = 'orders_support' WHERE id = $1`, [
      Number(staff.id),
    ]);
    const ticket = await supportService.createTicket({
      userId: Number(customer.id),
      domain: "ACCOUNT",
      type: "QUESTION",
      priority: "normal",
      subject: `compat incoming ${runTag}`,
      description: "opened from customer app",
    });

    const login = await request(baseUrl, staffActor, "POST", "/api/auth/login", {
      phone: staff.phone,
      pin: "1234",
    });
    assertStatus(login, 200, "staff login through user app");
    staffActor.token = String(login.data?.token || "");

    const list = await request(
      baseUrl,
      staffActor,
      "GET",
      `/api/support/tickets/mine?limit=50&search=${encodeURIComponent(runTag)}`
    );
    assertStatus(list, 200, "staff public support list compatibility");
    assert.ok(
      (list.data?.items || []).some((item) => Number(item.id) === Number(ticket.id)),
      "incoming customer ticket is visible to staff"
    );

    const details = await request(
      baseUrl,
      staffActor,
      "GET",
      `/api/support/tickets/${ticket.id}`
    );
    assertStatus(details, 200, "staff public support details compatibility");

    const reply = await request(
      baseUrl,
      staffActor,
      "POST",
      `/api/support/tickets/${ticket.id}/messages`,
      { body: "follow up from staff" }
    );
    assertStatus(reply, 201, "staff public support reply compatibility");
    assert.equal(reply.data?.message?.body, "follow up from staff");
  } finally {
    await stopLocalServer(server);
    await cleanup([Number(customer.id), Number(staff.id)]);
  }
});
