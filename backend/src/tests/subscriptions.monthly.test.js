import assert from "node:assert/strict";
import test from "node:test";

import {
  applySubscriptionPayment,
  buildInvoiceDraft,
  computeInvoiceStatus,
  resolveBillingMonth,
  resolveDueAt,
  resolveWaive,
  selectMerchantsNeedingInvoice,
  shouldGenerateSubscriptionInvoice,
} from "../modules/subscriptions/subscriptions.logic.js";
import { computeOrderFinancialSnapshot } from "../modules/commerce/merchant-financial.logic.js";

function monthlyProfile(overrides = {}) {
  return {
    commissionModel: "monthly_subscription",
    monthlySubscriptionAmount: 30000,
    profileVersion: 3,
    serviceFeeValue: 500,
    ...overrides,
  };
}

function percentageProfile(overrides = {}) {
  return {
    commissionModel: "percentage",
    monthlySubscriptionAmount: 0,
    ...overrides,
  };
}

test("resolveBillingMonth normalizes any input to first day of month", () => {
  assert.equal(resolveBillingMonth("2026-07-19"), "2026-07-01");
  assert.equal(resolveBillingMonth("2026-7"), "2026-07-01");
  assert.equal(
    resolveBillingMonth(new Date(Date.UTC(2026, 6, 31))),
    "2026-07-01"
  );
});

test("resolveDueAt returns the first day of the following month", () => {
  assert.equal(resolveDueAt("2026-07-01"), "2026-08-01T00:00:00.000Z");
  assert.equal(resolveDueAt("2026-12-01"), "2027-01-01T00:00:00.000Z");
});

test("only monthly_subscription merchants with amount > 0 get an invoice", () => {
  assert.equal(shouldGenerateSubscriptionInvoice(monthlyProfile()), true);
  assert.equal(shouldGenerateSubscriptionInvoice(percentageProfile()), false);
  assert.equal(
    shouldGenerateSubscriptionInvoice(monthlyProfile({ monthlySubscriptionAmount: 0 })),
    false
  );
});

test("selectMerchantsNeedingInvoice excludes percentage, zero-amount, and already-invoiced merchants (idempotent)", () => {
  const candidates = [
    { merchantId: 1, commissionModel: "monthly_subscription", monthlySubscriptionAmount: 30000 },
    { merchantId: 2, commissionModel: "percentage", monthlySubscriptionAmount: 0 },
    { merchantId: 3, commissionModel: "monthly_subscription", monthlySubscriptionAmount: 0 },
    { merchantId: 4, commissionModel: "monthly_subscription", monthlySubscriptionAmount: 45000 },
  ];
  // merchant 4 already has an invoice this month -> must be skipped
  const selected = selectMerchantsNeedingInvoice(candidates, [4], "2026-07-01");
  assert.deepEqual(
    selected.map((s) => s.merchantId),
    [1]
  );

  // Running generation twice with everything already present yields nothing new.
  const secondRun = selectMerchantsNeedingInvoice(candidates, [1, 4], "2026-07-01");
  assert.equal(secondRun.length, 0);
});

test("buildInvoiceDraft uses the profile amount, starts pending, and snapshots the profile", () => {
  const draft = buildInvoiceDraft({
    merchantId: 7,
    profile: monthlyProfile(),
    billingMonth: "2026-07-01",
    actorUserId: 99,
  });
  assert.equal(draft.merchantId, 7);
  assert.equal(draft.billingMonth, "2026-07-01");
  assert.equal(draft.subscriptionAmount, 30000);
  assert.equal(draft.paidAmount, 0);
  assert.equal(draft.remainingAmount, 30000);
  assert.equal(draft.status, "pending");
  assert.equal(draft.dueAt, "2026-08-01T00:00:00.000Z");
  assert.equal(draft.billingProfileSnapshot.commissionModel, "monthly_subscription");
  assert.equal(draft.billingProfileSnapshot.monthlySubscriptionAmount, 30000);
});

test("buildInvoiceDraft refuses to invoice non-subscription merchants", () => {
  assert.throws(
    () =>
      buildInvoiceDraft({
        merchantId: 8,
        profile: percentageProfile(),
        billingMonth: "2026-07-01",
      }),
    (error) => {
      assert.equal(error.message, "SUBSCRIPTION_INVOICE_NOT_APPLICABLE");
      assert.equal(error.status, 400);
      return true;
    }
  );
});

test("exact payment marks the invoice paid with a paid_at", () => {
  const applied = applySubscriptionPayment({
    invoice: { subscriptionAmount: 30000, paidAmount: 0, status: "pending" },
    amount: 30000,
    now: new Date("2026-07-10T08:00:00.000Z"),
  });
  assert.equal(applied.appliedAmount, 30000);
  assert.equal(applied.paidAmount, 30000);
  assert.equal(applied.remainingAmount, 0);
  assert.equal(applied.status, "paid");
  assert.equal(applied.paidAt, "2026-07-10T08:00:00.000Z");
});

test("partial payment marks partially_paid and keeps the remaining balance", () => {
  const applied = applySubscriptionPayment({
    invoice: { subscriptionAmount: 30000, paidAmount: 0, status: "pending" },
    amount: 12000,
  });
  assert.equal(applied.appliedAmount, 12000);
  assert.equal(applied.paidAmount, 12000);
  assert.equal(applied.remainingAmount, 18000);
  assert.equal(applied.status, "partially_paid");
  assert.equal(applied.paidAt, null);

  // A follow-up payment settles the rest -> paid.
  const settle = applySubscriptionPayment({
    invoice: { subscriptionAmount: 30000, paidAmount: 12000, status: "partially_paid" },
    amount: 18000,
  });
  assert.equal(settle.status, "paid");
  assert.equal(settle.remainingAmount, 0);
});

test("overpayment is clamped to the remaining balance", () => {
  const applied = applySubscriptionPayment({
    invoice: { subscriptionAmount: 30000, paidAmount: 25000, status: "partially_paid" },
    amount: 99999,
  });
  assert.equal(applied.appliedAmount, 5000);
  assert.equal(applied.overpaymentIgnored, 94999);
  assert.equal(applied.paidAmount, 30000);
  assert.equal(applied.status, "paid");
});

test("non-positive payments and waived invoices are rejected", () => {
  assert.throws(
    () =>
      applySubscriptionPayment({
        invoice: { subscriptionAmount: 30000, paidAmount: 0, status: "pending" },
        amount: 0,
      }),
    (error) => {
      assert.equal(error.message, "VALIDATION_ERROR");
      assert.equal(error.details.fields.amount, "PAYMENT_AMOUNT_INVALID");
      return true;
    }
  );
  assert.throws(
    () =>
      applySubscriptionPayment({
        invoice: { subscriptionAmount: 30000, paidAmount: 0, status: "waived" },
        amount: 1000,
      }),
    (error) => {
      assert.equal(error.message, "SUBSCRIPTION_INVOICE_ALREADY_WAIVED");
      return true;
    }
  );
});

test("waiving requires an explicit reason (cannot clear silently)", () => {
  assert.equal(resolveWaive({ reason: "goodwill credit" }), "goodwill credit");
  assert.throws(
    () => resolveWaive({ reason: "  " }),
    (error) => {
      assert.equal(error.message, "VALIDATION_ERROR");
      assert.equal(error.details.fields.reason, "WAIVE_REASON_REQUIRED");
      return true;
    }
  );
});

test("computeInvoiceStatus flags overdue only when unpaid past due date", () => {
  assert.equal(
    computeInvoiceStatus({
      subscriptionAmount: 30000,
      paidAmount: 0,
      dueAt: "2026-08-01T00:00:00.000Z",
      now: new Date("2026-08-05T00:00:00.000Z"),
    }),
    "overdue"
  );
  assert.equal(
    computeInvoiceStatus({
      subscriptionAmount: 30000,
      paidAmount: 0,
      dueAt: "2026-08-01T00:00:00.000Z",
      now: new Date("2026-07-15T00:00:00.000Z"),
    }),
    "pending"
  );
});

test("monthly subscription debt does not deduct commission from orders (separation of concerns)", () => {
  const snapshot = computeOrderFinancialSnapshot(
    {
      subtotal: 10000,
      service_fee: 500,
      delivery_fee: 1000,
      coupon_discount_total: 0,
      total_amount: 11500,
      delivery_type: "delivery",
      courier_source: "app",
      created_at: "2026-07-05T09:00:00.000Z",
    },
    {
      commission_model: "monthly_subscription",
      monthly_subscription_amount: 30000,
      service_fee_type: "fixed",
      service_fee_value: 500,
      app_delivery_fee_value: 1000,
    }
  );
  // Per-order commission stays 0; the 30000 subscription debt lives only on the
  // separate invoice, never inside the order settlement snapshot.
  assert.equal(snapshot.commissionAmount, 0);
  assert.equal(snapshot.serviceFeeAmount, 500);
  assert.equal(snapshot.storeNetReceivedAmount, 10000);
  assert.equal(snapshot.monthlySubscriptionAmount, 30000);
  assert.equal(snapshot.storeNetReceivedAmount, snapshot.subtotal);
});
