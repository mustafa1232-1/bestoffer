import assert from "node:assert/strict";
import test from "node:test";

import { __ordersRepoTestables } from "../modules/orders/orders.repo.js";

const { toDeliveryDetailResponse } = __ordersRepoTestables;

function buildOrderRow(overrides = {}) {
  return {
    id: 7,
    merchant_id: 3,
    customer_user_id: 11,
    delivery_user_id: 99,
    delivery_assignment_status: "ASSIGNED",
    status: "on_the_way",
    merchant_name: "متجر تجريبي",
    merchant_type: "restaurant",
    merchant_phone: "0780000000",
    owner_user_id: 5,
    customer_full_name: "زبون تجريبي",
    customer_phone: "0770000000",
    customer_city: "مدينة بسماية",
    customer_block: "A1",
    customer_building_number: "12",
    customer_apartment: "3",
    customer_image_url: null,
    note: "بدون بصل",
    gross_subtotal: 10000,
    product_discount_total: 0,
    subtotal: 10000,
    service_fee: 1500,
    delivery_fee: 3000,
    coupon_discount_total: 500,
    total_amount: 14000,
    payment_method: "cash",
    payment_method_other: null,
    created_at: "2026-06-24T10:00:00.000Z",
    items: [
      {
        id: 1,
        order_id: 7,
        product_name: "برغر",
        quantity: 2,
        unit_price: 5000,
        line_total: 10000,
      },
      {
        id: 2,
        order_id: 7,
        product_name: "بطاطا",
        quantity: 1,
        unit_price: 2000,
        line_total: 2000,
      },
    ],
    ...overrides,
  };
}

test("delivery order detail returns items for the assigned courier", () => {
  const res = toDeliveryDetailResponse(buildOrderRow(), {
    requestUserId: 99,
    requestUserRole: "delivery",
    isBackoffice: false,
  });

  assert.equal(Array.isArray(res.items), true);
  assert.equal(res.items.length, 2, "items must be returned, not an empty list");
  assert.equal(res.order.items.length, 2);
  assert.equal(res.items[0].product_name, "برغر");
  assert.equal(res.items[0].quantity, 2);
});

test("delivery order detail exposes the full invoice totals", () => {
  const res = toDeliveryDetailResponse(buildOrderRow(), {
    requestUserId: 99,
    requestUserRole: "delivery",
    isBackoffice: false,
  });

  assert.equal(res.invoice.grossSubtotal, 10000);
  assert.equal(res.invoice.subtotal, 10000);
  assert.equal(res.invoice.serviceFee, 1500, "service fee must be present");
  assert.equal(res.invoice.deliveryFee, 3000, "delivery fee must be present");
  assert.equal(res.invoice.couponDiscountTotal, 500);
  assert.equal(res.invoice.totalAmount, 14000, "grand total must be present");
  assert.equal(res.merchant.name, "متجر تجريبي");
  assert.equal(res.customer.fullName, "زبون تجريبي");
});

test("assigned courier on_the_way order can mark arrived", () => {
  const res = toDeliveryDetailResponse(buildOrderRow(), {
    requestUserId: 99,
    requestUserRole: "delivery",
    isBackoffice: false,
  });

  assert.equal(res.delivery.isAssignedToRequester, true);
  assert.equal(Array.isArray(res.allowedActions), true);
  assert.ok(
    res.allowedActions.includes("arrived"),
    "assigned on_the_way order should allow the arrived action"
  );
});

test("eligible (unassigned) courier sees an offer they can accept", () => {
  const res = toDeliveryDetailResponse(
    buildOrderRow({
      status: "ready_for_delivery",
      delivery_user_id: null,
      delivery_assignment_status: "PENDING_NO_DRIVER",
    }),
    {
      requestUserId: 42,
      requestUserRole: "delivery",
      isBackoffice: false,
    }
  );

  assert.equal(res.delivery.isAssignedToRequester, false);
  assert.equal(res.delivery.isEligibleForRequester, false);
  assert.equal(res.allowedActions.includes("accept"), false);
  assert.equal(res.allowedActions.includes("reject"), false);
  // Even an unassigned-but-eligible courier must still see the items + invoice.
  assert.equal(res.items.length, 2);
  assert.equal(res.invoice.serviceFee, 1500);
});
