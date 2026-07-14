import assert from "node:assert/strict";
import test from "node:test";

import { normalizeCommunityScope } from "../shared/utils/basmaya-address.js";
import { validateCreatePost } from "../modules/feed/feed.validators.js";

// The backend must reject forged/invalid scope + review values even when Flutter
// sends them — authorization is never UI-only (§3/§4, validation layer).

test("normalizeCommunityScope accepts only block/compound/building", () => {
  assert.equal(normalizeCommunityScope("block", "A").ok, true);
  assert.equal(normalizeCommunityScope("building", "A101").ok, true);
  // Non-community / relationship scopes are rejected outright.
  assert.equal(normalizeCommunityScope("followers", "X").ok, false);
  assert.equal(normalizeCommunityScope("area", "X").ok, false);
  assert.equal(normalizeCommunityScope("custom", "X").ok, false);
  // Forged / malformed scope codes are rejected.
  assert.equal(normalizeCommunityScope("block", "ZZZ").ok, false);
});

test("validateCreatePost rejects a forged community scope type", () => {
  const r = validateCreatePost({
    caption: "hi",
    postKind: "text",
    audienceScopeType: "followers", // not a valid community scope
    audienceScopeCode: "X",
  });
  assert.equal(r.ok, false);
  assert.ok(r.errors.includes("audienceScopeType"));
});

test("validateCreatePost accepts a valid building-scoped post", () => {
  const r = validateCreatePost({
    caption: "hi",
    postKind: "text",
    audienceScopeType: "building",
    audienceScopeCode: "A101",
  });
  assert.equal(r.ok, true);
  assert.equal(r.value.audienceScopeType, "building");
});

test("validateCreatePost requires merchant + rating for a review", () => {
  const missing = validateCreatePost({ caption: "", postKind: "merchant_review" });
  assert.equal(missing.ok, false);
  assert.ok(missing.errors.includes("merchantId_required"));
  assert.ok(missing.errors.includes("reviewRating_required"));
});

test("validateCreatePost rejects an out-of-range review rating", () => {
  const bad = validateCreatePost({
    caption: "",
    postKind: "merchant_review",
    merchantId: 5,
    reviewRating: 9,
  });
  assert.equal(bad.ok, false);
  assert.ok(bad.errors.includes("reviewRating"));
});

test("validateCreatePost accepts a valid merchant review", () => {
  const ok = validateCreatePost({
    caption: "great",
    postKind: "merchant_review",
    merchantId: 5,
    reviewRating: 4,
  });
  assert.equal(ok.ok, true);
});

// §3/§10: validateCreateStory now normalizes + validates authoritative scope.
test("validateCreateStory normalizes a valid building scope", async () => {
  const { validateCreateStory } = await import(
    "../modules/feed/feed.validators.js"
  );
  const r = validateCreateStory({
    caption: "hi",
    audienceScopeType: "building",
    audienceScopeCode: "A101",
  });
  assert.equal(r.ok, true);
  assert.equal(r.value.audienceScopeType, "building");
  assert.equal(r.value.audienceScopeCode, "A101");
});

test("validateCreateStory rejects relationship/forged scopes", async () => {
  const { validateCreateStory } = await import(
    "../modules/feed/feed.validators.js"
  );
  assert.equal(
    validateCreateStory({ caption: "x", audienceScopeType: "followers", audienceScopeCode: "X" }).ok,
    false
  );
  assert.equal(
    validateCreateStory({ caption: "x", audienceScopeType: "building", audienceScopeCode: "ZZZ" }).ok,
    false
  );
  // Code without a type is rejected.
  assert.equal(
    validateCreateStory({ caption: "x", audienceScopeCode: "A101" }).ok,
    false
  );
});

test("validateCreateStory defaults to global with no scope", async () => {
  const { validateCreateStory } = await import(
    "../modules/feed/feed.validators.js"
  );
  const r = validateCreateStory({ caption: "hi" });
  assert.equal(r.ok, true);
  assert.equal(r.value.audienceScopeType, "global");
  assert.equal(r.value.audienceScopeCode, null);
});

test("validateCreateStory never trusts the isOfficial flag", async () => {
  const { validateCreateStory } = await import(
    "../modules/feed/feed.validators.js"
  );
  const r = validateCreateStory({
    caption: "official",
    audienceScopeType: "building",
    audienceScopeCode: "A101",
    isOfficial: true,
  });
  // The validator only records the *request*; authorization is the service's job.
  assert.equal(r.value.isOfficialRequested, true);
});
