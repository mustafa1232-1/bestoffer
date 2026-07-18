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
import { ensureDeliveryJobForGroup, recomputeGroupReadiness, assignDeliveryJobTx } from "../modules/delivery/delivery-job.service.js";

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

test("eligibility: courier becomes selectable again after grouped delivery completes", async (t) => {
  const c = newClient();
  await c.connect();
  t.after(async () => {
    await cleanup(c).catch(() => {});
    await c.end();
  });
  await cleanup(c);

  const fx = await createMultiStoreFixture(c, { mark: MARK });
  await c.query("BEGIN");
  await ensureDeliveryJobForGroup(c, fx.orderGroupId);
  await recomputeGroupReadiness(c, fx.orderGroupId);
  await assignDeliveryJobTx(c, { orderGroupId: fx.orderGroupId, courierUserId: fx.courierId });
  await c.query("COMMIT");

  const jobId = Number(
    (await c.query("SELECT id FROM delivery_job WHERE order_group_id=$1", [fx.orderGroupId])).rows[0].id
  );
  await c.query(
    `UPDATE delivery_job
        SET assignment_status='ASSIGNED',
            lifecycle_status='DELIVERED',
            completed_at=NOW(),
            updated_at=NOW()
      WHERE id=$1`,
    [jobId]
  );
  await c.query(
    `UPDATE courier_assignment
        SET status='completed',
            completed_at=NOW(),
            ended_at=COALESCE(ended_at, NOW()),
            ended_reason=COALESCE(ended_reason, 'COMPLETED')
      WHERE delivery_job_id=$1 AND ended_at IS NULL`,
    [jobId]
  );

  const { courierUserId, excluded } = await selectEligibleCourier(c, {
    restrictToCourierUserIds: [fx.courierId],
  });
  assert.equal(
    courierUserId,
    fx.courierId,
    `delivered courier is selectable again; excluded=${JSON.stringify(excluded)}`
  );
  assert.ok(
    !excluded.some((e) => e.reason === "busy_grouped_job"),
    "terminal grouped job is not treated as busy"
  );

  await cleanupMultiStoreFixture(c, MARK);
});
