import assert from "node:assert/strict";
import test from "node:test";

import { computeOrderFinancialSnapshot } from "../modules/commerce/merchant-financial.logic.js";

function buildSnapshot(serviceFeeValue, { totalAmount = null, couponDiscountTotal = 0 } = {}) {
  const resolvedTotalAmount =
    totalAmount ?? 10000 + serviceFeeValue + 1000 - couponDiscountTotal;
  return computeOrderFinancialSnapshot(
    {
      subtotal: 10000,
      service_fee: 0,
      delivery_fee: 1000,
      coupon_discount_total: couponDiscountTotal,
      total_amount: resolvedTotalAmount,
      delivery_type: "delivery",
      courier_source: "app",
      has_free_delivery: false,
      created_at: "2026-07-05T09:00:00.000Z",
    },
    {
      commission_type: "fixed",
      commission_value: 0,
      service_fee_type: "fixed",
      service_fee_value: serviceFeeValue,
      delivery_fee_mode: "dynamic",
      app_delivery_fee_value: 1000,
      store_delivery_fee_value: 0,
      app_delivery_enabled: true,
      merchant_delivery_enabled: true,
      distribution_policy: "commission_service_delivery",
      settlement_cycle: "weekly",
    }
  );
}

test("computeOrderFinancialSnapshot keeps fixed service fee 750", () => {
  const snapshot = buildSnapshot(750);

  assert.equal(snapshot.serviceFeeAmount, 750);
  assert.equal(snapshot.appReceivableAmount, 1750);
  assert.equal(snapshot.storeNetAmount, 8250);
});

test("computeOrderFinancialSnapshot keeps fixed service fee 500", () => {
  const snapshot = buildSnapshot(500);

  assert.equal(snapshot.serviceFeeAmount, 500);
  assert.equal(snapshot.appReceivableAmount, 1500);
  assert.equal(snapshot.storeNetAmount, 8500);
});
