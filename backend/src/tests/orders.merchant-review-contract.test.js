import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { rateMerchant } from "../modules/orders/orders.service.js";
import { hashPin } from "../shared/utils/hash.js";

function makeSuffix(prefix = "") {
  return `${prefix}${Date.now().toString(36)}${Math.random()
    .toString(36)
    .slice(2, 8)}`;
}

function makePhone(seed = 0) {
  const tail = String(Date.now() + Number(seed || 0)).slice(-9);
  return `07${tail}`;
}

async function createTestUser() {
  return createUser({
    fullName: `Merchant Review Customer ${makeSuffix()}`,
    username: makeSuffix("reviewer").slice(0, 32),
    phone: makePhone(Math.floor(Math.random() * 1000)),
    pinHash: await hashPin("1234"),
    block: "A",
    buildingNumber: "101",
    apartment: "1",
    role: "user",
    analyticsConsentGranted: true,
    analyticsConsentVersion: "merchant_review_contract_test",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
}

async function createMerchant() {
  const merchant = await q(
    `INSERT INTO merchant (name, type)
     VALUES ($1, 'restaurant')
     RETURNING id`,
    [`Merchant Review ${makeSuffix()}`]
  );
  assert.equal(merchant.rowCount, 1, "merchant fixture must insert");
  return Number(merchant.rows[0].id);
}

async function createDeliveredOrder({ merchantId, customer }) {
  const order = await q(
    `INSERT INTO customer_order
      (
        merchant_id,
        customer_user_id,
        status,
        customer_full_name,
        customer_phone,
        customer_block,
        customer_building_number,
        customer_apartment,
        subtotal,
        delivery_fee,
        total_amount,
        delivered_at,
        customer_confirmed_at
      )
     VALUES ($1, $2, 'delivered', $3, $4, 'A', '101', '1', 0, 0, 0, NOW(), NOW())
     RETURNING id`,
    [merchantId, customer.id, customer.full_name, customer.phone]
  );
  assert.equal(order.rowCount, 1, "order fixture must insert");
  return Number(order.rows[0].id);
}

async function readMerchantReview(merchantId, customerId) {
  return q(
    `SELECT id, order_id, merchant_id, customer_user_id, rating, review_text, review_state
     FROM merchant_verified_review
     WHERE merchant_id = $1 AND customer_user_id = $2
     ORDER BY updated_at DESC, id DESC`,
    [merchantId, customerId]
  );
}

async function cleanupMerchantReviewFixture({ orderIds = [], merchantId, customerId }) {
  if (merchantId != null) {
    await q(`DELETE FROM merchant_verified_review WHERE merchant_id = $1`, [merchantId]);
  }
  if (orderIds.length > 0) {
    await q(`DELETE FROM customer_order WHERE id = ANY($1::bigint[])`, [orderIds.map(Number)]);
  }
  if (merchantId != null) {
    await q(`DELETE FROM merchant WHERE id = $1`, [merchantId]);
  }
  if (customerId != null) {
    await q(`DELETE FROM app_user WHERE id = $1`, [customerId]);
  }
}

test("merchant review create rejects a duplicate active review without editing it", async () => {
  const customer = await createTestUser();
  const merchantId = await createMerchant();
  const firstOrderId = await createDeliveredOrder({ merchantId, customer });
  const secondOrderId = await createDeliveredOrder({ merchantId, customer });

  try {
    await rateMerchant(customer.id, firstOrderId, 4, "first review");

    const firstReview = await readMerchantReview(merchantId, customer.id);
    assert.equal(firstReview.rowCount, 1);
    assert.equal(Number(firstReview.rows[0].order_id), firstOrderId);
    assert.equal(Number(firstReview.rows[0].rating), 4);
    assert.equal(firstReview.rows[0].review_state, "active");

    await assert.rejects(
      () => rateMerchant(customer.id, secondOrderId, 5, "duplicate review"),
      (error) => {
        assert.equal(error.code, "MERCHANT_REVIEW_ALREADY_EXISTS");
        assert.equal(error.status, 409);
        assert.equal(error.details?.merchantId, merchantId);
        assert.ok(Number(error.details?.existingReviewId) > 0);
        assert.equal(error.details?.existingPostId, null);
        return true;
      }
    );

    const reviewsAfterDuplicate = await readMerchantReview(merchantId, customer.id);
    assert.equal(reviewsAfterDuplicate.rowCount, 1, "duplicate create must not add a second review");
    assert.equal(Number(reviewsAfterDuplicate.rows[0].order_id), firstOrderId);
    assert.equal(Number(reviewsAfterDuplicate.rows[0].rating), 4);

    const secondOrder = await q(
      `SELECT merchant_rating, merchant_review
       FROM customer_order
       WHERE id = $1`,
      [secondOrderId]
    );
    assert.equal(secondOrder.rows[0].merchant_rating, null, "duplicate create must not edit the second order");
    assert.equal(secondOrder.rows[0].merchant_review, null, "duplicate create must not edit the second order");
  } finally {
    await cleanupMerchantReviewFixture({
      orderIds: [firstOrderId, secondOrderId],
      merchantId,
      customerId: customer.id,
    });
  }
});

test("merchant review concurrent creates collapse to one success and one duplicate conflict", async () => {
  const customer = await createTestUser();
  const merchantId = await createMerchant();
  const orderId = await createDeliveredOrder({ merchantId, customer });

  try {
    const results = await Promise.allSettled([
      rateMerchant(customer.id, orderId, 4, "concurrent-a"),
      rateMerchant(customer.id, orderId, 5, "concurrent-b"),
    ]);

    const fulfilled = results.filter((result) => result.status === "fulfilled");
    const rejected = results.filter((result) => result.status === "rejected");
    assert.equal(fulfilled.length, 1, "exactly one concurrent create should succeed");
    assert.equal(rejected.length, 1, "exactly one concurrent create should conflict");
    assert.equal(rejected[0].reason.code, "MERCHANT_REVIEW_ALREADY_EXISTS");
    assert.equal(rejected[0].reason.status, 409);

    const review = await readMerchantReview(merchantId, customer.id);
    assert.equal(review.rowCount, 1, "concurrent creates must still leave one review row");
    assert.equal(Number(review.rows[0].order_id), orderId);
    assert.ok([4, 5].includes(Number(review.rows[0].rating)));
  } finally {
    await cleanupMerchantReviewFixture({
      orderIds: [orderId],
      merchantId,
      customerId: customer.id,
    });
  }
});

test("merchant review rollback leaves no review row for an invalid order transition", async () => {
  const customer = await createTestUser();
  const merchantId = await createMerchant();
  const orderId = await q(
    `INSERT INTO customer_order
      (
        merchant_id,
        customer_user_id,
        status,
        customer_full_name,
        customer_phone,
        customer_block,
        customer_building_number,
        customer_apartment,
        subtotal,
        delivery_fee,
        total_amount
      )
     VALUES ($1, $2, 'pending', $3, $4, 'A', '101', '1', 0, 0, 0)
     RETURNING id`,
    [merchantId, customer.id, customer.full_name, customer.phone]
  );

  try {
    await assert.rejects(
      () => rateMerchant(customer.id, Number(orderId.rows[0].id), 4, "not deliverable"),
      (error) => {
        assert.equal(error.code, "ORDER_NOT_FOUND_OR_NOT_RATEABLE");
        assert.equal(error.status, 409);
        return true;
      }
    );

    const review = await readMerchantReview(merchantId, customer.id);
    assert.equal(review.rowCount, 0, "failed create must not leave a review row behind");
  } finally {
    await cleanupMerchantReviewFixture({
      orderIds: [Number(orderId.rows[0].id)],
      merchantId,
      customerId: customer.id,
    });
  }
});
