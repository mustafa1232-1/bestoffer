// End-to-end grouped multi-store delivery test (delivery closure §16).
//
// This test exercises the REAL production path — it does NOT call
// assignDeliveryJobTx directly:
//   1. Customer places a real two-store checkout via createOrderGroupWithItems.
//   2. The checkout transaction auto-creates ONE delivery_job + two pickup stops.
//   3. Store 1 accepts (real updateOwnerOrderStatus) → not ready yet.
//   4. Store 2 accepts → group becomes READY_FOR_ASSIGNMENT.
//   5. The real production worker (processGroupedAssignmentBatch) assigns ONE
//      courier to the whole job.
//   6. Assert one job, one courier, two stops, both children mirror the courier,
//      the courier grouped query returns one job, the User view is active, the
//      notification outbox event exists, and NO per-child individual assignment
//      was created by the legacy per-order worker.

// Disable the fire-and-forget recovery trigger so this file's real store
// acceptance calls do not spawn an unscoped background grouped pass that could
// race the foreground worker or touch other test files' groups (all test files
// share one database). Read at call-time inside requestDeliveryAssignmentRecovery.
process.env.DELIVERY_AUTO_RECOVERY_DISABLED = "1";

import test from "node:test";
import assert from "node:assert/strict";
import { pool } from "../config/db.js";
import {
  createRealMultiStoreCheckout,
  cleanupCheckoutFixture,
} from "./fixtures/multistore-checkout.fixture.js";
import { updateOwnerOrderStatus } from "../modules/orders/orders.repo.js";
import {
  processGroupedAssignmentBatch,
  loadPendingAssignmentOrders,
} from "../modules/orders/delivery-assignment.worker.js";
import {
  listCourierGroupedJobs,
  getGroupedAssignmentView,
} from "../modules/delivery/delivery-job.service.js";

async function jobRow(client, orderGroupId) {
  return (
    await client.query("SELECT * FROM delivery_job WHERE order_group_id=$1", [
      orderGroupId,
    ])
  ).rows[0];
}

async function acceptStoreFully(ownerUserId, orderId) {
  // pending → approved → preparing → ready_for_delivery (real transitions).
  await updateOwnerOrderStatus(ownerUserId, orderId, "approved", null, null);
  await updateOwnerOrderStatus(ownerUserId, orderId, "preparing", null, null);
  await updateOwnerOrderStatus(ownerUserId, orderId, "ready_for_delivery", null, null);
}

test("E2E: real checkout → store acceptance → grouped worker assigns one courier", async (t) => {
  const client = await pool.connect();
  t.after(async () => {
    // Let the fire-and-forget requestDeliveryAssignmentRecovery trigger (queued
    // by updateOwnerOrderStatus after commit) settle before we delete rows, so
    // its in-flight grouped pass does not race the teardown.
    await new Promise((r) => setTimeout(r, 500));
    await cleanupCheckoutFixture(client).catch(() => {});
    client.release();
  });

  const fx = await createRealMultiStoreCheckout(client);
  assert.equal(fx.childOrderIds.length, 2, "two child orders created");

  // (2) checkout auto-created the grouped job + two pickup stops.
  let job = await jobRow(client, fx.orderGroupId);
  assert.ok(job, "delivery_job auto-created by checkout");
  assert.equal(job.assignment_status, "PENDING_STORES", "job starts PENDING_STORES");
  const stopCount = Number(
    (
      await client.query(
        "SELECT COUNT(*)::int AS n FROM delivery_pickup_stop WHERE delivery_job_id=$1",
        [job.id]
      )
    ).rows[0].n
  );
  assert.equal(stopCount, 2, "one pickup stop per store");

  // (3) Store 1 accepts fully → still not ready (store 2 pending).
  const [c1, c2] = fx.childOrderIds;
  await acceptStoreFully(fx.childOwnerByOrderId.get(c1), c1);
  job = await jobRow(client, fx.orderGroupId);
  assert.notEqual(
    job.assignment_status,
    "READY_FOR_ASSIGNMENT",
    "not ready while store 2 is still pending"
  );

  // (4) Store 2 accepts → group becomes READY_FOR_ASSIGNMENT.
  await acceptStoreFully(fx.childOwnerByOrderId.get(c2), c2);
  job = await jobRow(client, fx.orderGroupId);
  assert.equal(
    job.assignment_status,
    "READY_FOR_ASSIGNMENT",
    "ready once every active store accepted"
  );
  assert.equal(job.delivery_user_id, null, "no courier before the worker runs");

  // (5) The REAL production worker assigns one courier to the whole job. Scoped
  // to this test's own group + courier so a shared, concurrently-written test
  // database cannot make the assertion flaky (production runs unscoped/global).
  const summary = await processGroupedAssignmentBatch({
    limit: 10,
    orderGroupIds: [fx.orderGroupId],
    restrictToCourierUserIds: [fx.courierId],
  });
  assert.ok(summary.assigned >= 1, "grouped worker assigned at least one job");

  // (6) Authoritative assertions.
  job = await jobRow(client, fx.orderGroupId);
  assert.equal(job.assignment_status, "ASSIGNED", "job ASSIGNED");
  assert.equal(Number(job.delivery_user_id), fx.courierId, "assigned to our courier");

  const activeStops = (
    await client.query(
      "SELECT * FROM delivery_pickup_stop WHERE delivery_job_id=$1 AND pickup_status<>'CANCELLED'",
      [job.id]
    )
  ).rows;
  assert.equal(activeStops.length, 2, "two active pickup stops");

  // Both child orders mirror the same courier (legacy-compat surfaces resolve it).
  const mirrored = (
    await client.query(
      `SELECT delivery_user_id, delivery_assignment_status
         FROM customer_order WHERE order_group_id=$1`,
      [fx.orderGroupId]
    )
  ).rows;
  for (const row of mirrored) {
    assert.equal(Number(row.delivery_user_id), fx.courierId, "child mirrors courier");
    assert.equal(row.delivery_assignment_status, "ASSIGNED", "child ASSIGNED");
  }

  // Authoritative courier grouped query returns ONE job with two stores.
  const jobs = await listCourierGroupedJobs(client, fx.courierId);
  assert.equal(jobs.length, 1, "courier sees exactly one grouped job");
  assert.equal(jobs[0].numberOfStores, 2, "one grouped job spanning two stores");

  // User/Store normalized assignment view is active only now.
  const view = await getGroupedAssignmentView(client, fx.orderGroupId);
  assert.equal(view.active, true, "assignment view active");
  assert.equal(view.courierUserId, fx.courierId, "view resolves the courier");

  // Notification outbox event was created in the assignment transaction.
  const outbox = (
    await client.query(
      `SELECT event_type, status FROM notification_outbox
        WHERE target_entity_type='delivery_job' AND target_entity_id=$1`,
      [job.id]
    )
  ).rows;
  assert.equal(outbox.length, 1, "one grouped assignment outbox event");
  assert.equal(
    outbox[0].event_type,
    "COURIER_MULTI_STORE_DELIVERY_ASSIGNED",
    "multi-store event type"
  );

  // The legacy per-order worker must NOT pick up group children at all.
  await client.query("BEGIN");
  const perOrder = await loadPendingAssignmentOrders(client, 50);
  await client.query("COMMIT");
  const leaked = perOrder.filter((r) => fx.childOrderIds.includes(Number(r.id)));
  assert.equal(leaked.length, 0, "per-order worker excludes group children");
});
