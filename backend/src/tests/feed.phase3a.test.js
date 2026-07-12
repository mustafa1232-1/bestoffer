import assert from "node:assert/strict";
import test from "node:test";

import {
  validateCreatePost,
  validateCreateStory,
  validateReelViewBody,
  validateSavedToggleBody,
  validateSocialSearchQuery,
} from "../modules/feed/feed.validators.js";

test("phase 3a social search query accepts the supported tabs", () => {
  for (const tab of ["all", "users", "posts", "reels", "hashtags", "merchants", "reviews"]) {
    const result = validateSocialSearchQuery({ search: "Phase3A", tab, limit: 12 });
    assert.equal(result.ok, true, `${tab} should be accepted`);
    assert.equal(result.value.tab, tab);
  }
});

test("phase 3a story validation keeps the story style payload intact", () => {
  const result = validateCreateStory({
    caption: "Story Phase3A",
    storyStyle: JSON.stringify({
      version: 1,
      mode: "text",
      background: {
        type: "solid",
        primaryColor: "#112233",
      },
    }),
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.caption, "Story Phase3A");
  assert.equal(result.value.storyStyle.version, 1);
  assert.equal(result.value.storyStyle.mode, "text");
});

test("phase 3a reel view validation normalizes counters and completion state", () => {
  const result = validateReelViewBody({
    watchDurationMs: "4200",
    completionRate: "97",
    replayCount: "2",
    completed: "true",
    context: "phase3a_reels",
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.watchDurationMs, 4200);
  assert.equal(result.value.completionRate, 97);
  assert.equal(result.value.replayCount, 2);
  assert.equal(result.value.completed, true);
  assert.equal(result.value.context, "phase3a_reels");
});

test("phase 3a saved toggle accepts reels and deduplicates collection ids", () => {
  const result = validateSavedToggleBody({
    entityType: "reel",
    entityId: 42,
    collectionIds: [7, "7", 9, "9", null],
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.entityType, "reel");
  assert.equal(result.value.entityId, 42);
  assert.deepEqual(result.value.collectionIds, [7, 9]);
});

test("phase 3a post validation parses tagged user ids from csv input", () => {
  const result = validateCreatePost({
    caption: "Tagged post Phase3A",
    postKind: "text",
    taggedUserIds: "7, 8, 8, 9",
  });

  assert.equal(result.ok, true);
  assert.deepEqual(result.value.taggedUserIds, [7, 8, 9]);
});
