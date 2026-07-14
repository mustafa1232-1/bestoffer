import fs from "node:fs";

import * as repo from "./feed.repo.js";
import {
  buildStreamPlaybackUrl,
  buildStreamThumbnailUrl,
  uploadVideoToCloudflareStream,
} from "../../shared/utils/cloudflare-stream.js";
import { deleteR2Object } from "../../shared/utils/cloudflare-r2.js";

function trim(value) {
  return String(value || "").trim();
}

function normalizeMediaKind(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized === "video") return "reel";
  if (["image", "reel", "video"].includes(normalized)) return normalized;
  return null;
}

function normalizeSourceType(value, fallback = "post") {
  const normalized = String(value || fallback).trim().toLowerCase();
  if (["post", "story", "reel"].includes(normalized)) return normalized;
  return fallback;
}

async function cleanupTemporarySource(media = null) {
  const r2Key = trim(media?.r2Key || media?.key);
  if (r2Key) {
    try {
      await deleteR2Object(r2Key);
    } catch (_) {
      // Best-effort cleanup only.
    }
    return;
  }
  const localPath = trim(media?.path);
  if (localPath && fs.existsSync(localPath)) {
    try {
      fs.unlinkSync(localPath);
    } catch (_) {
      // Best-effort cleanup only.
    }
  }
}

export async function prepareSocialMediaAsset({
  userId,
  media = null,
  preferredKind = null,
  sourceType = null,
}) {
  if (!media?.url) {
    return {
      mediaUrl: null,
      mediaKind: null,
      mediaAssetId: null,
      asset: null,
    };
  }

  const requestedKind = normalizeMediaKind(preferredKind || media.kind || media.mediaKind);
  const mediaKind = requestedKind === "reel" ? "video" : requestedKind;
  const resolvedSourceType = normalizeSourceType(sourceType || requestedKind || "post");
  const sourceUrl = trim(media.url);
  const isStreamEligibleVideo =
    mediaKind === "video" && (resolvedSourceType === "story" || resolvedSourceType === "reel");

  let provider = "r2";
  let normalizedUrl = sourceUrl;
  let posterUrl = mediaKind === "image" ? sourceUrl : null;
  let streamUid = null;
  let thumbnailUrl = posterUrl;
  let playbackUrl = normalizedUrl;
  let processingStatus = "ready";

  if (isStreamEligibleVideo) {
    const streamUpload = await uploadVideoToCloudflareStream({
      sourceUrl,
      sourcePath: media.path,
      originalName: media.name || media.filename || null,
      mimeType: media.mimetype || media.mimeType || null,
      title: media.name || media.filename || `${resolvedSourceType}_${userId}`,
    });
    provider = "stream";
    streamUid = streamUpload.uid;
    playbackUrl = streamUpload.playbackUrl || buildStreamPlaybackUrl(streamUpload.uid);
    thumbnailUrl = streamUpload.thumbnailUrl || buildStreamThumbnailUrl(streamUpload.uid) || null;
    normalizedUrl = playbackUrl;
    posterUrl = thumbnailUrl;
    processingStatus = streamUpload.readyToStream ? "ready" : "processing";
  }

  const asset = await repo.insertSocialMediaAsset({
    ownerUserId: userId,
    sourceType: resolvedSourceType,
    provider,
    streamUid,
    originalUrl: sourceUrl,
    normalizedUrl,
    posterUrl,
    playbackUrl,
    thumbnailUrl,
    mimeType: media.mimetype || media.mimeType || null,
    mediaKind,
    durationMs: media.durationMs || null,
    width: media.width || null,
    height: media.height || null,
    processingStatus,
  });

  if (isStreamEligibleVideo) {
    await cleanupTemporarySource(media);
  }

  if (asset?.id && requestedKind === "reel") {
    await repo.insertSocialMediaProcessingJob({
      assetId: Number(asset.id),
      jobType: "normalize_video",
      status: "completed",
    });
  }

  return {
    mediaUrl: normalizedUrl,
    mediaKind,
    mediaAssetId: asset?.id == null ? null : Number(asset.id),
    asset,
  };
}
