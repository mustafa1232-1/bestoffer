import assert from "node:assert/strict";
import test from "node:test";

import {
  mapStreamDetailsToStatus,
  extractStreamUidFromWebhook,
  extractStreamPlaybacks,
} from "../modules/feed/feed.media.service.js";

test("mapStreamDetailsToStatus maps provider states to internal states", () => {
  assert.equal(mapStreamDetailsToStatus({ status: "ready" }), "ready");
  assert.equal(mapStreamDetailsToStatus({ status: "ready_to_stream" }), "ready");
  assert.equal(mapStreamDetailsToStatus({ state: "success" }), "ready");
  assert.equal(mapStreamDetailsToStatus({ status: "inprogress" }, "processing"), "processing");
  assert.equal(mapStreamDetailsToStatus({ status: "error" }), "failed");
  assert.equal(mapStreamDetailsToStatus({ status: "failed" }), "failed");
  assert.equal(mapStreamDetailsToStatus({ status: "pending" }), "pending");
});

test("mapStreamDetailsToStatus is idempotent for a duplicate ready event", () => {
  const first = mapStreamDetailsToStatus({ status: "ready" });
  const second = mapStreamDetailsToStatus({ status: "ready" });
  assert.equal(first, second);
  assert.equal(first, "ready");
});

test("mapStreamDetailsToStatus falls back for an unknown status", () => {
  assert.equal(mapStreamDetailsToStatus({ status: "weird" }, "processing"), "processing");
  assert.equal(mapStreamDetailsToStatus({}, "processing"), "processing");
});

test("extractStreamUidFromWebhook reads uid from several shapes", () => {
  assert.equal(extractStreamUidFromWebhook({ uid: "abc" }), "abc");
  assert.equal(extractStreamUidFromWebhook({ data: { uid: "def" } }), "def");
  assert.equal(extractStreamUidFromWebhook({ stream_uid: "ghi" }), "ghi");
  assert.equal(extractStreamUidFromWebhook({ data: { streamUid: "jkl" } }), "jkl");
  assert.equal(extractStreamUidFromWebhook({}), "");
});

test("extractStreamPlaybacks reads hls playback + thumbnail", () => {
  const out = extractStreamPlaybacks({
    playback: { hls: "https://videodelivery.net/uid/manifest/video.m3u8" },
    thumbnail: "https://videodelivery.net/uid/thumbnails/thumbnail.jpg",
  });
  assert.equal(out.playbackUrl, "https://videodelivery.net/uid/manifest/video.m3u8");
  assert.equal(out.thumbnailUrl, "https://videodelivery.net/uid/thumbnails/thumbnail.jpg");
});

test("extractStreamPlaybacks tolerates a missing payload", () => {
  const out = extractStreamPlaybacks({});
  assert.equal(out.playbackUrl, null);
  assert.equal(out.thumbnailUrl, null);
});
