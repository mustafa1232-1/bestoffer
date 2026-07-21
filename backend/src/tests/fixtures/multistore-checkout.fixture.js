// Real multi-store checkout fixture (delivery closure §16).
//
// Unlike multistore-delivery.fixture.js (which inserts order_group/children
// directly), this fixture drives the REAL production order service
// `createOrderGroupWithItems` so the end-to-end test exercises the genuine
// checkout → delivery_job creation path, then the real store-acceptance service
// and the real assignment worker.
//
// Seed rows are marked `fixt_co_` for idempotent teardown.

import crypto from "node:crypto";

import { pool } from "../../config/db.js";
import { createOrderGroupWithItems } from "../../modules/orders/orders.repo.js";

const DEFAULT_MARK = "fixt_co_";

// The node test runner executes test files in parallel processes. Two files
// sharing one mark made each file's teardown delete the other file's merchant
// mid-checkout (FK 23503 on customer_order.merchant_id), so every consumer must
// own a distinct namespace.
function resolveMark(mark) {
  const normalized = String(mark || DEFAULT_MARK);
  if (!/^[a-z0-9_]+_$/.test(normalized)) {
    throw new Error(`INVALID_FIXTURE_MARK: ${normalized}`);
  }
  return normalized;
}

export async function cleanupCheckoutFixture(client, mark) {
  const MARK = resolveMark(mark);
  await client.query(
    `DELETE FROM delivery_pickup_stop WHERE child_order_id IN
       (SELECT id FROM customer_order WHERE customer_full_name LIKE '${MARK}%')`
  );
  await client.query(
    `DELETE FROM delivery_job WHERE order_group_id IN
       (SELECT id FROM order_group WHERE public_id LIKE '${MARK}%'
          OR customer_user_id IN (SELECT id FROM app_user WHERE username LIKE '${MARK}%'))`
  );
  await client.query(
    `DELETE FROM notification_outbox WHERE recipient_user_id IN
       (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  );
  await client.query(
    `DELETE FROM courier_assignment WHERE order_id IN
       (SELECT id FROM customer_order WHERE customer_full_name LIKE '${MARK}%')`
  ).catch(() => {});
  await client.query(
    `DELETE FROM order_group_item_summary WHERE order_group_id IN
       (SELECT id FROM order_group WHERE customer_user_id IN
          (SELECT id FROM app_user WHERE username LIKE '${MARK}%'))`
  ).catch(() => {});
  await client.query(
    `DELETE FROM customer_order WHERE customer_full_name LIKE '${MARK}%'`
  );
  await client.query(
    `DELETE FROM order_group WHERE customer_user_id IN
       (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  );
  await client.query(
    `DELETE FROM product WHERE merchant_id IN
       (SELECT id FROM merchant WHERE name LIKE '${MARK}%')`
  );
  await client.query(
    `DELETE FROM user_push_token WHERE user_id IN
       (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  ).catch(() => {});
  await client.query(
    `DELETE FROM app_notification WHERE user_id IN
       (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  ).catch(() => {});
  await client.query(
    `DELETE FROM user_session WHERE user_id IN
       (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  ).catch(() => {});
  await client.query(
    `DELETE FROM courier_presence WHERE courier_user_id IN
       (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  );
  await client.query(
    `DELETE FROM courier_profile WHERE user_id IN
       (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  );
  await client.query(`DELETE FROM merchant WHERE name LIKE '${MARK}%'`);
  await client.query(`DELETE FROM app_user WHERE username LIKE '${MARK}%'`);
}

// app_user.phone is globally unique, so it has to be namespaced by mark too --
// otherwise two parallel fixture consumers collide on the same seeded number.
function markedPhone(MARK, suffix) {
  const digest = crypto
    .createHash("sha1")
    .update(`${MARK}${suffix}`)
    .digest("hex");
  return `07${BigInt(`0x${digest.slice(0, 10)}`)}`.slice(0, 15);
}

async function insertUser(client, { role, name, suffix, mark: MARK }) {
  return Number(
    (
      await client.query(
        `INSERT INTO app_user
           (full_name, phone, pin_hash, block, building_number, apartment, username, role)
         VALUES ($1,$2,'x',$3,$4,$5,$6,$7)
         RETURNING id`,
        [name, markedPhone(MARK, suffix), "A101", "1", "1", `${MARK}${suffix}`, role]
      )
    ).rows[0].id
  );
}

async function insertMerchantWithProduct(client, { owner, storeName, suffix, mark: MARK }) {
  const merchantId = Number(
    (
      await client.query(
        `INSERT INTO merchant (name, type, owner_user_id, is_open, is_disabled)
         VALUES ($1,'market',$2,TRUE,FALSE) RETURNING id`,
        [storeName, owner]
      )
    ).rows[0].id
  );
  const productId = Number(
    (
      await client.query(
        `INSERT INTO product (merchant_id, name, price, is_available)
         VALUES ($1,$2,$3,TRUE) RETURNING id`,
        [merchantId, `${MARK}product_${suffix}`, 5000]
      )
    ).rows[0].id
  );
  return { merchantId, productId };
}

/**
 * Seeds two open stores (with one available product each), an approved+online
 * app courier, and a customer, then places a REAL two-store checkout via
 * createOrderGroupWithItems. Returns the identity map for the e2e test.
 */
export async function createRealMultiStoreCheckout(
  client,
  {
    courierOnline = true,
    presenceAgeSec = 5,
    mark,
    reuseCustomerId = null,
    reuseCourierId = null,
  } = {}
) {
  const MARK = resolveMark(mark);
  await cleanupCheckoutFixture(client, MARK);

  const customerId =
    reuseCustomerId == null
      ? await insertUser(client, {
          role: "user",
          name: `${MARK}customer`,
          suffix: "cust",
          mark: MARK,
        })
      : Number(reuseCustomerId);
  const owner1 = await insertUser(client, {
    role: "owner",
    name: `${MARK}o1`,
    suffix: "own1",
    mark: MARK,
  });
  const owner2 = await insertUser(client, {
    role: "owner",
    name: `${MARK}o2`,
    suffix: "own2",
    mark: MARK,
  });
  const courierId =
    reuseCourierId == null
      ? await insertUser(client, {
          role: "delivery",
          name: `${MARK}courier`,
          suffix: "cour",
          mark: MARK,
        })
      : Number(reuseCourierId);

  const store1 = await insertMerchantWithProduct(client, {
    owner: owner1,
    storeName: `${MARK}store1`,
    suffix: "s1",
    mark: MARK,
  });
  const store2 = await insertMerchantWithProduct(client, {
    owner: owner2,
    storeName: `${MARK}store2`,
    suffix: "s2",
    mark: MARK,
  });

  await client.query(
    `INSERT INTO courier_profile (user_id, is_app_courier, active_status, availability_status)
     VALUES ($1, TRUE, TRUE, $2)
     ON CONFLICT (user_id) DO UPDATE
       SET is_app_courier=TRUE, active_status=TRUE, availability_status=$2`,
    [courierId, courierOnline ? "online" : "offline"]
  );
  await client.query(
    `INSERT INTO courier_presence (courier_user_id, is_online, recorded_at, updated_at)
     VALUES ($1, $2, NOW() - ($3 || ' seconds')::interval, NOW())
     ON CONFLICT (courier_user_id) DO UPDATE
       SET is_online=EXCLUDED.is_online,
           recorded_at=EXCLUDED.recorded_at,
           updated_at=NOW()`,
    [courierId, courierOnline, String(presenceAgeSec)]
  );

  const customer = {
    id: customerId,
    full_name: `${MARK}customer`,
    phone: "07700000000",
    block: "A101",
    building_number: "1",
    apartment: "1",
    city: "مدينة بسماية",
  };

  const group = await createOrderGroupWithItems({
    customer,
    deliveryAddress: { block: "A101", building_number: "1", apartment: "1" },
    note: null,
    paymentMethod: "cash_on_delivery",
    storeOrders: [
      {
        merchantId: store1.merchantId,
        note: null,
        imageUrl: null,
        couponId: null,
        couponCode: null,
        normalizedItems: [
          { productId: store1.productId, quantity: 1, selectedModifiers: [], selectedVariant: null },
        ],
      },
      {
        merchantId: store2.merchantId,
        note: null,
        imageUrl: null,
        couponId: null,
        couponCode: null,
        normalizedItems: [
          { productId: store2.productId, quantity: 1, selectedModifiers: [], selectedVariant: null },
        ],
      },
    ],
  });

  const orderGroupId = Number(group.orderGroup?.id);
  const childOrders = (
    await client.query(
      `SELECT id, merchant_id, status FROM customer_order
        WHERE order_group_id=$1 ORDER BY id`,
      [orderGroupId]
    )
  ).rows;

  return {
    customerId,
    courierId,
    owners: [owner1, owner2],
    merchantIds: [store1.merchantId, store2.merchantId],
    orderGroupId,
    childOrderIds: childOrders.map((r) => Number(r.id)),
    childOwnerByOrderId: new Map([
      [Number(childOrders[0].id), owner1],
      [Number(childOrders[1].id), owner2],
    ]),
  };
}
