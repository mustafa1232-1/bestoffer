import assert from "node:assert/strict";
import test from "node:test";

import {
  validateConversationListQuery,
  validateCreateProposedCart,
} from "../modules/pharmacy/pharmacy.validators.js";

test("validateConversationListQuery keeps q and clamps limit", () => {
  const result = validateConversationListQuery({
    bucket: "active",
    q: "mona",
    limit: 999,
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.bucket, "active");
  assert.equal(result.value.q, "mona");
  assert.equal(result.value.limit, 120);
});

test("validateCreateProposedCart preserves pharmacy item flags", () => {
  const result = validateCreateProposedCart({
    deliveryFee: 1000,
    notes: "review before checkout",
    items: [
      {
        productId: 10,
        productName: "Paracetamol",
        quantity: 2,
        unitPrice: 6000,
        requiresPrescription: false,
        requiresReview: true,
        note: "500mg",
        alternativeGroupId: "pain-tier-a",
        metadata: {
          sku: "PARA-500",
        },
      },
    ],
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.deliveryFee, 1000);
  assert.equal(result.value.notes, "review before checkout");
  assert.equal(result.value.items.length, 1);
  assert.equal(result.value.items[0].requiresPrescription, false);
  assert.equal(result.value.items[0].requiresReview, true);
  assert.equal(result.value.items[0].note, "500mg");
  assert.equal(result.value.items[0].alternativeGroupId, "pain-tier-a");
  assert.equal(result.value.items[0].metadata.sku, "PARA-500");
});
