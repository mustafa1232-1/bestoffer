import assert from "node:assert/strict";
import test from "node:test";

import { pool } from "../config/db.js";
import { insertSocialMediaAsset } from "../modules/feed/feed.repo.js";

test("social media asset insert persists stream playback fields", async () => {
  const owner = await pool.query(
    "SELECT id FROM app_user ORDER BY id ASC LIMIT 1"
  );
  assert.equal(owner.rowCount > 0, true, "expected at least one user row");
  const ownerUserId = Number(owner.rows[0].id);

  const asset = await insertSocialMediaAsset({
    ownerUserId,
    sourceType: "reel",
    provider: "stream",
    streamUid: "stream_uid_test_001",
    originalUrl: "https://example.com/original.mp4",
    normalizedUrl: "https://customer-test.cloudflarestream.com/stream_uid_test_001/manifest/video.m3u8",
    posterUrl: "https://customer-test.cloudflarestream.com/stream_uid_test_001/thumbnails/thumbnail.jpg?time=1s",
    playbackUrl: "https://customer-test.cloudflarestream.com/stream_uid_test_001/manifest/video.m3u8",
    thumbnailUrl: "https://customer-test.cloudflarestream.com/stream_uid_test_001/thumbnails/thumbnail.jpg?time=1s",
    mimeType: "video/mp4",
    mediaKind: "video",
    durationMs: 42000,
    width: 1080,
    height: 1920,
    processingStatus: "ready",
  });

  assert.ok(asset);
  assert.equal(asset.provider, "stream");
  assert.equal(asset.stream_uid, "stream_uid_test_001");
  assert.equal(
    asset.playback_url,
    "https://customer-test.cloudflarestream.com/stream_uid_test_001/manifest/video.m3u8"
  );
  assert.equal(
    asset.thumbnail_url,
    "https://customer-test.cloudflarestream.com/stream_uid_test_001/thumbnails/thumbnail.jpg?time=1s"
  );
  assert.equal(asset.trace_id, "stream_uid_test_001");

  const persisted = await pool.query(
    "SELECT trace_id FROM social_media_asset WHERE id = $1",
    [asset.id]
  );
  assert.equal(persisted.rows[0].trace_id, "stream_uid_test_001");

  await pool.query("DELETE FROM social_media_asset WHERE id = $1", [asset.id]);
});
