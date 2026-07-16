// Pure unit tests for storefront delivery validation (ETA range, fee/min-order
// caps, null-clears-field). No DB access required.
import assert from "node:assert/strict";
import test from "node:test";

import { applyStorefrontDeliveryPatch } from "../modules/owner/owner.service.js";

function run(dto, currentMerchant = {}) {
  const patch = {};
  applyStorefrontDeliveryPatch({ dto, currentMerchant, patch });
  return patch;
}

test("accepts a valid ETA range + fee + minimum order", () => {
  const patch = run({
    deliveryEtaMinMinutes: 20,
    deliveryEtaMaxMinutes: 35,
    deliveryFee: 3000,
    minimumOrder: 10000,
  });
  assert.equal(patch.deliveryEtaMinMinutes, 20);
  assert.equal(patch.deliveryEtaMaxMinutes, 35);
  assert.equal(patch.deliveryFee, 3000);
  assert.equal(patch.minimumOrder, 10000);
});

test("rejects max < min ETA", () => {
  assert.throws(
    () => run({ deliveryEtaMinMinutes: 40, deliveryEtaMaxMinutes: 20 }),
    (e) => e.status === 400 && e.fields.includes("deliveryEtaRange")
  );
});

test("cross-field range uses stored min when only max is sent", () => {
  assert.throws(
    () =>
      run(
        { deliveryEtaMaxMinutes: 10 },
        { delivery_eta_min_minutes: 30 }
      ),
    (e) => e.fields.includes("deliveryEtaRange")
  );
});

test("rejects negative fee and over-cap fee", () => {
  assert.throws(
    () => run({ deliveryFee: -1 }),
    (e) => e.fields.includes("deliveryFee")
  );
  assert.throws(
    () => run({ deliveryFee: 5_000_000 }),
    (e) => e.fields.includes("deliveryFee")
  );
});

test("rejects non-integer ETA minutes", () => {
  assert.throws(
    () => run({ deliveryEtaMinMinutes: 12.5 }),
    (e) => e.fields.includes("deliveryEtaMinMinutes")
  );
});

test("null explicitly clears delivery fields (delivery disabled)", () => {
  const patch = run({
    deliveryEtaMinMinutes: null,
    deliveryEtaMaxMinutes: null,
    deliveryFee: null,
    minimumOrder: null,
  });
  assert.equal(patch.deliveryEtaMinMinutes, null);
  assert.equal(patch.deliveryEtaMaxMinutes, null);
  assert.equal(patch.deliveryFee, null);
  assert.equal(patch.minimumOrder, null);
});
