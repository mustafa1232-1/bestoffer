import assert from "node:assert/strict";
import test from "node:test";

import {
  buildDeliveryCashSettlementSnapshot,
  computeOrderFinancialSnapshot,
  evaluateCourierEndDayReadiness,
  resolveStoreCashConfirmationSnapshot,
} from "../modules/commerce/merchant-financial.logic.js";

function buildOrder(overrides = {}) {
  return {
    subtotal: 10000,
    service_fee: 500,
    delivery_fee: 1000,
    coupon_discount_total: 0,
    total_amount: 11500,
    delivery_type: "delivery",
    courier_source: "app",
    has_free_delivery: false,
    created_at: "2026-07-05T09:00:00.000Z",
    ...overrides,
  };
}

function buildProfile(overrides = {}) {
  return {
    commission_type: "percentage",
    commission_value: 10,
    commission_model: "percentage",
    monthly_subscription_amount: 0,
    service_fee_type: "fixed",
    service_fee_value: 500,
    delivery_fee_mode: "dynamic",
    app_delivery_fee_value: 1000,
    store_delivery_fee_value: 0,
    app_delivery_enabled: true,
    merchant_delivery_enabled: true,
    distribution_policy: "commission_service_delivery",
    settlement_cycle: "weekly",
    ...overrides,
  };
}

test("monthly subscription keeps commission at zero while service fee stays stored", () => {
  const snapshot = computeOrderFinancialSnapshot(
    buildOrder(),
    buildProfile({
      commission_model: "monthly_subscription",
      monthly_subscription_amount: 30000,
    })
  );

  assert.equal(snapshot.commissionAmount, 0);
  assert.equal(snapshot.serviceFeeAmount, 500);
  assert.equal(snapshot.deliveryCashAmount, 1000);
  assert.equal(snapshot.customerTotalAmount, 11500);
  assert.equal(snapshot.storeNetReceivedAmount, 10000);
  assert.equal(snapshot.appDueFromDelivery, 500);
});

test("percentage delivery cash settlement snapshot keeps stored service fee, coupon math, and delivery earning separate", () => {
  const snapshot = buildDeliveryCashSettlementSnapshot([
    buildOrder({
      coupon_discount_total: 250,
      total_amount: 11250,
    }),
  ], buildProfile({
    commission_model: "percentage",
    monthly_subscription_amount: 0,
  }));

  assert.equal(snapshot.ordersCount, 1);
  assert.equal(snapshot.subtotalAmount, 10000);
  assert.equal(snapshot.couponDiscountTotal, 250);
  assert.equal(snapshot.commissionModel, "percentage");
  assert.equal(snapshot.commissionAmount, 1000);
  assert.equal(snapshot.serviceFeeAmount, 500);
  assert.equal(snapshot.deliveryFeeAmount, 1000);
  assert.equal(snapshot.customerTotalAmount, 11250);
  assert.equal(snapshot.deliveryEarningAmount, 1000);
  assert.equal(snapshot.storeNetReceivedAmount, 8750);
  assert.equal(snapshot.appDueFromDelivery, 1500);
});

test("courier end-day readiness blocks while an open settlement remains", () => {
  const readiness = evaluateCourierEndDayReadiness([
    {
      id: 1,
      status: "pending",
      settlementStatus: "pending_store_confirmation",
      totalAmount: 11250,
      appDueFromDelivery: 1500,
    },
    {
      id: 2,
      status: "pending",
      settlementStatus: "closed",
      totalAmount: 1000,
      appDueFromDelivery: 0,
    },
    {
      id: 3,
      status: "received",
      settlementStatus: "received",
      totalAmount: 500,
      appDueFromDelivery: 500,
    },
  ]);

  assert.equal(readiness.canEndDay, false);
  assert.equal(readiness.outstandingAmount, 1500);
  assert.equal(readiness.openSettlements.length, 1);
  assert.equal(readiness.openSettlements[0].id, 1);
  assert.equal(readiness.openSettlements[0].appDueFromDelivery, 1500);
});

test("store cash confirmation snapshot records received status and difference review", () => {
  const confirmed = resolveStoreCashConfirmationSnapshot({
    expectedAmount: 8750,
    actualAmount: 8700,
    reason: "short cash",
    actorUserId: 77,
  });

  assert.equal(confirmed.storeCashConfirmed, true);
  assert.equal(confirmed.amountReceivedActual, 8700);
  assert.equal(confirmed.differenceAmount, -50);
  assert.equal(confirmed.differenceReason, "short cash");
  assert.equal(confirmed.settlementStatus, "difference_review");

  const exact = resolveStoreCashConfirmationSnapshot({
    expectedAmount: 8750,
    actualAmount: 8750,
    actorUserId: 77,
  });

  assert.equal(exact.differenceAmount, 0);
  assert.equal(exact.settlementStatus, "received");
});
