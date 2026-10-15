import assert from "node:assert/strict";
import test from "node:test";
import { validateCreatePost } from "../modules/feed/feed.validators.js";
import { assertPostInteractionAllowed } from "../modules/feed/feed.post-settings.js";

test("post settings preserve legacy defaults and accept multipart booleans", () => {
  assert.deepEqual(validateCreatePost({ caption: "Legacy" }).value.storyStyle, {});
  const result = validateCreatePost({
    postKind: "reel", commentsEnabled: "false", sharingEnabled: "true",
    reelStyle: JSON.stringify({ layers: [] }),
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.value.storyStyle.postSettings, {
    commentsEnabled: false, sharingEnabled: true,
  });
  assertPostInteractionAllowed({}, "comment");
  assertPostInteractionAllowed(null, "share");
});

test("invalid post settings are rejected rather than treated as enabled", () => {
  for (const value of ["maybe", {}, []]) {
    assert.equal(validateCreatePost({ commentsEnabled: value }).ok, false);
  }
  assert.equal(validateCreatePost({ reelStyle: { postSettings: [] } }).ok, false);
});

test("settings survive style roundtrip and top-level options take precedence", () => {
  const result = validateCreatePost({
    storyStyle: { postSettings: { commentsEnabled: false, sharingEnabled: false } },
    sharingEnabled: true,
  });
  assert.equal(result.ok, true);
  assert.equal(result.value.storyStyle.postSettings.sharingEnabled, true);
  assert.throws(() => assertPostInteractionAllowed(result.value.storyStyle, "comment"),
    { code: "POST_COMMENTS_DISABLED" });
  assert.throws(() => assertPostInteractionAllowed({ postSettings: { sharingEnabled: false } }, "share"),
    { code: "POST_SHARING_DISABLED" });
});
