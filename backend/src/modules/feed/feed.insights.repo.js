import { q } from "../../config/db.js";

export async function getProfileInsightSummary(userId, { lookbackDays = 30 } = {}) {
  const safeLookbackDays = Math.max(1, Math.min(180, Number(lookbackDays) || 30));
  const r = await q(
    `WITH posts AS (
       SELECT id, post_kind, created_at
       FROM social_post
       WHERE user_id = $1
         AND is_deleted = FALSE
         AND archived_by_owner_at IS NULL
         AND moderation_status = 'approved'
         AND created_at >= NOW() - ($2::int * INTERVAL '1 day')
     )
     SELECT
       COALESCE((SELECT COUNT(*)::int FROM posts), 0)::int AS content_count,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_content_impression i
         WHERE i.content_type IN ('post', 'reel')
           AND i.content_id IN (SELECT id FROM posts)
           AND i.created_at >= NOW() - ($2::int * INTERVAL '1 day')
       ), 0)::int AS impressions_count,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_post_like l
         WHERE l.post_id IN (SELECT id FROM posts)
           AND l.created_at >= NOW() - ($2::int * INTERVAL '1 day')
       ), 0)::int AS likes_count,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_post_comment c
         WHERE c.post_id IN (SELECT id FROM posts)
           AND c.is_deleted = FALSE
           AND c.moderation_status = 'approved'
           AND c.created_at >= NOW() - ($2::int * INTERVAL '1 day')
       ), 0)::int AS comments_count,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_saved_item s
         WHERE (
             (s.entity_type = 'post' AND s.entity_id IN (SELECT id FROM posts WHERE post_kind NOT IN ('reel', 'merchant_review')))
             OR (s.entity_type = 'reel' AND s.entity_id IN (SELECT id FROM posts WHERE post_kind = 'reel'))
             OR (s.entity_type = 'review' AND s.entity_id IN (SELECT id FROM posts WHERE post_kind = 'merchant_review'))
           )
           AND s.created_at >= NOW() - ($2::int * INTERVAL '1 day')
       ), 0)::int AS saves_count,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_reel_view_event rv
         WHERE rv.post_id IN (SELECT id FROM posts WHERE post_kind = 'reel')
           AND rv.created_at >= NOW() - ($2::int * INTERVAL '1 day')
       ), 0)::int AS reel_views_count,
       COALESCE((
         SELECT AVG(rv.watch_duration_ms)::numeric(12,2)
         FROM social_reel_view_event rv
         WHERE rv.post_id IN (SELECT id FROM posts WHERE post_kind = 'reel')
           AND rv.created_at >= NOW() - ($2::int * INTERVAL '1 day')
       ), 0)::numeric(12,2) AS average_watch_duration_ms,
       COALESCE((
         SELECT AVG(rv.completion_rate)::numeric(12,2)
         FROM social_reel_view_event rv
         WHERE rv.post_id IN (SELECT id FROM posts WHERE post_kind = 'reel')
           AND rv.created_at >= NOW() - ($2::int * INTERVAL '1 day')
       ), 0)::numeric(12,2) AS average_completion_rate`,
    [Number(userId), safeLookbackDays]
  );
  return r.rows[0] || null;
}

export async function listTopContentByInsight(userId, { limit = 8, lookbackDays = 30 } = {}) {
  const safeLimit = Math.max(1, Math.min(20, Number(limit) || 8));
  const safeLookbackDays = Math.max(1, Math.min(180, Number(lookbackDays) || 30));
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.created_at,
       p.updated_at,
       COALESCE((SELECT COUNT(*)::int FROM social_post_like l WHERE l.post_id = p.id), 0)::int AS likes_count,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_post_comment c
         WHERE c.post_id = p.id
           AND c.is_deleted = FALSE
           AND c.moderation_status = 'approved'
       ), 0)::int AS comments_count,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_saved_item s
         WHERE (
           (s.entity_type = 'post' AND p.post_kind NOT IN ('reel', 'merchant_review'))
           OR (s.entity_type = 'reel' AND p.post_kind = 'reel')
           OR (s.entity_type = 'review' AND p.post_kind = 'merchant_review')
         )
           AND s.entity_id = p.id
       ), 0)::int AS saves_count,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_content_impression i
         WHERE i.content_id = p.id
           AND i.content_type = CASE WHEN p.post_kind = 'reel' THEN 'reel' ELSE 'post' END
       ), 0)::int AS impressions_count,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_reel_view_event rv
         WHERE rv.post_id = p.id
       ), 0)::int AS reel_views_count
     FROM social_post p
     WHERE p.user_id = $1
       AND p.is_deleted = FALSE
       AND p.archived_by_owner_at IS NULL
       AND p.moderation_status = 'approved'
       AND p.created_at >= NOW() - ($3::int * INTERVAL '1 day')
     ORDER BY (
         COALESCE((SELECT COUNT(*)::int FROM social_post_like l WHERE l.post_id = p.id), 0) * 2
         + COALESCE((
           SELECT COUNT(*)::int
           FROM social_post_comment c
           WHERE c.post_id = p.id
             AND c.is_deleted = FALSE
             AND c.moderation_status = 'approved'
         ), 0) * 3
         + COALESCE((
           SELECT COUNT(*)::int
           FROM social_saved_item s
           WHERE (
             (s.entity_type = 'post' AND p.post_kind NOT IN ('reel', 'merchant_review'))
             OR (s.entity_type = 'reel' AND p.post_kind = 'reel')
             OR (s.entity_type = 'review' AND p.post_kind = 'merchant_review')
           )
             AND s.entity_id = p.id
         ), 0) * 4
       ) DESC,
       p.id DESC
     LIMIT $2`,
    [Number(userId), safeLimit, safeLookbackDays]
  );
  return r.rows;
}

export async function listBestPostingHours(userId, { lookbackDays = 60 } = {}) {
  const safeLookbackDays = Math.max(7, Math.min(180, Number(lookbackDays) || 60));
  const r = await q(
    `SELECT
       EXTRACT(HOUR FROM created_at)::int AS hour_of_day,
       COUNT(*)::int AS posts_count
     FROM social_post
     WHERE user_id = $1
       AND is_deleted = FALSE
       AND archived_by_owner_at IS NULL
       AND moderation_status = 'approved'
       AND created_at >= NOW() - ($2::int * INTERVAL '1 day')
     GROUP BY hour_of_day
     ORDER BY posts_count DESC, hour_of_day ASC
     LIMIT 5`,
    [Number(userId), safeLookbackDays]
  );
  return r.rows;
}

export async function listAudienceLocality(userId, { lookbackDays = 30 } = {}) {
  const safeLookbackDays = Math.max(1, Math.min(180, Number(lookbackDays) || 30));
  const r = await q(
    `SELECT
       u.block,
       u.building_number,
       COUNT(*)::int AS impressions_count
     FROM social_content_impression i
     JOIN app_user u ON u.id = i.viewer_user_id
     WHERE i.viewer_user_id IS NOT NULL
       AND i.created_at >= NOW() - ($2::int * INTERVAL '1 day')
       AND i.content_id IN (
         SELECT id
         FROM social_post
         WHERE user_id = $1
           AND is_deleted = FALSE
           AND archived_by_owner_at IS NULL
           AND moderation_status = 'approved'
       )
     GROUP BY u.block, u.building_number
     ORDER BY impressions_count DESC, u.block ASC, u.building_number ASC
     LIMIT 12`,
    [Number(userId), safeLookbackDays]
  );
  return r.rows;
}
