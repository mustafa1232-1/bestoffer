import test from "node:test";
import assert from "node:assert/strict";

import {
  normalizeRichProductPayload,
  validateRichProductPayload,
} from "../modules/products/product-catalog.logic.js";
import {
  normalizeStockQuantityInput,
  validateOwnerCategoryCreate,
  validateOwnerProductCreate,
} from "../modules/owner/owner.validators.js";

test("normalizes rich clothing attributes and concrete variant stock", () => {
  const body = {
    attributes: [{ code: "material", labelAr: "الخامة", valueText: "قطن", showInCard: true }],
      variantGroups: [
      { code: "color", labelAr: "اللون", options: [{ code: "black", labelAr: "أسود", swatchHex: "#000000", colorImageUrl: "/uploads/black.jpg" }] },
      { code: "size", labelAr: "المقاس", options: [{ code: "m", labelAr: "M" }] },
    ],
    variants: [{
      selections: [
        { groupCode: "size", optionCode: "m" },
        { groupCode: "color", optionCode: "black" },
      ],
      sku: "TS-BLK-M",
      stockQuantity: 7,
      priceOverride: 22000,
    }],
  };
  const rich = normalizeRichProductPayload(body);
  assert.equal(rich.attributes[0].showInCard, true);
  assert.equal(rich.variantGroups[0].options[0].imageUrl, "/uploads/black.jpg");
  assert.equal(rich.variants[0].signature, "color:black|size:m");
  assert.equal(rich.variants[0].stockQuantity, 7);
  assert.equal(validateRichProductPayload(body).ok, true);
});

test("owner contracts accept catalog type, stock, and rich arrays", () => {
  assert.equal(validateOwnerCategoryCreate({ name: "cloths", catalogType: "clothes" }).ok, true);
  assert.equal(validateOwnerCategoryCreate({ name: "Vapes", catalogType: "vapes" }).ok, true);
  assert.equal(validateOwnerCategoryCreate({ name: "Hookahs", catalogType: "hookah" }).ok, true);
  assert.equal(validateOwnerCategoryCreate({ name: "Protein", catalogType: "supplements" }).ok, true);
  assert.equal(validateOwnerCategoryCreate({ name: "x", catalogType: "unknown" }).ok, false);
  assert.equal(validateOwnerProductCreate({
    name: "تيشيرت",
    categoryId: 1,
    price: 100,
    stockQuantity: 2,
    attributes: [],
    variantGroups: [],
    variants: [],
    media: [],
  }).ok, true);
});

test("stock quantity input: absent/null/empty means untracked, not zero", () => {
  assert.equal(normalizeStockQuantityInput(undefined), undefined);
  assert.equal(normalizeStockQuantityInput(null), undefined);
  assert.equal(normalizeStockQuantityInput(""), undefined);
  assert.equal(normalizeStockQuantityInput("0"), 0);
  assert.equal(normalizeStockQuantityInput("5"), 5);
  assert.equal(normalizeStockQuantityInput(3), 3);
});
