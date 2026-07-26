import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import * as opsRepo from "../modules/admin/admin.ops.repo.js";
import { hashPin } from "../shared/utils/hash.js";

const userIds = [];
const alertIds = [];
let phoneSeq = 0;

function suffix() {
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

function makePhone() {
  phoneSeq += 1;
  return `079${String(Date.now() + phoneSeq).slice(-8)}`;
}

async function makeUser(role = "admin") {
  const user = await createUser({
    fullName: `Ops Alert ${role}`,
    username: `ops_alert_${suffix()}`.slice(0, 32),
    phone: makePhone(),
    pinHash: await hashPin("1234"),
    block: "A",
    buildingNumber: "1",
    apartment: "1",
    imageUrl: null,
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "ops_alert_test",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  userIds.push(id);
  return id;
}

async function makeAlert() {
  const r = await q(
    `INSERT INTO ops_alert
       (source, event_type, severity, status, title, details, entity_type, entity_id)
     VALUES ('ops_alert_test','TEST_EVENT','high','open','Test alert','{}'::jsonb,'order',1001)
     RETURNING id`
  );
  const id = Number(r.rows[0].id);
  alertIds.push(id);
  return id;
}

test.after(async () => {
  if (alertIds.length) {
    await q(`DELETE FROM ops_alert_ack WHERE alert_id = ANY($1::bigint[])`, [
      alertIds,
    ]);
    await q(`DELETE FROM ops_alert WHERE id = ANY($1::bigint[])`, [alertIds]);
  }
  if (userIds.length) {
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});

test("ops alerts record reasoned acknowledge assign and resolve timeline", async () => {
  const actorId = await makeUser("admin");
  const assigneeId = await makeUser("admin");
  const alertId = await makeAlert();

  const acked = await opsRepo.acknowledgeOpsAlert({
    alertId,
    actorUserId: actorId,
    note: "case OPS-100 acknowledged",
    toStatus: "acknowledged",
  });
  assert.equal(acked.status, "acknowledged");

  const assigned = await opsRepo.assignOpsAlert({
    alertId,
    actorUserId: actorId,
    assigneeUserId: assigneeId,
    reason: "case OPS-100 assigned to responder",
  });
  assert.equal(
    Number(assigned.details.ops_assignment.assignee_user_id),
    assigneeId
  );

  const resolved = await opsRepo.acknowledgeOpsAlert({
    alertId,
    actorUserId: actorId,
    note: "case OPS-100 resolved after verification",
    toStatus: "resolved",
  });
  assert.equal(resolved.status, "resolved");

  const listed = await opsRepo.listOpsAlerts({ status: "all", limit: 10 });
  const item = listed.find((row) => Number(row.id) === alertId);
  assert.ok(item);
  assert.equal(item.entity_type, "order");
  assert.equal(Number(item.entity_id), 1001);
  assert.ok(Array.isArray(item.timeline));
  assert.ok(item.timeline.some((row) => row.to_status === "assigned"));
  assert.ok(item.timeline.some((row) => row.to_status === "resolved"));
});

test("ops alert assignment rejects missing reason", async () => {
  const actorId = await makeUser("admin");
  const assigneeId = await makeUser("admin");
  const alertId = await makeAlert();

  const assigned = await opsRepo.assignOpsAlert({
    alertId,
    actorUserId: actorId,
    assigneeUserId: assigneeId,
    reason: "short",
  });
  assert.equal(assigned, null);
});
