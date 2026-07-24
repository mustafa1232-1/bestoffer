// Guest read-access contract for public social content.
//
// A guest (no authenticated user on `req`) must be able to read the home feed,
// stories, discovery and trending tags. These controllers previously sat behind
// `requireAuth`, so an unauthenticated request 401'd. They are now public
// (optionalAuth) and must resolve normally with a null viewer — returning public
// content (possibly empty) and never throwing an auth error.

import assert from "node:assert/strict";
import test from "node:test";

import * as controller from "../modules/feed/feed.controller.js";

/** Minimal Express-style res capturing the JSON body and status. */
function makeRes() {
  return {
    statusCode: 200,
    body: undefined,
    sentRaw: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(value) {
      this.body = value;
      return this;
    },
    type() {
      return this;
    },
    send(raw) {
      this.sentRaw = raw;
      return this;
    },
  };
}

/** Invokes a controller as a guest (no req.userId) and fails on any next(err). */
async function callAsGuest(handler, { query = {} } = {}) {
  const res = makeRes();
  let forwardedError = null;
  await handler({ query, headers: {} }, res, (err) => {
    if (err) forwardedError = err;
  });
  return { res, forwardedError };
}

test("guest can list home feed posts without a 401", async () => {
  const { res, forwardedError } = await callAsGuest(controller.listPosts);
  assert.equal(forwardedError, null, "guest feed must not raise an auth error");
  assert.ok(res.body, "guest feed must return a JSON body");
  assert.ok(Array.isArray(res.body.posts), "guest feed returns a posts array");
});

test("guest can list active stories without a 401", async () => {
  const { res, forwardedError } = await callAsGuest(controller.listStories);
  assert.equal(forwardedError, null, "guest stories must not raise an auth error");
  assert.ok(res.body, "guest stories must return a JSON body");
  assert.ok(
    Array.isArray(res.body.stories),
    "guest stories returns a stories array"
  );
});

test("guest can open the discovery/explore surface without a 401", async () => {
  const { res, forwardedError } = await callAsGuest(controller.listExplore);
  assert.equal(forwardedError, null, "guest explore must not raise an auth error");
  // Either a fresh JSON body or a cached raw payload is acceptable; the point is
  // that no auth error was forwarded and a response was produced.
  assert.ok(
    res.body !== undefined || res.sentRaw !== undefined,
    "guest explore must produce a response"
  );
});

test("guest can read trending tags without a 401", async () => {
  const { res, forwardedError } = await callAsGuest(controller.listTrendingTags);
  assert.equal(forwardedError, null, "guest trending must not raise an auth error");
  assert.ok(res.body, "guest trending must return a JSON body");
});
