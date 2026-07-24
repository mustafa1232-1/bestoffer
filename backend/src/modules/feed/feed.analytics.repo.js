import { q } from "../../config/db.js";

function asPositiveInt(value, fallback = null) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return fallback;
  return parsed;
}

export async function recordContentImpression({
  contentType,
  contentId,
  viewerUserId = null,
  context = "feed",
}) {
  const normalizedType = String(contentType || "").trim().toLowerCase();
  const normalizedContext = String(context || "feed").trim().toLowerCase().slice(0, 32);
  const r = await q(
    `INSERT INTO social_content_impression
      (content_type, content_id, viewer_user_id, impression_context)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [
      normalizedType,
      Number(contentId),
      asPositiveInt(viewerUserId),
      normalizedContext || "feed",
    ]
  );
  return r.rows[0] || null;
}

export async function recordReelViewEvent({
  postId,
  viewerUserId = null,
  watchDurationMs = 0,
  completionRate = 0,
  completed = false,
  replayCount = 0,
}) {
  const safeWatchDurationMs = Math.max(0, Number(watchDurationMs) || 0);
  const safeCompletionRate = Math.max(0, Math.min(100, Number(completionRate) || 0));
  const safeReplayCount = Math.max(0, Number(replayCount) || 0);
  const r = await q(
    `INSERT INTO social_reel_view_event
      (post_id, viewer_user_id, watch_duration_ms, completion_rate, completed, replay_count)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING *`,
    [
      Number(postId),
      asPositiveInt(viewerUserId),
      safeWatchDurationMs,
      safeCompletionRate,
      completed === true,
      safeReplayCount,
    ]
  );
  return r.rows[0] || null;
}

export async function listViewerContentPreferenceSignals({
  viewerUserId,
  lookbackDays = 45,
}) {
  const viewerId = asPositiveInt(viewerUserId);
  if (viewerId == null) return [];
  const safeLookbackDays = Math.max(1, Math.min(180, Number(lookbackDays) || 45));
  const r = await q(
    `WITH post_engagement AS (
       SELECT p.post_kind AS kind, COUNT(*)::int AS weight
       FROM social_post_like l
       JOIN social_post p ON p.id = l.post_id
       WHERE l.user_id = $1
         AND l.created_at >= NOW() - ($2::int * INTERVAL '1 day')
         AND p.is_deleted = FALSE
         AND p.archived_by_owner_at IS NULL
         AND p.moderation_status = 'approved'
       GROUP BY p.post_kind
       UNION ALL
       SELECT p.post_kind AS kind, (COUNT(*)::int * 2) AS weight
       FROM social_post_comment c
       JOIN social_post p ON p.id = c.post_id
       WHERE c.user_id = $1
         AND c.created_at >= NOW() - ($2::int * INTERVAL '1 day')
         AND c.is_deleted = FALSE
         AND c.moderation_status = 'approved'
         AND p.is_deleted = FALSE
         AND p.archived_by_owner_at IS NULL
         AND p.moderation_status = 'approved'
       GROUP BY p.post_kind
       UNION ALL
       SELECT
         CASE WHEN s.entity_type = 'review' THEN 'merchant_review' ELSE s.entity_type END AS kind,
         (COUNT(*)::int * 2) AS weight
       FROM social_saved_item s
       WHERE s.user_id = $1
         AND s.created_at >= NOW() - ($2::int * INTERVAL '1 day')
       GROUP BY
         CASE WHEN s.entity_type = 'review' THEN 'merchant_review' ELSE s.entity_type END
     )
     SELECT kind, SUM(weight)::int AS total_weight
     FROM post_engagement
     WHERE kind IS NOT NULL
     GROUP BY kind`,
    [viewerId, safeLookbackDays]
  );
  return r.rows;
}

export async function listRecentEngagementStatsForPosts({
  postIds,
  lookbackHours = 24,
}) {
  const normalizedPostIds = Array.isArray(postIds)
    ? [...new Set(postIds.map((value) => asPositiveInt(value)).filter((value) => value != null))]
    : [];
  if (normalizedPostIds.length <= 0) return [];
  const safeLookbackHours = Math.max(1, Math.min(168, Number(lookbackHours) || 24));
  const r = await q(
    `SELECT
       p.id AS post_id,
       COALESCE(l.likes_recent, 0)::int AS likes_recent,
       COALESCE(c.comments_recent, 0)::int AS comments_recent,
       COALESCE(s.saves_recent, 0)::int AS saves_recent,
       COALESCE(i.impressions_recent, 0)::int AS impressions_recent,
       COALESCE(rv.views_recent, 0)::int AS reel_views_recent
     FROM social_post p
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS likes_recent
       FROM social_post_like l
       WHERE l.post_id = p.id
         AND l.created_at >= NOW() - ($2::int * INTERVAL '1 hour')
     ) l ON TRUE
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS comments_recent
       FROM social_post_comment c
       WHERE c.post_id = p.id
         AND c.is_deleted = FALSE
         AND c.moderation_status = 'approved'
         AND c.created_at >= NOW() - ($2::int * INTERVAL '1 hour')
     ) c ON TRUE
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS saves_recent
       FROM social_saved_item s
       WHERE (
           (s.entity_type = 'post' AND p.post_kind <> 'reel')
           OR (s.entity_type = 'reel' AND p.post_kind = 'reel')
           OR (s.entity_type = 'review' AND p.post_kind = 'merchant_review')
         )
         AND s.entity_id = p.id
         AND s.created_at >= NOW() - ($2::int * INTERVAL '1 hour')
     ) s ON TRUE
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS impressions_recent
       FROM social_content_impression i
       WHERE i.content_type = CASE WHEN p.post_kind = 'reel' THEN 'reel' ELSE 'post' END
         AND i.content_id = p.id
         AND i.created_at >= NOW() - ($2::int * INTERVAL '1 hour')
     ) i ON TRUE
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS views_recent
       FROM social_reel_view_event rv
       WHERE rv.post_id = p.id
         AND rv.created_at >= NOW() - ($2::int * INTERVAL '1 hour')
     ) rv ON TRUE
     WHERE p.id = ANY($1::bigint[])`,
    [normalizedPostIds, safeLookbackHours]
  );
  return r.rows;
}

export async function listLifetimeEngagementStatsForPosts({ postIds, viewerUserId = null }) {
  const normalizedPostIds = Array.isArray(postIds)
    ? [...new Set(postIds.map((value) => asPositiveInt(value)).filter((value) => value != null))]
    : [];
  if (normalizedPostIds.length <= 0) return [];
  const viewerId = asPositiveInt(viewerUserId);
  const r = await q(
    `SELECT
       p.id AS post_id,
       COALESCE(ps.likes_count, 0)::int AS likes_count,
       COALESCE(ps.comments_count, 0)::int AS comments_count,
       COALESCE(ps.saves_count, 0)::int AS saves_count,
       COALESCE(ps.impressions_count, 0)::int AS impressions_count,
       COALESCE(ps.reel_views_count, 0)::int AS reel_views_count,
       COALESCE(v.is_liked, FALSE) AS is_liked,
       COALESCE(sv.is_saved, FALSE) AS is_saved
      FROM social_post p
      LEFT JOIN social_post_stats ps ON ps.post_id = p.id
      LEFT JOIN LATERAL (
        SELECT TRUE AS is_liked
        FROM social_post_like lv
       WHERE $2::bigint IS NOT NULL
         AND lv.post_id = p.id
         AND lv.user_id = $2::bigint
       LIMIT 1
     ) v ON TRUE
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_saved
       FROM social_saved_item s
       WHERE $2::bigint IS NOT NULL
         AND s.user_id = $2::bigint
         AND (
           (s.entity_type = 'post' AND p.post_kind <> 'reel')
           OR (s.entity_type = 'reel' AND p.post_kind = 'reel')
           OR (s.entity_type = 'review' AND p.post_kind = 'merchant_review')
         )
         AND s.entity_id = p.id
       LIMIT 1
     ) sv ON TRUE
     WHERE p.id = ANY($1::bigint[])`,
    [normalizedPostIds, viewerId]
  );
  return r.rows;
}
