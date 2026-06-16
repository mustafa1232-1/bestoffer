import * as repo from "./feed.repo.js";

function normalizeMediaKind(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized === "video") return "reel";
  if (["image", "reel", "video"].includes(normalized)) return normalized;
  return null;
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
  const resolvedSourceType = String(sourceType || requestedKind || "post").trim().toLowerCase();
  const normalizedUrl = String(media.url || "").trim();
  const posterUrl = mediaKind === "image" ? normalizedUrl : null;
  const processingStatus = "ready";

  const asset = await repo.insertSocialMediaAsset({
    ownerUserId: userId,
    sourceType: resolvedSourceType,
    originalUrl: normalizedUrl,
    normalizedUrl,
    posterUrl,
    mimeType: media.mimetype || media.mimeType || null,
    mediaKind,
    durationMs: media.durationMs || null,
    width: media.width || null,
    height: media.height || null,
    processingStatus,
  });

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
