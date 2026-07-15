import assert from "node:assert/strict";
import test from "node:test";

import {
  validateCommunityChatMessageBody,
  validateCreatePost,
  validateCreateStory,
  validateSendMessage,
} from "../modules/feed/feed.validators.js";

test("phase 3b thread messages accept clientMessageId and preserve it", () => {
  const result = validateSendMessage({
    body: "Phase 3B hello",
    clientMessageId: "msg_phase3b_001",
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.body, "Phase 3B hello");
  assert.equal(result.value.clientMessageId, "msg_phase3b_001");
});

test("phase 3b community messages accept clientMessageId and preserve it", () => {
  const result = validateCommunityChatMessageBody({
    body: "Community Phase 3B",
    clientMessageId: "community_phase3b_001",
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.body, "Community Phase 3B");
  assert.equal(result.value.clientMessageId, "community_phase3b_001");
});

test("phase 3b rejects overlong clientMessageId values", () => {
  const overlong = "x".repeat(121);
  const threadResult = validateSendMessage({
    body: "Phase 3B hello",
    clientMessageId: overlong,
  });
  const communityResult = validateCommunityChatMessageBody({
    body: "Community Phase 3B",
    clientMessageId: overlong,
  });

  assert.equal(threadResult.ok, false);
  assert.ok(threadResult.errors.includes("clientMessageId"));
  assert.equal(communityResult.ok, false);
  assert.ok(communityResult.errors.includes("clientMessageId"));
});

test("validateCreateStory persists explicit story interaction settings", () => {
  const result = validateCreateStory({
    caption: "Story flags",
    allowLikes: false,
    allowPrivateReplies: false,
    allowComments: true,
    allowSharing: "false",
    allowReshare: "true",
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.allowLikes, false);
  assert.equal(result.value.allowPrivateReplies, false);
  assert.equal(result.value.allowComments, true);
  assert.equal(result.value.allowSharing, false);
  assert.equal(result.value.allowReshare, true);
});

test("validateCreateStory accepts nested storyInteractionSettings", () => {
  const result = validateCreateStory({
    caption: "Story flags nested",
    storyInteractionSettings: {
      allowLikes: false,
      allowPrivateReplies: true,
      allowComments: false,
      allowSharing: true,
      allowReshare: false,
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.allowLikes, false);
  assert.equal(result.value.allowPrivateReplies, true);
  assert.equal(result.value.allowComments, false);
  assert.equal(result.value.allowSharing, true);
  assert.equal(result.value.allowReshare, false);
});

test("validateCreateStory rejects malformed story interaction booleans", () => {
  const result = validateCreateStory({
    caption: "Story flags",
    allowLikes: "maybe",
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.includes("allowLikes"));
});

test("shared entity allowlist accepts story, profile, user, and merchant review", () => {
  for (const sharedEntityType of [
    "story",
    "profile",
    "user",
    "merchant_review",
  ]) {
    const threadResult = validateSendMessage({
      body: "hi",
      sharedEntityType,
      sharedEntityId: 44,
    });
    const communityResult = validateCommunityChatMessageBody({
      body: "hi",
      sharedEntityType,
      sharedEntityId: 44,
    });
    assert.equal(threadResult.ok, true, sharedEntityType);
    assert.equal(communityResult.ok, true, sharedEntityType);
  }
});

test("merchant review validation requires merchant and a 1-5 integer rating", () => {
  const valid = validateCreatePost({
    postKind: "merchant_review",
    merchantId: 17,
    reviewRating: 5,
  });
  assert.equal(valid.ok, true);
  assert.equal(valid.value.postKind, "merchant_review");
  assert.equal(valid.value.merchantId, 17);
  assert.equal(valid.value.reviewRating, 5);

  const missingMerchant = validateCreatePost({
    postKind: "merchant_review",
    reviewRating: 4,
  });
  assert.equal(missingMerchant.ok, false);
  assert.ok(missingMerchant.errors.includes("merchantId_required"));

  for (const reviewRating of [0, 1.5, 6]) {
    const invalidRating = validateCreatePost({
      postKind: "merchant_review",
      merchantId: 17,
      reviewRating,
    });
    assert.equal(invalidRating.ok, false, String(reviewRating));
    assert.ok(invalidRating.errors.includes("reviewRating"));
  }
});
