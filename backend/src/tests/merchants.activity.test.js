import assert from "node:assert/strict";
import test from "node:test";

import { normalizeActivityType } from "../modules/merchants/store-activity.registry.js";
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

test("validateCreateMerchant accepts smoking supplies as an explicit market activity", () => {
  const result = validateCreateMerchant(
    baseCreateBody({ activityType: "smoking_supplies", type: "market" })
  );
  assert.equal(result.ok, true, JSON.stringify(result.errors));
});

test("validateCreateMerchant accepts furnishings and dietary supplements market activities", () => {
  for (const activityType of ["furnishings", "dietary_supplements"]) {
    const result = validateCreateMerchant(
      baseCreateBody({ activityType, type: "market" })
    );
    assert.equal(result.ok, true, `${activityType}: ${JSON.stringify(result.errors)}`);
  }
});

test("validateCreateMerchant accepts phone maintenance and phones technology market activities", () => {
  for (const activityType of ["phone_maintenance", "phones_technology"]) {
    const result = validateCreateMerchant(
      baseCreateBody({ activityType, type: "market" })
    );
    assert.equal(result.ok, true, `${activityType}: ${JSON.stringify(result.errors)}`);
  }
});

test("validateCreateMerchant rejects missing type", () => {
  const body = baseCreateBody();
  delete body.type;
  const result = validateCreateMerchant(body);
  assert.equal(result.ok, false);
  assert.ok(result.errors.includes("type"), JSON.stringify(result.errors));
});

test("validateCreateMerchant rejects invalid type", () => {
  const result = validateCreateMerchant(baseCreateBody({ type: "pharmacy" }));
  assert.equal(result.ok, false);
  assert.ok(result.errors.includes("type"), JSON.stringify(result.errors));
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

test("normalizeActivityType keeps fashion aliases on the fashion_clothing surface", () => {
  assert.equal(normalizeActivityType("fashion"), "fashion_clothing");
  assert.equal(normalizeActivityType("women_fashion"), "fashion_clothing");
  assert.equal(normalizeActivityType("men_fashion"), "fashion_clothing");
  assert.equal(normalizeActivityType("smoking_supplies"), "smoking_supplies");
  assert.equal(normalizeActivityType("furnishings"), "furnishings");
  assert.equal(normalizeActivityType("dietary_supplements"), "dietary_supplements");
  assert.equal(normalizeActivityType("phone_maintenance"), "phone_maintenance");
  assert.equal(normalizeActivityType("phones_technology"), "phones_technology");
});
