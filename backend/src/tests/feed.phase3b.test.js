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

test("validateCreateStory preserves typed story attachments for reel shares", () => {
  const result = validateCreateStory({
    caption: "Shared reel story",
    storyStyle: {
      mode: "reelShare",
      attachment: {
        type: "reelShare",
        reelId: 42,
        mediaAssetId: 77,
        streamUid: "stream-uid-77",
        authorId: 9,
        posterUrl: "https://example.com/poster.jpg",
        playbackUrl: "https://example.com/playback.m3u8",
        thumbnailUrl: "https://example.com/thumb.jpg",
        mediaKind: "video",
        aspectRatio: 0.5625,
        caption: "Nice reel",
        label: "Watch reel",
      },
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.storyStyle.attachment.type, "reel_share");
  assert.equal(result.value.storyStyle.attachment.reelId, 42);
  assert.equal(result.value.storyStyle.attachment.mediaAssetId, 77);
  assert.equal(result.value.storyStyle.attachment.streamUid, "stream-uid-77");
  assert.equal(result.value.storyStyle.attachment.authorId, 9);
  assert.equal(result.value.storyStyle.attachment.playbackUrl, "https://example.com/playback.m3u8");
  assert.equal(result.value.storyStyle.attachment.thumbnailUrl, "https://example.com/thumb.jpg");
});

test("validateCreateStory preserves text mention sticker and draw layers", () => {
  const result = validateCreateStory({
    caption: "Layered story",
    storyStyle: {
      mode: "text",
      layers: [
        {
          id: "text-1",
          type: "text",
          x: 0.2,
          y: 0.3,
          scale: 1.4,
          rotation: 0.15,
          zIndex: 3,
          text: "Hello",
          color: "#FF0000",
          backgroundColor: "#22000000",
          fontFamily: "system",
          fontWeight: "bold",
          textAlign: "center",
          fontScale: 1.2,
        },
        {
          id: "mention-1",
          type: "mention",
          x: 0.6,
          y: 0.4,
          scale: 1,
          rotation: 0,
          zIndex: 4,
          text: "@Ali",
          color: "#00FF00",
          backgroundColor: "#11000000",
          fontFamily: "system",
          fontWeight: "bold",
          textAlign: "left",
          fontScale: 1,
          mentionedUserId: 55,
          displayLabel: "Ali",
        },
        {
          id: "sticker-1",
          type: "sticker",
          x: 0.5,
          y: 0.5,
          scale: 1.1,
          rotation: 0.3,
          zIndex: 5,
          sticker: "🔥",
        },
        {
          id: "draw-1",
          type: "draw",
          x: 0.5,
          y: 0.5,
          scale: 1,
          rotation: 0,
          zIndex: 6,
          locked: true,
          strokes: [
            {
              color: "#ABCDEF",
              width: 6,
              points: [
                { x: 0.1, y: 0.2 },
                { x: 0.3, y: 0.4 },
              ],
            },
          ],
        },
      ],
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.storyStyle.layers.length, 4);
  assert.equal(result.value.storyStyle.layers[0].text, "Hello");
  assert.equal(result.value.storyStyle.layers[0].color, "#FF0000");
  assert.equal(result.value.storyStyle.layers[0].backgroundColor, "#22000000");
  assert.equal(result.value.storyStyle.layers[0].fontScale, 1.2);
  assert.equal(result.value.storyStyle.layers[1].mentionedUserId, 55);
  assert.equal(result.value.storyStyle.layers[1].displayLabel, "Ali");
  assert.equal(result.value.storyStyle.layers[2].sticker, "🔥");
  assert.equal(result.value.storyStyle.layers[3].strokes.length, 1);
  assert.equal(result.value.storyStyle.layers[3].strokes[0].points.length, 2);
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
