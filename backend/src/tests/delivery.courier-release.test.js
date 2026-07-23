// Courier release after a completed single-store delivery.
//
// Reported defect: "the courier takes the first order and finishes it normally,
// but is never assigned a second one". Root cause: the courier-facing completion
// endpoint (POST /api/orders/:id/courier/delivered -> courierMarkDelivered) only
// flipped the order to `delivered`. It left BOTH busy markers in place —
// customer_order.delivery_assignment_status='ASSIGNED' and an open
// courier_assignment (ended_at IS NULL) — which every eligibility filter reads
// as "still on a delivery", and which the partial unique index
// uq_courier_assignment_open_courier turns into a hard 23505 on the next
// assignment INSERT. One order per courier, forever.
//
// These tests pin the release contract and the worker's self-healing sweep.

import test from "node:test";
import assert from "node:assert/strict";
import pg from "pg";
import {
  courierMarkPickedUp,
  courierMarkArrived,
  courierMarkDelivered,
} from "../modules/commerce/commerce.repo.js";
import { reconcileStaleCourierAssignments } from "../modules/orders/delivery-assignment.worker.js";
import { getDeliveryOrderDetail } from "../modules/orders/orders.repo.js";
import { selectEligibleCourier } from "../modules/delivery/delivery-job.service.js";

const MARK = "fixt_rel_";

function newClient() {
  return new pg.Client({ connectionString: process.env.DATABASE_URL });
}

async function cleanup(c) {
  await c
    .query(
      `DELETE FROM courier_assignment
        WHERE courier_user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')
           OR order_id IN (
             SELECT id FROM customer_order
              WHERE customer_user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')
           )`
    )
    .catch(() => {});
  await c
    .query(
      `DELETE FROM customer_order
        WHERE customer_user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')
           OR delivery_user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
    )
    .catch(() => {});
  await c
    .query(`DELETE FROM merchant WHERE name LIKE '${MARK}%'`)
    .catch(() => {});
  await c
    .query(
      `DELETE FROM courier_presence WHERE courier_user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
    )
    .catch(() => {});
  await c
    .query(
      `DELETE FROM courier_profile WHERE user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
    )
    .catch(() => {});
  await c.query(`DELETE FROM app_user WHERE username LIKE '${MARK}%'`).catch(() => {});
}

async function makeUser(c, { suffix, role }) {
  return Number(
    (
      await c.query(
        `INSERT INTO app_user
           (full_name, phone, pin_hash, block, building_number, apartment, username, role,
            delivery_account_approved, is_account_disabled)
         VALUES ('rel',$1,'x','A','1','1',$2,$3,TRUE,FALSE)
         RETURNING id`,
        [`09${suffix}`.slice(0, 15), `${MARK}${suffix}`, role]
      )
    ).rows[0].id
  );
}

async function makeCourier(c, suffix) {
  const uid = await makeUser(c, { suffix, role: "delivery" });
  await c.query(
    `INSERT INTO courier_profile (user_id, is_app_courier, active_status, availability_status, driver_type)
     VALUES ($1, TRUE, TRUE, 'online', 'app_driver')`,
    [uid]
  );
  await c.query(
    `INSERT INTO courier_presence (courier_user_id, is_online, recorded_at, updated_at)
     VALUES ($1, TRUE, NOW(), NOW())`,
    [uid]
  );
  return uid;
}

async function makeAssignedOrder(c, { merchantId, customerId, courierId, suffix }) {
  const orderId = Number(
    (
      await c.query(
        `INSERT INTO customer_order
           (merchant_id, customer_user_id, customer_full_name, customer_phone, customer_block,
            customer_building_number, customer_apartment, status, delivery_type,
            delivery_assignment_status, delivery_user_id, courier_assigned_at)
         VALUES ($1,$2,$3,'0700','A','1','1','ready_for_delivery','delivery','ASSIGNED',$4,NOW())
         RETURNING id`,
        [merchantId, customerId, `${MARK}${suffix}`, courierId]
      )
    ).rows[0].id
  );
  await c.query(
    `INSERT INTO courier_assignment
       (order_id, courier_user_id, assignment_type, status, requested_at, assigned_at)
     VALUES ($1,$2,'store_auto','assigned',NOW(),NOW())`,
    [orderId, courierId]
  );
  return orderId;
}

async function busyMarkers(c, courierId) {
  const openAssignments = Number(
    (
      await c.query(
        `SELECT COUNT(*)::int AS n FROM courier_assignment
          WHERE courier_user_id = $1 AND ended_at IS NULL`,
        [courierId]
      )
    ).rows[0].n
  );
  const assignedOrders = Number(
    (
      await c.query(
        `SELECT COUNT(*)::int AS n FROM customer_order
          WHERE delivery_user_id = $1 AND delivery_assignment_status = 'ASSIGNED'`,
        [courierId]
      )
    ).rows[0].n
  );
  return { openAssignments, assignedOrders };
}

test("delivery: a courier who completes an order becomes available again", async (t) => {
  const c = newClient();
  await c.connect();
  t.after(async () => {
    await cleanup(c).catch(() => {});
    await c.end();
  });
  await cleanup(c);

  const merchantId = Number(
    (
      await c.query(
        `INSERT INTO merchant (name, type, is_open) VALUES ('${MARK}store','market',TRUE) RETURNING id`
      )
    ).rows[0].id
  );
  const customerId = await makeUser(c, { suffix: "cust", role: "user" });
  const courierId = await makeCourier(c, "drv");
  const orderId = await makeAssignedOrder(c, {
    merchantId,
    customerId,
    courierId,
    suffix: "o1",
  });

  const before = await busyMarkers(c, courierId);
  assert.equal(before.openAssignments, 1, "courier starts busy on the assignment");
  assert.equal(before.assignedOrders, 1, "courier starts busy on the order");

  await courierMarkPickedUp({ courierUserId: courierId, orderId });
  await courierMarkArrived({ courierUserId: courierId, orderId });
  await courierMarkDelivered({ courierUserId: courierId, orderId });

  const after = await busyMarkers(c, courierId);
  assert.equal(
    after.openAssignments,
    0,
    "the courier_assignment is closed when the delivery completes"
  );
  assert.equal(
    after.assignedOrders,
    0,
    "the order stops being flagged ASSIGNED to the courier"
  );

  const order = (
    await c.query(
      "SELECT status, delivery_assignment_status FROM customer_order WHERE id = $1",
      [orderId]
    )
  ).rows[0];
  assert.equal(order.status, "delivered");
  assert.equal(order.delivery_assignment_status, "COMPLETED");

  const assignment = (
    await c.query(
      "SELECT status, ended_reason FROM courier_assignment WHERE order_id = $1",
      [orderId]
    )
  ).rows[0];
  assert.equal(assignment.status, "completed");
  assert.equal(assignment.ended_reason, "COMPLETED");

  // The whole point: the dispatcher can pick this courier for the next order.
  const selection = await selectEligibleCourier(c, {
    restrictToCourierUserIds: [courierId],
  });
  assert.equal(
    selection.courierUserId,
    courierId,
    `courier is selectable for a second order; excluded=${JSON.stringify(selection.excluded)}`
  );

  // And a second assignment INSERT no longer collides with a leftover open row.
  const secondOrderId = await makeAssignedOrder(c, {
    merchantId,
    customerId,
    courierId,
    suffix: "o2",
  });
  const second = await busyMarkers(c, courierId);
  assert.equal(second.openAssignments, 1, "the second order assigns cleanly");
  assert.equal(second.assignedOrders, 1, "the courier is busy on the second order only");
});

test("delivery: the courier can still open the order they just delivered", async (t) => {
  // Pressing "delivered" flips delivery_assignment_status to COMPLETED. The
  // courier's order screen refetches the order right after, so gating that read
  // on ASSIGNED made it 404 (surfaced in the app as a route-not-found toast)
  // even though the delivery itself had succeeded.
  const c = newClient();
  await c.connect();
  t.after(async () => {
    await cleanup(c).catch(() => {});
    await c.end();
  });
  await cleanup(c);

  const merchantId = Number(
    (
      await c.query(
        `INSERT INTO merchant (name, type, is_open) VALUES ('${MARK}store5','market',TRUE) RETURNING id`
      )
    ).rows[0].id
  );
  const customerId = await makeUser(c, { suffix: "cust5", role: "user" });
  const courierId = await makeCourier(c, "drv5");
  const otherCourierId = await makeCourier(c, "drv5b");
  const orderId = await makeAssignedOrder(c, {
    merchantId,
    customerId,
    courierId,
    suffix: "o5",
  });

  await courierMarkPickedUp({ courierUserId: courierId, orderId });
  await courierMarkArrived({ courierUserId: courierId, orderId });
  await courierMarkDelivered({ courierUserId: courierId, orderId });

  const detail = await getDeliveryOrderDetail({
    requestUserId: courierId,
    requestUserRole: "delivery",
    orderId,
  });
  assert.equal(Number(detail.id ?? detail.order?.id), orderId);

  // A courier who never held the order still cannot read it.
  await assert.rejects(
    () =>
      getDeliveryOrderDetail({
        requestUserId: otherCourierId,
        requestUserRole: "delivery",
        orderId,
      }),
    (error) => String(error?.message).includes("ORDER_NOT_FOUND"),
    "an unrelated courier is still denied"
  );
});

test("delivery: the recovery sweep frees couriers stranded on terminal orders", async (t) => {
  const c = newClient();
  await c.connect();
  t.after(async () => {
    await cleanup(c).catch(() => {});
    await c.end();
  });
  await cleanup(c);

  const merchantId = Number(
    (
      await c.query(
        `INSERT INTO merchant (name, type, is_open) VALUES ('${MARK}store2','market',TRUE) RETURNING id`
      )
    ).rows[0].id
  );
  const customerId = await makeUser(c, { suffix: "cust2", role: "user" });
  const courierId = await makeCourier(c, "drv2");
  const orderId = await makeAssignedOrder(c, {
    merchantId,
    customerId,
    courierId,
    suffix: "o3",
  });

  // Simulate the pre-fix state written by an older build: the order is
  // delivered, yet both busy markers survived.
  await c.query(
    `UPDATE customer_order
        SET status = 'delivered', delivered_at = NOW()
      WHERE id = $1`,
    [orderId]
  );
  const stranded = await busyMarkers(c, courierId);
  assert.equal(stranded.openAssignments, 1, "reproduces the stranded open assignment");
  assert.equal(stranded.assignedOrders, 1, "reproduces the stranded ASSIGNED flag");

  const summary = await reconcileStaleCourierAssignments(c);
  assert.ok(
    summary.closedTerminalOrderAssignments >= 1,
    "sweep closes the assignment of a terminal order"
  );
  assert.ok(summary.clearedOrderFlags >= 1, "sweep clears the stale ASSIGNED flag");

  const healed = await busyMarkers(c, courierId);
  assert.equal(healed.openAssignments, 0, "no open assignment remains");
  assert.equal(healed.assignedOrders, 0, "no ASSIGNED order remains");

  const selection = await selectEligibleCourier(c, {
    restrictToCourierUserIds: [courierId],
  });
  assert.equal(
    selection.courierUserId,
    courierId,
    `stranded courier is selectable after the sweep; excluded=${JSON.stringify(selection.excluded)}`
  );
});

test("delivery: the sweep settles a grouped job whose children all finished", async (t) => {
  // Production shape: a multi-store job stayed ASSIGNED while its child orders
  // were completed through the per-order screens, so the grouped assignment kept
  // holding the courier as `busy_grouped_job` with no work left to do.
  const c = newClient();
  await c.connect();
  t.after(async () => {
    await cleanup(c).catch(() => {});
    await c.end();
  });
  await cleanup(c);

  const merchantId = Number(
    (
      await c.query(
        `INSERT INTO merchant (name, type, is_open) VALUES ('${MARK}store4','market',TRUE) RETURNING id`
      )
    ).rows[0].id
  );
  const customerId = await makeUser(c, { suffix: "cust4", role: "user" });
  const courierId = await makeCourier(c, "drv4");

  const groupId = Number(
    (
      await c.query(
        `INSERT INTO order_group
           (public_id, customer_user_id, status, is_multi_store, stores_count, payment_method)
         VALUES ($1,$2,'active',TRUE,2,'cash') RETURNING id`,
        [`${MARK}grp`, customerId]
      )
    ).rows[0].id
  );
  const childIds = [];
  for (const suffix of ["c1", "c2"]) {
    childIds.push(
      Number(
        (
          await c.query(
            `INSERT INTO customer_order
               (merchant_id, customer_user_id, customer_full_name, customer_phone, customer_block,
                customer_building_number, customer_apartment, status, delivery_type,
                delivery_assignment_status, delivery_user_id, order_group_id, order_scope, delivered_at)
             VALUES ($1,$2,$3,'0700','A','1','1','delivered','delivery','COMPLETED',$4,$5,'group_child',NOW())
             RETURNING id`,
            [merchantId, customerId, `${MARK}${suffix}`, courierId, groupId]
          )
        ).rows[0].id
      )
    );
  }
  const jobId = Number(
    (
      await c.query(
        `INSERT INTO delivery_job
           (order_group_id, customer_user_id, payment_method, delivery_user_id,
            assignment_status, lifecycle_status, assigned_at)
         VALUES ($1,$2,'cash',$3,'ASSIGNED','ASSIGNED',NOW()) RETURNING id`,
        [groupId, customerId, courierId]
      )
    ).rows[0].id
  );
  let seq = 1;
  for (const childId of childIds) {
    await c.query(
      `INSERT INTO delivery_pickup_stop
         (delivery_job_id, child_order_id, store_id, sequence_number)
       VALUES ($1,$2,$3,$4)`,
      [jobId, childId, merchantId, seq++]
    );
  }
  await c.query(
    `INSERT INTO courier_assignment
       (delivery_job_id, courier_user_id, assignment_type, status, requested_at, assigned_at)
     VALUES ($1,$2,'grouped','assigned',NOW(),NOW())`,
    [jobId, courierId]
  );

  const stranded = await busyMarkers(c, courierId);
  assert.equal(stranded.openAssignments, 1, "reproduces the held grouped assignment");

  const summary = await reconcileStaleCourierAssignments(c);
  assert.ok(
    summary.settledFinishedGroupedJobs >= 1,
    "sweep settles the finished grouped job"
  );

  const job = (
    await c.query(
      "SELECT assignment_status, lifecycle_status FROM delivery_job WHERE id = $1",
      [jobId]
    )
  ).rows[0];
  assert.equal(job.assignment_status, "COMPLETED");
  assert.equal(job.lifecycle_status, "DELIVERED");

  const healed = await busyMarkers(c, courierId);
  assert.equal(healed.openAssignments, 0, "grouped assignment is closed");

  const selection = await selectEligibleCourier(c, {
    restrictToCourierUserIds: [courierId],
  });
  assert.equal(
    selection.courierUserId,
    courierId,
    `courier is free after the grouped job settles; excluded=${JSON.stringify(selection.excluded)}`
  );

  await c.query("DELETE FROM courier_assignment WHERE delivery_job_id = $1", [jobId]);
  await c.query("DELETE FROM delivery_pickup_stop WHERE delivery_job_id = $1", [jobId]);
  await c.query("DELETE FROM delivery_job WHERE id = $1", [jobId]);
  await c.query("DELETE FROM customer_order WHERE order_group_id = $1", [groupId]);
  await c.query("DELETE FROM order_group WHERE id = $1", [groupId]);
});

test("delivery: an in-flight courier is never released by the sweep", async (t) => {
  const c = newClient();
  await c.connect();
  t.after(async () => {
    await cleanup(c).catch(() => {});
    await c.end();
  });
  await cleanup(c);

  const merchantId = Number(
    (
      await c.query(
        `INSERT INTO merchant (name, type, is_open) VALUES ('${MARK}store3','market',TRUE) RETURNING id`
      )
    ).rows[0].id
  );
  const customerId = await makeUser(c, { suffix: "cust3", role: "user" });
  const courierId = await makeCourier(c, "drv3");
  const orderId = await makeAssignedOrder(c, {
    merchantId,
    customerId,
    courierId,
    suffix: "o4",
  });
  await c.query(`UPDATE customer_order SET status = 'on_the_way' WHERE id = $1`, [
    orderId,
  ]);

  await reconcileStaleCourierAssignments(c);

  const markers = await busyMarkers(c, courierId);
  assert.equal(markers.openAssignments, 1, "an active delivery keeps its assignment");
  assert.equal(markers.assignedOrders, 1, "an active delivery stays ASSIGNED");
});
