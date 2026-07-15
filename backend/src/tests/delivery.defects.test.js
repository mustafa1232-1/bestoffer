// Regression tests for the four backend defects (delivery closure follow-up).
//   A (§2) current grouped job never returns a terminal (delivered) job
//   B (§3) assignment conflict retries to the NEXT eligible courier
//   C (§4) no silent courier replacement; explicit reassignment
//   D (§5) normalized authority from identity, not courier_name; pickupStops

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
  runGroupedAssignmentForGroupTx,
  getGroupedAssignmentView,
  getCourierCurrentGroupedJob,
  listCourierGroupedJobHistory,
  reassignGroupedJob,
} from "../modules/delivery/delivery-job.service.js";

const MARK = "fixt_dfx_";
function newClient() {
  return new pg.Client({ connectionString: process.env.DATABASE_URL });
}

async function readyJob(c, fx) {
  await c.query("BEGIN");
  await ensureDeliveryJobForGroup(c, fx.orderGroupId);
  await recomputeGroupReadiness(c, fx.orderGroupId);
  await c.query("COMMIT");
  return (
    await c.query("SELECT * FROM delivery_job WHERE order_group_id=$1", [fx.orderGroupId])
  ).rows[0];
}

// Add a second approved+online courier with OLDER presence (so the first courier
// is selected before this one). Returns its user id.
async function addSecondCourier(c, n, ageSec) {
  const uid = Number(
    (
      await c.query(
        `INSERT INTO app_user
           (full_name, phone, pin_hash, block, building_number, apartment, username, role, delivery_account_approved)
         VALUES ('c2',$1,'x','A','1','1',$2,'delivery',TRUE) RETURNING id`,
        [`0779000${n}`, `${MARK}c2_${n}`]
      )
    ).rows[0].id
  );
  await c.query(
    `INSERT INTO courier_profile (user_id, is_app_courier, active_status, availability_status)
     VALUES ($1,TRUE,TRUE,'online')`,
    [uid]
  );
  await c.query(
    `INSERT INTO courier_presence (courier_user_id, is_online, recorded_at, updated_at)
     VALUES ($1,TRUE, NOW() - ($2 || ' seconds')::interval, NOW())`,
    [uid, String(ageSec)]
  );
  return uid;
}

test("Defect A (§2): current grouped job never returns a delivered job", async () => {
  const c = newClient();
  await c.connect();
  try {
    const fx = await createMultiStoreFixture(c, { mark: MARK });
    const job = await readyJob(c, fx);
    await c.query("BEGIN");
    await assignDeliveryJobTx(c, { orderGroupId: fx.orderGroupId, courierUserId: fx.courierId });
    await c.query("COMMIT");

    // Active job → current returns it.
    let current = await getCourierCurrentGroupedJob(fx.courierId);
    assert.ok(current, "active job returned as current");
    assert.equal(Number(current.delivery_job_id), Number(job.id));

    // Deliver → current returns null; history contains it.
    await c.query(`UPDATE delivery_job SET lifecycle_status='DELIVERED', completed_at=NOW() WHERE id=$1`, [job.id]);
    current = await getCourierCurrentGroupedJob(fx.courierId);
    assert.equal(current, null, "delivered job is NOT returned as current");
    const history = await listCourierGroupedJobHistory(fx.courierId);
    assert.ok(history.some((h) => Number(h.deliveryJobId) === Number(job.id)), "delivered job in history");

    // Cancelled-only → still no current job.
    await c.query(`UPDATE delivery_job SET lifecycle_status='CANCELLED' WHERE id=$1`, [job.id]);
    assert.equal(await getCourierCurrentGroupedJob(fx.courierId), null, "cancelled job not current");
  } finally {
    await cleanupMultiStoreFixture(c, MARK);
    await c.query(`DELETE FROM courier_presence WHERE courier_user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`).catch(() => {});
    await c.end();
  }
});

test("Defect B (§3): assignment conflict retries to the next eligible courier", async () => {
  const c = newClient();
  await c.connect();
  const marker = "fixt_ms_c2_1";
  let courierB = null;
  try {
    const fx = await createMultiStoreFixture(c, { mark: MARK }); // courier A = fx.courierId (fresh presence)
    const job = await readyJob(c, fx);
    courierB = await addSecondCourier(c, 1, 40); // older presence → tried after A

    // Stale active grouped assignment for B on this job → assigning A collides
    // (courier_assignment target already held by B).
    await c.query(
      `INSERT INTO courier_assignment (delivery_job_id, courier_user_id, assignment_type, status, requested_at)
       VALUES ($1,$2,'grouped','assigned',NOW())`,
      [job.id, courierB]
    );

    await c.query("BEGIN");
    const outcome = await runGroupedAssignmentForGroupTx(c, fx.orderGroupId, {
      restrictToCourierUserIds: [fx.courierId, courierB],
    });
    await c.query("COMMIT");

    assert.equal(outcome.status, "ASSIGNED", "job assigned, not PENDING_NO_DRIVER");
    assert.equal(Number(outcome.courierUserId), Number(courierB), "the NEXT courier (B) won");

    const finalJob = (await c.query("SELECT * FROM delivery_job WHERE id=$1", [job.id])).rows[0];
    assert.equal(finalJob.assignment_status, "ASSIGNED");
    assert.equal(Number(finalJob.delivery_user_id), Number(courierB));

    const active = (
      await c.query(
        `SELECT COUNT(*)::int n FROM courier_assignment WHERE delivery_job_id=$1 AND ended_at IS NULL`,
        [job.id]
      )
    ).rows[0].n;
    assert.equal(Number(active), 1, "exactly one active courier_assignment");
  } finally {
    if (courierB) {
      await c.query(`DELETE FROM courier_assignment WHERE courier_user_id=$1`, [courierB]).catch(() => {});
      await c.query(`DELETE FROM courier_presence WHERE courier_user_id=$1`, [courierB]).catch(() => {});
      await c.query(`DELETE FROM courier_profile WHERE user_id=$1`, [courierB]).catch(() => {});
    }
    await cleanupMultiStoreFixture(c, MARK);
    await c.query(`DELETE FROM app_user WHERE username LIKE '${MARK}c2_%'`).catch(() => {});
    await c.end();
  }
});

test("Defect C (§4): no silent courier replacement; explicit reassignment works", async () => {
  const c = newClient();
  await c.connect();
  const marker = "fixt_ms_c2_2";
  let courierB = null;
  try {
    const fx = await createMultiStoreFixture(c, { mark: MARK });
    const job = await readyJob(c, fx);
    courierB = await addSecondCourier(c, 2, 40);

    // A stale active assignment held by B; assigning A must NOT silently replace B.
    await c.query(
      `INSERT INTO courier_assignment (delivery_job_id, courier_user_id, assignment_type, status, requested_at)
       VALUES ($1,$2,'grouped','assigned',NOW())`,
      [job.id, courierB]
    );
    await c.query("BEGIN");
    await assert.rejects(
      assignDeliveryJobTx(c, { orderGroupId: fx.orderGroupId, courierUserId: fx.courierId }),
      /ASSIGNMENT_CONFLICT/,
      "different courier is a hard conflict, not a silent replace"
    );
    await c.query("ROLLBACK");
    const holder = (
      await c.query(`SELECT courier_user_id FROM courier_assignment WHERE delivery_job_id=$1 AND ended_at IS NULL`, [job.id])
    ).rows[0];
    assert.equal(Number(holder.courier_user_id), Number(courierB), "courier not replaced");

    // Idempotent same-courier assignment for B succeeds.
    await c.query("BEGIN");
    const r = await assignDeliveryJobTx(c, { orderGroupId: fx.orderGroupId, courierUserId: courierB });
    await c.query("COMMIT");
    assert.ok(Number(r.assignmentId) > 0, "idempotent same-courier assignment returns the assignment");

    // Explicit reassignment A→ (currently B) → back to A: old ended, one active, A now.
    const res = await reassignGroupedJob({ orderGroupId: fx.orderGroupId, newCourierUserId: fx.courierId, reason: "TEST_REASSIGN" });
    assert.equal(Number(res.courierUserId), Number(fx.courierId));
    const afterJob = (await c.query("SELECT delivery_user_id FROM delivery_job WHERE id=$1", [job.id])).rows[0];
    assert.equal(Number(afterJob.delivery_user_id), Number(fx.courierId), "job now points to the new courier");
    const activeCount = Number(
      (await c.query(`SELECT COUNT(*)::int n FROM courier_assignment WHERE delivery_job_id=$1 AND ended_at IS NULL`, [job.id])).rows[0].n
    );
    assert.equal(activeCount, 1, "exactly one active assignment after reassignment");
    const endedCount = Number(
      (await c.query(`SELECT COUNT(*)::int n FROM courier_assignment WHERE delivery_job_id=$1 AND ended_at IS NOT NULL`, [job.id])).rows[0].n
    );
    assert.ok(endedCount >= 1, "old assignment closed with an ended reason");
  } finally {
    if (courierB) {
      await c.query(`DELETE FROM courier_assignment WHERE courier_user_id=$1`, [courierB]).catch(() => {});
      await c.query(`DELETE FROM courier_presence WHERE courier_user_id=$1`, [courierB]).catch(() => {});
      await c.query(`DELETE FROM courier_profile WHERE user_id=$1`, [courierB]).catch(() => {});
    }
    await cleanupMultiStoreFixture(c, MARK);
    await c.query(`DELETE FROM app_user WHERE username LIKE '${MARK}c2_%'`).catch(() => {});
    await c.end();
  }
});

test("Defect D (§5): normalized authority from identity, not courier_name; pickupStops", async () => {
  const c = newClient();
  await c.connect();
  try {
    const fx = await createMultiStoreFixture(c, { mark: MARK });
    const job = await readyJob(c, fx);
    await c.query("BEGIN");
    await assignDeliveryJobTx(c, { orderGroupId: fx.orderGroupId, courierUserId: fx.courierId });
    await c.query("COMMIT");

    // Null display name must NOT deactivate the assignment.
    await c.query(`UPDATE app_user SET full_name='' WHERE id=$1`, [fx.courierId]);
    let view = await getGroupedAssignmentView(c, fx.orderGroupId);
    assert.equal(view.active, true, "assignment active despite null courier name");
    assert.equal(Number(view.courierUserId), Number(fx.courierId));
    assert.ok(view.assignmentId > 0 && view.deliveryJobId > 0, "identity present");
    assert.equal(view.pickupStops.length, view.numberOfStores, "pickupStops agree with count");
    assert.ok(view.pickupStops.every((s) => s.stopId && s.storeId), "pickupStops carry store identity");

    // Ended assignment → inactive (authority is the courier_assignment).
    await c.query(`UPDATE courier_assignment SET ended_at=NOW(), status='released' WHERE delivery_job_id=$1`, [job.id]);
    view = await getGroupedAssignmentView(c, fx.orderGroupId);
    assert.equal(view.active, false, "ended assignment is inactive");
    assert.equal(view.pickupStops.length, 0, "no pickupStops when inactive");
  } finally {
    await cleanupMultiStoreFixture(c, MARK);
    await c.end();
  }
});
