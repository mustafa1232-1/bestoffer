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
  acknowledgeGroupedJob,
  headingToPickups,
  markStopArrived,
  markStopCollected,
  headingToCustomer,
  markGroupedDelivered,
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

test("completion releases courier for a second grouped job without relogin", async () => {
  const c = newClient();
  await c.connect();
  try {
    const fx = await createMultiStoreFixture(c, { mark: "fixt_ms_second_" });

    await c.query("BEGIN");
    await ensureDeliveryJobForGroup(c, fx.orderGroupId);
    await recomputeGroupReadiness(c, fx.orderGroupId);
    const first = await assignDeliveryJobTx(c, {
      orderGroupId: fx.orderGroupId,
      courierUserId: fx.courierId,
      idempotencyKey: `first-${fx.orderGroupId}`,
    });
    await c.query("COMMIT");

    await acknowledgeGroupedJob({
      courierUserId: fx.courierId,
      deliveryJobId: first.job.id,
    });
    await headingToPickups({
      courierUserId: fx.courierId,
      deliveryJobId: first.job.id,
    });
    for (const stop of first.stops) {
      await markStopArrived({
        courierUserId: fx.courierId,
        deliveryJobId: first.job.id,
        stopId: Number(stop.id),
      });
      await markStopCollected({
        courierUserId: fx.courierId,
        deliveryJobId: first.job.id,
        stopId: Number(stop.id),
      });
    }
    await headingToCustomer({
      courierUserId: fx.courierId,
      deliveryJobId: first.job.id,
    });
    await markGroupedDelivered({
      courierUserId: fx.courierId,
      deliveryJobId: first.job.id,
    });

    const closed = await c.query(
      `SELECT status, ended_at
       FROM courier_assignment
       WHERE delivery_job_id=$1`,
      [first.job.id]
    );
    assert.equal(closed.rows[0].status, "completed");
    assert.ok(closed.rows[0].ended_at, "first assignment ended");

    const eligibleAfterCompletion = await selectEligibleCourier(c, {
      restrictToCourierUserIds: [fx.courierId],
    });
    assert.equal(eligibleAfterCompletion.courierUserId, fx.courierId);

    const secondGroupId = Number(
      (
        await c.query(
          `INSERT INTO order_group
             (public_id, customer_user_id, status, is_multi_store, stores_count, payment_method)
           VALUES ($1,$2,'active',TRUE,2,'cash') RETURNING id`,
          [`fixt_ms_second_${Date.now()}_grp2`, fx.customerId]
        )
      ).rows[0].id
    );
    for (const [index, merchantId] of fx.merchantIds.entries()) {
      await c.query(
        `INSERT INTO customer_order
           (merchant_id, customer_user_id, customer_full_name, customer_phone,
            customer_block, customer_building_number, customer_apartment,
            order_group_id, status, delivery_type, delivery_assignment_status,
            order_scope, courier_source)
         VALUES ($1,$2,$3,'0770','A101','1','1',$4,'ready_for_delivery','delivery','NOT_REQUIRED','group_child','app')`,
        [merchantId, fx.customerId, `fixt_ms_second_order_${index}`, secondGroupId]
      );
    }

    await c.query("BEGIN");
    await ensureDeliveryJobForGroup(c, secondGroupId);
    await recomputeGroupReadiness(c, secondGroupId);
    const second = await assignDeliveryJobTx(c, {
      orderGroupId: secondGroupId,
      courierUserId: fx.courierId,
      idempotencyKey: `second-${secondGroupId}`,
    });
    await c.query("COMMIT");

    assert.equal(Number(second.job.delivery_user_id), fx.courierId);
    assert.equal(second.job.assignment_status, "ASSIGNED");
  } catch (error) {
    await c.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    await cleanupMultiStoreFixture(c, "fixt_ms_second_");
    await c.end();
  }
});

test("readiness starts after every active store accepts, but pickup waits for ready status", async () => {
  const c = newClient();
  await c.connect();
  try {
    const fx = await createMultiStoreFixture(c, { childStatus: "approved" });

    await c.query("BEGIN");
    await ensureDeliveryJobForGroup(c, fx.orderGroupId);
    let readiness = await recomputeGroupReadiness(c, fx.orderGroupId);
    assert.equal(readiness, "READY_FOR_ASSIGNMENT");
    const assigned = await assignDeliveryJobTx(c, {
      orderGroupId: fx.orderGroupId,
      courierUserId: fx.courierId,
    });
    await c.query("COMMIT");

    await acknowledgeGroupedJob({
      courierUserId: fx.courierId,
      deliveryJobId: assigned.job.id,
    });
    await headingToPickups({
      courierUserId: fx.courierId,
      deliveryJobId: assigned.job.id,
    });
    await markStopArrived({
      courierUserId: fx.courierId,
      deliveryJobId: assigned.job.id,
      stopId: Number(assigned.stops[0].id),
    });
    await assert.rejects(
      markStopCollected({
        courierUserId: fx.courierId,
        deliveryJobId: assigned.job.id,
        stopId: Number(assigned.stops[0].id),
      }),
      (error) => error.code === "PICKUP_STOP_NOT_READY"
    );

    await c.query(
      `UPDATE customer_order
       SET status='ready_for_delivery'
       WHERE order_group_id=$1`,
      [fx.orderGroupId]
    );
    const collected = await markStopCollected({
      courierUserId: fx.courierId,
      deliveryJobId: assigned.job.id,
      stopId: Number(assigned.stops[0].id),
    });
    assert.equal(collected.pickupStatus, "COLLECTED");
  } catch (error) {
    await c.query("ROLLBACK").catch(() => {});
    throw error;
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
