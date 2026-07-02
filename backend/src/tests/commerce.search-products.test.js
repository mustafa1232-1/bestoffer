import test from "node:test";
import assert from "node:assert/strict";

import { mapSearchProductResultRow } from "../modules/commerce/commerce.repo.js";

test("search payload exposes rich product fields and category metadata", () => {
  const row = {
    product_id: 9,
    product_category_id: 7,
    category_name: "cloths",
    category_sort_order: 4,
    product_name: "قميص",
    product_description: "قطن",
    product_image_url: "/main.jpg",
    base_price: 20000,
    discounted_price: 15000,
    final_price: 15000,
    discount_percent: 25,
    is_available: true,
    free_delivery: false,
    offer_label: "عرض خاص",
    merchant_id: 2,
    merchant_name: "متجر",
    merchant_type: "market",
    merchant_image_url: "/merchant.jpg",
    merchant_rating: 4.7,
    merchant_ratings_count: 18,
    orders_count: 44,
    eta_minutes: 32,
    proximity_rank: 1,
  };
  const rich = {
    hasVariants: true,
    summaryAttributes: [{ title: "الخامة", valueText: "قطن" }],
    variantGroups: [{ code: "color", options: [{ code: "red" }] }],
    variants: [{ id: 1 }],
    media: [{ imageUrl: "/red.jpg" }],
    primaryMedia: { imageUrl: "/red.jpg" },
  };

  const item = mapSearchProductResultRow(row, rich);

  assert.equal(item.categoryId, 7);
  assert.equal(item.categoryName, "cloths");
  assert.equal(item.categorySortOrder, 4);
  assert.equal(item.imageUrl, "/red.jpg");
  assert.equal(item.hasVariants, true);
  assert.deepEqual(item.variantGroups, rich.variantGroups);
  assert.deepEqual(item.variants, rich.variants);
  assert.deepEqual(item.media, rich.media);
  assert.equal(item.merchant.rating, 4.7);
  assert.equal(item.stats.etaMinutes, 32);
});
