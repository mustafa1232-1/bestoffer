import assert from "node:assert/strict";
import test from "node:test";

import { computeOrderFinancialSnapshot } from "../modules/commerce/merchant-financial.logic.js";

function buildSnapshot({
  commissionModel = "percentage",
  commissionValue = 10,
  monthlySubscriptionAmount = 0,
  couponDiscountTotal = 0,
  totalAmount = null,
} = {}) {
  const order = {
    subtotal: 10000,
    service_fee: 500,
    delivery_fee: 1000,
    coupon_discount_total: couponDiscountTotal,
    total_amount:
      totalAmount ?? 10000 - couponDiscountTotal + 500 + 1000,
    delivery_type: "delivery",
    courier_source: "app",
    has_free_delivery: false,
    created_at: "2026-07-05T09:00:00.000Z",
  };

  return computeOrderFinancialSnapshot(order, {
    commission_model: commissionModel,
    commission_rate: commissionValue,
    commission_type: "percentage",
    commission_value: commissionValue,
    monthly_subscription_amount: monthlySubscriptionAmount,
    service_fee_type: "fixed",
    service_fee_value: 500,
    delivery_fee_mode: "dynamic",
    app_delivery_fee_value: 1000,
    store_delivery_fee_value: 0,
    app_delivery_enabled: true,
    merchant_delivery_enabled: true,
    distribution_policy: "commission_service_delivery",
    settlement_cycle: "weekly",
  });
}

test("percentage model keeps commission separate from service fee and delivery earning", () => {
  const snapshot = buildSnapshot();

  assert.equal(snapshot.commissionModel, "percentage");
  assert.equal(snapshot.commissionAmount, 1000);
  assert.equal(snapshot.serviceFeeAmount, 500);
  assert.equal(snapshot.deliveryCashAmount, 1000);
  assert.equal(snapshot.appReceivableAmount, 1500);
  assert.equal(snapshot.appDueFromDelivery, 1500);
  assert.equal(snapshot.storeNetAmount, 9000);
  assert.equal(snapshot.storeNetReceivedAmount, 9000);
  assert.equal(snapshot.customerTotalAmount, 11500);
});

test("monthly subscription model keeps commission at zero and only charges service fee to app", () => {
  const snapshot = buildSnapshot({
    commissionModel: "monthly_subscription",
    commissionValue: 0,
    monthlySubscriptionAmount: 30000,
  });

  assert.equal(snapshot.commissionModel, "monthly_subscription");
  assert.equal(snapshot.commissionAmount, 0);
  assert.equal(snapshot.serviceFeeAmount, 500);
  assert.equal(snapshot.deliveryCashAmount, 1000);
  assert.equal(snapshot.appReceivableAmount, 500);
  assert.equal(snapshot.appDueFromDelivery, 500);
  assert.equal(snapshot.storeNetAmount, 10000);
  assert.equal(snapshot.storeNetReceivedAmount, 10000);
  assert.equal(snapshot.customerTotalAmount, 11500);
});

test("coupon discount lowers customer total without reducing stored service fee", () => {
  const snapshot = buildSnapshot({
    couponDiscountTotal: 250,
    totalAmount: 11250,
  });

  assert.equal(snapshot.serviceFeeAmount, 500);
  assert.equal(snapshot.deliveryCashAmount, 1000);
  assert.equal(snapshot.customerTotalAmount, 11250);
  assert.equal(snapshot.storeNetAmount, 8750);
  assert.equal(snapshot.storeNetReceivedAmount, 8750);
  assert.equal(snapshot.appReceivableAmount, 1500);
  assert.equal(snapshot.appDueFromDelivery, 1500);
});
