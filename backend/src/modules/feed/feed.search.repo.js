import { q } from "../../config/db.js";

export async function upsertRecentSearch({ userId, searchType, rawQuery }) {
  const normalized = String(rawQuery || "").trim().toLowerCase();
  if (!normalized) return null;
  const r = await q(
    `INSERT INTO social_search_recent
      (user_id, search_type, raw_query, normalized_query)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (user_id, search_type, normalized_query)
     DO UPDATE SET raw_query = EXCLUDED.raw_query, updated_at = NOW()
     RETURNING *`,
    [
      Number(userId),
      String(searchType || "all").trim().toLowerCase(),
      String(rawQuery || "").trim(),
      normalized,
    ]
  );
  return r.rows[0] || null;
}

export async function listRecentSearches(userId, { limit = 12 } = {}) {
  const r = await q(
    `SELECT *
     FROM social_search_recent
     WHERE user_id = $1
     ORDER BY updated_at DESC, id DESC
     LIMIT $2`,
    [Number(userId), Math.max(1, Math.min(30, Number(limit) || 12))]
  );
  return r.rows;
}

export async function searchHashtags({ query, limit = 12 }) {
  const search = String(query || "").trim().toLowerCase();
  const r = await q(
    `SELECT
       h.*,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_entity_hashtag eh
         WHERE eh.hashtag_id = h.id
       ), 0)::int AS usage_count,
       (
         SELECT MAX(eh.created_at)
         FROM social_entity_hashtag eh
         WHERE eh.hashtag_id = h.id
       ) AS last_used_at
     FROM social_hashtag h
     WHERE $1::text = ''
        OR h.normalized_tag LIKE ($1 || '%')
        OR h.normalized_tag LIKE ('%' || $1 || '%')
     ORDER BY
       CASE WHEN $1::text <> '' AND h.normalized_tag LIKE ($1 || '%') THEN 0 ELSE 1 END ASC,
       usage_count DESC,
       h.normalized_tag ASC
     LIMIT $2`,
    [search, Math.max(1, Math.min(30, Number(limit) || 12))]
  );
  return r.rows;
}

export async function searchMerchantsSocial({ query, limit = 12 }) {
  const search = String(query || "").trim();
  const r = await q(
    `SELECT
       m.id,
       m.name,
       m.type,
       m.activity_type,
       m.image_url,
       m.phone,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_post p
         WHERE p.merchant_id = m.id
           AND p.post_kind = 'merchant_review'
           AND p.is_deleted = FALSE
           AND p.archived_by_owner_at IS NULL
           AND p.moderation_status = 'approved'
       ), 0)::int AS review_posts_count
     FROM merchant m
     WHERE COALESCE(m.is_disabled, FALSE) = FALSE
       AND ($1::text = '' OR m.name ILIKE ('%' || $1 || '%'))
     ORDER BY
       CASE WHEN $1::text <> '' AND m.name ILIKE ($1 || '%') THEN 0 ELSE 1 END ASC,
       review_posts_count DESC,
       m.id DESC
     LIMIT $2`,
    [search, Math.max(1, Math.min(30, Number(limit) || 12))]
  );
  return r.rows;
}
