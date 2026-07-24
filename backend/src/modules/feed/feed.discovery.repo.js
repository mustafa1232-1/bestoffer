import { q } from "../../config/db.js";

function normalizePostKinds(postKinds) {
  if (!Array.isArray(postKinds) || postKinds.length <= 0) return null;
  const values = postKinds
    .map((value) => String(value || "").trim().toLowerCase())
    .flatMap((value) => {
      if (value.length <= 0) return [];
      if (value === "reel") return ["reel", "video"];
      return [value];
    })
    .filter((value) => value.length > 0);
  return values.length > 0 ? [...new Set(values)] : null;
}

function normalizedSearch(search) {
  return String(search || "").trim();
}

export async function listVisiblePostCandidates({
  viewerUserId,
  viewerBlockCode = null,
  viewerCompoundCode = null,
  viewerBuildingCode = null,
  limit = 60,
  beforeId = null,
  authorUserId = null,
  postKinds = null,
  search = "",
  hashtagId = null,
  mentionedUserId = null,
  includeCommunityScoped = true,
}) {
  const viewerId =
    Number.isInteger(Number(viewerUserId)) && Number(viewerUserId) > 0
      ? Number(viewerUserId)
      : null;
  const normalizedKinds = normalizePostKinds(postKinds);
  const searchQuery = normalizedSearch(search);
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.media_asset_id,
       p.merchant_id,
       p.review_rating,
       p.audience_scope_type,
       p.audience_scope_code,
       p.created_at,
       p.updated_at,
       p.moderation_status,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       u.block AS user_block,
       u.building_number AS user_building_number,
       u.apartment AS user_apartment,
       u.social_visibility_tier,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.image_url AS merchant_image_url,
       CASE WHEN m.id IS NOT NULL THEN TRUE ELSE FALSE END AS author_is_merchant,
       COALESCE(premium.is_active, FALSE) AS author_has_premium,
       CASE
         WHEN COALESCE(u.block, '') <> '' AND COALESCE(u.building_number, '') <> ''
           THEN TRUE
         ELSE FALSE
       END AS author_is_resident_verified,
       rel.status AS relation_status,
       rel.initiator_user_id AS relation_initiator_user_id,
       COALESCE(ps.likes_count, 0)::int AS likes_count,
       COALESCE(ps.comments_count, 0)::int AS comments_count,
       COALESCE(ps.saves_count, 0)::int AS saves_count,
       COALESCE(ps.impressions_count, 0)::int AS impressions_count,
       COALESCE(ps.reel_views_count, 0)::int AS reel_views_count,
       COALESCE(v.is_liked, FALSE) AS is_liked,
       COALESCE(sv.is_saved, FALSE) AS is_saved,
       COALESCE(rp.report_count, 0)::int AS report_count,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.duration_ms AS asset_duration_ms,
       asset.processing_status AS asset_processing_status,
       scl.target_type AS link_target_type,
       scl.merchant_id AS link_merchant_id,
       scl.product_id AS link_product_id,
       scl.offer_id AS link_offer_id,
       scl.coupon_id AS link_coupon_id
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     LEFT JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN social_media_asset asset ON asset.id = p.media_asset_id
     LEFT JOIN social_content_link scl
       ON scl.entity_type = CASE WHEN p.post_kind = 'reel' THEN 'reel' ELSE 'post' END
      AND scl.entity_id = p.id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, p.user_id)
      AND rel.user_b_id = GREATEST($1::bigint, p.user_id)
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_active
       FROM paid_upgrade_subscription s
       JOIN paid_upgrade_plan plan ON plan.id = s.plan_id
       WHERE s.user_id = p.user_id
         AND s.status = 'active'
         AND s.expires_at > NOW()
         AND plan.code = 'premium_monthly'
       LIMIT 1
     ) premium ON TRUE
     LEFT JOIN social_post_stats ps ON ps.post_id = p.id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_liked
       FROM social_post_like lv
       WHERE lv.post_id = p.id
         AND lv.user_id = $1
       LIMIT 1
     ) v ON TRUE
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_saved
       FROM social_saved_item si
       WHERE si.user_id = $1
         AND (
           (si.entity_type = 'post' AND p.post_kind NOT IN ('reel', 'merchant_review'))
           OR (si.entity_type = 'reel' AND p.post_kind = 'reel')
           OR (si.entity_type = 'review' AND p.post_kind = 'merchant_review')
         )
         AND si.entity_id = p.id
       LIMIT 1
     ) sv ON TRUE
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS report_count
       FROM social_post_report rp
       WHERE rp.post_id = p.id
     ) rp ON TRUE
     WHERE p.is_deleted = FALSE
       AND p.archived_by_owner_at IS NULL
       AND p.moderation_status = 'approved'
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND (
         COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
         OR p.user_id = $1
         OR COALESCE((SELECT social_visibility_tier FROM app_user WHERE id = $1), 'normal') = 'gray_zone'
       )
      AND (
        p.user_id = $1
        OR COALESCE(u.is_super_admin, FALSE) = TRUE
        OR COALESCE(
          (SELECT is_super_admin FROM app_user WHERE id = $1),
          FALSE
        ) = TRUE
        OR (
          u.social_posts_public = TRUE
          AND (
            COALESCE(u.social_account_private, FALSE) = FALSE
            OR COALESCE(rel.status, '') = 'accepted'
          )
        )
      )
       AND (
         COALESCE(p.audience_scope_type, 'global') = 'global'
         OR (
           $12::boolean = TRUE
           AND (
             (
               COALESCE(p.audience_scope_type, '') = 'block'
               AND $9::text IS NOT NULL
               AND p.audience_scope_code = $9::text
             )
             OR (
               COALESCE(p.audience_scope_type, '') = 'compound'
               AND $10::text IS NOT NULL
               AND p.audience_scope_code = $10::text
             )
             OR (
               COALESCE(p.audience_scope_type, '') = 'building'
               AND $11::text IS NOT NULL
               AND p.audience_scope_code = $11::text
             )
           )
         )
       )
       AND ($2::bigint IS NULL OR p.id < $2::bigint)
       AND ($3::bigint IS NULL OR p.user_id = $3::bigint)
       AND ($4::text[] IS NULL OR p.post_kind = ANY($4::text[]))
       AND ($5::text = '' OR COALESCE(p.caption, '') ILIKE ('%' || $5 || '%'))
       AND (
         $6::bigint IS NULL
         OR EXISTS (
           SELECT 1
           FROM social_entity_hashtag eh
           WHERE eh.entity_type = 'post'
             AND eh.entity_id = p.id
             AND eh.hashtag_id = $6::bigint
         )
       )
       AND (
         $7::bigint IS NULL
         OR EXISTS (
           SELECT 1
           FROM social_mention sm
           WHERE sm.entity_type = 'post'
             AND sm.entity_id = p.id
             AND sm.mentioned_user_id = $7::bigint
         )
       )
     ORDER BY p.id DESC
     LIMIT $8`,
    [
      viewerId,
      beforeId == null ? null : Number(beforeId),
      authorUserId == null ? null : Number(authorUserId),
      normalizedKinds,
      searchQuery,
      hashtagId == null ? null : Number(hashtagId),
      mentionedUserId == null ? null : Number(mentionedUserId),
      Math.max(1, Math.min(160, Number(limit) || 60)),
      viewerBlockCode == null ? null : String(viewerBlockCode).trim().toUpperCase(),
      viewerCompoundCode == null ? null : String(viewerCompoundCode).trim().toUpperCase(),
      viewerBuildingCode == null ? null : String(viewerBuildingCode).trim().toUpperCase(),
      includeCommunityScoped === true,
    ]
  );
  return r.rows;
}

export async function listTrendingHashtags({
  limit = 12,
  lookbackDays = 7,
  search = "",
}) {
  const r = await q(
    `SELECT
       h.id,
       h.tag,
       h.normalized_tag,
       COUNT(*)::int AS usage_count,
       MAX(eh.created_at) AS last_used_at
     FROM social_entity_hashtag eh
     JOIN social_hashtag h ON h.id = eh.hashtag_id
     WHERE eh.created_at >= NOW() - ($2::int * INTERVAL '1 day')
       AND ($3::text = '' OR h.normalized_tag LIKE ($3 || '%'))
     GROUP BY h.id, h.tag, h.normalized_tag
     ORDER BY usage_count DESC, last_used_at DESC
     LIMIT $1`,
    [
      Math.max(1, Math.min(40, Number(limit) || 12)),
      Math.max(1, Math.min(30, Number(lookbackDays) || 7)),
      String(search || "").trim().replace(/^#+/, "").toLowerCase(),
    ]
  );
  return r.rows;
}

export async function listVisiblePostsByIds({
  viewerUserId,
  viewerBlockCode = null,
  viewerCompoundCode = null,
  viewerBuildingCode = null,
  postIds = [],
}) {
  const normalizedIds = Array.isArray(postIds)
    ? [...new Set(postIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))]
    : [];
  if (normalizedIds.length <= 0) return [];
  const viewerId =
    Number.isInteger(Number(viewerUserId)) && Number(viewerUserId) > 0
      ? Number(viewerUserId)
      : null;
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.media_asset_id,
       p.merchant_id,
       p.review_rating,
       p.audience_scope_type,
       p.audience_scope_code,
       p.created_at,
       p.updated_at,
       p.moderation_status,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       u.block AS user_block,
       u.building_number AS user_building_number,
       u.apartment AS user_apartment,
       u.social_visibility_tier,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.image_url AS merchant_image_url,
       CASE WHEN m.id IS NOT NULL THEN TRUE ELSE FALSE END AS author_is_merchant,
       COALESCE(premium.is_active, FALSE) AS author_has_premium,
       CASE
         WHEN COALESCE(u.block, '') <> '' AND COALESCE(u.building_number, '') <> ''
           THEN TRUE
         ELSE FALSE
       END AS author_is_resident_verified,
       rel.status AS relation_status,
       rel.initiator_user_id AS relation_initiator_user_id,
       COALESCE(ps.likes_count, 0)::int AS likes_count,
       COALESCE(ps.comments_count, 0)::int AS comments_count,
       COALESCE(ps.saves_count, 0)::int AS saves_count,
       COALESCE(ps.impressions_count, 0)::int AS impressions_count,
       COALESCE(ps.reel_views_count, 0)::int AS reel_views_count,
       COALESCE(v.is_liked, FALSE) AS is_liked,
       COALESCE(sv.is_saved, FALSE) AS is_saved,
       COALESCE(rp.report_count, 0)::int AS report_count,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.duration_ms AS asset_duration_ms,
       asset.processing_status AS asset_processing_status,
       scl.target_type AS link_target_type,
       scl.merchant_id AS link_merchant_id,
       scl.product_id AS link_product_id,
       scl.offer_id AS link_offer_id,
       scl.coupon_id AS link_coupon_id
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     LEFT JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN social_media_asset asset ON asset.id = p.media_asset_id
     LEFT JOIN social_content_link scl
       ON scl.entity_type = CASE WHEN p.post_kind = 'reel' THEN 'reel' ELSE 'post' END
      AND scl.entity_id = p.id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, p.user_id)
      AND rel.user_b_id = GREATEST($1::bigint, p.user_id)
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_active
       FROM paid_upgrade_subscription s
       JOIN paid_upgrade_plan plan ON plan.id = s.plan_id
       WHERE s.user_id = p.user_id
         AND s.status = 'active'
         AND s.expires_at > NOW()
         AND plan.code = 'premium_monthly'
       LIMIT 1
     ) premium ON TRUE
     LEFT JOIN social_post_stats ps ON ps.post_id = p.id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_liked
       FROM social_post_like lv
       WHERE lv.post_id = p.id
         AND lv.user_id = $1
       LIMIT 1
     ) v ON TRUE
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_saved
       FROM social_saved_item si
       WHERE si.user_id = $1
         AND (
           (si.entity_type = 'post' AND p.post_kind NOT IN ('reel', 'merchant_review'))
           OR (si.entity_type = 'reel' AND p.post_kind = 'reel')
           OR (si.entity_type = 'review' AND p.post_kind = 'merchant_review')
         )
         AND si.entity_id = p.id
       LIMIT 1
     ) sv ON TRUE
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS report_count
       FROM social_post_report rp
       WHERE rp.post_id = p.id
     ) rp ON TRUE
     WHERE p.id = ANY($2::bigint[])
       AND p.is_deleted = FALSE
       AND p.archived_by_owner_at IS NULL
       AND p.moderation_status = 'approved'
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND (
         COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
         OR p.user_id = $1
         OR COALESCE((SELECT social_visibility_tier FROM app_user WHERE id = $1), 'normal') = 'gray_zone'
       )
      AND (
        p.user_id = $1
        OR COALESCE(u.is_super_admin, FALSE) = TRUE
        OR COALESCE(
          (SELECT is_super_admin FROM app_user WHERE id = $1),
          FALSE
        ) = TRUE
        OR (
          u.social_posts_public = TRUE
          AND (
            COALESCE(u.social_account_private, FALSE) = FALSE
            OR COALESCE(rel.status, '') = 'accepted'
          )
        )
      )
       AND (
         COALESCE(p.audience_scope_type, 'global') = 'global'
         OR (
           COALESCE(p.audience_scope_type, '') = 'block'
           AND $3::text IS NOT NULL
           AND p.audience_scope_code = $3::text
         )
         OR (
           COALESCE(p.audience_scope_type, '') = 'compound'
           AND $4::text IS NOT NULL
           AND p.audience_scope_code = $4::text
         )
         OR (
           COALESCE(p.audience_scope_type, '') = 'building'
           AND $5::text IS NOT NULL
           AND p.audience_scope_code = $5::text
         )
       )
     ORDER BY p.id DESC`,
    [
      viewerId,
      normalizedIds,
      viewerBlockCode == null ? null : String(viewerBlockCode).trim().toUpperCase(),
      viewerCompoundCode == null ? null : String(viewerCompoundCode).trim().toUpperCase(),
      viewerBuildingCode == null ? null : String(viewerBuildingCode).trim().toUpperCase(),
    ]
  );
  return r.rows;
}

export async function listSuggestedPeopleCandidates({ viewerUserId, limit = 36 }) {
  // Guests have no viewer id. Normalize to 0 (a non-existent user id) instead of
  // letting `Number(undefined)` become NaN and blow up the bigint bind param.
  // With id 0 the `viewer` CTE is empty, so the CROSS JOIN yields an empty
  // (there is nobody to personalize suggestions for) — the correct, privacy-safe
  // result for a logged-out visitor.
  const normalizedViewerId =
    Number.isInteger(Number(viewerUserId)) && Number(viewerUserId) > 0
      ? Number(viewerUserId)
      : 0;
  const r = await q(
    `WITH viewer AS (
       SELECT id, block, building_number, apartment
       FROM app_user
       WHERE id = $1
     ),
     mutuals AS (
       SELECT
         CASE
           WHEN rel.user_a_id = $1 THEN rel.user_b_id
           ELSE rel.user_a_id
         END AS related_user_id
       FROM social_user_relation rel
       WHERE rel.status = 'accepted'
         AND ($1 IN (rel.user_a_id, rel.user_b_id))
     )
     SELECT
       u.id,
       u.full_name,
       u.phone,
       u.role,
       u.image_url,
       u.block,
       u.building_number,
       u.apartment,
       rel.status,
       rel.initiator_user_id,
       CASE WHEN EXISTS (
         SELECT 1
         FROM mutuals mv
         JOIN social_user_relation rel2
           ON rel2.status = 'accepted'
          AND (
            (rel2.user_a_id = mv.related_user_id AND rel2.user_b_id = u.id)
            OR (rel2.user_b_id = mv.related_user_id AND rel2.user_a_id = u.id)
          )
       ) THEN TRUE ELSE FALSE END AS has_mutuals,
       (
         SELECT COUNT(*)::int
         FROM social_post p
         WHERE p.user_id = u.id
           AND p.is_deleted = FALSE
           AND p.archived_by_owner_at IS NULL
           AND p.moderation_status = 'approved'
           AND p.created_at >= NOW() - INTERVAL '21 days'
       ) AS recent_posts_count
     FROM app_user u
     CROSS JOIN viewer v
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, u.id)
      AND rel.user_b_id = GREATEST($1::bigint, u.id)
     WHERE u.id <> $1
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND COALESCE(rel.status, '') NOT IN ('accepted', 'blocked')
     ORDER BY
       CASE WHEN u.building_number = v.building_number AND u.block = v.block THEN 0 ELSE 1 END ASC,
       CASE WHEN u.block = v.block THEN 0 ELSE 1 END ASC,
       CASE WHEN EXISTS (
         SELECT 1
         FROM mutuals mv
         JOIN social_user_relation rel2
           ON rel2.status = 'accepted'
          AND (
            (rel2.user_a_id = mv.related_user_id AND rel2.user_b_id = u.id)
            OR (rel2.user_b_id = mv.related_user_id AND rel2.user_a_id = u.id)
          )
       ) THEN 0 ELSE 1 END ASC,
       recent_posts_count DESC,
       u.id DESC
     LIMIT $2`,
    [normalizedViewerId, Math.max(1, Math.min(60, Number(limit) || 36))]
  );
  return r.rows;
}
