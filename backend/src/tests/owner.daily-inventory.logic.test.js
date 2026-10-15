import test from "node:test";
import assert from "node:assert/strict";

import { __ownerInventoryTestables } from "../modules/owner/owner.service.js";

const { computeOwnerInventoryState } = __ownerInventoryTestables;

test("owner daily inventory marks zero quantity as out of stock and unavailable", () => {
  const state = computeOwnerInventoryState({
    quantity: 0,
    requestedAvailable: true,
    threshold: 5,
  });

  assert.deepEqual(state, {
    quantity: 0,
    reorderThreshold: 5,
    manualDisabled: false,
    autoDisabled: true,
    stockStatus: "out_of_stock",
    productIsAvailable: false,
  });
});

test("owner daily inventory restores positive quantity as available stock", () => {
  const state = computeOwnerInventoryState({
    quantity: 8,
    requestedAvailable: true,
    threshold: 5,
  });

  assert.deepEqual(state, {
    quantity: 8,
    reorderThreshold: 5,
    manualDisabled: false,
    autoDisabled: false,
    stockStatus: "in_stock",
    productIsAvailable: true,
  });
});

test("owner daily inventory keeps manually unavailable products disabled", () => {
  const state = computeOwnerInventoryState({
    quantity: 8,
    requestedAvailable: false,
    threshold: 5,
  });

  assert.deepEqual(state, {
    quantity: 8,
    reorderThreshold: 5,
    manualDisabled: true,
    autoDisabled: false,
    stockStatus: "manual_disabled",
    productIsAvailable: false,
  });
});
