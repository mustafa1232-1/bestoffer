import { q } from "../../config/db.js";

export async function listReelMetricSummaryForPosts(postIds) {
  if (!Array.isArray(postIds) || postIds.length <= 0) return [];
  const normalizedIds = [...new Set(postIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))];
  if (normalizedIds.length <= 0) return [];
  const r = await q(
    `SELECT
       p.id AS post_id,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_content_impression i
         WHERE i.content_type = 'reel'
           AND i.content_id = p.id
       ), 0)::int AS impressions_count,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_reel_view_event rv
         WHERE rv.post_id = p.id
       ), 0)::int AS views_count,
       COALESCE((
         SELECT AVG(rv.watch_duration_ms)::numeric(12,2)
         FROM social_reel_view_event rv
         WHERE rv.post_id = p.id
       ), 0)::numeric(12,2) AS avg_watch_duration_ms,
       COALESCE((
         SELECT AVG(rv.completion_rate)::numeric(12,2)
         FROM social_reel_view_event rv
         WHERE rv.post_id = p.id
       ), 0)::numeric(12,2) AS avg_completion_rate,
       COALESCE((
         SELECT SUM(rv.replay_count)::int
         FROM social_reel_view_event rv
         WHERE rv.post_id = p.id
       ), 0)::int AS replay_count
     FROM social_post p
     WHERE p.id = ANY($1::bigint[])`,
    [normalizedIds]
  );
  return r.rows;
}
