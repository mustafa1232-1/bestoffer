import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";

import { pool, q } from "../config/db.js";
import { directAssignDeliveryOrderTx } from "../modules/commerce/commerce.repo.js";
import { assignOrderCourierForMonitoring } from "../modules/admin/monitoring.orders.repo.js";

const MARK = "fx_mon_asg_";

function markedPhone(suffix) {
  const digest = crypto.createHash("sha1").update(`${MARK}${suffix}`).digest("hex");
  return `07${BigInt(`0x${digest.slice(0, 10)}`)}`.slice(0, 15);
}

async function cleanup() {
  await q(
    `DELETE FROM app_notification
     WHERE user_id IN (SELECT id FROM app_user WHERE username LIKE $1)`,
    [`${MARK}%`],
  ).catch(() => {});
  await q(
    `DELETE FROM courier_assignment
     WHERE courier_user_id IN (SELECT id FROM app_user WHERE username LIKE $1)
        OR order_id IN (SELECT id FROM customer_order WHERE customer_full_name LIKE $1)`,
    [`${MARK}%`],
  ).catch(() => {});
  await q(
    `DELETE FROM customer_order
     WHERE customer_full_name LIKE $1
        OR customer_user_id IN (SELECT id FROM app_user WHERE username LIKE $1)
        OR delivery_user_id IN (SELECT id FROM app_user WHERE username LIKE $1)`,
    [`${MARK}%`],
  ).catch(() => {});
  await q(`DELETE FROM product WHERE merchant_id IN (SELECT id FROM merchant WHERE name LIKE $1)`, [`${MARK}%`]).catch(() => {});
  await q(`DELETE FROM merchant WHERE name LIKE $1`, [`${MARK}%`]).catch(() => {});
  await q(`DELETE FROM courier_presence WHERE courier_user_id IN (SELECT id FROM app_user WHERE username LIKE $1)`, [`${MARK}%`]).catch(() => {});
  await q(`DELETE FROM courier_profile WHERE user_id IN (SELECT id FROM app_user WHERE username LIKE $1)`, [`${MARK}%`]).catch(() => {});
  await q(`DELETE FROM app_user WHERE username LIKE $1`, [`${MARK}%`]).catch(() => {});
}

async function insertUser({ role, suffix, name = suffix }) {
  const r = await q(
    `INSERT INTO app_user
       (full_name, phone, pin_hash, block, building_number, apartment, username, role,
        delivery_account_approved, is_account_disabled)
     VALUES ($1,$2,'x','A','1','1',$3,$4,$5,FALSE)
     RETURNING id`,
    [
      `${MARK}${name}`,
      markedPhone(suffix),
      `${MARK}${suffix}`,
      role,
      role === "delivery",
    ],
  );
  return Number(r.rows[0].id);
}

async function insertCourier(suffix, { presenceAgeSeconds = 0 } = {}) {
  const courierId = await insertUser({ role: "delivery", suffix, name: "courier" });
  await q(
    `INSERT INTO courier_profile
       (user_id, is_app_courier, active_status, availability_status)
     VALUES ($1, TRUE, TRUE, 'online')`,
    [courierId],
  );
  await q(
    `INSERT INTO courier_presence
       (courier_user_id, is_online, recorded_at, updated_at)
     VALUES ($1, TRUE, NOW() - ($2::text || ' seconds')::interval, NOW() - ($2::text || ' seconds')::interval)`,
    [courierId, String(presenceAgeSeconds)],
  );
  return courierId;
}

async function insertOrder({ merchantId, customerId, suffix }) {
  const r = await q(
    `INSERT INTO customer_order
       (merchant_id, customer_user_id, customer_full_name, customer_phone,
        customer_block, customer_building_number, customer_apartment,
        status, delivery_type, delivery_assignment_status)
     VALUES ($1,$2,$3,$4,'A','1','1','approved','delivery','NOT_REQUIRED')
     RETURNING id`,
    [merchantId, customerId, `${MARK}${suffix}`, markedPhone(`order_${suffix}`)],
  );
  return Number(r.rows[0].id);
}

async function latestNotification({ userId, orderId, type }) {
  const r = await q(
    `SELECT type, order_id, payload
     FROM app_notification
     WHERE user_id = $1
       AND order_id = $2
       AND type = $3
     ORDER BY id DESC
     LIMIT 1`,
    [Number(userId), Number(orderId), String(type)],
  );
  return r.rows[0] || null;
}

test.beforeEach(async () => {
  await cleanup();
});

test.afterEach(async () => {
  await cleanup();
});

test("auto assignment uses another courier when the first one is busy", async () => {
  const ownerId = await insertUser({ role: "owner", suffix: "owner" });
  const customerId = await insertUser({ role: "user", suffix: "customer" });
  const courierA = await insertCourier("courier_a");
  const courierB = await insertCourier("courier_b");
  const merchantId = Number(
    (
      await q(
        `INSERT INTO merchant (name, type, owner_user_id, is_open, is_disabled)
         VALUES ($1, 'market', $2, TRUE, FALSE)
         RETURNING id`,
        [`${MARK}merchant`, ownerId],
      )
    ).rows[0].id,
  );
  const orderA = await insertOrder({ merchantId, customerId, suffix: "order_a" });
  const orderB = await insertOrder({ merchantId, customerId, suffix: "order_b" });

  let client = await pool.connect();
  try {
    await client.query("BEGIN");
    const first = await directAssignDeliveryOrderTx(client, {
      orderId: orderA,
      merchantId,
      requestedByUserId: ownerId,
      explicitCourierUserId: courierA,
      allowPending: false,
      assignmentType: "store_auto",
    });
    await client.query("COMMIT");
    assert.equal(first.assignmentStatus, "ASSIGNED");
    assert.equal(Number(first.driver.id), courierA);
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    client.release();
  }

  client = await pool.connect();
  try {
    await client.query("BEGIN");
    const second = await directAssignDeliveryOrderTx(client, {
      orderId: orderB,
      merchantId,
      requestedByUserId: ownerId,
      allowPending: false,
      assignmentType: "store_auto",
    });
    await client.query("COMMIT");
    assert.equal(second.assignmentStatus, "ASSIGNED");
    assert.equal(Number(second.driver.id), courierB);
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    client.release();
  }

  const rows = await q(
    `SELECT id, delivery_user_id
     FROM customer_order
     WHERE id = ANY($1::bigint[])
     ORDER BY id`,
    [[orderA, orderB]],
  );
  assert.deepEqual(
    rows.rows.map((row) => Number(row.delivery_user_id)),
    [courierA, courierB],
  );
});

test("monitoring can manually assign a second active order to a busy courier", async () => {
  const ownerId = await insertUser({ role: "owner", suffix: "owner" });
  const customerId = await insertUser({ role: "user", suffix: "customer" });
  const adminId = await insertUser({ role: "admin", suffix: "admin" });
  const courierId = await insertCourier("courier");
  const replacementCourierId = await insertCourier("courier_b");
  const merchantId = Number(
    (
      await q(
        `INSERT INTO merchant (name, type, owner_user_id, is_open, is_disabled)
         VALUES ($1, 'market', $2, TRUE, FALSE)
         RETURNING id`,
        [`${MARK}merchant`, ownerId],
      )
    ).rows[0].id,
  );
  const orderA = await insertOrder({ merchantId, customerId, suffix: "order_a" });
  const orderB = await insertOrder({ merchantId, customerId, suffix: "order_b" });

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const first = await directAssignDeliveryOrderTx(client, {
      orderId: orderA,
      merchantId,
      requestedByUserId: ownerId,
      explicitCourierUserId: courierId,
      allowPending: false,
      assignmentType: "store_auto",
    });
    await client.query("COMMIT");
    assert.equal(first.assignmentStatus, "ASSIGNED");
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    client.release();
  }

  await assert.rejects(
    async () =>
      assignOrderCourierForMonitoring({
        actorUserId: adminId,
        orderId: orderB,
        courierUserId: courierId,
        allowBusyCourier: false,
      }),
    /COURIER_NOT_AVAILABLE/,
  );

  const second = await assignOrderCourierForMonitoring({
    actorUserId: adminId,
    orderId: orderB,
    courierUserId: courierId,
    allowBusyCourier: true,
    note: "test manual busy override",
  });
  assert.equal(second.assignmentStatus, "ASSIGNED");
  assert.equal(Number(second.driver.id), courierId);
  assert.equal(Number(second.activeOrderCountBefore), 1);

  const activeOrders = await q(
    `SELECT COUNT(*)::int AS count
     FROM customer_order
     WHERE delivery_user_id = $1
       AND delivery_assignment_status = 'ASSIGNED'`,
    [courierId],
  );
  assert.equal(Number(activeOrders.rows[0].count), 2);

  const openAssignments = await q(
    `SELECT COUNT(*)::int AS count
     FROM courier_assignment
     WHERE courier_user_id = $1
       AND ended_at IS NULL`,
    [courierId],
  );
  assert.equal(Number(openAssignments.rows[0].count), 2);

  const additionalAssignmentNotification = await latestNotification({
    userId: courierId,
    orderId: orderB,
    type: "delivery_order_assigned",
  });
  assert.ok(additionalAssignmentNotification);
  assert.equal(additionalAssignmentNotification.payload?.target, "courier_orders_current");
  assert.equal(additionalAssignmentNotification.payload?.additionalOrder, true);

  const reassigned = await assignOrderCourierForMonitoring({
    actorUserId: adminId,
    orderId: orderB,
    courierUserId: replacementCourierId,
    allowBusyCourier: false,
    note: "test manual replacement",
  });
  assert.equal(reassigned.assignmentStatus, "ASSIGNED");
  assert.equal(Number(reassigned.driver.id), replacementCourierId);
  assert.equal(Number(reassigned.previousDriver.id), courierId);

  const removedNotification = await latestNotification({
    userId: courierId,
    orderId: orderB,
    type: "delivery_order_removed",
  });
  assert.ok(removedNotification);
  assert.equal(removedNotification.payload?.target, "courier_orders_current");

  const replacementNotification = await latestNotification({
    userId: replacementCourierId,
    orderId: orderB,
    type: "delivery_order_assigned",
  });
  assert.ok(replacementNotification);
  assert.equal(replacementNotification.payload?.target, "courier_orders_current");
  assert.equal(replacementNotification.payload?.additionalOrder, false);
});

test("online courier remains assignable with stale presence, but offline does not", async () => {
  const ownerId = await insertUser({ role: "owner", suffix: "owner" });
  const customerId = await insertUser({ role: "user", suffix: "customer" });
  const adminId = await insertUser({ role: "admin", suffix: "admin" });
  const staleCourierId = await insertCourier("stale1", {
    presenceAgeSeconds: 10_000,
  });
  const manualStaleCourierId = await insertCourier("stale2", {
    presenceAgeSeconds: 10_000,
  });
  const offlineCourierId = await insertCourier("offline1");
  await q(
    `UPDATE courier_profile
        SET availability_status='offline'
      WHERE user_id=$1`,
    [offlineCourierId],
  );
  await q(
    `UPDATE courier_presence
        SET is_online=FALSE,
            recorded_at=NOW(),
            updated_at=NOW()
      WHERE courier_user_id=$1`,
    [offlineCourierId],
  );
  const merchantId = Number(
    (
      await q(
        `INSERT INTO merchant (name, type, owner_user_id, is_open, is_disabled)
         VALUES ($1, 'market', $2, TRUE, FALSE)
         RETURNING id`,
        [`${MARK}merchant`, ownerId],
      )
    ).rows[0].id,
  );
  const orderId = await insertOrder({ merchantId, customerId, suffix: "order_stale" });
  const offlineOrderId = await insertOrder({
    merchantId,
    customerId,
    suffix: "order_offline",
  });

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const assigned = await directAssignDeliveryOrderTx(client, {
      orderId,
      merchantId,
      requestedByUserId: ownerId,
      explicitCourierUserId: staleCourierId,
      allowPending: false,
      assignmentType: "store_auto",
    });
    assert.equal(assigned.assignmentStatus, "ASSIGNED");
    assert.equal(Number(assigned.driver.id), staleCourierId);
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    client.release();
  }

  await assert.rejects(
    () =>
      assignOrderCourierForMonitoring({
        actorUserId: adminId,
        orderId: offlineOrderId,
        courierUserId: offlineCourierId,
        allowBusyCourier: false,
        note: "test offline courier is not assignable",
      }),
    /COURIER_NOT_AVAILABLE/,
  );

  const manual = await assignOrderCourierForMonitoring({
    actorUserId: adminId,
    orderId: offlineOrderId,
    courierUserId: manualStaleCourierId,
    allowBusyCourier: false,
    note: "test manual stale online intent assignment",
  });

  assert.equal(manual.assignmentStatus, "ASSIGNED");
  assert.equal(Number(manual.driver.id), manualStaleCourierId);
});
