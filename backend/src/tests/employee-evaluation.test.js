import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as support from "../modules/support/support.service.js";
import * as evaluation from "../modules/employees/evaluation.repo.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let seq = 0;
const makePhone = () => `07${String(Date.now() + (seq += 1) + phoneSalt).slice(-9)}`;
const tag = () => `ev${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

const userIds = [];
const ticketIds = [];

async function makeUser() {
  const user = await createUser({
    fullName: `EV ${tag()}`, username: tag().slice(0, 32), phone: makePhone(),
    pinHash: await hashPin("1234"), block: "A", buildingNumber: "1", apartment: "1",
    imageUrl: null, role: "user", analyticsConsentGranted: true,
    analyticsConsentVersion: "ev_v1", analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  userIds.push(id);
  return id;
}

test.after(async () => {
  if (ticketIds.length) await q(`DELETE FROM support_ticket WHERE id = ANY($1::bigint[])`, [ticketIds]);
  if (userIds.length) {
    await q(`DELETE FROM company_employee_review WHERE employee_user_id = ANY($1::bigint[])`, [userIds]);
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});

test("evaluation aggregates quality (rating) and SLA, not just ticket counts", async () => {
  const customer = await makeUser();
  const agent = await makeUser();

  // two tickets assigned to the agent; both resolved, one rated 5
  for (let i = 0; i < 2; i += 1) {
    const t = await support.createTicket({
      userId: customer, domain: "TAXI", type: "PROBLEM", priority: "normal",
      subject: `eval ticket ${i}`,
    });
    ticketIds.push(Number(t.id));
    await support.assignTicket({ ticketId: t.id, actorUserId: agent, actorRole: "admin", assigneeUserId: agent });
    await support.agentReply({ ticketId: t.id, agentUserId: agent, agentRole: "admin", body: "on it" });
    await support.resolveTicket({ ticketId: t.id, actorUserId: agent, actorRole: "admin", summary: "fixed" });
    if (i === 0) {
      await support.rateTicket({ ticketId: t.id, userId: customer, rating: 5 });
    }
  }

  const metrics = await evaluation.computeTicketMetrics({ agentUserId: agent });
  assert.equal(metrics.received, 2);
  assert.equal(metrics.resolved, 2);
  assert.equal(metrics.avgRating, 5);      // quality dimension, not just counts
  assert.equal(metrics.ratedCount, 1);
  assert.ok(metrics.avgFirstResponseSecs != null);
  assert.equal(typeof metrics.slaBreachRate, "number");
});

test("supervisor review can be recorded and the employee can object", async () => {
  const agent = await makeUser();
  const supervisor = await makeUser();
  const period = "2026-05";

  const review = await evaluation.upsertReview({
    employeeUserId: agent, period, supervisorRating: 4,
    supervisorNote: "solid month", reviewedByUserId: supervisor,
  });
  assert.equal(review.supervisor_rating, 4);

  const objected = await evaluation.addObjection({
    employeeUserId: agent, period, objectionText: "I handled more than shown",
  });
  assert.equal(objected.code, "OK");
  assert.ok(objected.review.objection_at);
  assert.match(objected.review.objection_text, /handled more/);
});
