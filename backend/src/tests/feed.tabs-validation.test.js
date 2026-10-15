import assert from "node:assert/strict";
import test from "node:test";
import { validateListPosts } from "../modules/feed/feed.validators.js";

test("existing feed requests retain their validation shape", () => {
  assert.deepEqual(validateListPosts({ limit: "20", beforeId: "80", kind: "image" }), {
    ok: true, errors: [], value: { limit: 20, beforeId: 80, kind: "image" },
  });
});

test("feed tabs preserve cursor and content filters", () => {
  for (const feed of ["for_you", "following", "latest"]) {
    const out = validateListPosts({ feed, beforeId: "123", limit: "10", kind: "reel" });
    assert.equal(out.ok, true);
    assert.deepEqual(out.value, { feed, beforeId: 123, limit: 10, kind: "reel" });
  }
});

test("unknown feed tabs and invalid cursors are rejected", () => {
  assert.equal(validateListPosts({ feed: "private" }).ok, false);
  assert.equal(validateListPosts({ feed: "following", beforeId: "-1" }).ok, false);
});
