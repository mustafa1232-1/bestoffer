import assert from "node:assert/strict";
import test from "node:test";
import pg from "pg";

import {
  ensureDeliveryJobForGroup,
  recomputeGroupReadiness,
  selectEligibleCourier,
  assignDeliveryJobTx,
  listCourierGroupedJobs,
  getGroupedAssignmentView,
} from "../modules/delivery/delivery-job.service.js";
import {
  createMultiStoreFixture,
  cleanupMultiStoreFixture,
} from "./fixtures/multistore-delivery.fixture.js";

function newClient() {
  return new pg.Client({ connectionString: process.env.DATABASE_URL });
}

test("DEFECT reproduction: no grouped job → courier sees nothing", async () => {
  const c = newClient();
  await c.connect();
  try {
    const fx = await createMultiStoreFixture(c);
    // Simulate the legacy false-assigned state: mark ONE child order ASSIGNED
    // per the old per-order model, without any grouped delivery_job.
    await c.query(
      `UPDATE customer_order SET delivery_assignment_status='ASSIGNED', delivery_user_id=$2 WHERE id=$1`,
      [fx.childOrderIds[0], fx.courierId]
    );
    // The authoritative grouped view reports NOT active (no delivery_job) even
    // though a legacy per-child flag says assigned → the exact defect.
    const view = await getGroupedAssignmentView(c, fx.orderGroupId);
    assert.equal(view.active, false, "grouped assignment must not be active yet");
    const jobs = await listCourierGroupedJobs(c, fx.courierId);
    assert.equal(jobs.length, 0, "courier grouped query returns nothing pre-fix");
  } finally {
    await cleanupMultiStoreFixture(c);
    await c.end();
  }
});

test("FIX: one grouped job, one courier, two pickup stops, courier sees it", async () => {
  const c = newClient();
  await c.connect();
  try {
    const fx = await createMultiStoreFixture(c);

    await c.query("BEGIN");
    await ensureDeliveryJobForGroup(c, fx.orderGroupId);
    const readiness = await recomputeGroupReadiness(c, fx.orderGroupId);
    assert.equal(readiness, "READY_FOR_ASSIGNMENT");

    const { courierUserId, excluded } = await selectEligibleCourier(c, { restrictToCourierUserIds: [fx.courierId] });
    assert.equal(courierUserId, fx.courierId, `courier chosen; excluded=${JSON.stringify(excluded)}`);

    const result = await assignDeliveryJobTx(c, {
      orderGroupId: fx.orderGroupId,
      courierUserId,
      idempotencyKey: `test-${fx.orderGroupId}`,
    });
    await c.query("COMMIT");

    assert.equal(result.job.assignment_status, "ASSIGNED");
    assert.equal(Number(result.job.delivery_user_id), fx.courierId);
    assert.equal(result.stops.length, 2, "two pickup stops");

    // Courier now sees ONE grouped job with both stores.
    const jobs = await listCourierGroupedJobs(c, fx.courierId);
    assert.equal(jobs.length, 1, "exactly one grouped job");
    assert.equal(jobs[0].numberOfStores, 2);
    assert.equal(Number(jobs[0].order_group_id), fx.orderGroupId);

    // User/Store view now authoritatively shows assigned.
    const view = await getGroupedAssignmentView(c, fx.orderGroupId);
    assert.equal(view.active, true);
    assert.equal(view.courierUserId, fx.courierId);

    // Notification outbox event created in the same transaction.
    const outbox = await c.query(
      `SELECT event_type, target_surface FROM notification_outbox WHERE event_id=$1`,
      [`deliveryjob-assign-${result.job.id}-${fx.courierId}`]
    );
    assert.equal(outbox.rowCount, 1);
    assert.equal(outbox.rows[0].event_type, "COURIER_MULTI_STORE_DELIVERY_ASSIGNED");
    assert.equal(outbox.rows[0].target_surface, "delivery");

    // §6: exactly one authoritative grouped courier_assignment (not per child).
    assert.ok(Number(result.assignmentId) > 0, "assignmentId returned");
    const ca = await c.query(
      `SELECT id, order_id, delivery_job_id, assignment_type, status
         FROM courier_assignment WHERE delivery_job_id=$1 AND ended_at IS NULL`,
      [result.job.id]
    );
    assert.equal(ca.rowCount, 1, "one grouped courier_assignment");
    assert.equal(ca.rows[0].order_id, null, "grouped row has no order_id");
    assert.equal(ca.rows[0].assignment_type, "grouped");

    // Both legacy child orders point at the same courier (compatibility).
    const kids = await c.query(
      `SELECT delivery_user_id FROM customer_order WHERE order_group_id=$1`,
      [fx.orderGroupId]
    );
    assert.ok(kids.rows.every((r) => Number(r.delivery_user_id) === fx.courierId));
  } finally {
    await cleanupMultiStoreFixture(c);
    await c.end();
  }
});

test("concurrency: two assignment attempts → only one succeeds", async () => {
  const c = newClient();
  await c.connect();
  try {
    const fx = await createMultiStoreFixture(c);
    await c.query("BEGIN");
    await ensureDeliveryJobForGroup(c, fx.orderGroupId);
    await recomputeGroupReadiness(c, fx.orderGroupId);
    await c.query("COMMIT");

    const attempt = async () => {
      const client = newClient();
      await client.connect();
      try {
        await client.query("BEGIN");
        const r = await assignDeliveryJobTx(client, {
          orderGroupId: fx.orderGroupId,
          courierUserId: fx.courierId,
        });
        await client.query("COMMIT");
        return r.alreadyAssigned ? "already" : "assigned";
      } catch (e) {
        await client.query("ROLLBACK").catch(() => {});
        return `error:${e.code || e.message}`;
      } finally {
        await client.end();
      }
    };

    const [a, b] = await Promise.all([attempt(), attempt()]);
    const outcomes = [a, b].sort().join(",");
    // Exactly one fresh assignment; the other is a conflict or idempotent hit.
    const freshCount = [a, b].filter((x) => x === "assigned").length;
    assert.equal(freshCount, 1, `outcomes=${outcomes}`);

    // Still exactly one grouped job for the courier.
    const jobs = await listCourierGroupedJobs(c, fx.courierId);
    assert.equal(jobs.length, 1);
  } finally {
    await cleanupMultiStoreFixture(c);
    await c.end();
  }
});

test("PENDING_NO_DRIVER: no eligible courier → not assigned, no false state", async () => {
  const c = newClient();
  await c.connect();
  try {
    const fx = await createMultiStoreFixture(c, { courierOnline: false });
    await c.query("BEGIN");
    await ensureDeliveryJobForGroup(c, fx.orderGroupId);
    await recomputeGroupReadiness(c, fx.orderGroupId);
    await c.query("COMMIT");

    const { courierUserId, excluded } = await selectEligibleCourier(c, { restrictToCourierUserIds: [fx.courierId] });
    assert.equal(courierUserId, null);
    assert.ok(excluded.some((e) => e.courierUserId === fx.courierId));

    const view = await getGroupedAssignmentView(c, fx.orderGroupId);
    assert.equal(view.active, false, "no false ASSIGNED when no driver");
  } finally {
    await cleanupMultiStoreFixture(c);
    await c.end();
  }
});

test("partial cancellation: cancelled child removed from active pickups", async () => {
  const c = newClient();
  await c.connect();
  try {
    const fx = await createMultiStoreFixture(c);
    await c.query("BEGIN");
    await ensureDeliveryJobForGroup(c, fx.orderGroupId);
    // Cancel one child order, then re-sync.
    await c.query(`UPDATE customer_order SET status='cancelled' WHERE id=$1`, [
      fx.childOrderIds[1],
    ]);
    await ensureDeliveryJobForGroup(c, fx.orderGroupId);
    const readiness = await recomputeGroupReadiness(c, fx.orderGroupId);
    assert.equal(readiness, "READY_FOR_ASSIGNMENT", "still ready with 1 active store");
    const { courierUserId } = await selectEligibleCourier(c, { restrictToCourierUserIds: [fx.courierId] });
    const r = await assignDeliveryJobTx(c, {
      orderGroupId: fx.orderGroupId,
      courierUserId,
    });
    await c.query("COMMIT");
    assert.equal(r.stops.length, 1, "only the active store remains as a pickup");
  } finally {
    await cleanupMultiStoreFixture(c);
    await c.end();
  }
});
