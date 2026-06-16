import { deriveBasmayaHierarchy } from "../../shared/utils/basmaya-address.js";

import { mapSocialPostProductRow } from "./feed.product.mappers.js";
import * as repo from "./feed.insights.repo.js";

export async function getProfileInsights({ viewerUserId, targetUserId, isSuperAdmin = false }) {
  if (Number(viewerUserId) !== Number(targetUserId) && isSuperAdmin !== true) {
    return {
      summary: {
        contentCount: 0,
        impressionsCount: 0,
        likesCount: 0,
        commentsCount: 0,
        savesCount: 0,
        reelViewsCount: 0,
        averageWatchDurationMs: 0,
        averageCompletionRate: 0,
      },
      topContent: [],
      bestPostingTimes: [],
      audienceLocality: [],
    };
  }

  const [summary, topContent, bestPostingTimes, audienceLocality] = await Promise.all([
    repo.getProfileInsightSummary(targetUserId),
    repo.listTopContentByInsight(targetUserId),
    repo.listBestPostingHours(targetUserId),
    repo.listAudienceLocality(targetUserId),
  ]);

  return {
    summary: {
      contentCount: Number(summary?.content_count || 0),
      impressionsCount: Number(summary?.impressions_count || 0),
      likesCount: Number(summary?.likes_count || 0),
      commentsCount: Number(summary?.comments_count || 0),
      savesCount: Number(summary?.saves_count || 0),
      reelViewsCount: Number(summary?.reel_views_count || 0),
      averageWatchDurationMs: Number(summary?.average_watch_duration_ms || 0),
      averageCompletionRate: Number(summary?.average_completion_rate || 0),
    },
    topContent: topContent.map((row) =>
      mapSocialPostProductRow({
        ...row,
        user_full_name: "",
        user_role: "user",
        user_phone: "",
        user_image_url: null,
      })
    ),
    bestPostingTimes: bestPostingTimes.map((row) => ({
      hourOfDay: Number(row.hour_of_day || 0),
      postsCount: Number(row.posts_count || 0),
    })),
    audienceLocality: audienceLocality.map((row) => {
      const hierarchy = deriveBasmayaHierarchy({
        block: row.block,
        buildingNumber: row.building_number,
        apartment: null,
      });
      return {
        block: hierarchy.block || null,
        compound: hierarchy.compound || null,
        building: hierarchy.building || null,
        impressionsCount: Number(row.impressions_count || 0),
      };
    }),
  };
}
