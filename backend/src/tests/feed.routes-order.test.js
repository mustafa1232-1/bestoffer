// Regression guard: GET /api/feed/reels/explore must reach listExploreReels.
//
// The public route GET /reels/:reelId is declared before the authenticated
// block (it is intentionally unauthenticated). Without a numeric constraint it
// also matched /reels/explore with reelId="explore", so validatePostId rejected
// it and the Reels page got 400 BAD_REQUEST on every load — while opening a
// single reel by id kept working, which is exactly how the defect was reported.

import assert from "node:assert/strict";
import test from "node:test";

import { feedRouter } from "../modules/feed/feed.routes.js";

/** First router layer (in declaration order) that matches the given path. */
function firstMatchingRoute(router, path, method = "get") {
  for (const layer of router.stack) {
    if (!layer.route) continue;
    if (!layer.regexp?.test(path)) continue;
    if (layer.route.methods?.[method] !== true) continue;
    return layer.route.path;
  }
  return null;
}

function firstRouteLayerIndex(router, path, method = "get") {
  return router.stack.findIndex((layer) => {
    if (!layer.route) return false;
    if (!layer.regexp?.test(path)) return false;
    return layer.route.methods?.[method] === true;
  });
}

function firstMiddlewareIndex(router, name) {
  return router.stack.findIndex((layer) => !layer.route && layer.name === name);
}

test("feed: /reels/explore is not shadowed by /reels/:reelId", () => {
  assert.equal(
    firstMatchingRoute(feedRouter, "/reels/explore"),
    "/reels/explore",
    "GET /reels/explore must resolve to the explore handler, not the by-id route"
  );
});

test("feed: /reels/explore is public before the authenticated feed block", () => {
  const exploreIndex = firstRouteLayerIndex(feedRouter, "/reels/explore");
  const authIndex = firstMiddlewareIndex(feedRouter, "requireAuth");
  assert.notEqual(exploreIndex, -1, "GET /reels/explore must be registered");
  assert.notEqual(authIndex, -1, "feedRouter must keep its authenticated block");
  assert.ok(
    exploreIndex < authIndex,
    "GET /reels/explore must be reachable by guests before requireAuth"
  );
});

test("feed: reel view tracking is public before the authenticated feed block", () => {
  const viewIndex = firstRouteLayerIndex(feedRouter, "/reels/1234/view", "post");
  const authIndex = firstMiddlewareIndex(feedRouter, "requireAuth");
  assert.notEqual(viewIndex, -1, "POST /reels/:id/view must be registered");
  assert.notEqual(authIndex, -1, "feedRouter must keep its authenticated block");
  assert.ok(
    viewIndex < authIndex,
    "POST /reels/:id/view must not force guests into a 401 while watching"
  );
});

test("feed: a numeric reel id still resolves to the public by-id route", () => {
  assert.equal(
    firstMatchingRoute(feedRouter, "/reels/1234"),
    "/reels/:reelId(\\d+)",
    "GET /reels/:id must still serve a numeric reel id"
  );
});

test("feed: literal list routes are not shadowed by their :param siblings", () => {
  // Same class of defect, guarded across the router's other literal/param pairs.
  const cases = [
    ["/users/suggested", "/users/suggested"],
    ["/users/search", "/users/search"],
    ["/hashtags/trending", "/hashtags/trending"],
    ["/hashtags/suggest", "/hashtags/suggest"],
    ["/communities/scopes/me", "/communities/scopes/me"],
    ["/posts", "/posts"],
  ];
  for (const [path, expected] of cases) {
    assert.equal(
      firstMatchingRoute(feedRouter, path),
      expected,
      `GET ${path} must resolve to its literal route`
    );
  }
});
