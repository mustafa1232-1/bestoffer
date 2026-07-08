import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import * as deliveryService from "../modules/delivery/delivery.service.js";
import { __ordersRepoTestables } from "../modules/orders/orders.repo.js";

const { buildDeliveryEarnings, buildDeliveryRatings } = __ordersRepoTestables;

test("earnings sum delivery fees and split today/month from delivered orders", () => {
  const ref = new Date(2026, 5, 15, 12, 0, 0); // 15 June 2026 (month index 5)
  const rows = [
    {
      id: 1,
      status: "delivered",
      delivery_fee: 3000,
      service_fee: 500,
      total_amount: 14000,
      store_net_received_amount: 9500,
      app_due_from_delivery: 1000,
      difference_amount: 0,
      settlement_status: "received",
      store_cash_confirmed: true,
      payment_method: "cash",
      delivered_at: new Date(2026, 5, 15, 9, 0, 0), // today
      customer_name: "A",
      merchant_name: "M",
    },
    {
      id: 2,
      status: "completed",
      delivery_fee: 2000,
      service_fee: 250,
      total_amount: 10000,
      store_net_received_amount: 7000,
      app_due_from_delivery: 500,
      difference_amount: 50,
      settlement_status: "difference_review",
      store_cash_confirmed: false,
      delivered_at: new Date(2026, 5, 3, 9, 0, 0), // this month, not today
      customer_name: "B",
      merchant_name: "M",
    },
    {
      id: 3,
      status: "delivered",
      delivery_fee: 5000,
      service_fee: 125,
      total_amount: 20000,
      store_net_received_amount: 15000,
      app_due_from_delivery: 1500,
      difference_amount: 25,
      settlement_status: "received",
      store_cash_confirmed: true,
      delivered_at: new Date(2026, 3, 3, 9, 0, 0), // April (old)
      customer_name: "C",
      merchant_name: "M",
    },
  ];

  const out = buildDeliveryEarnings(rows, ref);
  assert.equal(out.todayEarnings, 3000);
  assert.equal(out.monthEarnings, 5000);
  assert.equal(out.deliveryFeeSum, 10000);
  assert.equal(out.serviceFeeSum, 875);
  assert.equal(out.appDueFromDeliverySum, 3000);
  assert.equal(out.storeNetReceivedAmountSum, 31500);
  assert.equal(out.differenceAmountSum, 75);
  assert.equal(out.storeCashConfirmedCount, 2);
  assert.equal(out.completedTodayCount, 1);
  assert.equal(out.completedMonthCount, 2);
  assert.equal(out.rows.length, 3);
  assert.equal(out.rows[0].orderId, 1);
  assert.equal(out.rows[0].deliveryFee, 3000);
  assert.equal(out.rows[0].serviceFee, 500);
  assert.equal(out.rows[0].storeNetReceivedAmount, 9500);
  assert.equal(out.rows[0].appDueFromDelivery, 1000);
  assert.equal(out.rows[0].differenceAmount, 0);
  assert.equal(out.rows[0].settlementStatus, "received");
  assert.equal(out.rows[0].totalInvoice, 14000);
  assert.equal(out.rows[0].paymentMethod, "cash");
});

test("earnings are an empty report (not a fake zero) when no delivered orders", () => {
  const out = buildDeliveryEarnings([], new Date(2026, 5, 15));
  assert.equal(out.todayEarnings, 0);
  assert.equal(out.monthEarnings, 0);
  assert.equal(out.deliveryFeeSum, 0);
  assert.deepEqual(out.rows, []);
});

test("earnings tolerate orders with no payment_method field (production schema)", () => {
  // customer_order has no payment_method column, so the SQL no longer selects
  // it and the row simply lacks the field. The builder must not crash and must
  // return paymentMethod=null while preserving the rest of the row.
  const out = buildDeliveryEarnings(
    [
      {
        id: 5,
        status: "delivered",
        delivery_fee: 1500,
        total_amount: 8000,
        delivered_at: new Date(2026, 5, 15),
        customer_name: "X",
        merchant_name: "Y",
      },
    ],
    new Date(2026, 5, 15)
  );
  assert.equal(out.rows.length, 1);
  assert.equal(out.rows[0].paymentMethod, null);
  assert.equal(out.rows[0].deliveryFee, 1500);
  assert.equal(out.todayEarnings, 1500);
});

test("ratings link each rating to its order and average correctly", () => {
  const rows = [
    {
      id: 10,
      delivery_rating: 5,
      delivery_review: "Great",
      customer_name: "A",
      merchant_name: "M",
      delivered_at: new Date(2026, 5, 1),
    },
    {
      id: 11,
      delivery_rating: 3,
      delivery_review: null,
      customer_name: "B",
      merchant_name: "M",
      delivered_at: new Date(2026, 5, 2),
    },
  ];

  const out = buildDeliveryRatings(rows);
  assert.equal(out.ratingCount, 2);
  assert.equal(out.averageRating, 4);
  assert.equal(out.rows[0].orderId, 10);
  assert.equal(out.rows[0].ratingId, 10);
  assert.equal(out.rows[0].stars, 5);
  assert.equal(out.rows[0].comment, "Great");
});

test("ratings skip rows without stars and survive an empty set", () => {
  const out = buildDeliveryRatings([
    { id: 12, delivery_rating: 0, customer_name: "A" },
    { id: 13, delivery_rating: 4, customer_name: "B" },
  ]);
  assert.equal(out.ratingCount, 1);
  assert.equal(out.rows.length, 1);
  assert.equal(out.rows[0].orderId, 13);

  const empty = buildDeliveryRatings([]);
  assert.equal(empty.averageRating, 0);
  assert.equal(empty.ratingCount, 0);
  assert.deepEqual(empty.rows, []);
});

test("getDeliveryEarnings casts the order_status enum to text (no 42883)", () => {
  // customer_order.status is the PostgreSQL enum `order_status`. Comparing it
  // directly to a text[] (o.status = ANY($2::text[])) raised a production 500
  // (42883 operator does not exist: order_status = text). Guard the regression
  // at the source level since a pure unit test cannot exercise the SQL operator.
  const repoPath = fileURLToPath(
    new URL("../modules/orders/orders.repo.js", import.meta.url)
  );
  const src = readFileSync(repoPath, "utf8");
  const start = src.indexOf("export async function getDeliveryEarnings");
  assert.ok(start >= 0, "getDeliveryEarnings must exist");
  const body = src.slice(start);

  assert.ok(
    body.includes("o.status::text = ANY($2::text[])"),
    "status enum must be cast to text before comparing to a text[]"
  );
  assert.ok(
    !/o\.status = ANY\(\$2::text\[\]\)/.test(body),
    "the un-cast enum=text comparison must not be present"
  );
});

test("getDeliveryEarnings selects service fee and cash settlement columns", () => {
  const repoPath = fileURLToPath(
    new URL("../modules/orders/orders.repo.js", import.meta.url)
  );
  const src = readFileSync(repoPath, "utf8");
  const start = src.indexOf("export async function getDeliveryEarnings");
  assert.ok(start >= 0, "getDeliveryEarnings must exist");
  const body = src.slice(start, start + 1800);

  for (const column of [
    "o.service_fee",
    "o.store_net_received_amount",
    "o.app_due_from_delivery",
    "o.difference_amount",
    "o.settlement_status",
    "o.store_cash_confirmed",
  ]) {
    assert.ok(body.includes(column), `getDeliveryEarnings must select ${column}`);
  }
});

test("getDeliveryAnalytics includes financial settlement totals", () => {
  const repoPath = fileURLToPath(
    new URL("../modules/analytics/analytics.repo.js", import.meta.url)
  );
  const src = readFileSync(repoPath, "utf8");
  const start = src.indexOf("export async function getDeliveryAnalytics");
  assert.ok(start >= 0, "getDeliveryAnalytics must exist");
  const body = src.slice(start, start + 2000);

  for (const column of [
    "o.total_amount",
    "o.delivery_fee",
    "o.service_fee",
    "o.store_net_received_amount",
    "o.app_due_from_delivery",
    "o.difference_amount",
    "inv.commission_amount",
  ]) {
    assert.ok(body.includes(column), `getDeliveryAnalytics must select ${column}`);
  }
});

test("delivery analytics service executes successfully on PostgreSQL", async () => {
  const out = await deliveryService.analytics(987654321);

  for (const key of ["day", "week", "month", "year", "all"]) {
    assert.ok(out[key], `analytics output must include ${key}`);
    assert.equal(Number(out[key].delivered_orders_count || 0) >= 0, true);
  }
});
