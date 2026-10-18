import assert from "node:assert/strict";
import test from "node:test";
import pg from "pg";

import {
  __ordersRepoTestables,
} from "../modules/orders/orders.repo.js";
import {
  createRealMultiStoreCheckout,
  cleanupCheckoutFixture,
} from "./fixtures/multistore-checkout.fixture.js";
import { isFreeDeliveryCampaignActive } from "../modules/commerce/free-delivery-campaign.js";

// Own namespace: test files run in parallel processes and must not delete each
// other's seeded merchants during teardown.
const FIXTURE_MARK = "fixt_cofee_";

const { buildGroupedDeliveryFeePlan, drainOrderSideEffectsForTests } =
  __ordersRepoTestables;

function makeEntry({
  rawDeliveryFee,
  customerDeliveryFee,
  storeOrder = {},
  subtotalAfterAllDiscounts = 0,
  serviceFee = 0,
}) {
  return {
    storeOrder,
    rawDeliveryFee,
    customerDeliveryFee,
    subtotalAfterAllDiscounts,
    serviceFee,
  };
}

test("grouped delivery fee plan keeps a single store unchanged", () => {
  const plan = buildGroupedDeliveryFeePlan([
    makeEntry({ rawDeliveryFee: 1200, subtotalAfterAllDiscounts: 10000, serviceFee: 500 }),
  ]);

  assert.equal(plan.rawDeliveryFeeTotal, 1200);
  assert.equal(plan.allocatedDeliveryFeeTotal, 1200);
  assert.equal(plan.entries.length, 1);
  assert.equal(plan.entries[0].deliveryFeeMultiplier, 1);
  assert.equal(plan.entries[0].rawDeliveryFee, 1200);
  assert.equal(plan.entries[0].allocatedDeliveryFee, 1200);
  assert.equal(plan.entries[0].totalAmount, 11700);
});

test("grouped delivery fee plan applies 100%, 50% rules for 2 stores", () => {
  const plan = buildGroupedDeliveryFeePlan([
    makeEntry({ rawDeliveryFee: 1000 }),
    makeEntry({ rawDeliveryFee: 1000 }),
  ]);

  assert.deepEqual(
    plan.entries.map((entry) => entry.deliveryFeeMultiplier),
    [1, 0.5]
  );
  assert.deepEqual(
    plan.entries.map((entry) => entry.allocatedDeliveryFee),
    [1000, 500]
  );
  assert.equal(plan.rawDeliveryFeeTotal, 2000);
  assert.equal(plan.allocatedDeliveryFeeTotal, 1500);
});

test("grouped delivery fee plan applies 100%, 50%, 50% rules for 3 stores", () => {
  const plan = buildGroupedDeliveryFeePlan([
    makeEntry({ rawDeliveryFee: 1000 }),
    makeEntry({ rawDeliveryFee: 1000 }),
    makeEntry({ rawDeliveryFee: 1000 }),
  ]);

  assert.deepEqual(
    plan.entries.map((entry) => entry.deliveryFeeMultiplier),
    [1, 0.5, 0.5]
  );
  assert.deepEqual(
    plan.entries.map((entry) => entry.allocatedDeliveryFee),
    [1000, 500, 500]
  );
  assert.equal(plan.rawDeliveryFeeTotal, 3000);
  assert.equal(plan.allocatedDeliveryFeeTotal, 2000);
});

test("grouped delivery fee plan caps four stores at 2000 IQD", () => {
  const plan = buildGroupedDeliveryFeePlan([
    makeEntry({ rawDeliveryFee: 1000 }),
    makeEntry({ rawDeliveryFee: 1000 }),
    makeEntry({ rawDeliveryFee: 1000 }),
    makeEntry({ rawDeliveryFee: 1000 }),
  ]);

  assert.deepEqual(
    plan.entries.map((entry) => entry.deliveryFeeMultiplier),
    [1, 0.5, 0.5, 0.5]
  );
  assert.deepEqual(
    plan.entries.map((entry) => entry.allocatedDeliveryFee),
    [1000, 500, 500, 0]
  );
  assert.equal(plan.rawDeliveryFeeTotal, 4000);
  assert.equal(plan.allocatedDeliveryFeeTotal, 2000);
});

test("grouped delivery fee plan never exceeds the 2000 IQD customer cap", () => {
  const plan = buildGroupedDeliveryFeePlan([
    makeEntry({ rawDeliveryFee: 1000 }),
    makeEntry({ rawDeliveryFee: 1000 }),
    makeEntry({ rawDeliveryFee: 1000 }),
    makeEntry({ rawDeliveryFee: 1000 }),
    makeEntry({ rawDeliveryFee: 1000 }),
    makeEntry({ rawDeliveryFee: 1000 }),
  ]);

  assert.deepEqual(
    plan.entries.map((entry) => entry.deliveryFeeMultiplier),
    [1, 0.5, 0.5, 0.5, 0.5, 0.5]
  );
  assert.deepEqual(
    plan.entries.map((entry) => entry.allocatedDeliveryFee),
    [1000, 500, 500, 0, 0, 0]
  );
  assert.equal(plan.rawDeliveryFeeTotal, 6000);
  assert.equal(plan.allocatedDeliveryFeeTotal, 2000);
});

test("grouped delivery fee plan honors pickup_sequence before checkout and creation order", () => {
  const plan = buildGroupedDeliveryFeePlan([
    makeEntry({ rawDeliveryFee: 1000, storeOrder: { pickup_sequence: 3 } }),
    makeEntry({ rawDeliveryFee: 1000, storeOrder: { pickupSequence: 1 } }),
    makeEntry({ rawDeliveryFee: 1000, storeOrder: { storeSequence: 2 } }),
  ]);

  assert.deepEqual(
    plan.entries.map((entry) => entry.deliveryFeeMultiplier),
    [0.5, 1, 0.5]
  );
  assert.deepEqual(
    plan.entries.map((entry) => entry.allocatedDeliveryFee),
    [500, 1000, 500]
  );
  assert.equal(plan.allocatedDeliveryFeeTotal, 2000);
});

test("grouped delivery fee plan rounds fractional allocations safely", () => {
  const plan = buildGroupedDeliveryFeePlan([
    makeEntry({ rawDeliveryFee: 999.99 }),
    makeEntry({ rawDeliveryFee: 999.99 }),
  ]);

  assert.equal(plan.entries[1].allocatedDeliveryFee, 500);
  assert.equal(plan.allocatedDeliveryFeeTotal, 1499.99);
});

test("grouped delivery fee plan preserves raw fees during a free campaign", () => {
  const plan = buildGroupedDeliveryFeePlan([
    makeEntry({ rawDeliveryFee: 1000, customerDeliveryFee: 0 }),
    makeEntry({ rawDeliveryFee: 1000, customerDeliveryFee: 0 }),
  ]);

  assert.equal(plan.rawDeliveryFeeTotal, 2000);
  assert.equal(plan.allocatedDeliveryFeeTotal, 0);
  assert.equal(plan.entries[0].rawDeliveryFee, 1000);
  assert.equal(plan.entries[1].rawDeliveryFee, 1000);
  assert.equal(plan.entries[0].deliveryFee, 0);
  assert.equal(plan.entries[1].deliveryFee, 0);
});

test("real multi-store checkout persists raw and allocated delivery fees", async (t) => {
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  t.after(async () => {
    await drainOrderSideEffectsForTests();
    await cleanupCheckoutFixture(client, FIXTURE_MARK).catch(() => {});
    await client.end();
  });

  await cleanupCheckoutFixture(client, FIXTURE_MARK);
  const fx = await createRealMultiStoreCheckout(client, { mark: FIXTURE_MARK });
  // Notifications reference the new child orders. Drain the post-commit fanout
  // while those rows still exist so the test cannot race its own teardown.
  await drainOrderSideEffectsForTests();

  const group = (
    await client.query(
      `SELECT id, delivery_fee_total, raw_delivery_fee_total, total_amount
         FROM order_group
        WHERE id=$1`,
      [fx.orderGroupId]
    )
  ).rows[0];
  assert.ok(group, "group row present");

  const children = (
    await client.query(
      `SELECT id, delivery_fee, delivery_fee_raw, total_amount
         FROM customer_order
        WHERE order_group_id=$1
        ORDER BY store_sequence ASC, id ASC`,
      [fx.orderGroupId]
    )
  ).rows;
  assert.equal(children.length, 2, "two child orders persisted");

  const rawTotal = children.reduce((sum, row) => sum + Number(row.delivery_fee_raw || 0), 0);
  const allocatedTotal = children.reduce((sum, row) => sum + Number(row.delivery_fee || 0), 0);
  assert.equal(Number(group.raw_delivery_fee_total || 0), rawTotal);
  assert.equal(Number(group.delivery_fee_total || 0), allocatedTotal);
  assert.ok(
    Number(group.raw_delivery_fee_total || 0) >= Number(group.delivery_fee_total || 0),
    "allocated total must not exceed raw total"
  );
  if (isFreeDeliveryCampaignActive()) {
    assert.ok(rawTotal > 0, "campaign preserves the original courier fee");
    assert.equal(allocatedTotal, 0, "customer delivery total is free");
    assert.ok(
      children.every(
        (row) =>
          Number(row.delivery_fee || 0) === 0 &&
          Number(row.delivery_fee_raw || 0) > 0,
      ),
      "every campaign child keeps its raw fee while charging the customer zero",
    );
  } else {
    assert.equal(
      Number(children[0].delivery_fee_raw || 0),
      Number(children[0].delivery_fee || 0),
      "first store keeps the full fee",
    );
    assert.ok(
      Number(children[1].delivery_fee_raw || 0) >
        Number(children[1].delivery_fee || 0),
      "second store receives the discounted fee",
    );
  }
});
