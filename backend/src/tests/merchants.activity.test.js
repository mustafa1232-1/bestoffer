import assert from "node:assert/strict";
import test from "node:test";

import { validateCreateMerchant } from "../modules/merchants/merchants.validators.js";
import { validateOwnerRegister } from "../modules/owner/owner.validators.js";

function baseCreateBody(overrides = {}) {
  return {
    name: "متجر تجريبي",
    type: "market",
    activityType: "fashion_clothing",
    ownerUserId: 7,
    ...overrides,
  };
}

test("validateCreateMerchant accepts a body with explicit activityType", () => {
  const result = validateCreateMerchant(baseCreateBody());
  assert.equal(result.ok, true, JSON.stringify(result.errors));
});

test("validateCreateMerchant rejects a merchant with no activityType (no silent default)", () => {
  const body = baseCreateBody();
  delete body.activityType;
  const result = validateCreateMerchant(body);
  assert.equal(result.ok, false);
  assert.ok(result.errors.includes("activityType"), JSON.stringify(result.errors));
});

test("validateCreateMerchant rejects empty/blank activityType", () => {
  const result = validateCreateMerchant(baseCreateBody({ activityType: "   " }));
  assert.equal(result.ok, false);
  assert.ok(result.errors.includes("activityType"));
});

test("validateOwnerRegister requires merchantActivityType (no legacy type fallback)", () => {
  // Legacy merchantType present but NO merchantActivityType must still fail.
  const without = validateOwnerRegister({ merchantType: "market" });
  assert.ok(
    without.errors.includes("merchantActivityType"),
    `expected merchantActivityType error, got ${JSON.stringify(without.errors)}`
  );

  // Providing the category removes that specific error.
  const withCategory = validateOwnerRegister({
    merchantType: "market",
    merchantActivityType: "fashion_clothing",
  });
  assert.ok(
    !withCategory.errors.includes("merchantActivityType"),
    `merchantActivityType should be satisfied, got ${JSON.stringify(withCategory.errors)}`
  );
});
