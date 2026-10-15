import assert from "node:assert/strict";
import test from "node:test";

import { rankCommerceCandidates } from "../modules/assistant/assistant.ai.service.js";
import { validateRecommendCommerceBody } from "../modules/assistant/assistant.validators.js";

const candidates = [
  {
    productId: 1,
    productName: "سماعة لاسلكية اقتصادية",
    productDescription: "سماعة بلوتوث",
    merchantName: "متجر التقنية",
    categoryName: "إلكترونيات",
    effectivePrice: 18000,
    discountedPrice: 18000,
    freeDelivery: false,
    avgRating: 4.1,
    ratingCount: 90,
    avgDeliveryMinutes: 45,
    completedOrders: 210,
  },
  {
    productId: 2,
    productName: "سماعة لاسلكية ممتازة",
    productDescription: "صوت واضح وبطارية طويلة",
    merchantName: "النور",
    categoryName: "إلكترونيات",
    effectivePrice: 32000,
    discountedPrice: 0,
    freeDelivery: true,
    avgRating: 4.9,
    ratingCount: 420,
    avgDeliveryMinutes: 35,
    completedOrders: 900,
  },
  {
    productId: 3,
    productName: "سماعة لاسلكية سريعة",
    productDescription: "متوفرة للتوصيل السريع",
    merchantName: "السوق السريع",
    categoryName: "إلكترونيات",
    effectivePrice: 27000,
    discountedPrice: 0,
    freeDelivery: false,
    avgRating: 4.4,
    ratingCount: 160,
    avgDeliveryMinutes: 15,
    completedOrders: 500,
  },
];

test("commerce ranking honors budget and exposes distinct decision choices", () => {
  const ranked = rankCommerceCandidates(candidates, {
    query: "أريد سماعة لاسلكية",
    maxPrice: 30000,
    priority: "balanced",
    limit: 10,
  });

  assert.equal(ranked.some((item) => item.productId === 2), false);
  assert.equal(ranked[0].recommendationKey, "best_match");
  assert.equal(
    ranked.some((item) => item.recommendationTags.includes("best_price")),
    true
  );
  assert.equal(ranked.some((item) => item.recommendationKey === "fastest"), true);
  assert.ok(ranked.every((item) => item.reason));
});

test("commerce ranking changes emphasis for price and rating priorities", () => {
  const byPrice = rankCommerceCandidates(candidates, {
    query: "سماعة",
    priority: "price",
  });
  const byRating = rankCommerceCandidates(candidates, {
    query: "سماعة",
    priority: "rating",
  });

  assert.equal(byPrice[0].productId, 1);
  assert.equal(byRating[0].productId, 2);
  assert.equal(byRating[0].recommendationKey, "best_rating");
});

test("commerce ranking rejects unrelated fallback pool items", () => {
  const ranked = rankCommerceCandidates(candidates, {
    query: "كنبة أثاث",
    priority: "balanced",
  });

  assert.deepEqual(ranked, []);
});

test("commerce recommendation validator accepts guided decision filters", () => {
  const valid = validateRecommendCommerceBody({
    query: "سماعة",
    kind: "shopping",
    priority: "rating",
    maxPrice: 25000,
    limit: 8,
  });
  const invalid = validateRecommendCommerceBody({
    priority: "unknown",
    maxPrice: -10,
  });

  assert.equal(valid.ok, true);
  assert.equal(valid.value.priority, "rating");
  assert.equal(valid.value.maxPrice, 25000);
  assert.equal(invalid.ok, false);
  assert.deepEqual(invalid.errors.sort(), ["maxPrice", "priority"]);
});
