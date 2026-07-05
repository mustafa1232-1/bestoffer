import * as discoveryRepo from "./feed.discovery.repo.js";
import { mapHashtagRow, mapSocialPostProductRow } from "./feed.product.mappers.js";
import * as recommendationsService from "./feed.recommendations.service.js";
import * as repo from "./feed.search.repo.js";

export async function searchSocial({
  viewerUserId,
  query,
  viewerScopeCodes,
  searchUsers,
}) {
  const term = String(query.search || "").trim();
  if (term) {
    await repo.upsertRecentSearch({
      userId: viewerUserId,
      searchType: query.tab || "all",
      rawQuery: term,
    });
  }

  const [recentRows, userOut, hashtagRows, merchantRows, postRows, reelRows, reviewRows] =
    await Promise.all([
      repo.listRecentSearches(viewerUserId, { limit: 10 }),
      query.tab === "posts" ||
      query.tab === "reels" ||
      query.tab === "hashtags" ||
      query.tab === "merchants" ||
      query.tab === "reviews"
        ? Promise.resolve({ users: [] })
        : searchUsers(viewerUserId, { search: term, limit: query.limit }),
      query.tab === "users"
        ? Promise.resolve([])
        : repo.searchHashtags({ query: term, limit: query.limit }),
      query.tab === "users" || query.tab === "hashtags"
        ? Promise.resolve([])
        : repo.searchMerchantsSocial({ query: term, limit: query.limit }),
      query.tab === "users" ||
      query.tab === "reels" ||
      query.tab === "hashtags" ||
      query.tab === "merchants" ||
      query.tab === "reviews"
        ? Promise.resolve([])
        : discoveryRepo.listVisiblePostCandidates({
            viewerUserId,
            viewerBlockCode: viewerScopeCodes.blockCode,
            viewerCompoundCode: viewerScopeCodes.compoundCode,
            viewerBuildingCode: viewerScopeCodes.buildingCode,
            limit: query.limit,
            beforeId: null,
            authorUserId: null,
            postKinds: ["text", "image"],
            search: term,
            hashtagId: null,
            mentionedUserId: null,
          }),
      query.tab === "users" ||
      query.tab === "posts" ||
      query.tab === "hashtags" ||
      query.tab === "merchants" ||
      query.tab === "reviews"
        ? Promise.resolve([])
        : discoveryRepo.listVisiblePostCandidates({
            viewerUserId,
            viewerBlockCode: viewerScopeCodes.blockCode,
            viewerCompoundCode: viewerScopeCodes.compoundCode,
            viewerBuildingCode: viewerScopeCodes.buildingCode,
            limit: query.limit,
            beforeId: null,
            authorUserId: null,
            postKinds: ["reel"],
            search: term,
            hashtagId: null,
            mentionedUserId: null,
          }),
      query.tab === "users" ||
      query.tab === "posts" ||
      query.tab === "reels" ||
      query.tab === "hashtags" ||
      query.tab === "merchants"
        ? Promise.resolve([])
        : discoveryRepo.listVisiblePostCandidates({
            viewerUserId,
            viewerBlockCode: viewerScopeCodes.blockCode,
            viewerCompoundCode: viewerScopeCodes.compoundCode,
            viewerBuildingCode: viewerScopeCodes.buildingCode,
            limit: query.limit,
            beforeId: null,
            authorUserId: null,
            postKinds: ["merchant_review"],
            search: term,
            hashtagId: null,
            mentionedUserId: null,
          }),
    ]);

  const suggested =
    query.tab === "all" && !term
      ? await recommendationsService.listSuggestedPeople({ viewerUserId, limit: 10 })
      : { users: [] };

  return {
    query: term,
    recentSearches: recentRows.map((row) => ({
      id: Number(row.id),
      searchType: row.search_type || "all",
      rawQuery: row.raw_query || "",
      createdAt: row.created_at || null,
      updatedAt: row.updated_at || null,
    })),
    results: {
      users: Array.isArray(userOut?.users) ? userOut.users : [],
      posts: postRows.map(mapSocialPostProductRow),
      reels: reelRows.map(mapSocialPostProductRow),
      hashtags: hashtagRows.map(mapHashtagRow),
      merchants: merchantRows.map(mapSocialMerchantSearchResultRow),
      reviews: reviewRows.map(mapSocialPostProductRow),
      suggestedPeople: Array.isArray(suggested?.users) ? suggested.users : [],
    },
  };
}

export function mapSocialMerchantSearchResultRow(row) {
  return {
    id: Number(row.id),
    name: row.name || "",
    type: row.type || "market",
    activityType: row.activity_type || row.type || "market",
    phone: row.phone || "",
    imageUrl: row.image_url || null,
    reviewPostsCount: Number(row.review_posts_count || 0),
  };
}
