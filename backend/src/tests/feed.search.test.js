import assert from "node:assert/strict";
import test from "node:test";

import { mapSocialMerchantSearchResultRow } from "../modules/feed/feed.search.service.js";

test("social merchant search labels the backend activity type", () => {
  const result = mapSocialMerchantSearchResultRow({
    id: 9,
    name: "Clothing House",
    type: "market",
    activity_type: "fashion_clothing",
    phone: "0770000000",
    image_url: "/merchant.jpg",
    review_posts_count: 14,
  });

  assert.equal(result.id, 9);
  assert.equal(result.type, "market");
  assert.equal(result.activityType, "fashion_clothing");
  assert.equal(result.reviewPostsCount, 14);
});

test("social merchant search falls back to type when activity type is missing", () => {
  const result = mapSocialMerchantSearchResultRow({
    id: 10,
    name: "General Store",
    type: "market",
    phone: "",
    image_url: null,
    review_posts_count: 0,
  });

  assert.equal(result.activityType, "market");
});
