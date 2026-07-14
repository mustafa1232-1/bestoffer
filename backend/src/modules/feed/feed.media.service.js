import fs from "node:fs";

import { AppError } from "../../shared/utils/errors.js";
import * as repo from "./feed.repo.js";
import {
  buildStreamPlaybackUrl,
  buildStreamThumbnailUrl,
  createCloudflareStreamUploadSession,
  fetchCloudflareStreamVideoDetails,
  isCloudflareStreamWebhookConfigured,
  uploadVideoToCloudflareStream,
  verifyCloudflareStreamWebhookSignature,
} from "../../shared/utils/cloudflare-stream.js";
import { deleteR2Object } from "../../shared/utils/cloudflare-r2.js";
import { env } from "../../config/env.js";

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

function mapSocialMediaAssetRow(row) {
  if (!row) return null;
  return {
    id: row.id == null ? null : Number(row.id),
    ownerUserId: row.owner_user_id == null ? null : Number(row.owner_user_id),
    sourceType: row.source_type || null,
    provider: row.provider || null,
    streamUid: row.stream_uid || null,
    originalUrl: row.original_url || null,
    normalizedUrl: row.normalized_url || null,
    posterUrl: row.poster_url || null,
    playbackUrl: row.playback_url || null,
    thumbnailUrl: row.thumbnail_url || null,
    mimeType: row.mime_type || null,
    mediaKind: row.media_kind || null,
    durationMs: row.duration_ms == null ? null : Number(row.duration_ms),
    width: row.width == null ? null : Number(row.width),
    height: row.height == null ? null : Number(row.height),
    processingStatus: row.processing_status || null,
    processingError: row.processing_error || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
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

export async function resolveSocialMediaAssetForPublishing({
  userId,
  mediaAssetId,
  expectedSourceType = null,
}) {
  const assetId = Number(mediaAssetId);
  if (!Number.isFinite(assetId) || assetId <= 0) {
    throw new AppError("MEDIA_ASSET_NOT_FOUND", { status: 404 });
  }
  const asset = await repo.findSocialMediaAssetById(assetId);
  if (!asset) {
    throw new AppError("MEDIA_ASSET_NOT_FOUND", { status: 404 });
  }
  if (Number(asset.owner_user_id) !== Number(userId)) {
    throw new AppError("MEDIA_ASSET_FORBIDDEN", { status: 403 });
  }
  if (expectedSourceType) {
    const normalizedExpected = normalizeSourceType(expectedSourceType);
    const normalizedActual = normalizeSourceType(asset.source_type || "post");
    if (normalizedExpected !== normalizedActual) {
      throw new AppError("MEDIA_ASSET_SOURCE_MISMATCH", { status: 409 });
    }
  }
  if (String(asset.processing_status || "").trim().toLowerCase() !== "ready") {
    throw new AppError("MEDIA_ASSET_NOT_READY", { status: 409 });
  }
  const mediaUrl =
    asset.playback_url ||
    asset.normalized_url ||
    buildStreamPlaybackUrl(asset.stream_uid) ||
    asset.original_url ||
    null;
  const mediaKind = asset.media_kind || "video";
  return {
    mediaUrl,
    mediaKind,
    mediaAssetId: Number(asset.id),
    asset,
  };
}

export async function createSocialMediaStreamUploadSession({
  userId,
  sourceType = "reel",
  sizeBytes,
  title = null,
  fileName = null,
  mimeType = "video/mp4",
}) {
  const normalizedSourceType = normalizeSourceType(sourceType, "reel");
  if (!["story", "reel"].includes(normalizedSourceType)) {
    throw new AppError("STREAM_UPLOAD_SOURCE_INVALID", { status: 400 });
  }

  const session = await createCloudflareStreamUploadSession({
    title,
    sizeBytes,
    filename: fileName,
    mimeType,
    sourceType: normalizedSourceType,
  });
  if (!session?.uploadUrl || !session?.streamUid) {
    throw new AppError("STREAM_UPLOAD_SESSION_FAILED", { status: 502 });
  }

  const asset = await repo.insertSocialMediaAsset({
    ownerUserId: userId,
    sourceType: normalizedSourceType,
    provider: "stream",
    streamUid: session.streamUid,
    originalUrl: session.uploadUrl,
    normalizedUrl: null,
    posterUrl: null,
    playbackUrl: null,
    thumbnailUrl: null,
    mimeType,
    mediaKind: "video",
    durationMs: null,
    width: null,
    height: null,
    processingStatus: "pending",
  });
  if (!asset?.id) {
    throw new AppError("STREAM_UPLOAD_ASSET_CREATE_FAILED", { status: 500 });
  }

  return {
    uploadSession: {
      assetId: Number(asset.id),
      streamUid: session.streamUid,
      uploadUrl: session.uploadUrl,
      sourceType: normalizedSourceType,
      mediaKind: "video",
      processingStatus: "pending",
      readyToStream: session.readyToStream === true,
      asset: mapSocialMediaAssetRow(asset),
    },
    asset: mapSocialMediaAssetRow(asset),
  };
}

export async function cancelSocialMediaStreamUploadSession({ userId, assetId }) {
  const asset = await repo.findSocialMediaAssetById(assetId);
  if (!asset) {
    throw new AppError("MEDIA_ASSET_NOT_FOUND", { status: 404 });
  }
  if (Number(asset.owner_user_id) !== Number(userId)) {
    throw new AppError("MEDIA_ASSET_FORBIDDEN", { status: 403 });
  }
  const status = String(asset.processing_status || "").trim().toLowerCase();
  // Only in-flight (pre-ready) sessions may be cancelled; a published/ready
  // asset must not be silently torn down here.
  if (["ready", "published"].includes(status)) {
    throw new AppError("MEDIA_ASSET_ALREADY_READY", { status: 409 });
  }
  const updated = await repo.updateSocialMediaAssetStatus({
    assetId: asset.id,
    streamUid: asset.stream_uid,
    processingStatus: "cancelled",
    processingError: "UPLOAD_CANCELLED_BY_OWNER",
  });
  return { asset: mapSocialMediaAssetRow(updated || asset) };
}

export async function getSocialMediaAssetById({ userId, assetId }) {
  const asset = await repo.findSocialMediaAssetById(assetId);
  if (!asset) {
    throw new AppError("MEDIA_ASSET_NOT_FOUND", { status: 404 });
  }
  if (Number(asset.owner_user_id) !== Number(userId)) {
    throw new AppError("MEDIA_ASSET_FORBIDDEN", { status: 403 });
  }
  return { asset: mapSocialMediaAssetRow(asset) };
}

export function mapStreamDetailsToStatus(details, fallbackStatus = "processing") {
  const normalized = String(
    details?.status || details?.state || details?.readyToStreamStatus || ""
  )
    .trim()
    .toLowerCase();
  if (["ready", "ready_to_stream", "complete", "completed", "success"].includes(normalized)) {
    return "ready";
  }
  if (["failed", "error", "errored", "rejected"].includes(normalized)) {
    return "failed";
  }
  if (normalized === "pending") return "pending";
  return fallbackStatus;
}

export function extractStreamUidFromWebhook(payload) {
  return String(
    payload?.uid ||
      payload?.streamUid ||
      payload?.stream_uid ||
      payload?.data?.uid ||
      payload?.data?.streamUid ||
      payload?.data?.stream_uid ||
      ""
  ).trim();
}

export function extractStreamPlaybacks(details) {
  return {
    playbackUrl:
      details?.playback?.hls ||
      details?.playbackUrl ||
      details?.playback_url ||
      details?.url ||
      null,
    thumbnailUrl:
      details?.thumbnail ||
      details?.thumbnailUrl ||
      details?.thumbnail_url ||
      details?.preview ||
      null,
  };
}

export async function handleCloudflareStreamWebhook({
  rawBody,
  signatureHeader,
}) {
  if (!isCloudflareStreamWebhookConfigured()) {
    throw new AppError("STREAM_WEBHOOK_NOT_CONFIGURED", { status: 503 });
  }
  const verification = verifyCloudflareStreamWebhookSignature({
    rawBody,
    signatureHeader,
  });
  if (!verification.ok) {
    throw new AppError(verification.reason || "STREAM_WEBHOOK_UNAUTHORIZED", {
      status: 401,
    });
  }

  const text = Buffer.isBuffer(rawBody) ? rawBody.toString("utf8") : String(rawBody || "");
  let payload = null;
  try {
    payload = JSON.parse(text);
  } catch (_) {
    throw new AppError("STREAM_WEBHOOK_INVALID_JSON", { status: 400 });
  }

  const streamUid = extractStreamUidFromWebhook(payload);
  if (!streamUid) {
    throw new AppError("STREAM_WEBHOOK_UID_REQUIRED", { status: 400 });
  }

  const current = await repo.findSocialMediaAssetByStreamUid(streamUid);
  if (!current) {
    return { ok: true, matched: false, streamUid };
  }

  const details = payload?.data || payload?.result || payload;
  const nextStatus = mapStreamDetailsToStatus(details, current.processing_status || "processing");
  const playbacks = extractStreamPlaybacks(details);
  const updated = await repo.updateSocialMediaAssetStatus({
    assetId: current.id,
    streamUid,
    processingStatus: nextStatus,
    processingError:
      details?.error?.message ||
      details?.error ||
      details?.last_error ||
      (nextStatus === "failed" ? "STREAM_PROCESSING_FAILED" : null),
    normalizedUrl: playbacks.playbackUrl || null,
    posterUrl: playbacks.thumbnailUrl || null,
    playbackUrl: playbacks.playbackUrl || null,
    thumbnailUrl: playbacks.thumbnailUrl || null,
    durationMs:
      details?.duration == null
        ? details?.durationMs == null
          ? null
          : Number(details.durationMs)
        : Number(details.duration),
    width:
      details?.video?.width == null
        ? details?.width == null
          ? null
          : Number(details.width)
        : Number(details.video.width),
    height:
      details?.video?.height == null
        ? details?.height == null
          ? null
          : Number(details.height)
        : Number(details.video.height),
  });
  return {
    ok: true,
    matched: true,
    asset: mapSocialMediaAssetRow(updated || current),
  };
}

async function reconcilePendingStreamAsset(asset) {
  if (!asset?.stream_uid) return null;
  try {
    const details = await fetchCloudflareStreamVideoDetails(asset.stream_uid);
    const nextStatus = mapStreamDetailsToStatus(details, asset.processing_status || "processing");
    const playbacks = extractStreamPlaybacks(details);
    return await repo.updateSocialMediaAssetStatus({
      assetId: asset.id,
      streamUid: asset.stream_uid,
      processingStatus: nextStatus,
      processingError:
        details?.error?.message ||
        details?.error ||
        details?.last_error ||
        (nextStatus === "failed" ? "STREAM_PROCESSING_FAILED" : null),
      normalizedUrl: playbacks.playbackUrl || null,
      posterUrl: playbacks.thumbnailUrl || null,
      playbackUrl: playbacks.playbackUrl || null,
      thumbnailUrl: playbacks.thumbnailUrl || null,
      durationMs:
        details?.duration == null
          ? details?.durationMs == null
            ? null
            : Number(details.durationMs)
          : Number(details.duration),
      width:
        details?.video?.width == null
          ? details?.width == null
            ? null
            : Number(details.width)
          : Number(details.video.width),
      height:
        details?.video?.height == null
          ? details?.height == null
            ? null
            : Number(details.height)
          : Number(details.video.height),
    });
  } catch (error) {
    const message = String(error?.message || error || "STREAM_RECONCILE_FAILED").slice(0, 500);
    return await repo.updateSocialMediaAssetStatus({
      assetId: asset.id,
      streamUid: asset.stream_uid,
      processingStatus: asset.processing_status || "processing",
      processingError: message,
    });
  }
}

let socialStreamReconcileWorker = null;
let socialStreamReconcileRunning = false;

async function processSocialStreamAssetReconciliation() {
  if (socialStreamReconcileRunning) return;
  socialStreamReconcileRunning = true;
  try {
    const assets = await repo.listPendingSocialMediaAssets({
      limit: env.socialStreamReconcileBatchSize || 20,
    });
    for (const asset of assets) {
      await reconcilePendingStreamAsset(asset);
    }
  } catch (error) {
    console.warn(
      "[social] stream asset reconciliation failed",
      error?.message || error
    );
  } finally {
    socialStreamReconcileRunning = false;
  }
}

export async function reconcileSocialMediaStreamAssets() {
  return await processSocialStreamAssetReconciliation();
}

export function startSocialStreamReconciliationWorker({ intervalMs = null } = {}) {
  if (socialStreamReconcileWorker) return;
  const cadence = Math.max(
    5000,
    Number(intervalMs ?? env.socialStreamReconcileIntervalMs ?? 30000) || 30000
  );
  socialStreamReconcileWorker = setInterval(() => {
    processSocialStreamAssetReconciliation().catch((error) => {
      console.warn(
        "[social] stream asset reconciliation worker tick failed",
        error?.message || error
      );
    });
  }, cadence);
  socialStreamReconcileWorker.unref?.();
  void processSocialStreamAssetReconciliation();
}

export function stopSocialStreamReconciliationWorker() {
  if (!socialStreamReconcileWorker) return;
  clearInterval(socialStreamReconcileWorker);
  socialStreamReconcileWorker = null;
}
