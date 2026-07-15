// Grouped-job details contract test (delivery closure client §1): the details
// response carries ONE authoritative customer destination + job financials,
// never derived from an arbitrary child order in the client.

import test from "node:test";
import assert from "node:assert/strict";
import pg from "pg";
import {
  createMultiStoreFixture,
  cleanupMultiStoreFixture,
} from "./fixtures/multistore-delivery.fixture.js";
import {
  ensureDeliveryJobForGroup,
  recomputeGroupReadiness,
  assignDeliveryJobTx,
  getCourierGroupedJobDetails,
} from "../modules/delivery/delivery-job.service.js";

const MARK = "fixt_dtl_";
function newClient() {
  return new pg.Client({ connectionString: process.env.DATABASE_URL });
}

test("grouped details expose the authoritative customer destination + financials", async (t) => {
  const c = newClient();
  await c.connect();
  t.after(async () => {
    await cleanupMultiStoreFixture(c, MARK).catch(() => {});
    await c.end();
  });
  await cleanupMultiStoreFixture(c, MARK);

  const fx = await createMultiStoreFixture(c, { mark: MARK });
  // Give the group a real total + store coordinates so the contract is populated.
  await c.query(`UPDATE order_group SET total_amount=25000, payment_method='cash', notes='اتركه عند الباب' WHERE id=$1`, [fx.orderGroupId]);
  await c.query(`UPDATE merchant SET latitude=33.3, longitude=44.4, phone='07801' WHERE id=$1`, [fx.merchantIds[0]]);

  await c.query("BEGIN");
  await ensureDeliveryJobForGroup(c, fx.orderGroupId);
  await recomputeGroupReadiness(c, fx.orderGroupId);
  const job = (await c.query("SELECT id FROM delivery_job WHERE order_group_id=$1", [fx.orderGroupId])).rows[0];
  await assignDeliveryJobTx(c, { orderGroupId: fx.orderGroupId, courierUserId: fx.courierId });
  await c.query("COMMIT");

  const details = await getCourierGroupedJobDetails(fx.courierId, job.id);

  // One customer destination.
  assert.ok(details.customer, "customer destination present");
  assert.equal(Number(details.customer.userId), Number(fx.customerId), "customer is the group's customer");
  assert.ok(details.customer.displayName, "displayName present");
  assert.ok(details.customer.phone, "phone present (courier authorized)");
  assert.match(details.customer.address, /A101/, "formatted address includes the block");
  assert.equal(details.customer.deliveryNotes, "اتركه عند الباب", "delivery notes surfaced");

  // Financials.
  assert.equal(details.paymentMethod, "cash");
  assert.equal(details.totalAmount, 25000);
  assert.equal(details.amountToCollect, 25000, "cash → collect the total");
  assert.ok(details.orderGroupPublicId, "public group id present");
  assert.ok(details.assignedAt, "assignedAt present");

  // Stops carry store identity + coordinates for navigation.
  assert.equal(details.pickupStops.length, 2);
  const withCoords = details.pickupStops.find((s) => Number(s.storeId) === Number(fx.merchantIds[0]));
  assert.equal(withCoords.latitude, 33.3);
  assert.equal(withCoords.longitude, 44.4);
  assert.ok(withCoords.storePhone, "store phone present");

  // Non-cash job collects nothing.
  await c.query(`UPDATE order_group SET payment_method='card' WHERE id=$1`, [fx.orderGroupId]);
  await c.query(`UPDATE delivery_job SET payment_method='card' WHERE id=$1`, [job.id]);
  const cardDetails = await getCourierGroupedJobDetails(fx.courierId, job.id);
  assert.equal(cardDetails.amountToCollect, 0, "non-cash collects nothing");
});
