import assert from "node:assert/strict";
import test from "node:test";

import {
  assertOwnerTransition,
  isDeliveryCurrentStatus,
  isOrderChatStatus,
  isOwnerCurrentStatus,
} from "../modules/orders/order-flow.logic.js";
import { __ordersRepoTestables } from "../modules/orders/orders.repo.js";

test("store can cancel an order before live delivery starts", () => {
  for (const currentStatus of [
    "pending",
    "approved",
    "preparing",
    "ready_for_delivery",
    "ready_for_pickup",
  ]) {
    assert.doesNotThrow(() =>
      assertOwnerTransition({
        currentStatus,
        nextStatus: "cancelled",
        deliveryUserId: 99,
        isMerchantDelivery: false,
        hasAppDeliveryAssignment: true,
      })
    );
  }
});

test("store cannot cancel after the order leaves for live delivery", () => {
  for (const currentStatus of ["on_the_way", "arrived", "delivered", "cancelled"]) {
    assert.throws(
      () =>
        assertOwnerTransition({
          currentStatus,
          nextStatus: "cancelled",
          deliveryUserId: 99,
          isMerchantDelivery: false,
          hasAppDeliveryAssignment: true,
        }),
      /لا يمكن إلغاء الطلب/
    );
  }
});

test("courier delivery is terminal without customer confirmation", () => {
  assert.equal(isOwnerCurrentStatus("delivered", null), false);
  assert.equal(isOwnerCurrentStatus("delivered", new Date()), false);
  assert.equal(isDeliveryCurrentStatus("delivered", null), false);
  assert.equal(isDeliveryCurrentStatus("delivered", new Date()), false);
  assert.equal(isOwnerCurrentStatus("arrived"), true);
  assert.equal(isDeliveryCurrentStatus("arrived"), true);
  assert.equal(isOrderChatStatus("delivered"), false);
});

test("single-store approval states trigger immediate delivery recovery", () => {
  const { shouldTriggerDeliveryAssignmentRecovery } = __ordersRepoTestables;

  assert.equal(shouldTriggerDeliveryAssignmentRecovery("approved", null), true);
  assert.equal(shouldTriggerDeliveryAssignmentRecovery("preparing", null), true);
  assert.equal(
    shouldTriggerDeliveryAssignmentRecovery("ready_for_delivery", null),
    true,
  );
  assert.equal(shouldTriggerDeliveryAssignmentRecovery("pending", null), false);
});

test("live courier updates preserve the canonical tracking stage mapping", () => {
  const { buildOrderTrackingStage } = __ordersRepoTestables;

  assert.equal(
    buildOrderTrackingStage({ status: "ready_for_delivery" }),
    "ready_for_pickup",
  );
  assert.equal(
    buildOrderTrackingStage({ status: "on_the_way" }),
    "heading_to_customer",
  );
  assert.equal(
    buildOrderTrackingStage({ status: "arrived" }),
    "near_customer",
  );
});
