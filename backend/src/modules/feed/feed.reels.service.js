import * as analyticsRepo from "./feed.analytics.repo.js";
import * as discoveryRepo from "./feed.discovery.repo.js";
import { mapSocialPostProductRow } from "./feed.product.mappers.js";
import * as repo from "./feed.reels.repo.js";

export async function listExploreReels({
  viewerUserId,
  query,
  viewerScopeCodes,
  rankFeedRows,
  preferenceWeights,
}) {
  const candidates = await discoveryRepo.listVisiblePostCandidates({
    viewerUserId,
    viewerBlockCode: viewerScopeCodes.blockCode,
    viewerCompoundCode: viewerScopeCodes.compoundCode,
    viewerBuildingCode: viewerScopeCodes.buildingCode,
    limit: Math.max(query.limit * 3, 48),
    beforeId: query.beforeId,
    authorUserId: null,
    postKinds: ["reel"],
    search: "",
    hashtagId: null,
    mentionedUserId: null,
  });
  const ranked = rankFeedRows(candidates, {
    viewerScopeCodes,
    preferenceWeights,
  }).slice(0, query.limit);
  const metricRows = await repo.listReelMetricSummaryForPosts(ranked.map((row) => Number(row.id)));
  const metricsById = new Map(metricRows.map((row) => [Number(row.post_id), row]));
  return {
    reels: ranked.map((row) => ({
      ...mapSocialPostProductRow(row),
      metrics: {
        impressionsCount: Number(metricsById.get(Number(row.id))?.impressions_count || 0),
        viewsCount: Number(metricsById.get(Number(row.id))?.views_count || 0),
        averageWatchDurationMs: Number(metricsById.get(Number(row.id))?.avg_watch_duration_ms || 0),
        averageCompletionRate: Number(metricsById.get(Number(row.id))?.avg_completion_rate || 0),
        replayCount: Number(metricsById.get(Number(row.id))?.replay_count || 0),
      },
    })),
    nextCursor: ranked.length > 0 ? Number(ranked[ranked.length - 1].id) : null,
  };
}

export async function recordReelView({ viewerUserId, reelId, dto }) {
  await analyticsRepo.recordContentImpression({
    contentType: "reel",
    contentId: reelId,
    viewerUserId,
    context: dto.context || "reel_viewer",
  });
  const inserted = await analyticsRepo.recordReelViewEvent({
    postId: reelId,
    viewerUserId,
    watchDurationMs: dto.watchDurationMs,
    completionRate: dto.completionRate,
    completed: dto.completed,
    replayCount: dto.replayCount,
  });
  return {
    ok: true,
    eventId: Number(inserted?.id || 0),
  };
}
