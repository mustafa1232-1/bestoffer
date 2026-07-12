import assert from "node:assert/strict";
import test from "node:test";

import {
  DELIVERY_ASSIGNMENT_STATUSES,
  deriveDeliveryAssignmentStatus,
  isDeliveryAssignmentAssigned,
  isDeliveryAssignmentPending,
  buildDeliveryDriverSummary,
  buildDeliveryAssignmentPresentation,
} from "../modules/orders/delivery-assignment.logic.js";

test("an active order with a delivery_user_id derives ASSIGNED", () => {
  const status = deriveDeliveryAssignmentStatus({
    status: "preparing",
    delivery_user_id: 4021,
  });
  assert.equal(status, DELIVERY_ASSIGNMENT_STATUSES.ASSIGNED);
});

test("an active order with no driver derives PENDING_NO_DRIVER", () => {
  const status = deriveDeliveryAssignmentStatus({
    status: "preparing",
    delivery_user_id: null,
  });
  assert.equal(status, DELIVERY_ASSIGNMENT_STATUSES.PENDING_NO_DRIVER);
});

test("a cancelled order derives CANCELLED regardless of driver", () => {
  const status = deriveDeliveryAssignmentStatus({
    status: "cancelled_by_store",
    delivery_user_id: 4021,
  });
  assert.equal(status, DELIVERY_ASSIGNMENT_STATUSES.CANCELLED);
});

test("an explicit assignment status is honored over derivation", () => {
  const status = deriveDeliveryAssignmentStatus({
    status: "preparing",
    delivery_assignment_status: "PENDING_NO_DRIVER",
    delivery_user_id: 4021,
  });
  assert.equal(status, DELIVERY_ASSIGNMENT_STATUSES.PENDING_NO_DRIVER);
});

test("ASSIGNED requires a real delivery_user_id (the authenticated account id)", () => {
  // Guards the canonical rule: an order is only "assigned" when
  // delivery_user_id holds a real account id (> 0). A profile id of 0/null
  // must never read as assigned.
  assert.equal(
    isDeliveryAssignmentAssigned({
      delivery_assignment_status: "ASSIGNED",
      delivery_user_id: 4021,
    }),
    true
  );
  assert.equal(
    isDeliveryAssignmentAssigned({
      delivery_assignment_status: "ASSIGNED",
      delivery_user_id: 0,
    }),
    false
  );
  assert.equal(
    isDeliveryAssignmentPending({
      delivery_assignment_status: "PENDING_NO_DRIVER",
    }),
    true
  );
});

test("driver summary id is the delivery account user id, not a profile id", () => {
  const driver = buildDeliveryDriverSummary({
    delivery_user_id: 4021,
    delivery_full_name: "سائق تجريبي",
    delivery_phone: "07800000000",
  });
  assert.equal(driver.id, 4021);
  assert.equal(driver.name, "سائق تجريبي");
});

test("presentation for a pending order has no driver and PENDING status", () => {
  const presentation = buildDeliveryAssignmentPresentation({
    order: {
      id: 181,
      status: "preparing",
      delivery_assignment_status: "PENDING_NO_DRIVER",
      delivery_user_id: null,
    },
  });
  assert.equal(
    presentation.assignmentStatus,
    DELIVERY_ASSIGNMENT_STATUSES.PENDING_NO_DRIVER
  );
  assert.equal(presentation.driver, null);
  assert.equal(presentation.orderId, 181);
});
