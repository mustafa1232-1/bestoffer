import { getRedisClient } from "../../config/redis.js";
import {
  buildRedisKey,
  redisPrefixes,
  redisTtls,
} from "../../config/redis-keys.js";

import * as analyticsRepo from "./feed.analytics.repo.js";
import * as discoveryRepo from "./feed.discovery.repo.js";
import { mapHashtagRow, mapSocialPostProductRow } from "./feed.product.mappers.js";
import { buildPreferenceWeightMap, rankFeedRows } from "./feed.ranking.service.js";
import * as recommendationsService from "./feed.recommendations.service.js";

function buildCacheKey(prefix, viewerUserId, query = {}, viewerScopeCodes = {}) {
  const normalized = {
    prefix,
    viewerUserId: Number(viewerUserId),
    limit: Number(query.limit || 0),
    beforeId: query.beforeId == null ? null : Number(query.beforeId),
    blockCode: viewerScopeCodes.blockCode || null,
    compoundCode: viewerScopeCodes.compoundCode || null,
    buildingCode: viewerScopeCodes.buildingCode || null,
  };
  return buildRedisKey(
    redisPrefixes.cache,
    "feed",
    prefix,
    Buffer.from(JSON.stringify(normalized)).toString("base64url")
  );
}

async function withShortCache(cacheKey, loader) {
  const client = await getRedisClient();
  if (!client) {
    return loader();
  }
  try {
    const cached = await client.get(cacheKey);
    if (cached) {
      return JSON.parse(cached);
    }
  } catch (_) {
    // ignore redis read failures
  }

  const value = await loader();
  try {
    await client.set(cacheKey, JSON.stringify(value), "EX", redisTtls.feedDiscoverySeconds);
  } catch (_) {
    // ignore redis write failures
  }
  return value;
}

async function buildRankingContext(viewerUserId) {
  const preferenceRows = await analyticsRepo.listViewerContentPreferenceSignals({
    viewerUserId,
  });
  return {
    preferenceWeights: buildPreferenceWeightMap(preferenceRows),
  };
}

function normalizeLimit(query, fallback = 24, max = 60) {
  return Math.max(1, Math.min(max, Number(query?.limit) || fallback));
}

export async function listExplore({
  viewerUserId,
  query,
  viewerScopeCodes,
}) {
  const cacheKey = buildCacheKey("explore", viewerUserId, query, viewerScopeCodes);
  return withShortCache(cacheKey, async () => {
    const limit = normalizeLimit(query, 18, 36);
    const { preferenceWeights } = await buildRankingContext(viewerUserId);

    const [
      allCandidates,
      reelCandidates,
      reviewCandidates,
      suggestedPeople,
      trendingTags,
    ] = await Promise.all([
      discoveryRepo.listVisiblePostCandidates({
        viewerUserId,
        viewerBlockCode: viewerScopeCodes.blockCode,
        viewerCompoundCode: viewerScopeCodes.compoundCode,
        viewerBuildingCode: viewerScopeCodes.buildingCode,
        limit: Math.max(limit * 4, 72),
        beforeId: null,
        authorUserId: null,
        postKinds: ["text", "image", "reel", "merchant_review"],
        search: "",
        hashtagId: null,
        mentionedUserId: null,
      }),
      discoveryRepo.listVisiblePostCandidates({
        viewerUserId,
        viewerBlockCode: viewerScopeCodes.blockCode,
        viewerCompoundCode: viewerScopeCodes.compoundCode,
        viewerBuildingCode: viewerScopeCodes.buildingCode,
        limit: Math.max(limit * 2, 36),
        beforeId: null,
        authorUserId: null,
        postKinds: ["reel"],
        search: "",
        hashtagId: null,
        mentionedUserId: null,
      }),
      discoveryRepo.listVisiblePostCandidates({
        viewerUserId,
        viewerBlockCode: viewerScopeCodes.blockCode,
        viewerCompoundCode: viewerScopeCodes.compoundCode,
        viewerBuildingCode: viewerScopeCodes.buildingCode,
        limit: Math.max(limit * 2, 24),
        beforeId: null,
        authorUserId: null,
        postKinds: ["merchant_review"],
        search: "",
        hashtagId: null,
        mentionedUserId: null,
      }),
      recommendationsService.listSuggestedPeople({ viewerUserId, limit: 12 }),
      discoveryRepo.listTrendingHashtags({ limit: 8 }),
    ]);

    const rankedAll = rankFeedRows(allCandidates, {
      viewerScopeCodes,
      preferenceWeights,
    });
    const rankedReels = rankFeedRows(reelCandidates, {
      viewerScopeCodes,
      preferenceWeights,
    });
    const rankedReviews = rankFeedRows(reviewCandidates, {
      viewerScopeCodes,
      preferenceWeights,
    });

    const sameArea = rankedAll
      .filter((row) => {
        const scopeCode = String(row.audience_scope_code || "").trim().toUpperCase();
        return (
          scopeCode === String(viewerScopeCodes.buildingCode || "").trim().toUpperCase() ||
          scopeCode === String(viewerScopeCodes.compoundCode || "").trim().toUpperCase() ||
          scopeCode === String(viewerScopeCodes.blockCode || "").trim().toUpperCase()
        );
      })
      .slice(0, 8);

    const popularPosts = rankedAll
      .filter((row) => String(row.post_kind || "").trim().toLowerCase() !== "merchant_review")
      .slice(0, 12);

    return {
      sections: {
        forYou: rankedAll.slice(0, 12).map(mapSocialPostProductRow),
        reels: rankedReels.slice(0, 10).map(mapSocialPostProductRow),
        trendingBasmaya: rankedAll.slice(0, 10).map(mapSocialPostProductRow),
        sameArea: sameArea.map(mapSocialPostProductRow),
        restaurantReviews: rankedReviews.slice(0, 8).map(mapSocialPostProductRow),
        popularPosts: popularPosts.map(mapSocialPostProductRow),
        localTopics: trendingTags.map(mapHashtagRow),
        suggestedPeople: suggestedPeople.users || [],
      },
      generatedAt: new Date().toISOString(),
    };
  });
}

export async function listTrending({
  viewerUserId,
  query,
  viewerScopeCodes,
}) {
  const cacheKey = buildCacheKey("trending", viewerUserId, query, viewerScopeCodes);
  return withShortCache(cacheKey, async () => {
    const limit = normalizeLimit(query, 16, 36);
    const { preferenceWeights } = await buildRankingContext(viewerUserId);
    const rows = await discoveryRepo.listVisiblePostCandidates({
      viewerUserId,
      viewerBlockCode: viewerScopeCodes.blockCode,
      viewerCompoundCode: viewerScopeCodes.compoundCode,
      viewerBuildingCode: viewerScopeCodes.buildingCode,
      limit: Math.max(limit * 4, 72),
      beforeId: query.beforeId,
      authorUserId: null,
      postKinds: ["text", "image", "reel", "merchant_review"],
      search: "",
      hashtagId: null,
      mentionedUserId: null,
    });
    const ranked = rankFeedRows(rows, { viewerScopeCodes, preferenceWeights }).slice(0, limit);
    return {
      posts: ranked.map(mapSocialPostProductRow),
      hashtags: (await discoveryRepo.listTrendingHashtags({ limit: 12 })).map(mapHashtagRow),
      nextCursor: ranked.length > 0 ? Number(ranked[ranked.length - 1].id) : null,
      generatedAt: new Date().toISOString(),
    };
  });
}
