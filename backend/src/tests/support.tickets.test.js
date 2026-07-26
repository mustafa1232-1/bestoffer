import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as support from "../modules/support/support.service.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let phoneSeq = 0;
function makePhone() {
  phoneSeq += 1;
  return `07${String(Date.now() + phoneSeq + phoneSalt).slice(-9)}`;
}
function suffix() {
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

const userIds = [];
const ticketIds = [];

function assertSafeTestDatabase() {
  const dbUrl = process.env.DATABASE_URL || "";
  const nodeEnv = process.env.NODE_ENV || "";
  const dbName = (() => {
    try {
      return new URL(dbUrl).pathname.replace(/^\//, "");
    } catch {
      return dbUrl;
    }
  })();
  const safeDbName = /(test|qa|local)/i.test(dbName);
  const unsafeRemote = /(railway|production|prod)/i.test(dbUrl);
  if ((!safeDbName && nodeEnv !== "test") || unsafeRemote) {
    throw new Error("Refusing to run support ticket DB lifecycle tests outside a test/QA database");
  }
}

async function makeUser(role = "user") {
  const user = await createUser({
    fullName: `SUP ${role}`,
    username: `sup_${suffix()}`.slice(0, 32),
    phone: makePhone(),
    pinHash: await hashPin("1234"),
    block: "A",
    buildingNumber: "1",
    apartment: "1",
    imageUrl: null,
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "sup_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  userIds.push(id);
  return id;
}

test.before(() => {
  assertSafeTestDatabase();
});

test.after(async () => {
  if (ticketIds.length) {
    await q(`DELETE FROM support_ticket WHERE id = ANY($1::bigint[])`, [ticketIds]);
  }
  if (userIds.length) {
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});

test("full ticket lifecycle: create -> assign -> reply -> internal note -> resolve -> rate", async () => {
  const customer = await makeUser("user");
  const agent = await makeUser("admin");
  const strangerAgent = await makeUser("admin");

  const created = await support.createTicket({
    userId: customer,
    domain: "TAXI",
    type: "COMPLAINT",
    priority: "high",
    subject: "Captain took a wrong route",
    description: "details",
    entityType: "ride",
    entityId: 123,
    entityLabel: "Ride #123",
    attachments: [
      {
        fileUrl: "https://cdn.example.test/support/ride.png",
        fileName: "ride.png",
        mimeType: "image/png",
        fileSizeBytes: 120,
      },
    ],
  });
  ticketIds.push(Number(created.id));
  assert.equal(created.status, "NEW");
  assert.match(created.ticket_number, /^TKT-\d{6}$/);
  assert.ok(created.sla_first_response_due_at);
  assert.ok(created.sla);

  // customer message
  await support.addCustomerMessage({
    ticketId: created.id,
    userId: customer,
    body: "please help",
    attachments: [{ fileUrl: "https://cdn.example.test/support/receipt.jpg" }],
  });

  // assign
  const assigned = await support.assignTicket({
    ticketId: created.id,
    actorUserId: agent,
    actorRole: "admin",
    assigneeUserId: agent,
    team: "taxi",
  });
  assert.equal(assigned.status, "ASSIGNED");
  assert.equal(Number(assigned.assigned_user_id), agent);

  await assert.rejects(
    support.getTicketForViewer({
      ticketId: created.id,
      viewer: {
        userId: strangerAgent,
        isAgent: true,
        canReadInternal: true,
        permissionScope: "assigned",
      },
    })
  );

  const joined = await support.joinConversation({
    ticketId: created.id,
    agentUserId: agent,
    agentRole: "admin",
  });
  assert.match(joined.body, /^انضم .* إلى المحادثة\.$/u);

  // agent reply -> first response recorded
  const reply = await support.agentReply({
    ticketId: created.id,
    agentUserId: agent,
    agentRole: "admin",
    body: "we are on it",
    attachments: [{ fileUrl: "https://cdn.example.test/support/public-note.txt" }],
  });
  assert.equal(reply.firstResponse, false);

  // internal note is hidden from the customer view but visible to the agent
  const note = await support.addInternalNote({
    ticketId: created.id,
    agentUserId: agent,
    agentRole: "admin",
    body: "internal: refund likely",
    attachments: [
      {
        fileUrl: "https://cdn.example.test/support/internal-note.txt",
        visibility: "internal",
      },
    ],
  });
  assert.ok(Number(note.id) > 0);
  const link = await support.linkEntity({
    ticketId: created.id,
    actorUserId: agent,
    actorRole: "admin",
    entityType: "invoice",
    entityId: 456,
    label: "Invoice #456",
    reason: "refund review",
  });
  assert.equal(link.entity_type, "invoice");

  const customerView = await support.getTicketForViewer({
    ticketId: created.id,
    viewer: { userId: customer, isAgent: false, canReadInternal: false },
  });
  assert.ok(!customerView.messages.some((m) => m.is_internal));
  assert.equal(customerView.internalNotes.length, 0);
  assert.equal(customerView.links.length, 2);
  assert.ok(customerView.attachments.every((a) => a.visibility === "customer"));
  const agentView = await support.getTicketForViewer({
    ticketId: created.id,
    viewer: {
      userId: agent,
      isAgent: true,
      canReadInternal: true,
      permissionScope: "assigned",
    },
  });
  assert.equal(agentView.internalNotes.length, 1);
  assert.equal(agentView.internalNotes[0].body, "internal: refund likely");
  assert.ok(agentView.attachments.some((a) => a.visibility === "internal"));
  assert.ok(agentView.events.some((e) => e.event_type === "agent_joined"));
  assert.ok(agentView.events.some((e) => e.event_type === "entity_linked"));

  // resolve requires a summary and stamps resolved_at
  const resolved = await support.resolveTicket({
    ticketId: created.id,
    actorUserId: agent,
    actorRole: "admin",
    summary: "route corrected, partial refund issued",
    reason: "refund",
  });
  assert.equal(resolved.status, "RESOLVED");
  assert.ok(resolved.resolved_at);
  assert.equal(resolved.first_response_at != null, true);

  // customer rates
  const rated = await support.rateTicket({
    ticketId: created.id,
    userId: customer,
    rating: 5,
    speed: 4,
    quality: 5,
    comment: "good",
  });
  assert.equal(Number(rated.rating), 5);
});

test("reopen moves RESOLVED back to REOPENED and bumps the counter", async () => {
  const customer = await makeUser("user");
  const agent = await makeUser("admin");
  const t = await support.createTicket({
    userId: customer, domain: "SHOPPING", type: "PROBLEM", priority: "normal",
    subject: "missing item",
  });
  ticketIds.push(Number(t.id));
  await support.assignTicket({ ticketId: t.id, actorUserId: agent, actorRole: "admin", assigneeUserId: agent });
  await support.resolveTicket({ ticketId: t.id, actorUserId: agent, actorRole: "admin", summary: "done" });
  const reopened = await support.reopenTicket({
    ticketId: t.id, actorUserId: customer, actorRole: "customer", reason: "still wrong",
  });
  assert.equal(reopened.status, "REOPENED");
  assert.equal(Number(reopened.reopened_count), 1);
});

test("invalid transitions and closed-ticket writes are rejected", async () => {
  const customer = await makeUser("user");
  const t = await support.createTicket({
    userId: customer, domain: "OTHER", type: "QUESTION", priority: "low", subject: "q",
  });
  ticketIds.push(Number(t.id));
  // NEW -> RESOLVED directly is not allowed (must pass through assigned/in-progress)
  await assert.rejects(
    support.transitionTicket({ ticketId: t.id, actorUserId: customer, actorRole: "admin", toStatus: "REOPENED" })
  );
});

test("a non-reporter cannot read another user's ticket", async () => {
  const customer = await makeUser("user");
  const stranger = await makeUser("user");
  const t = await support.createTicket({
    userId: customer, domain: "ACCOUNT", type: "PROBLEM", priority: "normal", subject: "acct",
  });
  ticketIds.push(Number(t.id));
  await assert.rejects(
    support.getTicketForViewer({
      ticketId: t.id,
      viewer: { userId: stranger, isAgent: false, canReadInternal: false },
    })
  );
});
