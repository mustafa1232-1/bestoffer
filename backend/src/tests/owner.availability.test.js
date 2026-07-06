import assert from "node:assert/strict";
import test from "node:test";

import {
  validateOwnerMarkOrderItemUnavailable,
  validateOwnerProductCreate,
  validateOwnerProductUpdate,
} from "../modules/owner/owner.validators.js";
import {
  __ownerServiceTestables,
} from "../modules/owner/owner.service.js";
import {
  normalizeRichProductPayload,
} from "../modules/products/product-catalog.logic.js";

const {
  normalizeIsoDateOrNull,
  snapshotAvailability,
  snapshotsDiffer,
  buildAvailabilityAuditValue,
  requiredOrderStatusPermissions,
  productAvailabilityChanged,
} = __ownerServiceTestables;

test("owner product validators accept stored unavailability fields", () => {
  const createResult = validateOwnerProductCreate({
    name: "Lamp",
    categoryId: 1,
    price: 12000,
    isAvailable: false,
    unavailableReason: "Seasonal pause",
    unavailableUntil: "2026-07-08T00:00:00.000Z",
  });
  assert.equal(createResult.ok, true);

  const updateResult = validateOwnerProductUpdate({
    isAvailable: true,
    unavailableReason: null,
    unavailableUntil: null,
  });
  assert.equal(updateResult.ok, true);
});

test("owner item unavailable validator accepts optional reason and date", () => {
  const result = validateOwnerMarkOrderItemUnavailable({
    unavailableReason: "Damaged in prep",
    unavailableUntil: "2026-07-10T00:00:00.000Z",
  });
  assert.equal(result.ok, true);
});

test("rich catalog normalization preserves variant availability metadata", () => {
  const payload = normalizeRichProductPayload({
    variants: [
      {
        selections: [
          { groupCode: "color", optionCode: "red" },
          { groupCode: "size", optionCode: "m" },
        ],
        isAvailable: false,
        unavailableReason: "Sold out",
        unavailableUntil: "2026-07-12T12:00:00.000Z",
      },
    ],
  });

  assert.equal(payload.variants.length, 1);
  assert.equal(payload.variants[0].isAvailable, false);
  assert.equal(payload.variants[0].unavailableReason, "Sold out");
  assert.equal(
    payload.variants[0].unavailableUntil,
    "2026-07-12T12:00:00.000Z"
  );
});

test("availability snapshots produce stable audit payloads", () => {
  const before = snapshotAvailability({ is_available: true });
  const after = snapshotAvailability({
    is_available: false,
    unavailable_reason: "Restocking",
    unavailable_until: "2026-07-09T01:02:03.000Z",
  });

  assert.equal(snapshotsDiffer(before, after), true);
  assert.deepEqual(buildAvailabilityAuditValue(before), {
    isAvailable: true,
    unavailableReason: null,
    unavailableUntil: null,
  });
  assert.deepEqual(buildAvailabilityAuditValue(after), {
    isAvailable: false,
    unavailableReason: "Restocking",
    unavailableUntil: "2026-07-09T01:02:03.000Z",
  });
  assert.equal(normalizeIsoDateOrNull("2026-07-09T01:02:03.000Z"), "2026-07-09T01:02:03.000Z");
});

test("product availability permission is only required when the stored state changes", () => {
  const current = {
    is_available: true,
    unavailable_reason: null,
    unavailable_until: null,
  };

  assert.equal(
    productAvailabilityChanged(current, {
      isAvailable: true,
      unavailableReason: null,
      unavailableUntil: null,
    }),
    false
  );
  assert.equal(
    productAvailabilityChanged(current, {
      isAvailable: false,
      unavailableReason: "Paused",
      unavailableUntil: null,
    }),
    true
  );
  assert.equal(
    productAvailabilityChanged(
      {
        is_available: false,
        unavailable_reason: "Paused",
        unavailable_until: "2026-07-11T00:00:00.000Z",
      },
      {
        isAvailable: false,
        unavailableReason: "Paused",
        unavailableUntil: "2026-07-11T00:00:00.000Z",
      }
    ),
    false
  );
});

test("owner order status permissions separate accept reject prepare flows", () => {
  assert.deepEqual(requiredOrderStatusPermissions("approved"), [
    "accept_orders",
    "change_order_status",
  ]);
  assert.deepEqual(requiredOrderStatusPermissions("preparing"), [
    "prepare_orders",
    "change_order_status",
  ]);
  assert.deepEqual(requiredOrderStatusPermissions("ready_for_delivery"), [
    "prepare_orders",
    "change_order_status",
  ]);
  assert.deepEqual(requiredOrderStatusPermissions("cancelled"), [
    "reject_orders",
    "change_order_status",
  ]);
  assert.deepEqual(requiredOrderStatusPermissions("on_the_way"), [
    "change_order_status",
  ]);
});
