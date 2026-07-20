import assert from "node:assert/strict";
import test from "node:test";

import crypto from "node:crypto";

import { pool } from "../config/db.js";
import {
  getSocialMediaAssetDiagnosticsById,
} from "../modules/feed/feed.media.service.js";
import {
  insertSocialMediaAsset,
  updateSocialMediaAssetStatus,
} from "../modules/feed/feed.repo.js";

// Seed an owner instead of borrowing whatever row happens to be first in
// app_user: each test file now runs against its own freshly cloned database, so
// there is no ambient user to pick up.
async function createAssetOwner() {
  const suffix = crypto.randomBytes(5).toString("hex");
  const result = await pool.query(
    `INSERT INTO app_user
       (full_name, username, phone, pin_hash, block, building_number, apartment, role)
     VALUES ($1,$2,$3,'x','A','1','1','user')
     RETURNING id`,
    [
      `Social Asset Owner ${suffix}`,
      `social_asset_${suffix}`,
      `079${suffix.replace(/\D/g, "").padEnd(8, "0").slice(0, 8)}`,
    ]
  );
  return Number(result.rows[0].id);
}

test("social media asset insert persists stream playback fields", async () => {
  const ownerUserId = await createAssetOwner();

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

test("social media asset diagnostics expose failure code and trace stages", async () => {
  const ownerUserId = await createAssetOwner();

  const asset = await insertSocialMediaAsset({
    ownerUserId,
    sourceType: "reel",
    provider: "stream",
    streamUid: "stream_uid_test_002",
    originalUrl: "https://example.com/original.mp4",
    normalizedUrl: null,
    posterUrl: null,
    playbackUrl: null,
    thumbnailUrl: null,
    mimeType: "video/mp4",
    mediaKind: "video",
    durationMs: 12000,
    width: 1080,
    height: 1920,
    processingStatus: "processing",
  });

  await updateSocialMediaAssetStatus({
    assetId: asset.id,
    streamUid: asset.stream_uid,
    processingStatus: "failed",
    processingError: "CF_STREAM_TIMEOUT",
  });

  const diagnostics = await getSocialMediaAssetDiagnosticsById({
    userId: ownerUserId,
    assetId: asset.id,
  });
  assert.equal(diagnostics.assetId, Number(asset.id));
  assert.equal(diagnostics.provider, "stream");
  assert.equal(diagnostics.failureCode, "CF_STREAM_TIMEOUT");
  assert.equal(diagnostics.traceStages?.length > 0, true);
  assert.equal(
    diagnostics.traceStages.some((stage) => stage.stage === "PROCESSING"),
    true
  );
  assert.equal(
    diagnostics.traceStages.some((stage) => stage.stage === "READY"),
    true
  );
  assert.equal(
    diagnostics.traceStages.some((stage) => stage.stage === "PUBLISHED"),
    true
  );

  await pool.query("DELETE FROM social_media_asset WHERE id = $1", [asset.id]);
});
