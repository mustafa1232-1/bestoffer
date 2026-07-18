// Courier eligibility exclusion tests (delivery closure §7).
//
// Verifies selectEligibleCourier enforces every authoritative rule and reports
// a precise exclusion reason per candidate. Each candidate is scoped by
// restrictToCourierUserIds so the shared test DB cannot leak other couriers in.

import test from "node:test";
import assert from "node:assert/strict";
import pg from "pg";
import { selectEligibleCourier } from "../modules/delivery/delivery-job.service.js";
import {
  createMultiStoreFixture,
  cleanupMultiStoreFixture,
} from "./fixtures/multistore-delivery.fixture.js";
import {
  ensureDeliveryJobForGroup,
  recomputeGroupReadiness,
  assignDeliveryJobTx,
  acknowledgeGroupedJob,
  headingToPickups,
  markStopArrived,
  markStopCollected,
  headingToCustomer,
  markGroupedDelivered,
} from "../modules/delivery/delivery-job.service.js";

const MARK = "fixt_el_";
function newClient() {
  return new pg.Client({ connectionString: process.env.DATABASE_URL });
}

async function cleanup(c) {
  await c.query(
    `WITH marker_users AS (
       SELECT id FROM app_user WHERE username LIKE '${MARK}%'
     ),
     marker_jobs AS (
       SELECT id
         FROM delivery_job
        WHERE customer_user_id IN (SELECT id FROM marker_users)
           OR delivery_user_id IN (SELECT id FROM marker_users)
     )
     DELETE FROM courier_assignment
      WHERE courier_user_id IN (SELECT id FROM marker_users)
         OR delivery_job_id IN (SELECT id FROM marker_jobs)`
  ).catch(() => {});
  await c.query(
    `WITH marker_users AS (
       SELECT id FROM app_user WHERE username LIKE '${MARK}%'
     ),
     marker_jobs AS (
       SELECT id
         FROM delivery_job
        WHERE customer_user_id IN (SELECT id FROM marker_users)
           OR delivery_user_id IN (SELECT id FROM marker_users)
     )
     DELETE FROM delivery_pickup_stop
      WHERE delivery_job_id IN (SELECT id FROM marker_jobs)`
  ).catch(() => {});
  await c.query(
    `WITH marker_users AS (
       SELECT id FROM app_user WHERE username LIKE '${MARK}%'
     )
     DELETE FROM delivery_job
      WHERE customer_user_id IN (SELECT id FROM marker_users)
         OR delivery_user_id IN (SELECT id FROM marker_users)`
  ).catch(() => {});
  await c.query(
    `WITH marker_users AS (
       SELECT id FROM app_user WHERE username LIKE '${MARK}%'
     )
     DELETE FROM customer_order
      WHERE customer_user_id IN (SELECT id FROM marker_users)
         OR delivery_user_id IN (SELECT id FROM marker_users)`
  ).catch(() => {});
  await c.query(
    `WITH marker_users AS (
       SELECT id FROM app_user WHERE username LIKE '${MARK}%'
     )
     DELETE FROM order_group
      WHERE customer_user_id IN (SELECT id FROM marker_users)`
  ).catch(() => {});
  await c.query(
    `DELETE FROM courier_assignment WHERE courier_user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  ).catch(() => {});
  await c.query(
    `DELETE FROM courier_presence WHERE courier_user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  );
  await c.query(
    `DELETE FROM courier_profile WHERE user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  );
  await c.query(`DELETE FROM app_user WHERE username LIKE '${MARK}%'`);
}

async function makeCourier(
  c,
  {
    suffix,
    role = "delivery",
    approved = true,
    disabled = false,
    lockedFuture = false,
    isApp = true,
    active = true,
    availability = "online",
    online = true,
    presenceAgeSec = 5,
  }
) {
  const uid = Number(
    (
      await c.query(
        `INSERT INTO app_user
           (full_name, phone, pin_hash, block, building_number, apartment, username, role,
            delivery_account_approved, is_account_disabled, locked_until)
         VALUES ('c',$1,'x','A','1','1',$2,$3,$4,$5,$6) RETURNING id`,
        [
          `0${suffix}`.slice(0, 15),
          `${MARK}${suffix}`,
          role,
          approved,
          disabled,
          lockedFuture ? new Date(Date.now() + 3600_000).toISOString() : null,
        ]
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
    [uid, online, String(presenceAgeSec)]
  );
  return uid;
}

async function reason(c, uid) {
  const { courierUserId, excluded } = await selectEligibleCourier(c, {
    restrictToCourierUserIds: [uid],
  });
  if (courierUserId === uid) return "SELECTED";
  const e = excluded.find((x) => x.courierUserId === uid);
  return e ? e.reason : "MISSING";
}

test("eligibility: each rule excludes with a precise reason", async (t) => {
  const c = newClient();
  await c.connect();
  t.after(async () => {
    await cleanup(c).catch(() => {});
    await c.end();
  });
  await cleanup(c);

  const eligible = await makeCourier(c, { suffix: "ok" });
  assert.equal(await reason(c, eligible), "SELECTED", "fully eligible courier is selected");

  assert.equal(await reason(c, await makeCourier(c, { suffix: "role", role: "user" })), "not_delivery_role");
  assert.equal(await reason(c, await makeCourier(c, { suffix: "appr", approved: false })), "account_not_approved");
  assert.equal(await reason(c, await makeCourier(c, { suffix: "dis", disabled: true })), "account_disabled");
  assert.equal(await reason(c, await makeCourier(c, { suffix: "lock", lockedFuture: true })), "account_locked");
  assert.equal(await reason(c, await makeCourier(c, { suffix: "napp", isApp: false })), "not_app_courier");
  assert.equal(await reason(c, await makeCourier(c, { suffix: "nact", active: false })), "account_not_active");
  assert.equal(await reason(c, await makeCourier(c, { suffix: "off", online: false })), "offline");
  assert.equal(await reason(c, await makeCourier(c, { suffix: "stale", presenceAgeSec: 9999 })), "presence_stale");

  // Busy in a legacy single-order courier_assignment → excluded.
  const legacyBusy = await makeCourier(c, { suffix: "leg" });
  // needs a real order_id; create a throwaway order via minimal insert path.
  const merchantId = Number(
    (await c.query(`INSERT INTO merchant (name,type,is_open) VALUES ('${MARK}m','market',TRUE) RETURNING id`)).rows[0].id
  );
  const custId = Number(
    (await c.query(`INSERT INTO app_user (full_name,phone,pin_hash,block,building_number,apartment,username,role) VALUES ('cu','0${MARK}c'::text,'x','A','1','1','${MARK}cust','user') RETURNING id`)).rows[0].id
  );
  const orderId = Number(
    (
      await c.query(
        `INSERT INTO customer_order
           (merchant_id, customer_user_id, customer_full_name, customer_phone, customer_block,
            customer_building_number, customer_apartment, status, delivery_type, delivery_assignment_status)
         VALUES ($1,$2,'${MARK}o','07','A','1','1','approved','delivery','ASSIGNED') RETURNING id`,
        [merchantId, custId]
      )
    ).rows[0].id
  );
  await c.query(
    `INSERT INTO courier_assignment (order_id, courier_user_id, assignment_type, status, requested_at)
     VALUES ($1,$2,'broadcast','assigned',NOW())`,
    [orderId, legacyBusy]
  );
  assert.equal(await reason(c, legacyBusy), "busy_legacy_order", "courier on a legacy order is excluded");

  await c.query(`DELETE FROM courier_assignment WHERE order_id=$1`, [orderId]);
  await c.query(`DELETE FROM customer_order WHERE id=$1`, [orderId]);
  await c.query(`DELETE FROM merchant WHERE id=$1`, [merchantId]);
  await c.query(`DELETE FROM app_user WHERE id=$1`, [custId]);
});

test("delivery: completed courier receives a second grouped job without relogin", async (t) => {
  const c = newClient();
  await c.connect();
  t.after(async () => {
    await cleanup(c).catch(() => {});
    await c.end();
  });
  await cleanup(c);

  const fxA = await createMultiStoreFixture(c, { mark: MARK + "a_" });
  await c.query("BEGIN");
  await ensureDeliveryJobForGroup(c, fxA.orderGroupId);
  await recomputeGroupReadiness(c, fxA.orderGroupId);
  await assignDeliveryJobTx(c, { orderGroupId: fxA.orderGroupId, courierUserId: fxA.courierId });
  await c.query("COMMIT");

  const jobAId = Number(
    (await c.query("SELECT id FROM delivery_job WHERE order_group_id=$1", [fxA.orderGroupId])).rows[0].id
  );
  const [stopA, stopB] = (
    await c.query(
      `SELECT id
         FROM delivery_pickup_stop
        WHERE delivery_job_id=$1
        ORDER BY sequence_number`,
      [jobAId]
    )
  ).rows.map((r) => Number(r.id));

  await acknowledgeGroupedJob({ courierUserId: fxA.courierId, deliveryJobId: jobAId });
  await headingToPickups({ courierUserId: fxA.courierId, deliveryJobId: jobAId });
  await markStopArrived({ courierUserId: fxA.courierId, deliveryJobId: jobAId, stopId: stopA });
  await markStopCollected({ courierUserId: fxA.courierId, deliveryJobId: jobAId, stopId: stopA });
  await markStopArrived({ courierUserId: fxA.courierId, deliveryJobId: jobAId, stopId: stopB });
  await markStopCollected({ courierUserId: fxA.courierId, deliveryJobId: jobAId, stopId: stopB });
  await headingToCustomer({ courierUserId: fxA.courierId, deliveryJobId: jobAId });
  const delivered = await markGroupedDelivered({ courierUserId: fxA.courierId, deliveryJobId: jobAId });
  assert.equal(delivered.lifecycleStatus, "DELIVERED");

  const jobA = (await c.query("SELECT * FROM delivery_job WHERE id=$1", [jobAId])).rows[0];
  assert.equal(jobA.assignment_status, "COMPLETED", "Job A releases the courier after delivery");
  assert.equal(jobA.lifecycle_status, "DELIVERED", "Job A reached terminal lifecycle");
  assert.ok(jobA.completed_at, "Job A completed_at is set");
  const activeA = Number(
    (
      await c.query(
        `SELECT COUNT(*)::int AS n
           FROM courier_assignment
          WHERE delivery_job_id=$1 AND ended_at IS NULL`,
        [jobAId]
      )
    ).rows[0].n
  );
  assert.equal(activeA, 0, "Job A courier_assignment is closed");
  const deliveredChildren = (
    await c.query(
      `SELECT status FROM customer_order WHERE order_group_id=$1 ORDER BY id`,
      [fxA.orderGroupId]
    )
  ).rows;
  assert.ok(
    deliveredChildren.length > 0 && deliveredChildren.every((r) => r.status === "delivered"),
    "all Job A child orders delivered"
  );

  const fxB = await createMultiStoreFixture(c, { mark: MARK + "b_" });
  await c.query("BEGIN");
  await ensureDeliveryJobForGroup(c, fxB.orderGroupId);
  await recomputeGroupReadiness(c, fxB.orderGroupId);
  await c.query("COMMIT");

  const selection = await selectEligibleCourier(c, {
    restrictToCourierUserIds: [fxA.courierId],
  });
  assert.equal(
    selection.courierUserId,
    fxA.courierId,
    `completed courier is selectable again; excluded=${JSON.stringify(selection.excluded)}`
  );
  assert.ok(
    !selection.excluded.some((e) => e.reason === "busy_grouped_job"),
    "terminal grouped job is not treated as busy"
  );

  await c.query("BEGIN");
  const assignedB = await assignDeliveryJobTx(c, {
    orderGroupId: fxB.orderGroupId,
    courierUserId: fxA.courierId,
  });
  await c.query("COMMIT");

  assert.equal(assignedB.job.assignment_status, "ASSIGNED", "Job B assigned");
  assert.equal(Number(assignedB.job.delivery_user_id), Number(fxA.courierId), "Job B assigned to the same courier");

  const jobB = (await c.query("SELECT * FROM delivery_job WHERE id=$1", [assignedB.job.id])).rows[0];
  assert.equal(jobB.assignment_status, "ASSIGNED", "Job B active");
  assert.equal(Number(jobB.delivery_user_id), Number(fxA.courierId), "Job B points to the same courier");
  const activeB = Number(
    (
      await c.query(
        `SELECT COUNT(*)::int AS n
           FROM courier_assignment
          WHERE delivery_job_id=$1 AND ended_at IS NULL`,
        [assignedB.job.id]
      )
    ).rows[0].n
  );
  assert.equal(activeB, 1, "Job B has one active courier_assignment");

  await cleanupMultiStoreFixture(c, MARK + "b_");
  await cleanupMultiStoreFixture(c, MARK + "a_");
});
