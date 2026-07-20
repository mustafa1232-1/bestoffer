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
  acknowledgeGroupedJob,
  headingToPickups,
  markStopArrived,
  markStopCollected,
  headingToCustomer,
  markGroupedDelivered,
} from "../modules/delivery/delivery-job.service.js";
import { drainNotificationOutbox } from "../modules/delivery/notification-outbox.worker.js";
import { __setFirebaseMessagingForTests } from "../modules/notifications/notifications.repo.js";

function mockMessaging() {
  return {
    async sendEachForMulticast(msg) {
      const responses = msg.tokens.map(() => ({ success: true, messageId: "m" }));
      return { responses, successCount: responses.length, failureCount: 0 };
    },
  };
}

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

  // Seed the courier's push targets + Firebase mock BEFORE assignment, because
  // the assignment worker drains the outbox at assignment time. A correct
  // delivery-surface token plus a wrong store-surface token: only the delivery
  // token must receive the courier event (§14.13 surface suppression).
  const sid = Number(
    (
      await client.query(
        `INSERT INTO user_session (user_id, refresh_token, expires_at)
         VALUES ($1,$2, NOW() + INTERVAL '1 day') RETURNING id`,
        [fx.courierId, `fixt_co_sess_${fx.courierId}`]
      )
    ).rows[0].id
  );
  await client.query(
    `INSERT INTO user_push_token (user_id, push_token, app_surface, is_active, auth_session_id, locale)
     VALUES ($1,$2,'delivery',TRUE,$3,'ar'), ($1,$4,'store',TRUE,$3,'ar')`,
    [fx.courierId, `fixt_co_tokD_${fx.courierId}`, sid, `fixt_co_tokS_${fx.courierId}`]
  );
  __setFirebaseMessagingForTests(mockMessaging());

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

  // (6) The authoritative grouped courier_assignment exists (§14.6).
  const assignmentId = Number(view.assignmentId);
  assert.ok(assignmentId > 0, "grouped assignment id present in normalized view");
  const caCount = Number(
    (
      await client.query(
        `SELECT COUNT(*)::int n FROM courier_assignment
          WHERE delivery_job_id=$1 AND order_id IS NULL AND ended_at IS NULL`,
        [job.id]
      )
    ).rows[0].n
  );
  assert.equal(caCount, 1, "exactly one grouped courier_assignment (not per child)");

  // (10-13) Outbox → exactly one app_notification, truthful status, no dupes.
  // The assignment worker already drained once (mock + tokens were set before
  // assignment); drain again to prove terminal rows are not reprocessed.
  await drainNotificationOutbox({ limit: 50 });
  const notifCount = async () =>
    Number(
      (
        await client.query(
          `SELECT COUNT(*)::int n FROM app_notification WHERE event_id=$1`,
          [`deliveryjob-assign-${job.id}-${fx.courierId}`]
        )
      ).rows[0].n
    );
  assert.equal(await notifCount(), 1, "outbox creates exactly one app_notification");
  const obState = (
    await client.query(
      `SELECT status, provider_result_json FROM notification_outbox WHERE event_id=$1`,
      [`deliveryjob-assign-${job.id}-${fx.courierId}`]
    )
  ).rows[0];
  assert.equal(obState.status, "PUSH_ACCEPTED", "truthful accepted status");
  assert.equal(obState.provider_result_json.acceptedTokens, 1, "only the delivery-surface token accepted");
  // Re-drain: terminal row is not reprocessed → still one notification.
  await drainNotificationOutbox({ limit: 50 });
  assert.equal(await notifCount(), 1, "retry does not duplicate the notification");

  // (14-16) Lifecycle: acknowledge → head → collect stop1 (stop2 pending) →
  // cannot head to customer → collect stop2 → head → deliver all surfaces.
  const [stopA, stopB] = jobs[0].pickupStops.map((s) => Number(s.id));
  await acknowledgeGroupedJob({ courierUserId: fx.courierId, deliveryJobId: job.id });
  await headingToPickups({ courierUserId: fx.courierId, deliveryJobId: job.id });
  await markStopArrived({ courierUserId: fx.courierId, deliveryJobId: job.id, stopId: stopA });
  const col1 = await markStopCollected({ courierUserId: fx.courierId, deliveryJobId: job.id, stopId: stopA });
  assert.equal(col1.allCollected, false, "collecting stop 1 leaves stop 2 pending");
  assert.equal(col1.remainingStops, 1);

  await assert.rejects(
    headingToCustomer({ courierUserId: fx.courierId, deliveryJobId: job.id }),
    /PICKUPS_INCOMPLETE/,
    "cannot head to customer before all stops collected"
  );

  const col2 = await markStopCollected({ courierUserId: fx.courierId, deliveryJobId: job.id, stopId: stopB });
  assert.equal(col2.allCollected, true, "both stops collected");
  const htc = await headingToCustomer({ courierUserId: fx.courierId, deliveryJobId: job.id });
  assert.equal(htc.lifecycleStatus, "HEADING_TO_CUSTOMER");

  const delivered = await markGroupedDelivered({ courierUserId: fx.courierId, deliveryJobId: job.id });
  assert.equal(delivered.lifecycleStatus, "DELIVERED");

  // All surfaces complete: children delivered, grouped assignment completed.
  const finalChildren = (
    await client.query(
      `SELECT status FROM customer_order WHERE order_group_id=$1`,
      [fx.orderGroupId]
    )
  ).rows;
  assert.ok(
    finalChildren.every((r) => r.status === "delivered"),
    "all child orders delivered"
  );
  const finalGroup = (
    await client.query(
      `SELECT status FROM order_group WHERE id=$1`,
      [fx.orderGroupId]
    )
  ).rows[0];
  assert.equal(finalGroup.status, "completed", "order group terminal status");
  const caFinal = (
    await client.query(
      `SELECT status, completed_at FROM courier_assignment WHERE delivery_job_id=$1`,
      [job.id]
    )
  ).rows[0];
  assert.equal(caFinal.status, "completed", "grouped assignment completed");
  assert.ok(caFinal.completed_at, "assignment completed_at set");

  __setFirebaseMessagingForTests(null);
});
