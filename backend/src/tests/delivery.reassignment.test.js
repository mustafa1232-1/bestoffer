// Reassignment eligibility + history regression tests (delivery closure §1A/§1B).

import test from "node:test";
import assert from "node:assert/strict";
import pg from "pg";
import {
  createMultiStoreFixture,
  cleanupMultiStoreFixture,
} from "./fixtures/multistore-delivery.fixture.js";
import {
  ensureDeliveryJobForGroup,
  recomputeGroupReadiness,
  assignDeliveryJobTx,
  reassignGroupedJob,
  listCourierGroupedJobHistory,
  listCourierActiveGroupedJobs,
} from "../modules/delivery/delivery-job.service.js";

const MARK = "fixt_rea_";
let phoneSeq = 0;
function candidatePhone() {
  // Distinctive digit phone that cannot collide with fixture hash phones.
  return `0555${String(100000 + phoneSeq++).slice(0, 9)}`;
}
function newClient() {
  return new pg.Client({ connectionString: process.env.DATABASE_URL });
}

async function readyAssign(c, fx) {
  await c.query("BEGIN");
  await ensureDeliveryJobForGroup(c, fx.orderGroupId);
  await recomputeGroupReadiness(c, fx.orderGroupId);
  await assignDeliveryJobTx(c, { orderGroupId: fx.orderGroupId, courierUserId: fx.courierId });
  await c.query("COMMIT");
  return (await c.query("SELECT * FROM delivery_job WHERE order_group_id=$1", [fx.orderGroupId])).rows[0];
}

// A candidate courier with configurable eligibility.
async function makeCandidate(c, n, opts = {}) {
  const {
    approved = true, disabled = false, isApp = true, active = true,
    availability = "online", online = true, ageSec = 5,
  } = opts;
  const uid = Number(
    (
      await c.query(
        `INSERT INTO app_user
           (full_name, phone, pin_hash, block, building_number, apartment, username, role, delivery_account_approved, is_account_disabled)
         VALUES ('cand',$1,'x','A','1','1',$2,'delivery',$3,$4) RETURNING id`,
        [candidatePhone(), `${MARK}c_${n}`, approved, disabled]
      )
    ).rows[0].id
  );
  await c.query(
    `INSERT INTO courier_profile (user_id, is_app_courier, active_status, availability_status)
     VALUES ($1,$2,$3,$4)`,
    [uid, isApp, active, availability]
  );
  await c.query(
    `INSERT INTO courier_presence (courier_user_id, is_online, recorded_at, updated_at)
     VALUES ($1,$2, NOW() - ($3 || ' seconds')::interval, NOW())`,
    [uid, online, String(ageSec)]
  );
  return uid;
}

async function cleanup(c) {
  await c.query(`DELETE FROM courier_assignment WHERE courier_user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`).catch(() => {});
  await c.query(`DELETE FROM courier_presence WHERE courier_user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`).catch(() => {});
  await c.query(`DELETE FROM courier_profile WHERE user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`).catch(() => {});
  await c.query(`DELETE FROM app_user WHERE username LIKE '${MARK}%'`).catch(() => {});
  await cleanupMultiStoreFixture(c, MARK);
}

async function activeHolder(c, jobId) {
  const r = (await c.query(`SELECT courier_user_id FROM courier_assignment WHERE delivery_job_id=$1 AND ended_at IS NULL`, [jobId])).rows;
  return r.length === 1 ? Number(r[0].courier_user_id) : null;
}

test("§1A: ineligible new courier is rejected and preserves the old assignment", async (t) => {
  const c = newClient();
  await c.connect();
  t.after(async () => { await cleanup(c).catch(() => {}); await c.end(); });
  await cleanup(c);
  const fx = await createMultiStoreFixture(c, { mark: MARK });
  const job = await readyAssign(c, fx); // courier A = fx.courierId active on job

  const cases = [
    ["unapproved", { approved: false }, "account_not_approved"],
    ["offline", { online: false }, "offline"],
    ["stale", { ageSec: 9999 }, "presence_stale"],
    ["disabled", { disabled: true }, "account_disabled"],
    ["not_active", { active: false }, "account_not_active"],
  ];
  let n = 0;
  for (const [label, opts, reason] of cases) {
    const cand = await makeCandidate(c, `bad_${n++}`, opts);
    await assert.rejects(
      reassignGroupedJob({ orderGroupId: fx.orderGroupId, newCourierUserId: cand, reason: "TEST" }),
      (e) => e.code === "COURIER_NOT_ELIGIBLE" && e.details?.reason === reason,
      `${label} rejected with ${reason}`
    );
    // Old courier A still holds the job — failed reassignment did not close it.
    assert.equal(await activeHolder(c, job.id), Number(fx.courierId), `${label}: old assignment preserved`);
    const j = (await c.query("SELECT delivery_user_id, assignment_status FROM delivery_job WHERE id=$1", [job.id])).rows[0];
    assert.equal(Number(j.delivery_user_id), Number(fx.courierId), `${label}: job still A`);
    assert.equal(j.assignment_status, "ASSIGNED", `${label}: job still ASSIGNED`);
  }

  // Busy candidate holds another active grouped job (a second real group+job).
  const busy = await makeCandidate(c, "busy");
  const fx2 = await createMultiStoreFixture(c, { mark: MARK + "b_" });
  await c.query("BEGIN");
  await ensureDeliveryJobForGroup(c, fx2.orderGroupId);
  await recomputeGroupReadiness(c, fx2.orderGroupId);
  await assignDeliveryJobTx(c, { orderGroupId: fx2.orderGroupId, courierUserId: busy });
  await c.query("COMMIT");
  await assert.rejects(
    reassignGroupedJob({ orderGroupId: fx.orderGroupId, newCourierUserId: busy, reason: "TEST" }),
    (e) => e.code === "COURIER_NOT_ELIGIBLE" && e.details?.reason === "busy_grouped_job",
    "busy candidate rejected"
  );
  assert.equal(await activeHolder(c, job.id), Number(fx.courierId), "old assignment still preserved after busy rejection");
  await cleanupMultiStoreFixture(c, MARK + "b_");
});

test("§1A/§1B: valid reassignment succeeds; both histories stay accurate", async (t) => {
  const c = newClient();
  await c.connect();
  t.after(async () => { await cleanup(c).catch(() => {}); await c.end(); });
  await cleanup(c);
  const fx = await createMultiStoreFixture(c, { mark: MARK });
  const job = await readyAssign(c, fx);
  const A = Number(fx.courierId);
  const B = await makeCandidate(c, "good");

  const res = await reassignGroupedJob({ orderGroupId: fx.orderGroupId, newCourierUserId: B, reason: "OWNER_REASSIGN" });
  assert.equal(Number(res.courierUserId), B, "job reassigned to B");
  assert.equal(await activeHolder(c, job.id), B, "B holds the one active assignment");

  // Current/active resolves to B, not A.
  assert.equal((await listCourierActiveGroupedJobs(A)).length, 0, "A has no active job");
  assert.equal((await listCourierActiveGroupedJobs(B)).length, 1, "B has the active job");

  // §1B: A's HISTORY still contains the assignment it once held, with reason.
  const aHist = await listCourierGroupedJobHistory(A);
  const aRow = aHist.find((h) => Number(h.deliveryJobId) === Number(job.id));
  assert.ok(aRow, "A's history retains the reassigned-away job");
  assert.ok(aRow.endedAt, "A's assignment has endedAt");
  assert.equal(aRow.endedReason, "OWNER_REASSIGN", "A's assignment records the ended reason");
  assert.ok(aRow.storeCount >= 1, "A's history carries the store count");

  // B currently ACTIVE (not terminal) → not in history yet, but visible as active.
  const bHist = await listCourierGroupedJobHistory(B);
  assert.ok(!bHist.some((h) => h.endedReason === "OWNER_REASSIGN"), "B does not inherit A's ended reason");
});
