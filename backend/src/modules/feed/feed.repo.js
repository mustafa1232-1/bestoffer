import { pool, q } from "../../config/db.js";

/**
 * Purpose:
 * repository المجتمع والمحادثات. يحتوي الاستعلامات الثقيلة الخاصة بالمنشورات،
 * العلاقات، الـ presence، الرسائل، read receipts، والوسائط.
 *
 * Used by:
 * - `feed.service.js`
 *
 * Critical notes:
 * - كثير من منطق feed يعتمد على استعلامات مركبة وLATERAL joins؛ أي تعديل
 *   يجب أن يراجع الأداء وصحة counts والفلترة والصلاحيات.
 */
const PRESENCE_HEARTBEAT_THROTTLE_MS = 15000;
const userPresenceHeartbeatCache = new Map();

/**
 * يجلب feed العام المرئي للمستخدم الحالي مع كل فلاتر الخصوصية والعلاقات.
 */
export async function listFeedPosts({
  viewerUserId,
  viewerBlockCode = null,
  viewerCompoundCode = null,
  viewerBuildingCode = null,
  limit = 20,
  beforeId = null,
  postKind = null,
}) {
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.shared_entity_type,
       p.shared_entity_id,
       p.shared_snapshot_json,
       p.media_asset_id,
       p.merchant_id,
       p.review_rating,
       p.audience_scope_type,
       p.audience_scope_code,
       p.created_at,
     p.updated_at,
       u.username AS user_username,
       u.full_name AS user_full_name,
     u.phone AS user_phone,
     u.image_url AS user_image_url,
     u.role AS user_role,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.image_url AS merchant_image_url,
       COALESCE(ps.likes_count, 0)::int AS likes_count,
       COALESCE(ps.comments_count, 0)::int AS comments_count,
       COALESCE(v.is_liked, FALSE) AS is_liked
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     LEFT JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, p.user_id)
      AND rel.user_b_id = GREATEST($1::bigint, p.user_id)
     LEFT JOIN social_post_stats ps ON ps.post_id = p.id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_liked
       FROM social_post_like lv
       WHERE lv.post_id = p.id
         AND lv.user_id = $1
       LIMIT 1
      ) v ON TRUE
      WHERE p.is_deleted = FALSE
        AND p.archived_by_owner_at IS NULL
        AND p.moderation_status = 'approved'
        AND COALESCE(u.is_account_disabled, FALSE) = FALSE
        AND (
          COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
          OR p.user_id = $1
          OR COALESCE(
            (SELECT social_visibility_tier FROM app_user WHERE id = $1),
            'normal'
          ) = 'gray_zone'
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
            AND $4::text IS NOT NULL
            AND p.audience_scope_code = $4::text
          )
          OR (
            COALESCE(p.audience_scope_type, '') = 'compound'
            AND $5::text IS NOT NULL
            AND p.audience_scope_code = $5::text
          )
          OR (
            COALESCE(p.audience_scope_type, '') = 'building'
            AND $6::text IS NOT NULL
            AND p.audience_scope_code = $6::text
          )
        )
       AND ($2::bigint IS NULL OR p.id < $2::bigint)
       AND ($3::text IS NULL OR p.post_kind = $3::text)
     ORDER BY p.id DESC
     LIMIT $7`,
    [
      Number(viewerUserId),
      beforeId,
      postKind,
      viewerBlockCode == null ? null : String(viewerBlockCode).trim().toUpperCase(),
      viewerCompoundCode == null
        ? null
        : String(viewerCompoundCode).trim().toUpperCase(),
      viewerBuildingCode == null
        ? null
        : String(viewerBuildingCode).trim().toUpperCase(),
      Number(limit),
    ]
  );
  return r.rows;
}

/**
 * يجلب منشورات مستخدم واحد مع مراعاة الخصوصية والعلاقات وعدادات التفاعل.
 */
export async function listUserFeedPosts({
  viewerUserId,
  userId,
  viewerBlockCode = null,
  viewerCompoundCode = null,
  viewerBuildingCode = null,
  limit = 20,
  beforeId = null,
  postKind = null,
}) {
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.shared_entity_type,
       p.shared_entity_id,
       p.shared_snapshot_json,
       p.merchant_id,
       p.review_rating,
       p.audience_scope_type,
       p.audience_scope_code,
       p.created_at,
       p.updated_at,
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
       COALESCE(ps.likes_count, 0)::int AS likes_count,
       COALESCE(ps.comments_count, 0)::int AS comments_count,
       COALESCE(sv.is_saved, FALSE) AS is_saved,
       COALESCE(v.is_liked, FALSE) AS is_liked,
       COALESCE(ps.saves_count, 0)::int AS saves_count,
       COALESCE(ps.impressions_count, 0)::int AS impressions_count,
       COALESCE(ps.reel_views_count, 0)::int AS reel_views_count,
       COALESCE(rp.report_count, 0)::int AS report_count,
       asset.provider AS asset_provider,
       asset.stream_uid AS asset_stream_uid,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.playback_url AS asset_playback_url,
       asset.thumbnail_url AS asset_thumbnail_url,
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
     WHERE p.user_id = $2
        AND p.is_deleted = FALSE
        AND p.archived_by_owner_at IS NULL
        AND p.moderation_status = 'approved'
        AND COALESCE(u.is_account_disabled, FALSE) = FALSE
        AND (
          COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
          OR p.user_id = $1
          OR COALESCE(
            (SELECT social_visibility_tier FROM app_user WHERE id = $1),
            'normal'
          ) = 'gray_zone'
        )
        AND (
          COALESCE(p.audience_scope_type, 'global') = 'global'
          OR (
            COALESCE(p.audience_scope_type, '') = 'block'
            AND $5::text IS NOT NULL
            AND p.audience_scope_code = $5::text
          )
          OR (
            COALESCE(p.audience_scope_type, '') = 'compound'
            AND $6::text IS NOT NULL
            AND p.audience_scope_code = $6::text
          )
          OR (
            COALESCE(p.audience_scope_type, '') = 'building'
            AND $7::text IS NOT NULL
            AND p.audience_scope_code = $7::text
          )
        )
        AND ($3::bigint IS NULL OR p.id < $3::bigint)
       AND (
         $4::text IS NULL
         OR (
           $4::text = 'reel'
           AND p.post_kind IN ('reel', 'video')
         )
         OR p.post_kind = $4::text
       )
     ORDER BY p.id DESC
     LIMIT $8`,
    [
      Number(viewerUserId),
      Number(userId),
      beforeId,
      postKind,
      viewerBlockCode == null ? null : String(viewerBlockCode).trim().toUpperCase(),
      viewerCompoundCode == null
        ? null
        : String(viewerCompoundCode).trim().toUpperCase(),
      viewerBuildingCode == null
        ? null
        : String(viewerBuildingCode).trim().toUpperCase(),
      Number(limit),
    ]
  );
  return r.rows;
}

export async function listMyReportedPosts({
  userId,
  limit = 40,
  beforeId = null,
}) {
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.shared_entity_type,
       p.shared_entity_id,
       p.shared_snapshot_json,
       p.merchant_id,
       p.review_rating,
       p.audience_scope_type,
       p.audience_scope_code,
       p.moderation_status,
       p.moderation_note,
       p.moderation_requested_at,
       p.created_at,
       p.updated_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.image_url AS merchant_image_url,
       COALESCE(ps.likes_count, 0)::int AS likes_count,
       COALESCE(ps.comments_count, 0)::int AS comments_count,
       COALESCE(v.is_liked, FALSE) AS is_liked
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     LEFT JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, p.user_id)
      AND rel.user_b_id = GREATEST($1::bigint, p.user_id)
     LEFT JOIN social_post_stats ps ON ps.post_id = p.id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_liked
       FROM social_post_like lv
       WHERE lv.post_id = p.id
         AND lv.user_id = $1
       LIMIT 1
     ) v ON TRUE
     WHERE p.user_id = $1
       AND p.is_deleted = FALSE
       AND p.moderation_status = 'pending'
       AND (p.moderation_note IS NOT NULL AND LENGTH(TRIM(p.moderation_note)) > 0)
       AND ($2::bigint IS NULL OR p.id < $2::bigint)
     ORDER BY p.id DESC
     LIMIT $3`,
    [
      Number(userId),
      beforeId,
      Math.max(1, Math.min(120, Number(limit) || 40)),
    ]
  );
  return r.rows;
}

export async function listMyReportedStories({
  userId,
  limit = 40,
  beforeId = null,
}) {
  const r = await q(
    `SELECT
       s.id,
       s.user_id,
       s.caption,
       s.media_url,
       s.media_kind,
       s.media_asset_id,
       s.story_style,
       s.allow_likes,
       s.allow_private_replies,
       s.allow_comments,
       s.allow_sharing,
       s.allow_reshare,
       s.moderation_status,
       s.moderation_note,
       s.moderation_requested_at,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       asset.provider AS asset_provider,
       asset.stream_uid AS asset_stream_uid,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.playback_url AS asset_playback_url,
       asset.thumbnail_url AS asset_thumbnail_url,
       asset.duration_ms AS asset_duration_ms,
       asset.processing_status AS asset_processing_status,
       (SELECT COUNT(*)::int
          FROM social_story_like sl
         WHERE sl.story_id = s.id) AS likes_count,
       (SELECT COUNT(*)::int
          FROM social_story_comment sc
         WHERE sc.story_id = s.id
           AND sc.is_deleted = FALSE) AS comments_count,
       EXISTS (
         SELECT 1
         FROM social_story_like viewer_like
         WHERE viewer_like.story_id = s.id
           AND viewer_like.user_id = $1
       ) AS is_liked,
       EXISTS (
         SELECT 1
         FROM social_story_view viewer_view
         WHERE viewer_view.story_id = s.id
           AND viewer_view.user_id = $1
       ) AS is_viewed
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_media_asset asset ON asset.id = s.media_asset_id
     WHERE s.user_id = $1
       AND s.is_deleted = FALSE
       AND s.moderation_status = 'pending'
       AND (s.moderation_note IS NOT NULL AND LENGTH(TRIM(s.moderation_note)) > 0)
       AND ($2::bigint IS NULL OR s.id < $2::bigint)
     ORDER BY s.id DESC
     LIMIT $3`,
    [
      Number(userId),
      beforeId,
      Math.max(1, Math.min(120, Number(limit) || 40)),
    ]
  );
  return r.rows;
}

export async function findFeedPostById({
  viewerUserId,
  postId,
  viewerBlockCode = null,
  viewerCompoundCode = null,
  viewerBuildingCode = null,
}) {
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.shared_entity_type,
       p.shared_entity_id,
       p.shared_snapshot_json,
       p.merchant_id,
       p.review_rating,
       p.audience_scope_type,
       p.audience_scope_code,
       p.created_at,
       p.updated_at,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.image_url AS merchant_image_url,
       COALESCE(ps.likes_count, 0)::int AS likes_count,
       COALESCE(ps.comments_count, 0)::int AS comments_count,
       COALESCE(v.is_liked, FALSE) AS is_liked
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     LEFT JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, p.user_id)
      AND rel.user_b_id = GREATEST($1::bigint, p.user_id)
     LEFT JOIN social_post_stats ps ON ps.post_id = p.id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_liked
       FROM social_post_like lv
       WHERE lv.post_id = p.id
         AND lv.user_id = $1
       LIMIT 1
     ) v ON TRUE
      WHERE p.id = $2
        AND p.is_deleted = FALSE
        AND p.archived_by_owner_at IS NULL
        AND p.moderation_status = 'approved'
        AND COALESCE(u.is_account_disabled, FALSE) = FALSE
        AND (
          COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
          OR p.user_id = $1
          OR COALESCE(
            (SELECT social_visibility_tier FROM app_user WHERE id = $1),
            'normal'
          ) = 'gray_zone'
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
     LIMIT 1`,
    [
      Number(viewerUserId),
      Number(postId),
      viewerBlockCode == null ? null : String(viewerBlockCode).trim().toUpperCase(),
      viewerCompoundCode == null
        ? null
        : String(viewerCompoundCode).trim().toUpperCase(),
      viewerBuildingCode == null
        ? null
        : String(viewerBuildingCode).trim().toUpperCase(),
    ]
  );
  return r.rows[0] || null;
}

export async function listActiveStoriesRaw({
  viewerUserId,
  limitRows = 500,
}) {
  const r = await q(
    `SELECT
       s.id,
       s.user_id,
       s.caption,
       s.media_url,
       s.media_kind,
       s.media_asset_id,
       s.story_style,
       s.allow_likes,
       s.allow_private_replies,
       s.allow_comments,
       s.allow_sharing,
       s.allow_reshare,
       s.moderation_status,
       s.moderation_note,
       s.moderation_requested_at,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       asset.provider AS asset_provider,
       asset.stream_uid AS asset_stream_uid,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.playback_url AS asset_playback_url,
       asset.thumbnail_url AS asset_thumbnail_url,
       asset.duration_ms AS asset_duration_ms,
       asset.processing_status AS asset_processing_status,
       (SELECT COUNT(*)::int
          FROM social_story_like sl
         WHERE sl.story_id = s.id) AS likes_count,
       (SELECT COUNT(*)::int
          FROM social_story_comment sc
         WHERE sc.story_id = s.id
           AND sc.is_deleted = FALSE) AS comments_count,
       EXISTS (
         SELECT 1
         FROM social_story_like viewer_like
         WHERE viewer_like.story_id = s.id
           AND viewer_like.user_id = $1
       ) AS is_liked,
       COALESCE(v.story_id IS NOT NULL, FALSE) AS is_viewed
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_media_asset asset ON asset.id = s.media_asset_id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, s.user_id)
      AND rel.user_b_id = GREATEST($1::bigint, s.user_id)
     LEFT JOIN social_story_view v
       ON v.story_id = s.id
      AND v.user_id = $1
      WHERE s.is_deleted = FALSE
        AND s.archived_by_owner_at IS NULL
        AND s.moderation_status = 'approved'
        AND COALESCE(u.is_account_disabled, FALSE) = FALSE
        AND (
          COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
          OR s.user_id = $1
          OR COALESCE(
            (SELECT social_visibility_tier FROM app_user WHERE id = $1),
            'normal'
          ) = 'gray_zone'
       )
       AND s.expires_at > NOW()
       AND (
         s.user_id = $1
         OR COALESCE(u.is_super_admin, FALSE) = TRUE
         OR COALESCE(
           (SELECT is_super_admin FROM app_user WHERE id = $1),
           FALSE
         ) = TRUE
         OR (
           u.social_stories_public = TRUE
           AND (
             COALESCE(u.social_account_private, FALSE) = FALSE
             OR COALESCE(rel.status, '') = 'accepted'
           )
         )
       )
     ORDER BY s.created_at DESC, s.id DESC
     LIMIT $2`,
    [Number(viewerUserId), Number(limitRows)]
  );
  return r.rows;
}

export async function listArchivedStoriesRaw({
  viewerUserId,
  ownerUserId,
  beforeId = null,
  limit = 40,
}) {
  const r = await q(
    `SELECT
       s.id,
       s.user_id,
       s.caption,
       s.media_url,
       s.media_kind,
       s.media_asset_id,
       s.story_style,
       s.archived_by_owner_at,
       s.allow_likes,
       s.allow_private_replies,
       s.allow_comments,
       s.allow_sharing,
       s.allow_reshare,
       s.moderation_status,
       s.moderation_note,
       s.moderation_requested_at,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       asset.provider AS asset_provider,
       asset.stream_uid AS asset_stream_uid,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.playback_url AS asset_playback_url,
       asset.thumbnail_url AS asset_thumbnail_url,
       asset.duration_ms AS asset_duration_ms,
       asset.processing_status AS asset_processing_status,
       (SELECT COUNT(*)::int
          FROM social_story_like sl
         WHERE sl.story_id = s.id) AS likes_count,
       (SELECT COUNT(*)::int
          FROM social_story_comment sc
         WHERE sc.story_id = s.id
           AND sc.is_deleted = FALSE) AS comments_count,
       EXISTS (
         SELECT 1
         FROM social_story_like viewer_like
         WHERE viewer_like.story_id = s.id
           AND viewer_like.user_id = $1
       ) AS is_liked,
       COALESCE(v.story_id IS NOT NULL, FALSE) AS is_viewed
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_media_asset asset ON asset.id = s.media_asset_id
     LEFT JOIN social_story_view v
       ON v.story_id = s.id
      AND v.user_id = $1
      WHERE s.user_id = $2
        AND s.is_deleted = FALSE
        AND s.moderation_status = 'approved'
        AND COALESCE(u.is_account_disabled, FALSE) = FALSE
        AND (
          COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
          OR s.user_id = $1
          OR COALESCE(
            (SELECT social_visibility_tier FROM app_user WHERE id = $1),
            'normal'
          ) = 'gray_zone'
        )
        AND (
          s.archived_by_owner_at IS NOT NULL
          OR s.expires_at <= NOW()
        )
       AND ($3::bigint IS NULL OR s.id < $3::bigint)
     ORDER BY COALESCE(s.archived_by_owner_at, s.expires_at) DESC, s.id DESC
     LIMIT $4`,
    [
      Number(viewerUserId),
      Number(ownerUserId),
      beforeId == null ? null : Number(beforeId),
      Number(limit),
    ]
  );
  return r.rows;
}

export async function listUserHighlightsRaw({
  viewerUserId,
  ownerUserId,
  limit = 40,
}) {
  const r = await q(
    `SELECT
       h.id AS highlight_id,
       h.owner_user_id,
       h.title AS highlight_title,
       h.created_at AS highlight_created_at,
       s.id,
       s.user_id,
       s.caption,
       s.media_url,
       s.media_kind,
       s.media_asset_id,
       s.story_style,
       s.allow_likes,
       s.allow_private_replies,
       s.allow_comments,
       s.allow_sharing,
       s.allow_reshare,
       s.moderation_status,
       s.moderation_note,
       s.moderation_requested_at,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       asset.provider AS asset_provider,
       asset.stream_uid AS asset_stream_uid,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.playback_url AS asset_playback_url,
       asset.thumbnail_url AS asset_thumbnail_url,
       asset.duration_ms AS asset_duration_ms,
       asset.processing_status AS asset_processing_status,
       (SELECT COUNT(*)::int
          FROM social_story_like sl
         WHERE sl.story_id = s.id) AS likes_count,
       (SELECT COUNT(*)::int
          FROM social_story_comment sc
         WHERE sc.story_id = s.id
           AND sc.is_deleted = FALSE) AS comments_count,
       EXISTS (
         SELECT 1
         FROM social_story_like viewer_like
         WHERE viewer_like.story_id = s.id
           AND viewer_like.user_id = $1
       ) AS is_liked,
       COALESCE(v.story_id IS NOT NULL, FALSE) AS is_viewed
     FROM social_story_highlight h
     JOIN social_story s ON s.id = h.story_id
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_media_asset asset ON asset.id = s.media_asset_id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, s.user_id)
      AND rel.user_b_id = GREATEST($1::bigint, s.user_id)
     LEFT JOIN social_story_view v
       ON v.story_id = s.id
      AND v.user_id = $1
      WHERE h.owner_user_id = $2
        AND s.is_deleted = FALSE
        AND s.archived_by_owner_at IS NULL
        AND s.moderation_status = 'approved'
        AND COALESCE(u.is_account_disabled, FALSE) = FALSE
        AND (
          COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
          OR s.user_id = $1
          OR COALESCE(
            (SELECT social_visibility_tier FROM app_user WHERE id = $1),
            'normal'
          ) = 'gray_zone'
        )
        AND (
          s.user_id = $1
          OR COALESCE(u.is_super_admin, FALSE) = TRUE
          OR COALESCE(
            (SELECT is_super_admin FROM app_user WHERE id = $1),
            FALSE
          ) = TRUE
          OR (
            u.social_stories_public = TRUE
            AND (
              COALESCE(u.social_account_private, FALSE) = FALSE
              OR COALESCE(rel.status, '') = 'accepted'
            )
          )
        )
      ORDER BY h.id DESC
     LIMIT $3`,
    [Number(viewerUserId), Number(ownerUserId), Number(limit)]
  );
  return r.rows;
}

export async function upsertStoryHighlight({
  ownerUserId,
  storyId,
  title = null,
}) {
  const normalizedTitle = typeof title === "string" ? title.trim() : "";
  const r = await q(
    `INSERT INTO social_story_highlight
      (owner_user_id, story_id, title)
     VALUES ($1, $2, $3)
     ON CONFLICT (owner_user_id, story_id)
     DO UPDATE SET
       title = COALESCE(NULLIF(EXCLUDED.title, ''), social_story_highlight.title),
       updated_at = NOW()
     RETURNING *`,
    [Number(ownerUserId), Number(storyId), normalizedTitle]
  );
  return r.rows[0] || null;
}

export async function findHighlightById({ viewerUserId, highlightId }) {
  const r = await q(
    `SELECT
       h.id AS highlight_id,
       h.owner_user_id,
       h.title AS highlight_title,
       h.created_at AS highlight_created_at,
       s.id,
       s.user_id,
       s.caption,
       s.media_url,
       s.media_kind,
       s.media_asset_id,
       s.story_style,
       s.allow_likes,
       s.allow_private_replies,
       s.allow_comments,
       s.allow_sharing,
       s.allow_reshare,
       s.moderation_status,
       s.moderation_note,
       s.moderation_requested_at,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       asset.provider AS asset_provider,
       asset.stream_uid AS asset_stream_uid,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.playback_url AS asset_playback_url,
       asset.thumbnail_url AS asset_thumbnail_url,
       asset.duration_ms AS asset_duration_ms,
       asset.processing_status AS asset_processing_status,
       (SELECT COUNT(*)::int
          FROM social_story_like sl
         WHERE sl.story_id = s.id) AS likes_count,
       (SELECT COUNT(*)::int
          FROM social_story_comment sc
         WHERE sc.story_id = s.id
           AND sc.is_deleted = FALSE) AS comments_count,
       EXISTS (
         SELECT 1
         FROM social_story_like viewer_like
         WHERE viewer_like.story_id = s.id
           AND viewer_like.user_id = $1
       ) AS is_liked,
       COALESCE(v.story_id IS NOT NULL, FALSE) AS is_viewed
     FROM social_story_highlight h
     JOIN social_story s ON s.id = h.story_id
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_media_asset asset ON asset.id = s.media_asset_id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, s.user_id)
      AND rel.user_b_id = GREATEST($1::bigint, s.user_id)
     LEFT JOIN social_story_view v
       ON v.story_id = s.id
      AND v.user_id = $1
      WHERE h.id = $2
        AND s.is_deleted = FALSE
        AND s.archived_by_owner_at IS NULL
        AND s.moderation_status = 'approved'
        AND COALESCE(u.is_account_disabled, FALSE) = FALSE
        AND (
          COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
          OR s.user_id = $1
          OR COALESCE(
            (SELECT social_visibility_tier FROM app_user WHERE id = $1),
            'normal'
          ) = 'gray_zone'
        )
        AND (
          s.user_id = $1
          OR COALESCE(u.is_super_admin, FALSE) = TRUE
          OR COALESCE(
            (SELECT is_super_admin FROM app_user WHERE id = $1),
            FALSE
          ) = TRUE
          OR (
            u.social_stories_public = TRUE
            AND (
              COALESCE(u.social_account_private, FALSE) = FALSE
              OR COALESCE(rel.status, '') = 'accepted'
            )
          )
        )
      LIMIT 1`,
    [Number(viewerUserId), Number(highlightId)]
  );
  return r.rows[0] || null;
}

export async function deleteStoryHighlight({ ownerUserId, highlightId }) {
  const r = await q(
    `DELETE FROM social_story_highlight
     WHERE id = $1
       AND owner_user_id = $2
     RETURNING id`,
    [Number(highlightId), Number(ownerUserId)]
  );
  return r.rows[0] || null;
}

export async function insertStory({
  userId,
  caption,
  mediaUrl = null,
  mediaKind = null,
  mediaAssetId = null,
  storyStyle = {},
  allowLikes = true,
  allowPrivateReplies = true,
  allowComments = true,
  allowSharing = true,
  allowReshare = true,
}) {
  const r = await q(
    `INSERT INTO social_story
      (
        user_id,
        caption,
        media_url,
        media_kind,
        media_asset_id,
        story_style,
        allow_likes,
        allow_private_replies,
        allow_comments,
        allow_sharing,
        allow_reshare,
        moderation_status
      )
     VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9, $10, $11, 'approved')
     RETURNING *`,
    [
      Number(userId),
      caption || null,
      mediaUrl,
      mediaKind,
      mediaAssetId == null ? null : Number(mediaAssetId),
      JSON.stringify(storyStyle && typeof storyStyle === "object" ? storyStyle : {}),
      allowLikes !== false,
      allowPrivateReplies !== false,
      allowComments !== false,
      allowSharing !== false,
      allowReshare !== false,
    ]
  );
  return r.rows[0] || null;
}

/// Idempotency lookup: the most recent story this user created from a given
/// media asset. Used so a create retry with the same mediaAssetId returns the
/// existing Story instead of inserting a duplicate.
export async function findStoryIdByOwnerAndAsset(userId, mediaAssetId) {
  if (mediaAssetId == null) return null;
  const r = await q(
    `SELECT id FROM social_story
      WHERE user_id = $1 AND media_asset_id = $2
      ORDER BY id DESC
      LIMIT 1`,
    [Number(userId), Number(mediaAssetId)]
  );
  return r.rows[0]?.id == null ? null : Number(r.rows[0].id);
}

/// Idempotency lookup for reels/posts created from a given media asset.
export async function findPostIdByOwnerAndAsset(userId, mediaAssetId) {
  if (mediaAssetId == null) return null;
  const r = await q(
    `SELECT id
       FROM social_post
      WHERE user_id = $1
        AND media_asset_id = $2
        AND post_kind = 'reel'
      ORDER BY id DESC
      LIMIT 1`,
    [Number(userId), Number(mediaAssetId)]
  );
  return r.rows[0]?.id == null ? null : Number(r.rows[0].id);
}

export async function findPostIdByOwnerAndSharedEntity({
  userId,
  postKind = null,
  sharedEntityType,
  sharedEntityId,
}) {
  if (!sharedEntityType || !Number.isInteger(Number(sharedEntityId))) return null;
  const r = await q(
    `SELECT id
       FROM social_post
      WHERE user_id = $1
        AND is_deleted = FALSE
        AND COALESCE(shared_entity_type, '') = $2
        AND shared_entity_id = $3
        AND ($4::text IS NULL OR post_kind = $4::text)
      ORDER BY id DESC
      LIMIT 1`,
    [
      Number(userId),
      String(sharedEntityType || "").trim().toLowerCase(),
      Number(sharedEntityId),
      postKind == null ? null : String(postKind).trim().toLowerCase(),
    ]
  );
  return r.rows[0]?.id == null ? null : Number(r.rows[0].id);
}

export async function findStoryById({
  viewerUserId,
  storyId,
  includeArchivedForOwner = false,
}) {
  const r = await q(
    `SELECT
       s.id,
       s.user_id,
       s.caption,
       s.media_url,
       s.media_kind,
       s.media_asset_id,
       s.story_style,
       s.allow_likes,
       s.allow_private_replies,
       s.allow_comments,
       s.allow_sharing,
       s.allow_reshare,
       s.archived_by_owner_at,
       s.moderation_status,
       s.moderation_note,
       s.moderation_requested_at,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       asset.provider AS asset_provider,
       asset.stream_uid AS asset_stream_uid,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.playback_url AS asset_playback_url,
       asset.thumbnail_url AS asset_thumbnail_url,
       asset.duration_ms AS asset_duration_ms,
       asset.processing_status AS asset_processing_status,
       (SELECT COUNT(*)::int
          FROM social_story_like sl
         WHERE sl.story_id = s.id) AS likes_count,
       (SELECT COUNT(*)::int
          FROM social_story_comment sc
         WHERE sc.story_id = s.id
           AND sc.is_deleted = FALSE) AS comments_count,
       EXISTS (
         SELECT 1
         FROM social_story_like viewer_like
         WHERE viewer_like.story_id = s.id
           AND viewer_like.user_id = $1
       ) AS is_liked,
       COALESCE(v.story_id IS NOT NULL, FALSE) AS is_viewed
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_media_asset asset ON asset.id = s.media_asset_id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, s.user_id)
      AND rel.user_b_id = GREATEST($1::bigint, s.user_id)
     LEFT JOIN social_story_view v
       ON v.story_id = s.id
      AND v.user_id = $1
      WHERE s.id = $2
        AND s.is_deleted = FALSE
        AND (
          s.archived_by_owner_at IS NULL
          OR ($3::boolean = TRUE AND s.user_id = $1)
        )
        AND s.moderation_status = 'approved'
        AND COALESCE(u.is_account_disabled, FALSE) = FALSE
        AND (
          COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
          OR s.user_id = $1
          OR COALESCE(
            (SELECT social_visibility_tier FROM app_user WHERE id = $1),
            'normal'
          ) = 'gray_zone'
        )
        AND (
          s.user_id = $1
          OR COALESCE(u.is_super_admin, FALSE) = TRUE
          OR COALESCE(
            (SELECT is_super_admin FROM app_user WHERE id = $1),
            FALSE
          ) = TRUE
          OR (
            u.social_stories_public = TRUE
            AND (
              COALESCE(u.social_account_private, FALSE) = FALSE
              OR COALESCE(rel.status, '') = 'accepted'
            )
          )
        )
        AND (
          s.expires_at > NOW()
          OR ($3::boolean = TRUE AND s.user_id = $1)
        )
     LIMIT 1`,
    [Number(viewerUserId), Number(storyId), includeArchivedForOwner === true]
  );
  return r.rows[0] || null;
}

export async function findStoryForHighlight({ ownerUserId, storyId }) {
  const r = await q(
    `SELECT
       s.id,
       s.user_id,
       s.caption,
       s.media_url,
       s.media_kind,
       s.media_asset_id,
       s.story_style,
       s.allow_likes,
       s.allow_private_replies,
       s.allow_comments,
       s.allow_sharing,
       s.allow_reshare,
       s.moderation_status,
       s.moderation_note,
       s.moderation_requested_at,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       asset.provider AS asset_provider,
       asset.stream_uid AS asset_stream_uid,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.playback_url AS asset_playback_url,
       asset.thumbnail_url AS asset_thumbnail_url,
       asset.duration_ms AS asset_duration_ms,
       asset.processing_status AS asset_processing_status,
       (SELECT COUNT(*)::int
          FROM social_story_like sl
         WHERE sl.story_id = s.id) AS likes_count,
       (SELECT COUNT(*)::int
          FROM social_story_comment sc
         WHERE sc.story_id = s.id
           AND sc.is_deleted = FALSE) AS comments_count,
       EXISTS (
         SELECT 1
         FROM social_story_like viewer_like
         WHERE viewer_like.story_id = s.id
           AND viewer_like.user_id = $2
       ) AS is_liked,
       EXISTS (
         SELECT 1
         FROM social_story_view viewer_view
         WHERE viewer_view.story_id = s.id
           AND viewer_view.user_id = $2
       ) AS is_viewed
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_media_asset asset ON asset.id = s.media_asset_id
     WHERE s.id = $1
       AND s.user_id = $2
       AND s.is_deleted = FALSE
       AND s.archived_by_owner_at IS NULL
       AND s.moderation_status = 'approved'
     LIMIT 1`,
    [Number(storyId), Number(ownerUserId)]
  );
  return r.rows[0] || null;
}

export async function markStoryViewed({ storyId, userId }) {
  await q(
    `INSERT INTO social_story_view (story_id, user_id, viewed_at)
     VALUES ($1, $2, NOW())
     ON CONFLICT (story_id, user_id)
     DO UPDATE SET viewed_at = EXCLUDED.viewed_at`,
    [Number(storyId), Number(userId)]
  );
}

export async function hasStoryLike({ storyId, userId }) {
  const r = await q(
    `SELECT 1
     FROM social_story_like
     WHERE story_id = $1
       AND user_id = $2
     LIMIT 1`,
    [Number(storyId), Number(userId)]
  );
  return (r.rowCount || 0) > 0;
}

export async function addStoryLike({ storyId, userId }) {
  await q(
    `INSERT INTO social_story_like (story_id, user_id)
     VALUES ($1, $2)
     ON CONFLICT (story_id, user_id) DO NOTHING`,
    [Number(storyId), Number(userId)]
  );
}

export async function removeStoryLike({ storyId, userId }) {
  await q(
    `DELETE FROM social_story_like
     WHERE story_id = $1
       AND user_id = $2`,
    [Number(storyId), Number(userId)]
  );
}

export async function countStoryLikes(storyId) {
  const r = await q(
    `SELECT COUNT(*)::int AS likes_count
     FROM social_story_like
     WHERE story_id = $1`,
    [Number(storyId)]
  );
  return Number(r.rows[0]?.likes_count || 0);
}

export async function countStoryComments(storyId) {
  const r = await q(
    `SELECT COUNT(*)::int AS comments_count
     FROM social_story_comment
     WHERE story_id = $1
       AND is_deleted = FALSE`,
    [Number(storyId)]
  );
  return Number(r.rows[0]?.comments_count || 0);
}

export async function setStoryArchivedState({
  storyId,
  userId,
  archived,
}) {
  const r = await q(
    `UPDATE social_story
     SET archived_by_owner_at = CASE WHEN $3::boolean = TRUE THEN NOW() ELSE NULL END,
         updated_at = NOW()
     WHERE id = $1
       AND user_id = $2
       AND is_deleted = FALSE
     RETURNING *`,
    [Number(storyId), Number(userId), archived === true]
  );
  return r.rows[0] || null;
}

export async function listStoryComments({
  storyId,
  viewerUserId,
  limit = 40,
  beforeId = null,
}) {
  const r = await q(
    `SELECT
       c.id,
       c.story_id,
       c.user_id,
       c.body,
       c.is_deleted,
       c.created_at,
       c.updated_at,
       c.edited_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.role AS user_role,
       u.image_url AS user_image_url
     FROM social_story_comment c
     JOIN app_user u ON u.id = c.user_id
     WHERE c.story_id = $1
       AND ($2::bigint IS NULL OR c.id < $2::bigint)
     ORDER BY c.id DESC
     LIMIT $3`,
    [Number(storyId), beforeId, Number(limit)]
  );
  return r.rows;
}

export async function insertStoryComment({ storyId, userId, body }) {
  const r = await q(
    `INSERT INTO social_story_comment (story_id, user_id, body)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [Number(storyId), Number(userId), String(body || "").trim()]
  );
  return r.rows[0] || null;
}

export async function insertStoryReport({
  storyId,
  reporterUserId,
  reason,
  details = null,
}) {
  const r = await q(
    `INSERT INTO social_story_report (story_id, reporter_user_id, reason, details)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (story_id, reporter_user_id)
     DO UPDATE SET
       reason = EXCLUDED.reason,
       details = EXCLUDED.details,
       created_at = NOW()
     RETURNING id`,
    [
      Number(storyId),
      Number(reporterUserId),
      String(reason || "").trim(),
      details == null ? null : String(details).trim() || null,
    ]
  );
  return r.rows[0] || null;
}

export async function listAudienceUserIdsForActor({
  actorUserId,
  broadcastToAll = false,
  limit = 4000,
}) {
  const r = await q(
    `SELECT u.id
     FROM app_user u
     WHERE u.id <> $1
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND (
         $2::boolean = TRUE
         OR EXISTS (
           SELECT 1
           FROM social_user_relation rel
           WHERE rel.status = 'accepted'
             AND (
               (rel.user_a_id = $1 AND rel.user_b_id = u.id)
               OR (rel.user_b_id = $1 AND rel.user_a_id = u.id)
             )
         )
       )
       AND NOT EXISTS (
         SELECT 1
         FROM social_user_notification_pref pref
         WHERE pref.user_id = u.id
           AND pref.actor_user_id = $1
           AND pref.muted = TRUE
       )
     ORDER BY u.id DESC
     LIMIT $3`,
    [
      Number(actorUserId),
      broadcastToAll === true,
      Math.max(1, Math.min(12000, Number(limit) || 4000)),
    ]
  );
  return r.rows.map((row) => Number(row.id)).filter((id) => id > 0);
}

export async function listStoryAudienceUserIds({
  excludeUserId,
  limit = 1500,
}) {
  return listAudienceUserIdsForActor({
    actorUserId: excludeUserId,
    broadcastToAll: true,
    limit,
  });
}

export async function insertPost({
  userId,
  postKind,
  caption,
  mediaUrl = null,
  mediaKind = null,
  mediaAssetId = null,
  merchantId = null,
  reviewRating = null,
  sharedEntity = null,
  audienceScopeType = "global",
  audienceScopeCode = null,
}) {
  const r = await q(
    `INSERT INTO social_post
      (
        user_id,
        post_kind,
        caption,
        media_url,
        media_kind,
        media_asset_id,
        merchant_id,
        review_rating,
        shared_entity_type,
        shared_entity_id,
        shared_snapshot_json,
        audience_scope_type,
        audience_scope_code,
        moderation_status
      )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, 'approved')
     RETURNING *`,
    [
      Number(userId),
      postKind,
      caption || null,
      mediaUrl,
      mediaKind,
      mediaAssetId == null ? null : Number(mediaAssetId),
      merchantId == null ? null : Number(merchantId),
      reviewRating == null ? null : Number(reviewRating),
      sharedEntity?.type || null,
      sharedEntity?.id == null ? null : Number(sharedEntity.id),
      sharedEntity?.snapshot == null ? null : JSON.stringify(sharedEntity.snapshot),
      String(audienceScopeType || "global").trim().toLowerCase(),
      audienceScopeCode == null ? null : String(audienceScopeCode).trim().toUpperCase(),
    ]
  );
  return r.rows[0] || null;
}

export async function replacePostMediaItems({ postId, items = [] }) {
  await q(`DELETE FROM social_post_media WHERE post_id = $1`, [Number(postId)]);
  if (!Array.isArray(items) || items.length <= 0) {
    return [];
  }

  const inserted = [];
  for (let index = 0; index < items.length; index += 1) {
    const item = items[index] || {};
    const r = await q(
      `INSERT INTO social_post_media
        (
          post_id,
          sort_order,
          media_url,
          media_kind,
          media_asset_id
        )
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [
        Number(postId),
        index,
        String(item.mediaUrl || "").trim(),
        String(item.mediaKind || "image").trim().toLowerCase(),
        item.mediaAssetId == null ? null : Number(item.mediaAssetId),
      ]
    );
    if (r.rows[0]) inserted.push(r.rows[0]);
  }
  return inserted;
}

export async function listPostMediaItemsByPostIds(postIds = []) {
  const normalized = [
    ...new Set(
      (Array.isArray(postIds) ? postIds : [])
        .map((value) => Number(value))
        .filter((value) => Number.isFinite(value) && value > 0)
    ),
  ];
  if (normalized.length <= 0) return [];

  const r = await q(
    `SELECT
       pm.id,
       pm.post_id,
       pm.sort_order,
       pm.media_url,
       pm.media_kind,
       pm.media_asset_id,
       asset.provider AS asset_provider,
       asset.stream_uid AS asset_stream_uid,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.playback_url AS asset_playback_url,
       asset.thumbnail_url AS asset_thumbnail_url,
       asset.duration_ms AS asset_duration_ms,
       asset.processing_status AS asset_processing_status
     FROM social_post_media pm
     LEFT JOIN social_media_asset asset ON asset.id = pm.media_asset_id
     WHERE pm.post_id = ANY($1::bigint[])
     ORDER BY pm.post_id ASC, pm.sort_order ASC, pm.id ASC`,
    [normalized]
  );
  return r.rows;
}

export async function setPostArchivedState({
  postId,
  userId,
  archived,
}) {
  const r = await q(
    `UPDATE social_post
     SET archived_by_owner_at = CASE WHEN $3::boolean = TRUE THEN NOW() ELSE NULL END,
         updated_at = NOW()
     WHERE id = $1
       AND user_id = $2
       AND is_deleted = FALSE
     RETURNING *`,
    [Number(postId), Number(userId), archived === true]
  );
  return r.rows[0] || null;
}

export async function softDeletePost({ postId, userId }) {
  const r = await q(
    `UPDATE social_post
     SET is_deleted = TRUE,
         updated_at = NOW()
     WHERE id = $1
       AND user_id = $2
       AND is_deleted = FALSE
     RETURNING id`,
    [Number(postId), Number(userId)]
  );
  return r.rows[0] || null;
}

export async function listArchivedPostsRaw({
  viewerUserId,
  ownerUserId,
  limit = 24,
  beforeId = null,
  postKind = null,
}) {
  if (Number(viewerUserId) !== Number(ownerUserId)) return [];
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.shared_entity_type,
       p.shared_entity_id,
       p.shared_snapshot_json,
       p.media_asset_id,
       p.merchant_id,
       p.review_rating,
       p.audience_scope_type,
       p.audience_scope_code,
       p.archived_by_owner_at,
       p.created_at,
       p.updated_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
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
       COALESCE(ps.likes_count, 0)::int AS likes_count,
       COALESCE(ps.comments_count, 0)::int AS comments_count,
       COALESCE(sv.is_saved, FALSE) AS is_saved,
       COALESCE(v.is_liked, FALSE) AS is_liked,
       COALESCE(ps.saves_count, 0)::int AS saves_count,
       COALESCE(ps.impressions_count, 0)::int AS impressions_count,
       COALESCE(ps.reel_views_count, 0)::int AS reel_views_count,
       COALESCE(rp.report_count, 0)::int AS report_count,
       asset.provider AS asset_provider,
       asset.stream_uid AS asset_stream_uid,
       asset.normalized_url AS asset_normalized_url,
       asset.poster_url AS asset_poster_url,
       asset.playback_url AS asset_playback_url,
       asset.thumbnail_url AS asset_thumbnail_url,
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
     WHERE p.user_id = $2
       AND p.is_deleted = FALSE
       AND p.moderation_status = 'approved'
       AND p.archived_by_owner_at IS NOT NULL
       AND ($3::bigint IS NULL OR p.id < $3::bigint)
       AND (
         $4::text IS NULL
         OR (
           $4::text = 'reel'
           AND p.post_kind IN ('reel', 'video')
         )
         OR p.post_kind = $4::text
       )
     ORDER BY p.archived_by_owner_at DESC, p.id DESC
     LIMIT $5`,
    [
      Number(viewerUserId),
      Number(ownerUserId),
      beforeId == null ? null : Number(beforeId),
      postKind == null ? null : String(postKind).trim().toLowerCase(),
      Number(limit),
    ]
  );
  return r.rows;
}

export async function updatePostAfterEditRequest({
  postId,
  userId,
  caption,
  mediaUrl = null,
  mediaKind = null,
  postKind = null,
}) {
  const r = await q(
    `UPDATE social_post
     SET caption = $3,
         media_url = $4,
         media_kind = $5,
         post_kind = $6,
         updated_at = NOW(),
         moderation_requested_at = NOW()
     WHERE id = $1
       AND user_id = $2
       AND is_deleted = FALSE
       AND moderation_status = 'pending'
     RETURNING *`,
    [
      Number(postId),
      Number(userId),
      caption == null ? null : String(caption || "").trim(),
      mediaUrl,
      mediaKind,
      postKind == null ? null : String(postKind).trim().toLowerCase(),
    ]
  );
  return r.rows[0] || null;
}

export async function findStoryForOwnerEdit({ storyId, ownerUserId }) {
  const r = await q(
    `SELECT
       s.*,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     WHERE s.id = $1
       AND s.user_id = $2
       AND s.is_deleted = FALSE
     LIMIT 1`,
    [Number(storyId), Number(ownerUserId)]
  );
  return r.rows[0] || null;
}

export async function updateStoryAfterEditRequest({
  storyId,
  userId,
  caption,
  mediaUrl = null,
  mediaKind = null,
}) {
  const r = await q(
    `UPDATE social_story
     SET caption = $3,
         media_url = $4,
         media_kind = $5,
         updated_at = NOW(),
         moderation_requested_at = NOW()
     WHERE id = $1
       AND user_id = $2
       AND is_deleted = FALSE
       AND moderation_status = 'pending'
     RETURNING *`,
    [
      Number(storyId),
      Number(userId),
      caption == null ? null : String(caption || "").trim(),
      mediaUrl,
      mediaKind,
    ]
  );
  return r.rows[0] || null;
}

export async function findPostById(postId) {
  const r = await q(
    `SELECT
     p.*,
     u.full_name AS user_full_name,
     u.phone AS user_phone,
     u.role AS user_role,
     u.image_url AS user_image_url,
     u.social_posts_public AS user_posts_public,
     m.name AS merchant_name,
     m.type AS merchant_type,
     m.image_url AS merchant_image_url,
     asset.provider AS asset_provider,
     asset.stream_uid AS asset_stream_uid,
     asset.normalized_url AS asset_normalized_url,
     asset.poster_url AS asset_poster_url,
     asset.playback_url AS asset_playback_url,
     asset.thumbnail_url AS asset_thumbnail_url,
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
       ON scl.entity_type = 'post'
      AND scl.entity_id = p.id
     WHERE p.id = $1
       AND p.is_deleted = FALSE
       AND p.archived_by_owner_at IS NULL
     LIMIT 1`,
    [Number(postId)]
  );
  return r.rows[0] || null;
}

export async function findPostByIdForViewer({
  postId,
  viewerUserId,
  includeArchivedForOwner = false,
}) {
  const r = await q(
    `SELECT
       p.*,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.role AS user_role,
       u.image_url AS user_image_url,
     u.social_posts_public AS user_posts_public,
     m.name AS merchant_name,
     m.type AS merchant_type,
     m.image_url AS merchant_image_url,
     asset.provider AS asset_provider,
     asset.stream_uid AS asset_stream_uid,
     asset.normalized_url AS asset_normalized_url,
     asset.poster_url AS asset_poster_url,
     asset.playback_url AS asset_playback_url,
     asset.thumbnail_url AS asset_thumbnail_url,
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
     WHERE p.id = $1
       AND p.is_deleted = FALSE
       AND (
         p.archived_by_owner_at IS NULL
         OR ($3::boolean = TRUE AND p.user_id = $2)
       )
     LIMIT 1`,
    [
      Number(postId),
      Number(viewerUserId),
      includeArchivedForOwner === true,
    ]
  );
  return r.rows[0] || null;
}

export async function hasLike(postId, userId) {
  const r = await q(
    `SELECT 1
     FROM social_post_like
     WHERE post_id = $1
       AND user_id = $2
     LIMIT 1`,
    [Number(postId), Number(userId)]
  );
  return (r.rowCount || 0) > 0;
}

export async function addLike(postId, userId) {
  await q(
    `INSERT INTO social_post_like (post_id, user_id)
     VALUES ($1, $2)
     ON CONFLICT (post_id, user_id) DO NOTHING`,
    [Number(postId), Number(userId)]
  );
}

export async function removeLike(postId, userId) {
  await q(
    `DELETE FROM social_post_like
     WHERE post_id = $1
       AND user_id = $2`,
    [Number(postId), Number(userId)]
  );
}

export async function countPostLikes(postId) {
  const r = await q(
    `SELECT COUNT(*)::int AS likes_count
     FROM social_post_like
     WHERE post_id = $1`,
    [Number(postId)]
  );
  return Number(r.rows[0]?.likes_count || 0);
}

export async function listPostLikers({
  viewerUserId,
  postId,
  limit = 120,
}) {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.role,
       u.image_url,
       u.social_show_phone,
       l.created_at AS liked_at,
       rel.user_a_id,
       rel.user_b_id,
       rel.initiator_user_id,
       rel.status,
       rel.requested_at,
       rel.responded_at,
       rel.updated_at
     FROM social_post_like l
     JOIN app_user u ON u.id = l.user_id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, u.id)
      AND rel.user_b_id = GREATEST($1::bigint, u.id)
     WHERE l.post_id = $2
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
     ORDER BY l.created_at DESC, u.id DESC
     LIMIT $3`,
    [
      Number(viewerUserId),
      Number(postId),
      Math.max(1, Math.min(200, Number(limit) || 120)),
    ]
  );
  return r.rows;
}

export async function listPostsLikedByUser({
  viewerUserId,
  targetUserId,
  viewerBlockCode = null,
  viewerCompoundCode = null,
  viewerBuildingCode = null,
  limit = 20,
  beforeId = null,
  postKind = null,
}) {
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.shared_entity_type,
       p.shared_entity_id,
       p.shared_snapshot_json,
       p.merchant_id,
       p.review_rating,
       p.audience_scope_type,
       p.audience_scope_code,
       p.created_at,
       p.updated_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.image_url AS merchant_image_url,
       COALESCE(ps.likes_count, 0)::int AS likes_count,
       COALESCE(ps.comments_count, 0)::int AS comments_count,
       COALESCE(v.is_liked, FALSE) AS is_liked
     FROM social_post_like tl
     JOIN social_post p ON p.id = tl.post_id
     JOIN app_user u ON u.id = p.user_id
     LEFT JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, p.user_id)
      AND rel.user_b_id = GREATEST($1::bigint, p.user_id)
     LEFT JOIN social_post_stats ps ON ps.post_id = p.id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_liked
       FROM social_post_like lv
       WHERE lv.post_id = p.id
         AND lv.user_id = $1
       LIMIT 1
     ) v ON TRUE
     WHERE tl.user_id = $2
       AND p.is_deleted = FALSE
       AND p.archived_by_owner_at IS NULL
       AND p.moderation_status = 'approved'
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND (
         COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
         OR p.user_id = $1
         OR COALESCE(
           (SELECT social_visibility_tier FROM app_user WHERE id = $1),
           'normal'
         ) = 'gray_zone'
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
           AND $5::text IS NOT NULL
           AND p.audience_scope_code = $5::text
         )
         OR (
           COALESCE(p.audience_scope_type, '') = 'compound'
           AND $6::text IS NOT NULL
           AND p.audience_scope_code = $6::text
         )
         OR (
           COALESCE(p.audience_scope_type, '') = 'building'
           AND $7::text IS NOT NULL
           AND p.audience_scope_code = $7::text
         )
       )
       AND ($3::bigint IS NULL OR p.id < $3::bigint)
       AND ($4::text IS NULL OR p.post_kind = $4::text)
     ORDER BY tl.created_at DESC, p.id DESC
     LIMIT $8`,
    [
      Number(viewerUserId),
      Number(targetUserId),
      beforeId,
      postKind,
      viewerBlockCode == null ? null : String(viewerBlockCode).trim().toUpperCase(),
      viewerCompoundCode == null
        ? null
        : String(viewerCompoundCode).trim().toUpperCase(),
      viewerBuildingCode == null
        ? null
        : String(viewerBuildingCode).trim().toUpperCase(),
      Number(limit),
    ]
  );
  return r.rows;
}

export async function listPostsCommentedByUser({
  viewerUserId,
  targetUserId,
  viewerBlockCode = null,
  viewerCompoundCode = null,
  viewerBuildingCode = null,
  limit = 20,
  beforeId = null,
  postKind = null,
}) {
  const r = await q(
    `WITH user_comments AS (
       SELECT
         c.post_id,
         MAX(c.id) AS latest_comment_id
       FROM social_post_comment c
       WHERE c.user_id = $2
         AND c.is_deleted = FALSE
         AND c.moderation_status = 'approved'
       GROUP BY c.post_id
     )
     SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.shared_entity_type,
       p.shared_entity_id,
       p.shared_snapshot_json,
       p.merchant_id,
       p.review_rating,
       p.audience_scope_type,
       p.audience_scope_code,
       p.created_at,
       p.updated_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.image_url AS merchant_image_url,
       COALESCE(ps.likes_count, 0)::int AS likes_count,
       COALESCE(ps.comments_count, 0)::int AS comments_count,
       COALESCE(v.is_liked, FALSE) AS is_liked
     FROM user_comments uc
     JOIN social_post p ON p.id = uc.post_id
     JOIN app_user u ON u.id = p.user_id
     LEFT JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, p.user_id)
      AND rel.user_b_id = GREATEST($1::bigint, p.user_id)
     LEFT JOIN social_post_stats ps ON ps.post_id = p.id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_liked
       FROM social_post_like lv
       WHERE lv.post_id = p.id
         AND lv.user_id = $1
       LIMIT 1
     ) v ON TRUE
     WHERE p.is_deleted = FALSE
       AND p.archived_by_owner_at IS NULL
       AND p.moderation_status = 'approved'
       AND p.user_id <> $2
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND (
         COALESCE(u.social_visibility_tier, 'normal') <> 'gray_zone'
         OR p.user_id = $1
         OR COALESCE(
           (SELECT social_visibility_tier FROM app_user WHERE id = $1),
           'normal'
         ) = 'gray_zone'
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
           AND $5::text IS NOT NULL
           AND p.audience_scope_code = $5::text
         )
         OR (
           COALESCE(p.audience_scope_type, '') = 'compound'
           AND $6::text IS NOT NULL
           AND p.audience_scope_code = $6::text
         )
         OR (
           COALESCE(p.audience_scope_type, '') = 'building'
           AND $7::text IS NOT NULL
           AND p.audience_scope_code = $7::text
         )
       )
       AND ($3::bigint IS NULL OR p.id < $3::bigint)
       AND ($4::text IS NULL OR p.post_kind = $4::text)
     ORDER BY uc.latest_comment_id DESC, p.id DESC
     LIMIT $8`,
    [
      Number(viewerUserId),
      Number(targetUserId),
      beforeId,
      postKind,
      viewerBlockCode == null ? null : String(viewerBlockCode).trim().toUpperCase(),
      viewerCompoundCode == null
        ? null
        : String(viewerCompoundCode).trim().toUpperCase(),
      viewerBuildingCode == null
        ? null
        : String(viewerBuildingCode).trim().toUpperCase(),
      Number(limit),
    ]
  );
  return r.rows;
}

export async function listPostComments({
  postId,
  viewerUserId,
  limit = 40,
  beforeId = null,
}) {
  const r = await q(
    `SELECT
       c.id,
       c.post_id,
       c.user_id,
       c.parent_comment_id,
       c.body,
       c.is_deleted,
       c.created_at,
       c.updated_at,
       c.edited_at,
       COALESCE(cl.likes_count, 0)::int AS likes_count,
       COALESCE(my_like.user_id IS NOT NULL, FALSE) AS is_liked,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.role AS user_role,
       u.image_url AS user_image_url,
       COALESCE(comment_premium.is_active, FALSE) AS user_has_premium
     FROM social_post_comment c
     JOIN app_user u ON u.id = c.user_id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_active
       FROM paid_upgrade_subscription s
       JOIN paid_upgrade_plan plan ON plan.id = s.plan_id
       WHERE s.user_id = c.user_id
         AND s.status = 'active'
         AND s.expires_at > NOW()
         AND plan.code = 'premium_monthly'
       LIMIT 1
     ) comment_premium ON TRUE
     LEFT JOIN (
       SELECT post_comment_id, COUNT(*)::int AS likes_count
       FROM social_post_comment_like
       GROUP BY post_comment_id
     ) cl ON cl.post_comment_id = c.id
     LEFT JOIN social_post_comment_like my_like
       ON my_like.post_comment_id = c.id
      AND my_like.user_id = $4
     WHERE c.post_id = $1
       AND c.moderation_status = 'approved'
       AND ($2::bigint IS NULL OR c.id < $2::bigint)
     ORDER BY c.id DESC
     LIMIT $3`,
    [Number(postId), beforeId, Number(limit), Number(viewerUserId)]
  );
  return r.rows;
}

export async function insertComment({
  postId,
  userId,
  body,
  parentCommentId = null,
}) {
  const r = await q(
    `INSERT INTO social_post_comment
      (post_id, user_id, parent_comment_id, body, moderation_status)
     VALUES ($1, $2, $3, $4, 'approved')
     RETURNING *`,
    [
      Number(postId),
      Number(userId),
      parentCommentId == null ? null : Number(parentCommentId),
      String(body || "").trim(),
    ]
  );
  return r.rows[0] || null;
}

export async function countPostComments(postId) {
  const r = await q(
    `SELECT COUNT(*)::int AS comments_count
     FROM social_post_comment
     WHERE post_id = $1
       AND is_deleted = FALSE
       AND moderation_status = 'approved'`,
    [Number(postId)]
  );
  return Number(r.rows[0]?.comments_count || 0);
}

export async function findPostCommentById({ postId, commentId }) {
  const r = await q(
    `SELECT *
     FROM social_post_comment
     WHERE id = $1
       AND post_id = $2
       AND moderation_status = 'approved'
     LIMIT 1`,
    [Number(commentId), Number(postId)]
  );
  return r.rows[0] || null;
}

export async function findPostCommentViewById({
  postId,
  commentId,
  viewerUserId,
}) {
  const r = await q(
    `SELECT
       c.id,
       c.post_id,
       c.user_id,
       c.parent_comment_id,
       c.body,
       c.is_deleted,
       c.created_at,
       c.updated_at,
       c.edited_at,
       COALESCE(cl.likes_count, 0)::int AS likes_count,
       COALESCE(my_like.user_id IS NOT NULL, FALSE) AS is_liked,
       u.username AS user_username,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.role AS user_role,
       u.image_url AS user_image_url,
       COALESCE(comment_premium.is_active, FALSE) AS user_has_premium
     FROM social_post_comment c
     JOIN app_user u ON u.id = c.user_id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_active
       FROM paid_upgrade_subscription s
       JOIN paid_upgrade_plan plan ON plan.id = s.plan_id
       WHERE s.user_id = c.user_id
         AND s.status = 'active'
         AND s.expires_at > NOW()
         AND plan.code = 'premium_monthly'
       LIMIT 1
     ) comment_premium ON TRUE
     LEFT JOIN (
       SELECT post_comment_id, COUNT(*)::int AS likes_count
       FROM social_post_comment_like
       GROUP BY post_comment_id
     ) cl ON cl.post_comment_id = c.id
     LEFT JOIN social_post_comment_like my_like
       ON my_like.post_comment_id = c.id
      AND my_like.user_id = $3
     WHERE c.id = $1
       AND c.post_id = $2
       AND c.moderation_status = 'approved'
     LIMIT 1`,
    [Number(commentId), Number(postId), Number(viewerUserId)]
  );
  return r.rows[0] || null;
}

export async function updatePostCommentBody({ commentId, body }) {
  const r = await q(
    `UPDATE social_post_comment
     SET body = $2,
         edited_at = NOW()
     WHERE id = $1
       AND moderation_status = 'approved'
     RETURNING *`,
    [Number(commentId), String(body || "").trim()]
  );
  return r.rows[0] || null;
}

export async function softDeletePostComment({ commentId }) {
  const r = await q(
    `UPDATE social_post_comment
     SET is_deleted = TRUE,
         body = '',
         edited_at = NOW()
     WHERE id = $1
       AND moderation_status = 'approved'
     RETURNING *`,
    [Number(commentId)]
  );
  return r.rows[0] || null;
}

export async function hasPostCommentLike({ commentId, userId }) {
  const r = await q(
    `SELECT 1
     FROM social_post_comment_like
     WHERE post_comment_id = $1
       AND user_id = $2
     LIMIT 1`,
    [Number(commentId), Number(userId)]
  );
  return (r.rowCount || 0) > 0;
}

export async function addPostCommentLike({ commentId, userId }) {
  await q(
    `INSERT INTO social_post_comment_like (post_comment_id, user_id)
     VALUES ($1, $2)
     ON CONFLICT (post_comment_id, user_id) DO NOTHING`,
    [Number(commentId), Number(userId)]
  );
}

export async function removePostCommentLike({ commentId, userId }) {
  await q(
    `DELETE FROM social_post_comment_like
     WHERE post_comment_id = $1
       AND user_id = $2`,
    [Number(commentId), Number(userId)]
  );
}

export async function countPostCommentLikes(commentId) {
  const r = await q(
    `SELECT COUNT(*)::int AS likes_count
     FROM social_post_comment_like
     WHERE post_comment_id = $1`,
    [Number(commentId)]
  );
  return Number(r.rows[0]?.likes_count || 0);
}

export async function insertPostReport({
  postId,
  reporterUserId,
  reason,
  details = null,
}) {
  const r = await q(
    `INSERT INTO social_post_report (post_id, reporter_user_id, reason, details)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (post_id, reporter_user_id)
     DO UPDATE SET
       reason = EXCLUDED.reason,
       details = EXCLUDED.details,
       created_at = NOW()
     RETURNING id`,
    [
      Number(postId),
      Number(reporterUserId),
      String(reason || "").trim(),
      details == null ? null : String(details).trim() || null,
    ]
  );
  return r.rows[0] || null;
}

export async function insertUserReport({
  reportedUserId,
  reporterUserId,
  reason,
  details = null,
}) {
  const r = await q(
    `INSERT INTO social_user_report
      (reported_user_id, reporter_user_id, reason, details)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (reported_user_id, reporter_user_id)
     DO UPDATE SET
       reason = EXCLUDED.reason,
       details = EXCLUDED.details,
       created_at = NOW()
     RETURNING id`,
    [
      Number(reportedUserId),
      Number(reporterUserId),
      String(reason || "").trim(),
      details == null ? null : String(details).trim() || null,
    ]
  );
  return r.rows[0] || null;
}

export async function listMerchantOptions({
  viewerUserId,
  search = "",
  limit = 120,
}) {
  const viewerId = Number(viewerUserId);
  const searchQuery = String(search || "").trim();
  const digitsOnlyQuery = searchQuery.replace(/[^\d]/g, "");
  const r = await q(
    `SELECT
       m.id,
       m.name,
       m.type,
       m.phone,
       m.image_url,
       COALESCE(eligible.eligible_orders_count, 0)::int AS eligible_orders_count,
       eligible.last_eligible_order_at,
       COALESCE(any_order.orders_count, 0)::int AS orders_count,
       any_order.last_ordered_at
     FROM merchant m
     LEFT JOIN LATERAL (
       SELECT
         COUNT(*)::int AS eligible_orders_count,
         MAX(o.created_at) AS last_eligible_order_at
       FROM customer_order o
       WHERE o.customer_user_id = $1
         AND o.merchant_id = m.id
         AND o.status IN ('delivered', 'completed')
     ) eligible ON TRUE
     LEFT JOIN LATERAL (
       SELECT
         COUNT(*)::int AS orders_count,
         MAX(o.created_at) AS last_ordered_at
       FROM customer_order o
       WHERE o.customer_user_id = $1
         AND o.merchant_id = m.id
         AND o.status <> 'cancelled'
     ) any_order ON TRUE
     WHERE COALESCE(m.is_disabled, FALSE) = FALSE
       AND COALESCE(m.is_approved, TRUE) = TRUE
       AND COALESCE(TRIM(LOWER(m.type::text)), '') NOT IN ('car', 'cars', 'automotive', 'vehicles')
       AND (
         $2::text = ''
         OR m.name ILIKE ('%' || $2 || '%')
         OR m.phone ILIKE ('%' || $2 || '%')
         OR (
           $4::text <> ''
           AND regexp_replace(COALESCE(m.phone, ''), '\\D', '', 'g') LIKE ('%' || $4 || '%')
         )
       )
     ORDER BY
       COALESCE(eligible.last_eligible_order_at, any_order.last_ordered_at) DESC NULLS LAST,
       COALESCE(eligible.eligible_orders_count, 0) DESC,
       COALESCE(any_order.orders_count, 0) DESC,
       m.name ASC
     LIMIT $3`,
    [viewerId, searchQuery, Number(limit), digitsOnlyQuery]
  );
  return r.rows;
}

export async function hasUserOrderedMerchant({ customerUserId, merchantId }) {
  const row = await getMerchantReviewEligibility({ customerUserId, merchantId });
  return row.can_review === true;
}

export async function getMerchantReviewEligibility({
  customerUserId,
  merchantId,
}) {
  const r = await q(
    `SELECT
       EXISTS (
         SELECT 1
         FROM customer_order o
         WHERE o.customer_user_id = $1
           AND o.merchant_id = $2
           AND o.status IN ('delivered', 'completed')
       ) AS can_review,
       COALESCE((
         SELECT COUNT(*)::int
         FROM customer_order o
         WHERE o.customer_user_id = $1
           AND o.merchant_id = $2
           AND o.status IN ('delivered', 'completed')
       ), 0)::int AS eligible_orders_count,
       (
         SELECT MAX(o.created_at)
         FROM customer_order o
         WHERE o.customer_user_id = $1
           AND o.merchant_id = $2
           AND o.status IN ('delivered', 'completed')
       ) AS last_eligible_order_at
     FROM merchant m
     WHERE m.id = $2
       AND COALESCE(m.is_disabled, FALSE) = FALSE
       AND COALESCE(m.is_approved, TRUE) = TRUE
     LIMIT 1`,
    [Number(customerUserId), Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function listUsersForSearch({ viewerUserId, search = "", limit = 60 }) {
  const viewerId = Number(viewerUserId);
  const searchQuery = String(search || "").trim();
  const digitsOnlyQuery = searchQuery.replace(/[^\d]/g, "");
  const r = await q(
    `SELECT
       u.id,
       u.username,
       u.full_name,
       u.phone,
       u.role,
       u.image_url,
       u.social_show_phone,
       u.social_account_private,
       rel.user_a_id,
       rel.user_b_id,
       rel.initiator_user_id,
       rel.status,
       rel.requested_at,
       rel.responded_at,
       rel.updated_at
     FROM app_user u
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($1::bigint, u.id)
      AND rel.user_b_id = GREATEST($1::bigint, u.id)
     WHERE u.id <> $1
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND (
         $2::text = ''
         OR LOWER(COALESCE(u.username, '')) LIKE LOWER('%' || $2 || '%')
         OR u.full_name ILIKE ('%' || $2 || '%')
         OR u.phone ILIKE ('%' || $2 || '%')
         OR (
           $4::text <> ''
           AND regexp_replace(COALESCE(u.phone, ''), '\\D', '', 'g') LIKE ('%' || $4 || '%')
         )
       )
     ORDER BY
       CASE WHEN $2::text <> '' AND LOWER(COALESCE(u.username, '')) LIKE LOWER($2 || '%') THEN 0 ELSE 1 END ASC,
       CASE WHEN $2::text <> '' AND u.full_name ILIKE ($2 || '%') THEN 0 ELSE 1 END ASC,
       CASE WHEN $2::text <> '' AND u.phone ILIKE ($2 || '%') THEN 0 ELSE 1 END ASC,
       COALESCE(NULLIF(TRIM(u.username), ''), 'zzzzzz') ASC,
       COALESCE(NULLIF(TRIM(u.full_name), ''), u.phone, '') ASC,
       u.id DESC
     LIMIT $3`,
    [viewerId, searchQuery, Number(limit), digitsOnlyQuery]
  );
  return r.rows;
}

export async function listUsersForCommunityScopeSearch({
  scopeType,
  scopeCode,
  search = "",
  limit = 80,
  excludedRoles = [],
  includeChatRestriction = false,
  includeScopeRemoval = false,
  requireApartmentForBuilding = false,
}) {
  const safeScopeType = String(scopeType || "").trim().toLowerCase();
  const safeScopeCode = String(scopeCode || "").trim().toUpperCase();
  const searchQuery = String(search || "").trim();
  const digitsOnlyQuery = searchQuery.replace(/[^\d]/g, "");
  const normalizedExcludedRoles = Array.isArray(excludedRoles)
    ? excludedRoles
        .map((role) => String(role || "").trim().toLowerCase())
        .filter((role) => role.length > 0)
    : [];
  const scopeExpr = resolveScopeAddressExpression(safeScopeType, "u");

  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.role,
       u.image_url,
       CASE WHEN m.manager_user_id IS NOT NULL THEN TRUE ELSE FALSE END AS is_manager,
       CASE
         WHEN $8::boolean = TRUE AND b.user_id IS NOT NULL THEN TRUE
         ELSE FALSE
       END AS is_chat_restricted,
       CASE
         WHEN $9::boolean = TRUE AND rm.user_id IS NOT NULL THEN TRUE
         ELSE FALSE
       END AS is_scope_removed
     FROM app_user u
     LEFT JOIN social_scope_manager m
       ON m.scope_type = $4
      AND m.scope_code = $5
      AND m.manager_user_id = u.id
     LEFT JOIN social_scope_chat_ban b
       ON b.scope_type = $4
      AND b.scope_code = $5
      AND b.user_id = u.id
     LEFT JOIN social_scope_member_removal rm
       ON rm.scope_type = $4
      AND rm.scope_code = $5
      AND rm.user_id = u.id
     WHERE (${scopeExpr}) = $1::text
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND (
         $2::text = ''
         OR u.full_name ILIKE ('%' || $2 || '%')
         OR u.phone ILIKE ('%' || $2 || '%')
         OR (
           $6::text <> ''
           AND regexp_replace(COALESCE(u.phone, ''), '\\D', '', 'g') LIKE ('%' || $6 || '%')
         )
       )
        AND (
          $3::text[] IS NULL
          OR NOT (LOWER(COALESCE(u.role::text, '')) = ANY($3::text[]))
        )
        AND (
          $10::boolean = FALSE
          OR $4::text <> 'building'
          OR NULLIF(TRIM(COALESCE(u.apartment, '')), '') IS NOT NULL
        )
      ORDER BY
        CASE WHEN m.manager_user_id IS NOT NULL THEN 0 ELSE 1 END ASC,
        CASE WHEN $2::text <> '' AND u.full_name ILIKE ($2 || '%') THEN 0 ELSE 1 END ASC,
       CASE WHEN $2::text <> '' AND u.phone ILIKE ($2 || '%') THEN 0 ELSE 1 END ASC,
       COALESCE(NULLIF(TRIM(u.full_name), ''), u.phone, '') ASC,
       u.id DESC
     LIMIT $7`,
    [
      safeScopeCode,
      searchQuery,
      normalizedExcludedRoles.length > 0 ? normalizedExcludedRoles : null,
      safeScopeType,
      safeScopeCode,
      digitsOnlyQuery,
      Math.max(1, Math.min(200, Number(limit) || 80)),
      includeChatRestriction === true,
      includeScopeRemoval === true,
      requireApartmentForBuilding === true,
    ]
  );

  return r.rows;
}

export async function listScopeAudienceUserIds({
  scopeType,
  scopeCode,
  excludeUserIds = [],
  includeBackoffice = false,
  apartmentCode = null,
  limit = 8000,
}) {
  const safeScopeType = String(scopeType || "").trim().toLowerCase();
  const safeScopeCode = String(scopeCode || "").trim().toUpperCase();
  const safeApartmentCode =
    apartmentCode == null ? null : String(apartmentCode).trim().toUpperCase();
  const scopeExpr = resolveScopeAddressExpression(safeScopeType, "u");
  const safeExcludedUserIds = Array.isArray(excludeUserIds)
    ? excludeUserIds
        .map((value) => Number(value))
        .filter((value) => Number.isInteger(value) && value > 0)
    : [];

  const r = await q(
    `SELECT DISTINCT u.id
     FROM app_user u
     WHERE COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND NOT EXISTS (
         SELECT 1
         FROM social_scope_member_removal rm
         WHERE rm.scope_type = $6::text
           AND rm.scope_code = $1::text
           AND rm.user_id = u.id
       )
       AND (
         (
           LOWER(COALESCE(u.role::text, '')) = 'user'
           AND (${scopeExpr}) = $1::text
           AND (
             $5::text IS NULL
             OR UPPER(TRIM(COALESCE(u.apartment, ''))) = $5::text
           )
         )
         OR (
           $2::boolean = TRUE
           AND (
             COALESCE(u.is_super_admin, FALSE) = TRUE
             OR LOWER(COALESCE(u.role::text, '')) IN ('admin', 'deputy_admin')
           )
         )
       )
       AND (
         CARDINALITY($3::bigint[]) = 0
         OR u.id <> ALL($3::bigint[])
       )
     ORDER BY u.id DESC
     LIMIT $4`,
    [
      safeScopeCode,
      includeBackoffice === true,
      safeExcludedUserIds,
      Math.max(1, Math.min(20000, Number(limit) || 8000)),
      safeApartmentCode,
      safeScopeType,
    ]
  );

  return r.rows.map((row) => Number(row.id)).filter((id) => id > 0);
}

export async function findUserPublicProfile(userId) {
  const r = await q(
    `SELECT
       id,
       username,
       full_name,
       phone,
       preferred_locale,
       role,
       image_url,
       work_title,
       work_company,
       is_super_admin,
       is_account_disabled,
       social_age,
       social_show_phone,
       social_account_private,
       social_posts_public,
       social_stories_public,
       social_relations_public,
       social_online_visibility,
       social_last_seen_visibility,
       social_read_receipts_enabled,
       social_typing_indicators_enabled,
       social_profile_core_updated_at,
       social_write_block_until,
       social_visibility_tier,
       social_reports_blocked,
       social_false_reports_count,
       social_violation_strikes
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function listUserPublicProfiles(userIds = []) {
  const normalizedUserIds = Array.isArray(userIds)
    ? [
        ...new Set(
          userIds
            .map((value) => Number(value))
            .filter((value) => Number.isInteger(value) && value > 0)
        ),
      ]
    : [];
  if (normalizedUserIds.length <= 0) return [];
  const r = await q(
    `SELECT
       id,
       username,
       full_name,
       phone,
       role,
       image_url,
       work_title,
       work_company,
       is_super_admin,
       is_account_disabled,
       social_age,
       social_show_phone,
       social_account_private,
       social_posts_public,
       social_stories_public,
       social_relations_public,
       social_online_visibility,
       social_last_seen_visibility,
       social_read_receipts_enabled,
       social_typing_indicators_enabled,
       social_profile_core_updated_at,
       social_write_block_until,
       social_visibility_tier,
       social_reports_blocked,
       social_false_reports_count,
       social_violation_strikes
     FROM app_user
     WHERE id = ANY($1::bigint[])`,
    [normalizedUserIds]
  );
  return r.rows;
}

export async function findUserSocialModerationState(userId) {
  const r = await q(
    `SELECT
       id,
       is_account_disabled,
       social_write_block_until,
       social_visibility_tier,
       social_reports_blocked,
       social_false_reports_count,
       social_violation_strikes
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function findActiveSocialCapabilityRestriction({
  userId,
  capabilityKey,
  at = null,
}) {
  const normalizedKey = String(capabilityKey || "").trim().toLowerCase();
  if (!normalizedKey) return null;
  const effectiveAt = at == null ? new Date().toISOString() : new Date(at).toISOString();
  const r = await q(
    `SELECT *
     FROM social_capability_restriction
     WHERE user_id = $1
       AND capability_key = $2
       AND revoked_at IS NULL
       AND starts_at <= $3::timestamptz
       AND (ends_at IS NULL OR ends_at > $3::timestamptz)
     ORDER BY starts_at DESC, id DESC
     LIMIT 1`,
    [Number(userId), normalizedKey, effectiveAt]
  );
  return r.rows[0] || null;
}

export async function listActiveSocialCapabilityRestrictionsForUser(userId, { at = null } = {}) {
  const effectiveAt = at == null ? new Date().toISOString() : new Date(at).toISOString();
  const r = await q(
    `SELECT *
     FROM social_capability_restriction
     WHERE user_id = $1
       AND revoked_at IS NULL
       AND starts_at <= $2::timestamptz
       AND (ends_at IS NULL OR ends_at > $2::timestamptz)
     ORDER BY capability_key ASC, starts_at DESC, id DESC`,
    [Number(userId), effectiveAt]
  );
  return r.rows;
}

export async function findUserResidenceSnapshot(userId) {
  const r = await q(
    `SELECT
       u.id AS user_id,
       u.full_name,
       u.phone,
       u.block,
       u.building_number,
       u.apartment,
       info.document_type,
       info.town,
       info.building_number AS residence_building_number,
       info.apartment_number,
       info.floor_number,
       info.contract_number,
       info.issue_date,
       info.visible_id_number,
       info.image_url,
       info.extracted_payload,
       info.updated_at AS residence_info_updated_at
     FROM app_user u
     LEFT JOIN user_residence_info info ON info.user_id = u.id
     WHERE u.id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function findLatestResidenceChangeRequestByUser(userId) {
  const r = await q(
    `SELECT *
     FROM residence_change_request
     WHERE user_id = $1
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function findPendingResidenceChangeRequestByUser(userId) {
  const r = await q(
    `SELECT *
     FROM residence_change_request
     WHERE user_id = $1
       AND status = 'pending'
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function findLatestProfileCoreChangeRequestByUser(userId) {
  const r = await q(
    `SELECT *
     FROM social_profile_change_request
     WHERE user_id = $1
       AND change_kind = 'core_identity'
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function findPendingProfileCoreChangeRequestByUser(userId) {
  const r = await q(
    `SELECT *
     FROM social_profile_change_request
     WHERE user_id = $1
       AND change_kind = 'core_identity'
       AND status = 'pending'
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function createProfileCoreChangeRequest({
  userId,
  currentSnapshotJson,
  requestedSnapshotJson,
}) {
  const r = await q(
    `INSERT INTO social_profile_change_request
      (
        user_id,
        change_kind,
        status,
        current_snapshot_json,
        requested_snapshot_json
      )
     VALUES ($1, 'core_identity', 'pending', $2::jsonb, $3::jsonb)
     RETURNING *`,
    [
      Number(userId),
      JSON.stringify(currentSnapshotJson || {}),
      JSON.stringify(requestedSnapshotJson || {}),
    ]
  );
  return r.rows[0] || null;
}

export async function updatePendingProfileCoreChangeRequest({
  requestId,
  userId,
  currentSnapshotJson,
  requestedSnapshotJson,
}) {
  const r = await q(
    `UPDATE social_profile_change_request
     SET current_snapshot_json = $3::jsonb,
         requested_snapshot_json = $4::jsonb,
         review_note = NULL,
         reviewed_by_user_id = NULL,
         reviewed_at = NULL,
         updated_at = NOW()
     WHERE id = $1
       AND user_id = $2
       AND change_kind = 'core_identity'
       AND status = 'pending'
     RETURNING *`,
    [
      Number(requestId),
      Number(userId),
      JSON.stringify(currentSnapshotJson || {}),
      JSON.stringify(requestedSnapshotJson || {}),
    ]
  );
  return r.rows[0] || null;
}

export async function createResidenceChangeRequest({
  userId,
  currentSnapshotJson,
  requestedSnapshotJson,
  note = null,
  documentImageUrl = null,
}) {
  const r = await q(
    `INSERT INTO residence_change_request
      (
        user_id,
        status,
        current_snapshot_json,
        requested_snapshot_json,
        note,
        document_image_url
      )
     VALUES ($1, 'pending', $2::jsonb, $3::jsonb, $4, $5)
     RETURNING *`,
    [
      Number(userId),
      JSON.stringify(currentSnapshotJson || {}),
      JSON.stringify(requestedSnapshotJson || {}),
      note == null ? null : String(note).trim() || null,
      documentImageUrl == null ? null : String(documentImageUrl).trim() || null,
    ]
  );
  return r.rows[0] || null;
}

export async function cancelResidenceChangeRequest({ requestId, userId }) {
  const r = await q(
    `UPDATE residence_change_request
     SET status = 'cancelled',
         review_note = COALESCE(review_note, 'Cancelled by user'),
         reviewed_at = COALESCE(reviewed_at, NOW())
     WHERE id = $1
       AND user_id = $2
       AND status = 'pending'
     RETURNING *`,
    [Number(requestId), Number(userId)]
  );
  return r.rows[0] || null;
}

export async function listSuperAdminUserIds(limit = 60) {
  const r = await q(
    `SELECT id
     FROM app_user
     WHERE COALESCE(is_super_admin, FALSE) = TRUE
       AND COALESCE(is_account_disabled, FALSE) = FALSE
     ORDER BY id DESC
     LIMIT $1`,
    [Math.max(1, Math.min(400, Number(limit) || 60))]
  );
  return r.rows.map((row) => Number(row.id)).filter((id) => id > 0);
}

// All users who can review admin queues (matches `requireAdmin`: super-admins
// plus role='admin'). Used so admin alerts aren't limited to super-admins only.
export async function listAdminUserIds(limit = 120) {
  const r = await q(
    `SELECT id
     FROM app_user
     WHERE (
         COALESCE(is_super_admin, FALSE) = TRUE
         OR LOWER(COALESCE(role::text, '')) = 'admin'
       )
       AND COALESCE(is_account_disabled, FALSE) = FALSE
     ORDER BY id DESC
     LIMIT $1`,
    [Math.max(1, Math.min(400, Number(limit) || 120))]
  );
  return r.rows.map((row) => Number(row.id)).filter((id) => id > 0);
}

export async function findUserSocialProfile(userId) {
  const r = await q(
    `SELECT
       id,
       username,
       full_name,
       phone,
       role,
       image_url,
       block,
       building_number,
       apartment,
       work_title,
       work_company,
       is_super_admin,
       is_account_disabled,
       social_age,
       social_bio,
       social_show_phone,
       social_account_private,
       social_posts_public,
       social_stories_public,
       social_relations_public,
       social_online_visibility,
       social_last_seen_visibility,
       social_read_receipts_enabled,
       social_typing_indicators_enabled,
       social_profile_core_updated_at,
       social_write_block_until,
       social_visibility_tier,
       social_reports_blocked,
       social_false_reports_count,
       social_violation_strikes,
       created_at
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function updateUserSocialProfile({
  userId,
  username,
  fullName,
  bio,
  age,
  imageUrl,
  workTitle,
  workCompany,
  showPhone,
  accountPrivate,
  postsPublic,
  storiesPublic,
  relationsPublic,
  onlineStatusVisibility,
  lastSeenVisibility,
  readReceiptsEnabled,
  typingIndicatorsEnabled,
  preferredLocale,
  touchCoreProfileUpdateAt = false,
}) {
  const sets = [];
  const params = [];

  if (fullName !== undefined) {
    params.push(String(fullName).trim());
    sets.push(`full_name = $${params.length}`);
  }
  if (username !== undefined) {
    params.push(String(username || "").trim().toLowerCase() || null);
    sets.push(`username = $${params.length}`);
  }
  if (bio !== undefined) {
    params.push(String(bio || "").trim());
    sets.push(`social_bio = $${params.length}`);
  }
  if (age !== undefined) {
    params.push(age == null ? null : Number(age));
    sets.push(`social_age = $${params.length}`);
  }
  if (imageUrl !== undefined) {
    params.push(String(imageUrl || "").trim() || null);
    sets.push(`image_url = $${params.length}`);
  }
  if (workTitle !== undefined) {
    params.push(String(workTitle || "").trim().slice(0, 160) || null);
    sets.push(`work_title = $${params.length}`);
  }
  if (workCompany !== undefined) {
    params.push(String(workCompany || "").trim().slice(0, 180) || null);
    sets.push(`work_company = $${params.length}`);
  }
  if (showPhone !== undefined) {
    params.push(showPhone === true);
    sets.push(`social_show_phone = $${params.length}`);
  }
  if (accountPrivate !== undefined) {
    params.push(accountPrivate === true);
    sets.push(`social_account_private = $${params.length}`);
  }
  if (postsPublic !== undefined) {
    params.push(postsPublic === true);
    sets.push(`social_posts_public = $${params.length}`);
  }
  if (storiesPublic !== undefined) {
    params.push(storiesPublic === true);
    sets.push(`social_stories_public = $${params.length}`);
  }
  if (relationsPublic !== undefined) {
    params.push(relationsPublic === true);
    sets.push(`social_relations_public = $${params.length}`);
  }
  if (onlineStatusVisibility !== undefined) {
    params.push(String(onlineStatusVisibility || "").trim().toLowerCase() || "connections");
    sets.push(`social_online_visibility = $${params.length}`);
  }
  if (lastSeenVisibility !== undefined) {
    params.push(String(lastSeenVisibility || "").trim().toLowerCase() || "connections");
    sets.push(`social_last_seen_visibility = $${params.length}`);
  }
  if (readReceiptsEnabled !== undefined) {
    params.push(readReceiptsEnabled === true);
    sets.push(`social_read_receipts_enabled = $${params.length}`);
  }
  if (typingIndicatorsEnabled !== undefined) {
    params.push(typingIndicatorsEnabled === true);
    sets.push(`social_typing_indicators_enabled = $${params.length}`);
  }
  if (preferredLocale !== undefined) {
    params.push(String(preferredLocale || "ar").trim().toLowerCase() || "ar");
    sets.push(`preferred_locale = $${params.length}`);
  }
  if (touchCoreProfileUpdateAt) {
    sets.push(`social_profile_core_updated_at = NOW()`);
  }

  if (sets.length <= 0) {
    return findUserSocialProfile(userId);
  }

  params.push(Number(userId));
  const r = await q(
    `UPDATE app_user
     SET ${sets.join(", ")}
     WHERE id = $${params.length}
     RETURNING
       id,
       username,
       full_name,
       phone,
       preferred_locale,
       role,
       image_url,
       work_title,
       work_company,
       is_super_admin,
       is_account_disabled,
       social_age,
       social_bio,
       social_show_phone,
       social_account_private,
       social_posts_public,
       social_stories_public,
       social_relations_public,
       social_online_visibility,
       social_last_seen_visibility,
       social_read_receipts_enabled,
       social_typing_indicators_enabled,
       social_profile_core_updated_at,
       created_at`,
    params
  );
  return r.rows[0] || null;
}

export async function findUserByUsername(username) {
  const normalized = String(username || "").trim().toLowerCase();
  if (!normalized) return null;
  const r = await q(
    `SELECT id, username, full_name, phone, role, image_url, is_account_disabled
     FROM app_user
     WHERE LOWER(username) = $1
     LIMIT 1`,
    [normalized]
  );
  return r.rows[0] || null;
}

export async function isUsernameTaken({ username, excludeUserId = null }) {
  const normalized = String(username || "").trim().toLowerCase();
  if (!normalized) return false;
  const r = await q(
    `SELECT 1
     FROM app_user
     WHERE LOWER(username) = $1
       AND ($2::bigint IS NULL OR id <> $2::bigint)
     LIMIT 1`,
    [normalized, excludeUserId == null ? null : Number(excludeUserId)]
  );
  return Boolean(r.rows[0]);
}

export async function getUserSocialStats(userId) {
  const r = await q(
    `SELECT
       COUNT(*)::int AS total_posts,
       COUNT(*) FILTER (WHERE post_kind = 'image')::int AS image_posts,
       COUNT(*) FILTER (WHERE post_kind IN ('video', 'reel'))::int AS video_posts,
       COUNT(*) FILTER (WHERE post_kind = 'merchant_review')::int AS review_posts,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_post_like l_by_user
         JOIN social_post p_by_like ON p_by_like.id = l_by_user.post_id
         WHERE l_by_user.user_id = $1
           AND p_by_like.is_deleted = FALSE
           AND p_by_like.moderation_status = 'approved'
       ), 0)::int AS likes_given,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_post_comment c_by_user
         JOIN social_post p_by_comment ON p_by_comment.id = c_by_user.post_id
         WHERE c_by_user.user_id = $1
           AND c_by_user.is_deleted = FALSE
           AND c_by_user.moderation_status = 'approved'
           AND p_by_comment.is_deleted = FALSE
           AND p_by_comment.moderation_status = 'approved'
           AND p_by_comment.user_id <> $1
       ), 0)::int AS comments_made,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_post_like l
         JOIN social_post p2 ON p2.id = l.post_id
         WHERE p2.user_id = $1
           AND p2.is_deleted = FALSE
           AND p2.moderation_status = 'approved'
       ), 0)::int AS likes_received,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_post_comment c
         JOIN social_post p3 ON p3.id = c.post_id
         WHERE p3.user_id = $1
           AND c.is_deleted = FALSE
           AND c.moderation_status = 'approved'
           AND p3.is_deleted = FALSE
           AND p3.moderation_status = 'approved'
       ), 0)::int AS comments_received,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_story s
         WHERE s.user_id = $1
           AND s.is_deleted = FALSE
           AND s.moderation_status = 'approved'
           AND s.expires_at > NOW()
       ), 0)::int AS active_stories,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_story_highlight h
         JOIN social_story s2 ON s2.id = h.story_id
         WHERE h.owner_user_id = $1
           AND s2.is_deleted = FALSE
           AND s2.moderation_status = 'approved'
       ), 0)::int AS highlights_count
     FROM social_post
     WHERE user_id = $1
       AND is_deleted = FALSE
       AND archived_by_owner_at IS NULL
       AND moderation_status = 'approved'`,
    [Number(userId)]
  );
  return r.rows[0] || {
    total_posts: 0,
    image_posts: 0,
    video_posts: 0,
    review_posts: 0,
    likes_given: 0,
    comments_made: 0,
    likes_received: 0,
    comments_received: 0,
    active_stories: 0,
    highlights_count: 0,
  };
}

export async function countSavedItemsByUser(userId) {
  const r = await q(
    `SELECT COUNT(*)::int AS total
     FROM social_saved_item
     WHERE user_id = $1`,
    [Number(userId)]
  );
  return Number(r.rows[0]?.total || 0);
}

export async function countTaggedPostsByUser(userId) {
  const r = await q(
    `SELECT COUNT(DISTINCT sct.entity_id)::int AS total
     FROM social_content_tag sct
     JOIN social_post p ON p.id = sct.entity_id
     WHERE sct.tagged_user_id = $1
       AND p.is_deleted = FALSE
       AND p.archived_by_owner_at IS NULL
       AND p.moderation_status = 'approved'`,
    [Number(userId)]
  );
  return Number(r.rows[0]?.total || 0);
}

export async function createOrGetThread({
  userAId,
  userBId,
  threadKind = "private",
  contextType = "none",
  contextId = 0,
  contextStatus = "active",
  contextSnapshot = {},
}) {
  const a = Math.min(Number(userAId), Number(userBId));
  const b = Math.max(Number(userAId), Number(userBId));
  const normalizedThreadKind = String(threadKind || "private")
    .trim()
    .toLowerCase();
  const normalizedContextType = String(contextType || "none")
    .trim()
    .toLowerCase();
  const normalizedContextId = Math.max(0, Number(contextId) || 0);
  const normalizedContextStatus = String(contextStatus || "active")
    .trim()
    .toLowerCase();
  const normalizedContextSnapshot =
    contextSnapshot &&
    typeof contextSnapshot === "object" &&
    !Array.isArray(contextSnapshot)
      ? JSON.stringify(contextSnapshot)
      : JSON.stringify({});

  const advisoryKey = [
    "social_chat_thread",
    a,
    b,
    normalizedThreadKind,
    normalizedContextType,
    normalizedContextId,
  ].join(":");

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [advisoryKey]);

    const existing = await client.query(
      `SELECT *
       FROM social_chat_thread
       WHERE user_a_id = $1
         AND user_b_id = $2
         AND thread_kind = $3
         AND context_type = $4
         AND context_id = $5
       LIMIT 1`,
      [
        a,
        b,
        normalizedThreadKind,
        normalizedContextType,
        normalizedContextId,
      ]
    );

    if (existing.rows[0]) {
      const updated = await client.query(
        `UPDATE social_chat_thread
         SET updated_at = NOW(),
             context_status = $1,
             context_snapshot_json = $2::jsonb
         WHERE id = $3
         RETURNING *`,
        [
          normalizedContextStatus,
          normalizedContextSnapshot,
          Number(existing.rows[0].id),
        ]
      );
      await client.query("COMMIT");
      return updated.rows[0] || existing.rows[0];
    }

    const inserted = await client.query(
      `INSERT INTO social_chat_thread
        (
          user_a_id,
          user_b_id,
          thread_kind,
          context_type,
          context_id,
          context_status,
          context_snapshot_json,
          last_message_at
        )
       VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, NOW())
       RETURNING *`,
      [
        a,
        b,
        normalizedThreadKind,
        normalizedContextType,
        normalizedContextId,
        normalizedContextStatus,
        normalizedContextSnapshot,
      ]
    );
    await client.query("COMMIT");
    return inserted.rows[0] || null;
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // noop
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function createGroupThread({
  ownerUserId,
  title,
  imageUrl = null,
  memberUserIds = [],
}) {
  const ownerId = Number(ownerUserId);
  const normalizedMemberIds = Array.isArray(memberUserIds)
    ? [
        ...new Set(
          memberUserIds
            .map((value) => Number(value))
            .filter((value) => Number.isInteger(value) && value > 0 && value !== ownerId)
        ),
      ]
    : [];
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const threadResult = await client.query(
      `INSERT INTO social_chat_thread
        (
          user_a_id,
          user_b_id,
          thread_kind,
          context_type,
          context_id,
          context_status,
          context_snapshot_json,
          last_message_at
        )
       VALUES ($1, $1, 'group', 'none', 0, 'active', '{}'::jsonb, NOW())
       RETURNING *`,
      [ownerId]
    );
    const thread = threadResult.rows[0] || null;
    if (!thread) {
      throw new Error("GROUP_THREAD_CREATE_FAILED");
    }

    await client.query(
      `INSERT INTO social_chat_group
        (thread_id, owner_user_id, title, image_url)
       VALUES ($1, $2, $3, $4)`,
      [
        Number(thread.id),
        ownerId,
        String(title || "").trim(),
        imageUrl == null ? null : String(imageUrl || "").trim() || null,
      ]
    );

    const membershipRows = [
      [Number(thread.id), ownerId, "owner", ownerId],
      ...normalizedMemberIds.map((memberUserId) => [
        Number(thread.id),
        memberUserId,
        "member",
        ownerId,
      ]),
    ];

    await client.query(
      `INSERT INTO social_chat_thread_member
        (thread_id, user_id, member_role, added_by_user_id)
       SELECT
         entry.thread_id,
         entry.user_id,
         entry.member_role,
         entry.added_by_user_id
       FROM UNNEST($1::bigint[], $2::bigint[], $3::text[], $4::bigint[])
         AS entry(thread_id, user_id, member_role, added_by_user_id)
       ON CONFLICT (thread_id, user_id) DO NOTHING`,
      [
        membershipRows.map((row) => row[0]),
        membershipRows.map((row) => row[1]),
        membershipRows.map((row) => row[2]),
        membershipRows.map((row) => row[3]),
      ]
    );

    await client.query(
      `INSERT INTO social_chat_thread_participant_state
        (
          thread_id,
          user_id,
          inbox_bucket,
          request_status,
          accepted_at
        )
       SELECT
         entry.thread_id,
         entry.user_id,
         'primary',
         'accepted',
         NOW()
       FROM UNNEST($1::bigint[], $2::bigint[]) AS entry(thread_id, user_id)
       ON CONFLICT (thread_id, user_id)
       DO UPDATE SET
         inbox_bucket = 'primary',
         request_status = 'accepted',
         accepted_at = COALESCE(
           social_chat_thread_participant_state.accepted_at,
           NOW()
         ),
         updated_at = NOW()`,
      [
        membershipRows.map((row) => row[0]),
        membershipRows.map((row) => row[1]),
      ]
    );

    await client.query("COMMIT");
    return thread;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listThreadMemberUserIds({ threadId, excludeUserId = null }) {
  const r = await q(
    `SELECT user_id
     FROM social_chat_thread_member
     WHERE thread_id = $1
       AND ($2::bigint IS NULL OR user_id <> $2::bigint)`,
    [
      Number(threadId),
      excludeUserId == null ? null : Number(excludeUserId),
    ]
  );
  return r.rows.map((row) => Number(row.user_id)).filter((value) => value > 0);
}

export async function getGroupThreadMember({ threadId, userId }) {
  const r = await q(
    `SELECT *
     FROM social_chat_thread_member
     WHERE thread_id = $1
       AND user_id = $2
     LIMIT 1`,
    [Number(threadId), Number(userId)]
  );
  return r.rows[0] || null;
}

export async function listGroupThreadMembers({ threadId }) {
  const r = await q(
    `SELECT
       m.thread_id,
       m.user_id,
       m.member_role,
       m.added_by_user_id,
       m.created_at AS member_created_at,
       u.username,
       u.full_name,
       u.phone,
       u.role,
       u.image_url,
       u.social_online_visibility,
       u.social_last_seen_visibility,
       u.social_read_receipts_enabled,
       u.social_typing_indicators_enabled,
       presence.heartbeat_at AS presence_heartbeat_at,
       presence.last_seen_at AS presence_last_seen_at,
       COALESCE(premium.is_active, FALSE) AS has_premium
     FROM social_chat_thread_member m
     JOIN app_user u ON u.id = m.user_id
     LEFT JOIN social_user_presence presence ON presence.user_id = u.id
     LEFT JOIN user_paid_upgrade_state premium
       ON premium.user_id = u.id
      AND premium.is_active = TRUE
     WHERE m.thread_id = $1
     ORDER BY
       CASE m.member_role
         WHEN 'owner' THEN 0
         WHEN 'admin' THEN 1
         ELSE 2
       END,
       LOWER(COALESCE(u.full_name, '')),
       m.user_id ASC`,
    [Number(threadId)]
  );
  return r.rows;
}

export async function updateGroupThreadMetadata({
  threadId,
  title = undefined,
}) {
  const sets = [];
  const params = [Number(threadId)];
  if (title !== undefined) {
    params.push(String(title || "").trim());
    sets.push(`title = $${params.length}`);
  }
  if (sets.length <= 0) return null;
  params.push(new Date().toISOString());
  const r = await q(
    `UPDATE social_chat_group
     SET ${sets.join(", ")},
         updated_at = $${params.length}
     WHERE thread_id = $1
     RETURNING *`,
    params
  );
  return r.rows[0] || null;
}

export async function addGroupThreadMembers({
  threadId,
  memberUserIds = [],
  addedByUserId,
}) {
  const normalizedMemberIds = Array.isArray(memberUserIds)
    ? [
        ...new Set(
          memberUserIds
            .map((value) => Number(value))
            .filter((value) => Number.isInteger(value) && value > 0)
        ),
      ]
    : [];
  if (normalizedMemberIds.length <= 0) return [];
  const safeThreadId = Number(threadId);
  const actorUserId = Number(addedByUserId);
  await q(
    `INSERT INTO social_chat_thread_member
      (thread_id, user_id, member_role, added_by_user_id)
     SELECT
       entry.thread_id,
       entry.user_id,
       'member',
       entry.added_by_user_id
     FROM UNNEST($1::bigint[], $2::bigint[], $3::bigint[])
       AS entry(thread_id, user_id, added_by_user_id)
     ON CONFLICT (thread_id, user_id) DO NOTHING`,
    [
      normalizedMemberIds.map(() => safeThreadId),
      normalizedMemberIds,
      normalizedMemberIds.map(() => actorUserId),
    ]
  );
  await q(
    `INSERT INTO social_chat_thread_participant_state
      (
        thread_id,
        user_id,
        inbox_bucket,
        request_status,
        accepted_at
      )
     SELECT
       entry.thread_id,
       entry.user_id,
       'primary',
       'accepted',
       NOW()
     FROM UNNEST($1::bigint[], $2::bigint[]) AS entry(thread_id, user_id)
     ON CONFLICT (thread_id, user_id)
     DO UPDATE SET
       inbox_bucket = 'primary',
       request_status = 'accepted',
       accepted_at = COALESCE(
         social_chat_thread_participant_state.accepted_at,
         NOW()
       ),
       updated_at = NOW()`,
    [
      normalizedMemberIds.map(() => safeThreadId),
      normalizedMemberIds,
    ]
  );
  return normalizedMemberIds;
}

export async function removeGroupThreadMember({ threadId, userId }) {
  const safeThreadId = Number(threadId);
  const safeUserId = Number(userId);
  await q(
    `DELETE FROM social_chat_thread_participant_state
     WHERE thread_id = $1
       AND user_id = $2`,
    [safeThreadId, safeUserId]
  );
  const r = await q(
    `DELETE FROM social_chat_thread_member
     WHERE thread_id = $1
       AND user_id = $2
     RETURNING *`,
    [safeThreadId, safeUserId]
  );
  return r.rows[0] || null;
}

export async function updateGroupThreadMemberRole({
  threadId,
  userId,
  memberRole,
}) {
  const safeThreadId = Number(threadId);
  const safeUserId = Number(userId);
  const normalizedRole = String(memberRole || "member").trim().toLowerCase();
  const r = await q(
    `UPDATE social_chat_thread_member
     SET member_role = $3
     WHERE thread_id = $1
       AND user_id = $2
     RETURNING *`,
    [safeThreadId, safeUserId, normalizedRole]
  );
  return r.rows[0] || null;
}

export async function findDirectThreadBetweenUsers({ userAId, userBId }) {
  const a = Math.min(Number(userAId), Number(userBId));
  const b = Math.max(Number(userAId), Number(userBId));
  const r = await q(
    `SELECT *
     FROM social_chat_thread
     WHERE user_a_id = $1
       AND user_b_id = $2
       AND thread_kind = 'private'
       AND context_type = 'none'
       AND context_id = 0
     LIMIT 1`,
    [a, b]
  );
  return r.rows[0] || null;
}

async function getDirectOrBusinessThreadForUserRow({ threadId, userId }) {
  const r = await q(
    `SELECT
       t.*,
       CASE WHEN t.user_a_id = $2 THEN t.user_b_id ELSE t.user_a_id END AS peer_user_id,
       self_user.social_typing_indicators_enabled AS self_typing_indicators_enabled,
       peer.username AS peer_username,
       peer.full_name AS peer_full_name,
       peer.phone AS peer_phone,
       peer.role AS peer_role,
       peer.image_url AS peer_image_url,
       peer.social_online_visibility AS peer_online_visibility,
       peer.social_last_seen_visibility AS peer_last_seen_visibility,
       peer.social_read_receipts_enabled AS peer_read_receipts_enabled,
       peer.social_typing_indicators_enabled AS peer_typing_indicators_enabled,
       presence.heartbeat_at AS peer_presence_heartbeat_at,
       presence.last_seen_at AS peer_presence_last_seen_at,
       COALESCE(peer_premium.is_active, FALSE) AS peer_has_premium,
       chat_rel.status AS relation_status,
       self_state.inbox_bucket,
       self_state.request_status,
       self_state.accepted_at,
       self_state.rejected_at,
       self_state.muted_until,
       self_state.theme_key,
       self_state.last_read_message_id,
       self_state.last_delivered_message_id,
       peer_state.request_status AS peer_request_status,
       peer_state.last_read_message_id AS peer_last_read_message_id,
       peer_state.last_delivered_message_id AS peer_last_delivered_message_id
      FROM social_chat_thread t
      JOIN app_user self_user ON self_user.id = $2
      JOIN app_user peer ON peer.id = CASE WHEN t.user_a_id = $2 THEN t.user_b_id ELSE t.user_a_id END
      LEFT JOIN social_user_presence presence
        ON presence.user_id = CASE WHEN t.user_a_id = $2 THEN t.user_b_id ELSE t.user_a_id END
      LEFT JOIN social_user_relation chat_rel
        ON chat_rel.user_a_id = LEAST($2::bigint, CASE WHEN t.user_a_id = $2 THEN t.user_b_id ELSE t.user_a_id END)
       AND chat_rel.user_b_id = GREATEST($2::bigint, CASE WHEN t.user_a_id = $2 THEN t.user_b_id ELSE t.user_a_id END)
      LEFT JOIN LATERAL (
        SELECT TRUE AS is_active
        FROM paid_upgrade_subscription s
        JOIN paid_upgrade_plan plan ON plan.id = s.plan_id
        WHERE s.user_id = CASE WHEN t.user_a_id = $2 THEN t.user_b_id ELSE t.user_a_id END
          AND s.status = 'active'
          AND s.expires_at > NOW()
          AND plan.code = 'premium_monthly'
        LIMIT 1
      ) peer_premium ON TRUE
      LEFT JOIN social_chat_thread_participant_state self_state
        ON self_state.thread_id = t.id
       AND self_state.user_id = $2
      LEFT JOIN social_chat_thread_participant_state peer_state
        ON peer_state.thread_id = t.id
       AND peer_state.user_id = CASE WHEN t.user_a_id = $2 THEN t.user_b_id ELSE t.user_a_id END
      WHERE t.id = $1
        AND t.thread_kind <> 'group'
        AND (t.user_a_id = $2 OR t.user_b_id = $2)
      LIMIT 1`,
    [Number(threadId), Number(userId)]
  );
  return r.rows[0] || null;
}

async function getGroupThreadForUserRow({ threadId, userId }) {
  const r = await q(
    `SELECT
       t.*,
       0::bigint AS peer_user_id,
       self_user.social_typing_indicators_enabled AS self_typing_indicators_enabled,
       NULL::text AS peer_username,
       g.title AS peer_full_name,
       ''::text AS peer_phone,
       'group'::text AS peer_role,
       g.image_url AS peer_image_url,
       'nobody'::text AS peer_online_visibility,
       'nobody'::text AS peer_last_seen_visibility,
       FALSE AS peer_read_receipts_enabled,
       TRUE AS peer_typing_indicators_enabled,
       NULL::timestamptz AS peer_presence_heartbeat_at,
       NULL::timestamptz AS peer_presence_last_seen_at,
       FALSE AS peer_has_premium,
       'accepted'::text AS relation_status,
       self_state.inbox_bucket,
       self_state.request_status,
       self_state.accepted_at,
       self_state.rejected_at,
       self_state.muted_until,
       self_state.theme_key,
       self_state.last_read_message_id,
       self_state.last_delivered_message_id,
       NULL::text AS peer_request_status,
       NULL::bigint AS peer_last_read_message_id,
       NULL::bigint AS peer_last_delivered_message_id,
       g.owner_user_id AS group_owner_user_id,
       g.title AS group_title,
       g.image_url AS group_image_url,
       counts.member_count AS group_member_count,
       counts.admin_count AS group_admin_count,
       self_member.member_role AS group_member_role
      FROM social_chat_thread t
      JOIN app_user self_user ON self_user.id = $2
      JOIN social_chat_group g ON g.thread_id = t.id
      JOIN social_chat_thread_member self_member
        ON self_member.thread_id = t.id
       AND self_member.user_id = $2
      LEFT JOIN LATERAL (
        SELECT
          COUNT(*)::int AS member_count,
          COUNT(*) FILTER (WHERE member_role IN ('owner', 'admin'))::int AS admin_count
        FROM social_chat_thread_member gm
        WHERE gm.thread_id = t.id
      ) counts ON TRUE
      LEFT JOIN social_chat_thread_participant_state self_state
        ON self_state.thread_id = t.id
       AND self_state.user_id = $2
      WHERE t.id = $1
        AND t.thread_kind = 'group'
      LIMIT 1`,
    [Number(threadId), Number(userId)]
  );
  return r.rows[0] || null;
}

async function listDirectOrBusinessThreadsForUserRows({
  userId,
  limit = 50,
  inboxBucket = "primary",
  requestStatuses = null,
}) {
  const safeStatuses = Array.isArray(requestStatuses)
    ? [
        ...new Set(
          requestStatuses
            .map((value) => String(value || "").trim().toLowerCase())
            .filter((value) =>
              ["accepted", "pending", "rejected", "blocked"].includes(value)
            )
        ),
      ]
    : [];
  const r = await q(
    `SELECT
        t.id,
        t.user_a_id,
        t.user_b_id,
        t.thread_kind,
        t.context_type,
        t.context_id,
        t.context_status,
        t.context_snapshot_json,
        t.created_at,
        t.updated_at,
        t.last_message_at,
        CASE WHEN t.user_a_id = $1 THEN t.user_b_id ELSE t.user_a_id END AS peer_user_id,
        peer.username AS peer_username,
        peer.full_name AS peer_full_name,
        peer.phone AS peer_phone,
        peer.role AS peer_role,
        peer.image_url AS peer_image_url,
        peer.social_online_visibility AS peer_online_visibility,
        peer.social_last_seen_visibility AS peer_last_seen_visibility,
        peer.social_read_receipts_enabled AS peer_read_receipts_enabled,
        peer.social_typing_indicators_enabled AS peer_typing_indicators_enabled,
        presence.heartbeat_at AS peer_presence_heartbeat_at,
        presence.last_seen_at AS peer_presence_last_seen_at,
        COALESCE(peer_premium.is_active, FALSE) AS peer_has_premium,
        chat_rel.status AS relation_status,
        self_state.inbox_bucket,
        self_state.request_status,
        self_state.accepted_at,
        self_state.rejected_at,
        self_state.muted_until,
        self_state.pinned_at,
        self_state.theme_key,
        self_state.last_read_message_id,
        self_state.last_delivered_message_id,
        lm.id AS last_message_id,
        lm.sender_user_id AS last_message_sender_user_id,
        lm.body AS last_message_body,
        lm.created_at AS last_message_created_at,
        lm.attachment_url AS last_message_attachment_url,
        lm.attachment_kind AS last_message_attachment_kind,
        lm.attachment_name AS last_message_attachment_name,
        lm.shared_entity_type AS last_message_shared_entity_type,
        lm.shared_entity_id AS last_message_shared_entity_id,
        lm.shared_snapshot_json AS last_message_shared_snapshot_json
      FROM social_chat_thread t
      JOIN app_user peer ON peer.id = CASE WHEN t.user_a_id = $1 THEN t.user_b_id ELSE t.user_a_id END
      LEFT JOIN social_user_presence presence
        ON presence.user_id = CASE WHEN t.user_a_id = $1 THEN t.user_b_id ELSE t.user_a_id END
      LEFT JOIN social_user_relation chat_rel
        ON chat_rel.user_a_id = LEAST($1::bigint, CASE WHEN t.user_a_id = $1 THEN t.user_b_id ELSE t.user_a_id END)
       AND chat_rel.user_b_id = GREATEST($1::bigint, CASE WHEN t.user_a_id = $1 THEN t.user_b_id ELSE t.user_a_id END)
      LEFT JOIN LATERAL (
        SELECT TRUE AS is_active
        FROM paid_upgrade_subscription s
        JOIN paid_upgrade_plan plan ON plan.id = s.plan_id
        WHERE s.user_id = CASE WHEN t.user_a_id = $1 THEN t.user_b_id ELSE t.user_a_id END
          AND s.status = 'active'
          AND s.expires_at > NOW()
          AND plan.code = 'premium_monthly'
        LIMIT 1
      ) peer_premium ON TRUE
      LEFT JOIN social_chat_thread_participant_state self_state
        ON self_state.thread_id = t.id
       AND self_state.user_id = $1
      LEFT JOIN LATERAL (
        SELECT
          m.id,
          m.sender_user_id,
          m.body,
          m.created_at,
          m.attachment_url,
          m.attachment_kind,
          m.attachment_name,
          m.shared_entity_type,
          m.shared_entity_id,
          m.shared_snapshot_json
        FROM social_chat_message m
        WHERE m.thread_id = t.id
          AND m.is_deleted = FALSE
        ORDER BY m.id DESC
        LIMIT 1
      ) lm ON TRUE
      WHERE t.thread_kind <> 'group'
        AND (t.user_a_id = $1 OR t.user_b_id = $1)
        AND COALESCE(self_state.inbox_bucket, 'primary') = $3
        AND (
          CARDINALITY($4::text[]) = 0
          OR COALESCE(self_state.request_status, 'accepted') = ANY($4::text[])
        )
      ORDER BY COALESCE(lm.created_at, t.last_message_at) DESC, t.id DESC
      LIMIT $2`,
    [
      Number(userId),
      Number(limit),
      String(inboxBucket || "primary").trim().toLowerCase() === "requests"
        ? "requests"
        : "primary",
      safeStatuses,
    ]
  );
  return r.rows;
}

async function listGroupThreadsForUserRows({ userId, limit = 50, inboxBucket = "primary" }) {
  if (String(inboxBucket || "primary").trim().toLowerCase() === "requests") {
    return [];
  }
  const r = await q(
    `SELECT
        t.id,
        t.user_a_id,
        t.user_b_id,
        t.thread_kind,
        t.context_type,
        t.context_id,
        t.context_status,
        t.context_snapshot_json,
        t.created_at,
        t.updated_at,
        t.last_message_at,
        0::bigint AS peer_user_id,
        NULL::text AS peer_username,
        g.title AS peer_full_name,
        ''::text AS peer_phone,
        'group'::text AS peer_role,
        g.image_url AS peer_image_url,
        'nobody'::text AS peer_online_visibility,
        'nobody'::text AS peer_last_seen_visibility,
        FALSE AS peer_read_receipts_enabled,
        TRUE AS peer_typing_indicators_enabled,
        NULL::timestamptz AS peer_presence_heartbeat_at,
        NULL::timestamptz AS peer_presence_last_seen_at,
        FALSE AS peer_has_premium,
        'accepted'::text AS relation_status,
        self_state.inbox_bucket,
        self_state.request_status,
        self_state.accepted_at,
        self_state.rejected_at,
        self_state.muted_until,
        self_state.pinned_at,
        self_state.theme_key,
        self_state.last_read_message_id,
        self_state.last_delivered_message_id,
        lm.id AS last_message_id,
        lm.sender_user_id AS last_message_sender_user_id,
        lm.body AS last_message_body,
        lm.created_at AS last_message_created_at,
        lm.attachment_url AS last_message_attachment_url,
        lm.attachment_kind AS last_message_attachment_kind,
        lm.attachment_name AS last_message_attachment_name,
        lm.shared_entity_type AS last_message_shared_entity_type,
        lm.shared_entity_id AS last_message_shared_entity_id,
        lm.shared_snapshot_json AS last_message_shared_snapshot_json,
        g.owner_user_id AS group_owner_user_id,
        g.title AS group_title,
        g.image_url AS group_image_url,
        counts.member_count AS group_member_count,
        counts.admin_count AS group_admin_count,
        self_member.member_role AS group_member_role
      FROM social_chat_thread t
      JOIN social_chat_group g ON g.thread_id = t.id
      JOIN social_chat_thread_member self_member
        ON self_member.thread_id = t.id
       AND self_member.user_id = $1
      LEFT JOIN social_chat_thread_participant_state self_state
        ON self_state.thread_id = t.id
       AND self_state.user_id = $1
      LEFT JOIN LATERAL (
        SELECT
          COUNT(*)::int AS member_count,
          COUNT(*) FILTER (WHERE member_role IN ('owner', 'admin'))::int AS admin_count
        FROM social_chat_thread_member gm
        WHERE gm.thread_id = t.id
      ) counts ON TRUE
      LEFT JOIN LATERAL (
        SELECT
          m.id,
          m.sender_user_id,
          m.body,
          m.created_at,
          m.attachment_url,
          m.attachment_kind,
          m.attachment_name,
          m.shared_entity_type,
          m.shared_entity_id,
          m.shared_snapshot_json
        FROM social_chat_message m
        WHERE m.thread_id = t.id
          AND m.is_deleted = FALSE
        ORDER BY m.id DESC
        LIMIT 1
      ) lm ON TRUE
      WHERE t.thread_kind = 'group'
        AND COALESCE(self_state.inbox_bucket, 'primary') = 'primary'
        AND COALESCE(self_state.request_status, 'accepted') = 'accepted'
      ORDER BY COALESCE(lm.created_at, t.last_message_at) DESC, t.id DESC
      LIMIT $2`,
    [Number(userId), Number(limit)]
  );
  return r.rows;
}

export async function hasActiveOrderChatAccess({ userId, otherUserId }) {
  const r = await q(
    `SELECT 1
     FROM customer_order o
     WHERE (
         (o.customer_user_id = $1 AND o.delivery_user_id = $2)
         OR (o.customer_user_id = $2 AND o.delivery_user_id = $1)
       )
       AND (
         o.status::text = ANY($3::text[])
         OR (o.status = 'delivered' AND o.customer_confirmed_at IS NULL)
       )
     LIMIT 1`,
    [
      Number(userId),
      Number(otherUserId),
      ["approved", "preparing", "ready_for_delivery", "on_the_way", "arrived"],
    ]
  );
  return Boolean(r.rows[0]);
}

export async function getThreadForUser({ threadId, userId }) {
  const directOrBusiness = await getDirectOrBusinessThreadForUserRow({
    threadId,
    userId,
  });
  if (directOrBusiness) return directOrBusiness;
  return getGroupThreadForUserRow({ threadId, userId });
}

export async function listThreadsForUser({
  userId,
  limit = 50,
  inboxBucket = "primary",
  requestStatuses = null,
}) {
  const [directOrBusinessRows, groupRows] = await Promise.all([
    listDirectOrBusinessThreadsForUserRows({
      userId,
      limit,
      inboxBucket,
      requestStatuses,
    }),
    listGroupThreadsForUserRows({ userId, limit, inboxBucket }),
  ]);
  return [...directOrBusinessRows, ...groupRows]
    .sort((a, b) => {
      const aAt = new Date(a.last_message_created_at || a.last_message_at || 0).getTime();
      const bAt = new Date(b.last_message_created_at || b.last_message_at || 0).getTime();
      const aPinnedAt = a.pinned_at ? new Date(a.pinned_at).getTime() : 0;
      const bPinnedAt = b.pinned_at ? new Date(b.pinned_at).getTime() : 0;
      if (aPinnedAt !== bPinnedAt) return bPinnedAt - aPinnedAt;
      if (aAt !== bAt) return bAt - aAt;
      return Number(b.id || 0) - Number(a.id || 0);
    })
    .slice(0, Math.max(1, Number(limit) || 50));
}

export async function listMessagesForThread({
  threadId,
  limit = 40,
  beforeId = null,
}) {
  const r = await q(
    `SELECT
       m.id,
       m.thread_id,
       m.sender_user_id,
       m.body,
       m.client_message_id,
       m.is_deleted,
       m.reply_to_message_id,
       m.attachment_url,
       m.attachment_kind,
       m.attachment_name,
       m.attachment_mime_type,
       m.attachment_size_bytes,
       m.attachment_duration_ms,
       m.attachment_provider,
       m.attachment_preview_url,
       m.attachment_thumbnail_url,
       m.attachment_width,
       m.attachment_height,
       m.attachment_upload_state,
       m.attachment_trace_id,
       pm.pinned_at,
       pm.pinned_by_user_id,
       m.shared_entity_type,
       m.shared_entity_id,
       m.shared_snapshot_json,
       m.created_at,
       m.updated_at,
       m.edited_at,
       m.deleted_at,
       u.username AS sender_username,
       u.full_name AS sender_full_name,
       u.phone AS sender_phone,
       u.role AS sender_role,
       u.image_url AS sender_image_url,
       COALESCE(sender_premium.is_active, FALSE) AS sender_has_premium,
       rm.id AS reply_message_id,
       rm.sender_user_id AS reply_sender_user_id,
       rm.body AS reply_body,
       rm.attachment_kind AS reply_attachment_kind,
       rm.attachment_name AS reply_attachment_name,
       ru.username AS reply_sender_username,
       ru.full_name AS reply_sender_full_name
     FROM social_chat_message m
     JOIN app_user u ON u.id = m.sender_user_id
     LEFT JOIN social_chat_thread_pinned_message pm
       ON pm.thread_id = m.thread_id
      AND pm.message_id = m.id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_active
       FROM paid_upgrade_subscription s
       JOIN paid_upgrade_plan plan ON plan.id = s.plan_id
       WHERE s.user_id = m.sender_user_id
         AND s.status = 'active'
         AND s.expires_at > NOW()
         AND plan.code = 'premium_monthly'
       LIMIT 1
     ) sender_premium ON TRUE
     LEFT JOIN social_chat_message rm
       ON rm.id = m.reply_to_message_id
      AND rm.is_deleted = FALSE
     LEFT JOIN app_user ru ON ru.id = rm.sender_user_id
     WHERE m.thread_id = $1
       AND ($2::bigint IS NULL OR m.id < $2::bigint)
     ORDER BY m.id DESC
     LIMIT $3`,
    [Number(threadId), beforeId, Number(limit)]
  );
  return r.rows;
}

export async function searchMessagesInThread({
  threadId,
  search,
  limit = 20,
  beforeId = null,
}) {
  const normalizedSearch = String(search || "").trim();
  const like = `%${normalizedSearch}%`;
  const r = await q(
    `SELECT
       m.id,
       m.thread_id,
       m.sender_user_id,
       m.body,
       m.client_message_id,
       m.is_deleted,
       m.reply_to_message_id,
       m.attachment_url,
       m.attachment_kind,
       m.attachment_name,
       m.attachment_mime_type,
       m.attachment_size_bytes,
       m.attachment_duration_ms,
       m.attachment_provider,
       m.attachment_preview_url,
       m.attachment_thumbnail_url,
       m.attachment_width,
       m.attachment_height,
       m.attachment_upload_state,
       m.attachment_trace_id,
       pm.pinned_at,
       pm.pinned_by_user_id,
       m.shared_entity_type,
       m.shared_entity_id,
       m.shared_snapshot_json,
       m.created_at,
       m.updated_at,
       m.edited_at,
       m.deleted_at,
       u.username AS sender_username,
       u.full_name AS sender_full_name,
       u.phone AS sender_phone,
       u.role AS sender_role,
       u.image_url AS sender_image_url,
       COALESCE(sender_premium.is_active, FALSE) AS sender_has_premium,
       rm.id AS reply_message_id,
       rm.sender_user_id AS reply_sender_user_id,
       rm.body AS reply_body,
       rm.attachment_kind AS reply_attachment_kind,
       rm.attachment_name AS reply_attachment_name,
       ru.username AS reply_sender_username,
       ru.full_name AS reply_sender_full_name
     FROM social_chat_message m
     JOIN app_user u ON u.id = m.sender_user_id
     LEFT JOIN social_chat_thread_pinned_message pm
       ON pm.thread_id = m.thread_id
      AND pm.message_id = m.id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_active
       FROM paid_upgrade_subscription s
       JOIN paid_upgrade_plan plan ON plan.id = s.plan_id
       WHERE s.user_id = m.sender_user_id
         AND s.status = 'active'
         AND s.expires_at > NOW()
         AND plan.code = 'premium_monthly'
       LIMIT 1
     ) sender_premium ON TRUE
     LEFT JOIN social_chat_message rm
       ON rm.id = m.reply_to_message_id
      AND rm.is_deleted = FALSE
     LEFT JOIN app_user ru ON ru.id = rm.sender_user_id
     WHERE m.thread_id = $1
       AND m.is_deleted = FALSE
       AND ($2::bigint IS NULL OR m.id < $2::bigint)
       AND (
         COALESCE(m.body, '') ILIKE $3
         OR COALESCE(m.attachment_name, '') ILIKE $3
       )
     ORDER BY m.id DESC
     LIMIT $4`,
    [
      Number(threadId),
      beforeId,
      like,
      Math.max(1, Math.min(60, Number(limit) || 20)),
    ]
  );
  return r.rows;
}

export async function listPinnedMessagesForThread({
  threadId,
  limit = 3,
}) {
  const r = await q(
    `SELECT
       m.id,
       m.thread_id,
       m.sender_user_id,
       m.body,
       m.client_message_id,
       m.is_deleted,
       m.reply_to_message_id,
       m.attachment_url,
       m.attachment_kind,
       m.attachment_name,
       m.attachment_mime_type,
       m.attachment_size_bytes,
       m.attachment_duration_ms,
       m.attachment_provider,
       m.attachment_preview_url,
       m.attachment_thumbnail_url,
       m.attachment_width,
       m.attachment_height,
       m.attachment_upload_state,
       m.attachment_trace_id,
       pm.pinned_at,
       pm.pinned_by_user_id,
       m.shared_entity_type,
       m.shared_entity_id,
       m.shared_snapshot_json,
       m.created_at,
       m.updated_at,
       m.edited_at,
       m.deleted_at,
       u.username AS sender_username,
       u.full_name AS sender_full_name,
       u.phone AS sender_phone,
       u.role AS sender_role,
       u.image_url AS sender_image_url,
       COALESCE(sender_premium.is_active, FALSE) AS sender_has_premium,
       rm.id AS reply_message_id,
       rm.sender_user_id AS reply_sender_user_id,
       rm.body AS reply_body,
       rm.attachment_kind AS reply_attachment_kind,
       rm.attachment_name AS reply_attachment_name,
       ru.username AS reply_sender_username,
       ru.full_name AS reply_sender_full_name
     FROM social_chat_thread_pinned_message pm
     JOIN social_chat_message m
       ON m.thread_id = pm.thread_id
      AND m.id = pm.message_id
      AND m.is_deleted = FALSE
     JOIN app_user u ON u.id = m.sender_user_id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_active
       FROM paid_upgrade_subscription s
       JOIN paid_upgrade_plan plan ON plan.id = s.plan_id
       WHERE s.user_id = m.sender_user_id
         AND s.status = 'active'
         AND s.expires_at > NOW()
         AND plan.code = 'premium_monthly'
       LIMIT 1
     ) sender_premium ON TRUE
     LEFT JOIN social_chat_message rm
       ON rm.id = m.reply_to_message_id
      AND rm.is_deleted = FALSE
     LEFT JOIN app_user ru ON ru.id = rm.sender_user_id
     WHERE pm.thread_id = $1
     ORDER BY pm.pinned_at DESC, pm.message_id DESC
     LIMIT $2`,
    [Number(threadId), Math.max(1, Math.min(3, Number(limit) || 3))]
  );
  return r.rows;
}

export async function countPinnedMessagesForThread({ threadId }) {
  const r = await q(
    `SELECT COUNT(*)::int AS pinned_count
     FROM social_chat_thread_pinned_message
     WHERE thread_id = $1`,
    [Number(threadId)]
  );
  return Number(r.rows[0]?.pinned_count || 0);
}

export async function isThreadMessagePinned({ threadId, messageId }) {
  const r = await q(
    `SELECT pinned_at
     FROM social_chat_thread_pinned_message
     WHERE thread_id = $1
       AND message_id = $2
     LIMIT 1`,
    [Number(threadId), Number(messageId)]
  );
  return Boolean(r.rows[0]?.pinned_at);
}

export async function pinThreadMessage({
  threadId,
  messageId,
  pinnedByUserId,
}) {
  const r = await q(
    `INSERT INTO social_chat_thread_pinned_message
      (thread_id, message_id, pinned_by_user_id)
     VALUES ($1, $2, $3)
     ON CONFLICT (thread_id, message_id)
     DO UPDATE SET
       pinned_by_user_id = EXCLUDED.pinned_by_user_id,
       pinned_at = NOW()
     RETURNING *`,
    [Number(threadId), Number(messageId), Number(pinnedByUserId)]
  );
  return r.rows[0] || null;
}

export async function unpinThreadMessage({ threadId, messageId }) {
  const r = await q(
    `DELETE FROM social_chat_thread_pinned_message
     WHERE thread_id = $1
       AND message_id = $2`,
    [Number(threadId), Number(messageId)]
  );
  return (r.rowCount || 0) > 0;
}

export async function getThreadMessageById({ threadId, messageId }) {
  const r = await q(
    `SELECT *
     FROM social_chat_message
     WHERE id = $1
       AND thread_id = $2
       AND is_deleted = FALSE
     LIMIT 1`,
    [Number(messageId), Number(threadId)]
  );
  return r.rows[0] || null;
}

export async function getThreadMessageDetailsById({
  threadId,
  messageId,
  includeDeleted = false,
}) {
  const r = await q(
    `SELECT
       m.id,
       m.thread_id,
       m.sender_user_id,
       m.body,
       m.client_message_id,
       m.is_deleted,
       m.reply_to_message_id,
       m.attachment_url,
       m.attachment_kind,
       m.attachment_name,
       m.attachment_mime_type,
       m.attachment_size_bytes,
       m.attachment_duration_ms,
       m.attachment_provider,
       m.attachment_preview_url,
       m.attachment_thumbnail_url,
       m.attachment_width,
       m.attachment_height,
       m.attachment_upload_state,
       m.attachment_trace_id,
       pm.pinned_at,
       pm.pinned_by_user_id,
       m.shared_entity_type,
       m.shared_entity_id,
       m.shared_snapshot_json,
       m.created_at,
       m.updated_at,
       m.edited_at,
       m.deleted_at,
       u.username AS sender_username,
       u.full_name AS sender_full_name,
       u.phone AS sender_phone,
       u.role AS sender_role,
       u.image_url AS sender_image_url,
       COALESCE(sender_premium.is_active, FALSE) AS sender_has_premium,
       rm.id AS reply_message_id,
       rm.sender_user_id AS reply_sender_user_id,
       rm.body AS reply_body,
       rm.attachment_kind AS reply_attachment_kind,
       rm.attachment_name AS reply_attachment_name,
       ru.username AS reply_sender_username,
       ru.full_name AS reply_sender_full_name
     FROM social_chat_message m
     JOIN app_user u ON u.id = m.sender_user_id
     LEFT JOIN social_chat_thread_pinned_message pm
       ON pm.thread_id = m.thread_id
      AND pm.message_id = m.id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_active
       FROM paid_upgrade_subscription s
       JOIN paid_upgrade_plan plan ON plan.id = s.plan_id
       WHERE s.user_id = m.sender_user_id
         AND s.status = 'active'
         AND s.expires_at > NOW()
         AND plan.code = 'premium_monthly'
       LIMIT 1
     ) sender_premium ON TRUE
     LEFT JOIN social_chat_message rm
       ON rm.id = m.reply_to_message_id
      AND rm.is_deleted = FALSE
     LEFT JOIN app_user ru ON ru.id = rm.sender_user_id
     WHERE m.id = $1
       AND m.thread_id = $2
       AND ($3::boolean = TRUE OR m.is_deleted = FALSE)
     LIMIT 1`,
    [Number(messageId), Number(threadId), includeDeleted === true]
  );
  return r.rows[0] || null;
}

/**
 * يحدث last seen للمستخدم مع throttling داخل العملية لتقليل ضغط DB.
 */
export async function touchUserPresence(userId) {
  const normalizedUserId = Number(userId);
  if (!Number.isInteger(normalizedUserId) || normalizedUserId <= 0) {
    return null;
  }
  const now = Date.now();
  const cachedAt = Number(userPresenceHeartbeatCache.get(normalizedUserId) || 0);
  if (cachedAt > 0 && now - cachedAt < PRESENCE_HEARTBEAT_THROTTLE_MS) {
    return null;
  }
  const r = await q(
    `INSERT INTO social_user_presence (user_id, heartbeat_at, last_seen_at)
     VALUES ($1, NOW(), NOW())
     ON CONFLICT (user_id)
     DO UPDATE SET
       heartbeat_at = NOW(),
       last_seen_at = NOW()
     RETURNING *`,
    [normalizedUserId]
  );
  userPresenceHeartbeatCache.set(normalizedUserId, now);
  return r.rows[0] || null;
}

export async function getLatestThreadMessageId(threadId) {
  const r = await q(
    `SELECT id
     FROM social_chat_message
     WHERE thread_id = $1
     ORDER BY id DESC
     LIMIT 1`,
    [Number(threadId)]
  );
  const value = Number(r.rows[0]?.id || 0);
  return Number.isInteger(value) && value > 0 ? value : null;
}

export async function listMessageReactionsForMessages({ messageIds, userId }) {
  const ids = Array.isArray(messageIds)
    ? [...new Set(messageIds.map((v) => Number(v)).filter((v) => Number.isFinite(v) && v > 0))]
    : [];
  if (ids.length <= 0) return {};

  const countsRes = await q(
    `SELECT
       message_id,
       reaction,
       COUNT(*)::int AS reaction_count
     FROM social_chat_message_reaction
     WHERE message_id = ANY($1::bigint[])
     GROUP BY message_id, reaction`,
    [ids]
  );

  const mineRes = await q(
    `SELECT message_id, reaction
     FROM social_chat_message_reaction
     WHERE user_id = $1
       AND message_id = ANY($2::bigint[])`,
    [Number(userId), ids]
  );

  const out = {};
  for (const id of ids) {
    out[id] = { counts: {}, myReaction: null, totalCount: 0 };
  }

  for (const row of countsRes.rows) {
    const messageId = Number(row.message_id);
    const reaction = String(row.reaction || "").trim();
    const count = Number(row.reaction_count || 0);
    if (!out[messageId] || !reaction) continue;
    out[messageId].counts[reaction] = count;
    out[messageId].totalCount += count;
  }

  for (const row of mineRes.rows) {
    const messageId = Number(row.message_id);
    const reaction = String(row.reaction || "").trim();
    if (!out[messageId] || !reaction) continue;
    out[messageId].myReaction = reaction;
  }

  return out;
}

export async function toggleMessageReaction({ messageId, userId, reaction }) {
  const targetReaction = String(reaction || "").trim().toLowerCase();
  const allowed = new Set(["like", "heart", "laugh", "fire"]);
  const safeReaction = allowed.has(targetReaction) ? targetReaction : "like";

  const existingRes = await q(
    `SELECT reaction
     FROM social_chat_message_reaction
     WHERE message_id = $1
       AND user_id = $2
     LIMIT 1`,
    [Number(messageId), Number(userId)]
  );
  const existing = existingRes.rows[0] || null;

  if (existing && String(existing.reaction || "").trim().toLowerCase() === safeReaction) {
    await q(
      `DELETE FROM social_chat_message_reaction
       WHERE message_id = $1
         AND user_id = $2`,
      [Number(messageId), Number(userId)]
    );
    return { active: false, reaction: null };
  }

  await q(
    `INSERT INTO social_chat_message_reaction (message_id, user_id, reaction)
     VALUES ($1, $2, $3)
     ON CONFLICT (message_id, user_id)
     DO UPDATE SET
       reaction = EXCLUDED.reaction,
       updated_at = NOW()`,
    [Number(messageId), Number(userId), safeReaction]
  );
  return { active: true, reaction: safeReaction };
}

/**
 * يخزن رسالة thread واحدة مع المرفقات والـ shared entity metadata.
 */
export async function insertThreadMessage({
  threadId,
  senderUserId,
  body,
  replyToMessageId = null,
  attachment = null,
  sharedEntity = null,
  clientMessageId = null,
}) {
  const normalizedClientMessageId =
    clientMessageId == null ? null : String(clientMessageId).trim();
  if (normalizedClientMessageId) {
    const r = await q(
      `WITH inserted AS (
         INSERT INTO social_chat_message
           (
             thread_id,
             sender_user_id,
             body,
             reply_to_message_id,
             attachment_url,
             attachment_kind,
             attachment_name,
             attachment_mime_type,
             attachment_size_bytes,
             attachment_duration_ms,
             attachment_provider,
             attachment_preview_url,
             attachment_thumbnail_url,
             attachment_width,
             attachment_height,
             attachment_upload_state,
             attachment_trace_id,
             shared_entity_type,
             shared_entity_id,
             shared_snapshot_json,
             client_message_id
           )
         VALUES (
           $1, $2, $3, $4, $5,
           $6, $7, $8, $9, $10,
           $11, $12, $13, $14, $15,
           $16, $17, $18, $19, $20,
           $21
         )
         ON CONFLICT (thread_id, sender_user_id, client_message_id)
         WHERE client_message_id IS NOT NULL
         DO NOTHING
         RETURNING *, TRUE AS _inserted
       ),
       existing AS (
         SELECT m.*, FALSE AS _inserted
         FROM social_chat_message m
         WHERE m.thread_id = $1
           AND m.sender_user_id = $2
           AND m.client_message_id = $21
         LIMIT 1
       )
       SELECT *
       FROM inserted
       UNION ALL
       SELECT *
       FROM existing
       WHERE NOT EXISTS (SELECT 1 FROM inserted)
       LIMIT 1`,
      [
        Number(threadId),
        Number(senderUserId),
        String(body || "").trim(),
        replyToMessageId == null ? null : Number(replyToMessageId),
        attachment?.url || null,
        attachment?.kind || null,
        attachment?.name || null,
        attachment?.mimeType || null,
        attachment?.sizeBytes == null ? null : Number(attachment.sizeBytes),
        attachment?.durationMs == null ? null : Number(attachment.durationMs),
        attachment?.provider == null ? null : String(attachment.provider).trim() || null,
        attachment?.previewUrl == null ? null : String(attachment.previewUrl).trim() || null,
        attachment?.thumbnailUrl == null
          ? null
          : String(attachment.thumbnailUrl).trim() || null,
        attachment?.width == null ? null : Number(attachment.width),
        attachment?.height == null ? null : Number(attachment.height),
        attachment?.uploadState == null
          ? null
          : String(attachment.uploadState).trim().toUpperCase() || null,
        attachment?.traceId == null ? null : String(attachment.traceId).trim() || null,
        sharedEntity?.type || null,
        sharedEntity?.id == null ? null : Number(sharedEntity.id),
        sharedEntity?.snapshot == null ? null : JSON.stringify(sharedEntity.snapshot),
        normalizedClientMessageId,
      ]
    );
    return r.rows[0] || null;
  }

  const r = await q(
    `INSERT INTO social_chat_message
      (
        thread_id,
        sender_user_id,
        body,
        reply_to_message_id,
        attachment_url,
        attachment_kind,
        attachment_name,
        attachment_mime_type,
        attachment_size_bytes,
        attachment_duration_ms,
        attachment_provider,
        attachment_preview_url,
        attachment_thumbnail_url,
        attachment_width,
        attachment_height,
        attachment_upload_state,
        attachment_trace_id,
        shared_entity_type,
        shared_entity_id,
        shared_snapshot_json
      )
     VALUES (
       $1, $2, $3, $4, $5,
       $6, $7, $8, $9, $10,
       $11, $12, $13, $14, $15,
       $16, $17, $18, $19, $20
     )
     RETURNING *`,
    [
      Number(threadId),
      Number(senderUserId),
      String(body || "").trim(),
      replyToMessageId == null ? null : Number(replyToMessageId),
      attachment?.url || null,
      attachment?.kind || null,
      attachment?.name || null,
      attachment?.mimeType || null,
      attachment?.sizeBytes == null ? null : Number(attachment.sizeBytes),
      attachment?.durationMs == null ? null : Number(attachment.durationMs),
      attachment?.provider == null ? null : String(attachment.provider).trim() || null,
      attachment?.previewUrl == null ? null : String(attachment.previewUrl).trim() || null,
      attachment?.thumbnailUrl == null
        ? null
        : String(attachment.thumbnailUrl).trim() || null,
      attachment?.width == null ? null : Number(attachment.width),
      attachment?.height == null ? null : Number(attachment.height),
      attachment?.uploadState == null
        ? null
        : String(attachment.uploadState).trim().toUpperCase() || null,
      attachment?.traceId == null ? null : String(attachment.traceId).trim() || null,
      sharedEntity?.type || null,
      sharedEntity?.id == null ? null : Number(sharedEntity.id),
      sharedEntity?.snapshot == null ? null : JSON.stringify(sharedEntity.snapshot),
    ]
  );
  const row = r.rows[0] || null;
  return row ? { ...row, _inserted: true } : null;
}

export async function insertScheduledThreadMessage({
  threadId,
  senderUserId,
  body,
  scheduledFor,
  replyToMessageId = null,
  attachment = null,
  sharedEntity = null,
}) {
  const r = await q(
    `INSERT INTO social_chat_scheduled_message
      (
        thread_id,
        sender_user_id,
        body,
        reply_to_message_id,
        attachment_url,
        attachment_kind,
        attachment_name,
        attachment_mime_type,
        attachment_size_bytes,
        attachment_duration_ms,
        attachment_provider,
        attachment_preview_url,
        attachment_thumbnail_url,
        attachment_width,
        attachment_height,
        attachment_upload_state,
        attachment_trace_id,
        shared_entity_type,
        shared_entity_id,
        shared_snapshot_json,
        scheduled_for
      )
     VALUES (
       $1, $2, $3, $4, $5,
       $6, $7, $8, $9, $10,
       $11, $12, $13, $14, $15,
       $16, $17, $18, $19, $20,
       $21
     )
     RETURNING *`,
    [
      Number(threadId),
      Number(senderUserId),
      String(body || "").trim(),
      replyToMessageId == null ? null : Number(replyToMessageId),
      attachment?.url || null,
      attachment?.kind || null,
      attachment?.name || null,
      attachment?.mimeType || null,
      attachment?.sizeBytes == null ? null : Number(attachment.sizeBytes),
      attachment?.durationMs == null ? null : Number(attachment.durationMs),
      attachment?.provider == null ? null : String(attachment.provider).trim() || null,
      attachment?.previewUrl == null ? null : String(attachment.previewUrl).trim() || null,
      attachment?.thumbnailUrl == null
        ? null
        : String(attachment.thumbnailUrl).trim() || null,
      attachment?.width == null ? null : Number(attachment.width),
      attachment?.height == null ? null : Number(attachment.height),
      attachment?.uploadState == null
        ? null
        : String(attachment.uploadState).trim().toUpperCase() || null,
      attachment?.traceId == null ? null : String(attachment.traceId).trim() || null,
      sharedEntity?.type || null,
      sharedEntity?.id == null ? null : Number(sharedEntity.id),
      sharedEntity?.snapshot == null ? null : JSON.stringify(sharedEntity.snapshot),
      new Date(scheduledFor).toISOString(),
    ]
  );
  return r.rows[0] || null;
}

export async function listScheduledMessagesForUserThread({
  threadId,
  userId,
  limit = 20,
}) {
  const r = await q(
    `SELECT
       sm.id,
       sm.thread_id,
       sm.sender_user_id,
       sm.body,
       sm.reply_to_message_id,
       sm.attachment_url,
       sm.attachment_kind,
       sm.attachment_name,
       sm.attachment_mime_type,
       sm.attachment_size_bytes,
       sm.attachment_duration_ms,
       sm.attachment_provider,
       sm.attachment_preview_url,
       sm.attachment_thumbnail_url,
       sm.attachment_width,
       sm.attachment_height,
       sm.attachment_upload_state,
       sm.attachment_trace_id,
       sm.shared_entity_type,
       sm.shared_entity_id,
       sm.shared_snapshot_json,
       sm.scheduled_for,
       sm.status,
       sm.attempts,
       sm.last_error_code,
       sm.sent_message_id,
       sm.sent_at,
       sm.created_at,
       rm.id AS reply_message_id,
       rm.sender_user_id AS reply_sender_user_id,
       rm.body AS reply_body,
       rm.attachment_kind AS reply_attachment_kind,
       rm.attachment_name AS reply_attachment_name,
       ru.username AS reply_sender_username,
       ru.full_name AS reply_sender_full_name
     FROM social_chat_scheduled_message sm
     LEFT JOIN social_chat_message rm
       ON rm.id = sm.reply_to_message_id
      AND rm.is_deleted = FALSE
     LEFT JOIN app_user ru ON ru.id = rm.sender_user_id
     WHERE sm.thread_id = $1
       AND sm.sender_user_id = $2
       AND sm.status IN ('scheduled', 'processing', 'failed')
     ORDER BY sm.scheduled_for ASC, sm.id ASC
     LIMIT $3`,
    [Number(threadId), Number(userId), Math.max(1, Math.min(60, Number(limit) || 20))]
  );
  return r.rows;
}

export async function cancelScheduledThreadMessage({
  threadId,
  scheduledMessageId,
  senderUserId,
}) {
  const r = await q(
    `UPDATE social_chat_scheduled_message
     SET status = 'cancelled',
         cancelled_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND thread_id = $2
       AND sender_user_id = $3
       AND status IN ('scheduled', 'failed')
     RETURNING *`,
    [Number(scheduledMessageId), Number(threadId), Number(senderUserId)]
  );
  return r.rows[0] || null;
}

export async function listDueScheduledThreadMessages({ limit = 20 }) {
  const r = await q(
    `SELECT
       sm.*
     FROM social_chat_scheduled_message sm
     WHERE sm.status = 'scheduled'
       AND sm.scheduled_for <= NOW()
     ORDER BY sm.scheduled_for ASC, sm.id ASC
     LIMIT $1`,
    [Math.max(1, Math.min(100, Number(limit) || 20))]
  );
  return r.rows;
}

export async function claimScheduledThreadMessage({ scheduledMessageId }) {
  const r = await q(
    `UPDATE social_chat_scheduled_message
     SET status = 'processing',
         processing_started_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND status = 'scheduled'
       AND scheduled_for <= NOW()
     RETURNING *`,
    [Number(scheduledMessageId)]
  );
  return r.rows[0] || null;
}

export async function markScheduledThreadMessageSent({
  scheduledMessageId,
  sentMessageId,
}) {
  const r = await q(
    `UPDATE social_chat_scheduled_message
     SET status = 'sent',
         sent_message_id = $2,
         sent_at = NOW(),
         processing_started_at = NULL,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(scheduledMessageId), Number(sentMessageId)]
  );
  return r.rows[0] || null;
}

export async function rescheduleScheduledThreadMessageFailure({
  scheduledMessageId,
  errorCode = null,
}) {
  const r = await q(
    `UPDATE social_chat_scheduled_message
     SET attempts = attempts + 1,
         last_error_code = $2,
         scheduled_for = CASE
           WHEN attempts + 1 >= 5 THEN scheduled_for
           ELSE NOW() + make_interval(secs => LEAST(300, 30 * (attempts + 1)))
         END,
         status = CASE
           WHEN attempts + 1 >= 5 THEN 'failed'
           ELSE 'scheduled'
         END,
         processing_started_at = NULL,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(scheduledMessageId), errorCode == null ? null : String(errorCode).slice(0, 80)]
  );
  return r.rows[0] || null;
}

export async function updateThreadMessage({
  threadId,
  messageId,
  body,
}) {
  const r = await q(
    `UPDATE social_chat_message
     SET body = $3,
         edited_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND thread_id = $2
       AND is_deleted = FALSE
     RETURNING *`,
    [Number(messageId), Number(threadId), String(body || "").trim()]
  );
  return r.rows[0] || null;
}

export async function softDeleteThreadMessage({
  threadId,
  messageId,
}) {
  await q(
    `DELETE FROM social_chat_thread_pinned_message
     WHERE thread_id = $1
       AND message_id = $2`,
    [Number(threadId), Number(messageId)]
  );
  const r = await q(
    `UPDATE social_chat_message
     SET is_deleted = TRUE,
         body = '',
         attachment_url = NULL,
         attachment_kind = NULL,
         attachment_name = NULL,
         attachment_mime_type = NULL,
         attachment_size_bytes = NULL,
         attachment_duration_ms = NULL,
         deleted_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND thread_id = $2
       AND is_deleted = FALSE
     RETURNING id`,
    [Number(messageId), Number(threadId)]
  );
  return (r.rowCount || 0) > 0;
}

export async function getUserChatQualityReviewConsent(userId) {
  const r = await q(
    `SELECT chat_quality_review_consent
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function setUserChatQualityReviewConsent({ userId, enabled }) {
  const r = await q(
    `UPDATE app_user
     SET chat_quality_review_consent = $2
     WHERE id = $1
     RETURNING id, chat_quality_review_consent`,
    [Number(userId), enabled === true]
  );
  return r.rows[0] || null;
}

export async function listMonitorableThreadsForSuperAdmin({
  search = "",
  limit = 60,
}) {
  const normalizedSearch = String(search || "").trim();
  const like = normalizedSearch ? `%${normalizedSearch}%` : "";
  const r = await q(
    `SELECT
       t.id,
       t.user_a_id,
       t.user_b_id,
       t.created_at,
       t.updated_at,
       t.last_message_at,
       ua.full_name AS user_a_full_name,
       ua.phone AS user_a_phone,
       ua.role AS user_a_role,
       ua.image_url AS user_a_image_url,
       ub.full_name AS user_b_full_name,
       ub.phone AS user_b_phone,
       ub.role AS user_b_role,
       ub.image_url AS user_b_image_url,
       lm.id AS last_message_id,
       lm.sender_user_id AS last_message_sender_user_id,
       lm.body AS last_message_body,
       lm.created_at AS last_message_created_at,
       lm.attachment_url AS last_message_attachment_url,
       lm.attachment_kind AS last_message_attachment_kind,
       lm.attachment_name AS last_message_attachment_name
     FROM social_chat_thread t
     JOIN app_user ua ON ua.id = t.user_a_id
     JOIN app_user ub ON ub.id = t.user_b_id
     LEFT JOIN LATERAL (
       SELECT
         m.id,
         m.sender_user_id,
         m.body,
         m.created_at,
         m.attachment_url,
         m.attachment_kind,
         m.attachment_name
       FROM social_chat_message m
       WHERE m.thread_id = t.id
         AND m.is_deleted = FALSE
       ORDER BY m.id DESC
       LIMIT 1
     ) lm ON TRUE
     WHERE (
         $1::text = ''
         OR ua.full_name ILIKE $2
         OR ub.full_name ILIKE $2
         OR ua.phone ILIKE $2
         OR ub.phone ILIKE $2
         OR COALESCE(lm.body, '') ILIKE $2
         OR COALESCE(lm.attachment_name, '') ILIKE $2
       )
     ORDER BY COALESCE(lm.created_at, t.last_message_at) DESC, t.id DESC
     LIMIT $3`,
    [normalizedSearch, like, Math.max(1, Math.min(150, Number(limit) || 60))]
  );
  return r.rows;
}

export async function getMonitorableThreadForSuperAdmin(threadId) {
  const r = await q(
    `SELECT
       t.id,
       t.user_a_id,
       t.user_b_id,
       t.created_at,
       t.updated_at,
       t.last_message_at,
       ua.full_name AS user_a_full_name,
       ua.phone AS user_a_phone,
       ua.role AS user_a_role,
       ua.image_url AS user_a_image_url,
       ub.full_name AS user_b_full_name,
       ub.phone AS user_b_phone,
       ub.role AS user_b_role,
       ub.image_url AS user_b_image_url
     FROM social_chat_thread t
     JOIN app_user ua ON ua.id = t.user_a_id
     JOIN app_user ub ON ub.id = t.user_b_id
     WHERE t.id = $1
     LIMIT 1`,
    [Number(threadId)]
  );
  return r.rows[0] || null;
}

export async function listMonitorableCommunityChatsForSuperAdmin({
  search = "",
  limit = 60,
}) {
  const normalizedSearch = String(search || "").trim();
  const like = normalizedSearch ? `%${normalizedSearch}%` : "";
  const r = await q(
    `WITH scope_index AS (
       SELECT DISTINCT m.scope_type, m.scope_code
       FROM social_scope_chat_message m
     )
     SELECT
       s.scope_type,
       s.scope_code,
       lm.id AS last_message_id,
       lm.sender_user_id AS last_message_sender_user_id,
       lm.body AS last_message_body,
       lm.created_at AS last_message_created_at,
       u.full_name AS last_sender_full_name,
       u.phone AS last_sender_phone,
       u.role AS last_sender_role,
       u.image_url AS last_sender_image_url,
       COALESCE(p.participant_count, 0)::int AS participant_count
     FROM scope_index s
     LEFT JOIN LATERAL (
       SELECT
         m.id,
         m.sender_user_id,
         m.body,
         m.created_at
       FROM social_scope_chat_message m
       WHERE m.scope_type = s.scope_type
         AND m.scope_code = s.scope_code
       ORDER BY m.id DESC
       LIMIT 1
     ) lm ON TRUE
     LEFT JOIN app_user u ON u.id = lm.sender_user_id
     LEFT JOIN LATERAL (
       SELECT COUNT(DISTINCT m.sender_user_id)::int AS participant_count
       FROM social_scope_chat_message m
       WHERE m.scope_type = s.scope_type
         AND m.scope_code = s.scope_code
         AND m.sender_user_id IS NOT NULL
     ) p ON TRUE
     WHERE (
       $1::text = ''
       OR s.scope_type ILIKE $2
       OR s.scope_code ILIKE $2
       OR COALESCE(lm.body, '') ILIKE $2
       OR COALESCE(u.full_name, '') ILIKE $2
       OR COALESCE(u.phone, '') ILIKE $2
     )
     ORDER BY COALESCE(lm.created_at, NOW()) DESC, s.scope_type, s.scope_code
     LIMIT $3`,
    [normalizedSearch, like, Math.max(1, Math.min(150, Number(limit) || 60))]
  );
  return r.rows;
}

export async function getMonitorableCommunityChatForSuperAdmin({
  scopeType,
  scopeCode,
}) {
  const r = await q(
    `SELECT
       s.scope_type,
       s.scope_code,
       lm.id AS last_message_id,
       lm.sender_user_id AS last_message_sender_user_id,
       lm.body AS last_message_body,
       lm.created_at AS last_message_created_at,
       u.full_name AS last_sender_full_name,
       u.phone AS last_sender_phone,
       u.role AS last_sender_role,
       u.image_url AS last_sender_image_url,
       COALESCE(p.participant_count, 0)::int AS participant_count
     FROM (
       SELECT DISTINCT m.scope_type, m.scope_code
       FROM social_scope_chat_message m
       WHERE m.scope_type = $1
         AND m.scope_code = $2
     ) s
     LEFT JOIN LATERAL (
       SELECT
         m.id,
         m.sender_user_id,
         m.body,
         m.created_at
       FROM social_scope_chat_message m
       WHERE m.scope_type = s.scope_type
         AND m.scope_code = s.scope_code
       ORDER BY m.id DESC
       LIMIT 1
     ) lm ON TRUE
     LEFT JOIN app_user u ON u.id = lm.sender_user_id
     LEFT JOIN LATERAL (
       SELECT COUNT(DISTINCT m.sender_user_id)::int AS participant_count
       FROM social_scope_chat_message m
       WHERE m.scope_type = s.scope_type
         AND m.scope_code = s.scope_code
         AND m.sender_user_id IS NOT NULL
     ) p ON TRUE
     LIMIT 1`,
    [scopeType, scopeCode]
  );
  return r.rows[0] || null;
}

/**
 * يحدث metadata آخر رسالة للـ thread لتسريع قوائم المحادثات.
 */
export async function touchThreadLastMessage(threadId) {
  await q(
    `UPDATE social_chat_thread
     SET last_message_at = NOW(),
         updated_at = NOW()
     WHERE id = $1`,
    [Number(threadId)]
  );
}

function normalizeRelationPair(userIdA, userIdB) {
  const a = Number(userIdA);
  const b = Number(userIdB);
  return {
    userAId: Math.min(a, b),
    userBId: Math.max(a, b),
  };
}

export async function getUserRelation({ userId, otherUserId }) {
  const pair = normalizeRelationPair(userId, otherUserId);
  const r = await q(
    `SELECT *
     FROM social_user_relation
     WHERE user_a_id = $1
       AND user_b_id = $2
     LIMIT 1`,
    [pair.userAId, pair.userBId]
  );
  return r.rows[0] || null;
}

export async function getUserNotificationPreference({ userId, actorUserId }) {
  const r = await q(
    `SELECT user_id, actor_user_id, muted, created_at, updated_at
     FROM social_user_notification_pref
     WHERE user_id = $1
       AND actor_user_id = $2
     LIMIT 1`,
    [Number(userId), Number(actorUserId)]
  );
  return r.rows[0] || null;
}

export async function upsertUserNotificationPreference({
  userId,
  actorUserId,
  enabled,
  updatedByUserId = null,
}) {
  const muted = enabled !== true;
  const r = await q(
    `INSERT INTO social_user_notification_pref
      (user_id, actor_user_id, muted, updated_by_user_id, created_at, updated_at)
     VALUES ($1, $2, $3, $4, NOW(), NOW())
     ON CONFLICT (user_id, actor_user_id)
     DO UPDATE SET
       muted = EXCLUDED.muted,
       updated_by_user_id = EXCLUDED.updated_by_user_id,
       updated_at = NOW()
     RETURNING user_id, actor_user_id, muted, created_at, updated_at`,
    [
      Number(userId),
      Number(actorUserId),
      muted === true,
      updatedByUserId == null ? null : Number(updatedByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function upsertPendingRelation({ fromUserId, toUserId }) {
  const pair = normalizeRelationPair(fromUserId, toUserId);
  const r = await q(
    `INSERT INTO social_user_relation
      (
        user_a_id,
        user_b_id,
        initiator_user_id,
        status,
        requested_at,
        responded_at
      )
     VALUES ($1, $2, $3, 'pending', NOW(), NULL)
     ON CONFLICT (user_a_id, user_b_id)
     DO UPDATE SET
       initiator_user_id = EXCLUDED.initiator_user_id,
       status = 'pending',
       requested_at = NOW(),
       responded_at = NULL,
       updated_at = NOW()
     RETURNING *`,
    [pair.userAId, pair.userBId, Number(fromUserId)]
  );
  return r.rows[0] || null;
}

export async function updateRelationStatus({
  userId,
  otherUserId,
  status,
  initiatorUserId = null,
}) {
  const pair = normalizeRelationPair(userId, otherUserId);
  const normalizedStatus = String(status || "").trim().toLowerCase();
  const allowed = new Set(["pending", "accepted", "rejected", "cancelled", "blocked"]);
  const safeStatus = allowed.has(normalizedStatus) ? normalizedStatus : "pending";
  const params = [pair.userAId, pair.userBId, safeStatus];
  const setInitiator =
    initiatorUserId == null
      ? ""
      : `, initiator_user_id = $${params.push(Number(initiatorUserId))}`;
  const r = await q(
    `UPDATE social_user_relation
     SET status = CAST($3 AS VARCHAR(16)),
         requested_at = CASE
           WHEN CAST($3 AS TEXT) = 'pending' THEN NOW()
           ELSE requested_at
         END,
         responded_at = CASE
           WHEN CAST($3 AS TEXT) = 'pending' THEN NULL
           ELSE NOW()
         END
         ${setInitiator},
         updated_at = NOW()
     WHERE user_a_id = $1
       AND user_b_id = $2
     RETURNING *`,
    params
  );
  return r.rows[0] || null;
}

export async function deleteRelation({ userId, otherUserId }) {
  const pair = normalizeRelationPair(userId, otherUserId);
  const r = await q(
    `DELETE FROM social_user_relation
     WHERE user_a_id = $1
       AND user_b_id = $2
     RETURNING *`,
    [pair.userAId, pair.userBId]
  );
  return r.rows[0] || null;
}

export async function listIncomingRelationRequests({ userId, limit = 100 }) {
  const r = await q(
    `SELECT
       rel.user_a_id,
       rel.user_b_id,
       rel.initiator_user_id,
       rel.status,
       rel.requested_at,
       rel.responded_at,
       rel.updated_at,
       requester.id AS requester_user_id,
       requester.full_name AS requester_full_name,
       requester.phone AS requester_phone,
       requester.role AS requester_role,
       requester.image_url AS requester_image_url
     FROM social_user_relation rel
     JOIN app_user requester ON requester.id = rel.initiator_user_id
     WHERE rel.status = 'pending'
       AND rel.initiator_user_id <> $1
       AND (rel.user_a_id = $1 OR rel.user_b_id = $1)
     ORDER BY rel.requested_at DESC, rel.updated_at DESC
     LIMIT $2`,
    [Number(userId), Math.max(1, Math.min(200, Number(limit) || 100))]
  );
  return r.rows;
}

export async function listOutgoingRelationRequests({ userId, limit = 100 }) {
  const r = await q(
    `SELECT
       rel.user_a_id,
       rel.user_b_id,
       rel.initiator_user_id,
       rel.status,
       rel.requested_at,
       rel.responded_at,
       rel.updated_at,
       target.id AS target_user_id,
       target.full_name AS target_full_name,
       target.phone AS target_phone,
       target.role AS target_role,
       target.image_url AS target_image_url
     FROM social_user_relation rel
     JOIN app_user target
       ON target.id = CASE
           WHEN rel.user_a_id = $1 THEN rel.user_b_id
           ELSE rel.user_a_id
         END
     WHERE rel.status = 'pending'
       AND rel.initiator_user_id = $1
       AND (rel.user_a_id = $1 OR rel.user_b_id = $1)
     ORDER BY rel.requested_at DESC, rel.updated_at DESC
     LIMIT $2`,
    [Number(userId), Math.max(1, Math.min(200, Number(limit) || 100))]
  );
  return r.rows;
}

export async function getUserRelationStats(userId) {
  const r = await q(
    `SELECT
       COUNT(*) FILTER (WHERE status = 'accepted')::int AS accepted_count,
       COUNT(*) FILTER (
         WHERE status = 'accepted' AND initiator_user_id <> $1
       )::int AS followers_count,
       COUNT(*) FILTER (
         WHERE status = 'accepted' AND initiator_user_id = $1
       )::int AS following_count,
       COUNT(*) FILTER (
         WHERE status = 'pending' AND initiator_user_id <> $1
       )::int AS pending_incoming_count,
       COUNT(*) FILTER (
         WHERE status = 'pending' AND initiator_user_id = $1
       )::int AS pending_outgoing_count,
       COUNT(*) FILTER (
         WHERE status = 'blocked' AND initiator_user_id = $1
       )::int AS blocked_by_me_count
     FROM social_user_relation
     WHERE user_a_id = $1 OR user_b_id = $1`,
    [Number(userId)]
  );
  return (
    r.rows[0] || {
      accepted_count: 0,
      followers_count: 0,
      following_count: 0,
      pending_incoming_count: 0,
      pending_outgoing_count: 0,
      blocked_by_me_count: 0,
    }
  );
}

export async function listUserRelationsByType({
  viewerUserId,
  targetUserId,
  relationType = "friends",
  limit = 120,
}) {
  const normalizedType = String(relationType || "").trim().toLowerCase();
  const safeType = new Set(["followers", "following", "friends"]).has(
    normalizedType
  )
    ? normalizedType
    : "friends";
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 120));

  const r = await q(
    `WITH target_rel AS (
       SELECT
         CASE
           WHEN rel.user_a_id = $1 THEN rel.user_b_id
           ELSE rel.user_a_id
         END AS other_user_id,
         COALESCE(rel.responded_at, rel.requested_at, rel.updated_at) AS related_at
       FROM social_user_relation rel
       WHERE rel.status = 'accepted'
         AND (rel.user_a_id = $1 OR rel.user_b_id = $1)
         AND (
           $3::text = 'friends'
           OR ($3::text = 'followers' AND rel.initiator_user_id <> $1)
           OR ($3::text = 'following' AND rel.initiator_user_id = $1)
         )
     )
     SELECT
       u.id,
       u.full_name,
       u.phone,
       u.role,
       u.image_url,
       u.social_show_phone,
       tr.related_at,
       rel.user_a_id,
       rel.user_b_id,
       rel.initiator_user_id,
       rel.status,
       rel.requested_at,
       rel.responded_at,
       rel.updated_at
     FROM target_rel tr
     JOIN app_user u ON u.id = tr.other_user_id
     LEFT JOIN social_user_relation rel
       ON rel.user_a_id = LEAST($2::bigint, u.id)
      AND rel.user_b_id = GREATEST($2::bigint, u.id)
     WHERE COALESCE(u.is_account_disabled, FALSE) = FALSE
     ORDER BY tr.related_at DESC NULLS LAST, u.id DESC
     LIMIT $4`,
    [
      Number(targetUserId),
      Number(viewerUserId),
      safeType,
      safeLimit,
    ]
  );
  return r.rows;
}

function normalizeSocialCallSession(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    threadId: Number(row.thread_id),
    callerUserId: Number(row.caller_user_id),
    calleeUserId: Number(row.callee_user_id),
    status: row.status,
    startedAt: row.started_at || row.created_at || null,
    answeredAt: row.answered_at || null,
    endedAt: row.ended_at || null,
    endReason: row.end_reason || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function normalizeSocialCallSignal(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    sessionId: Number(row.session_id),
    threadId: Number(row.thread_id),
    senderUserId: Number(row.sender_user_id),
    signalType: row.signal_type || "ice",
    signalPayload: row.signal_payload || null,
    createdAt: row.created_at || null,
  };
}

export async function getActiveThreadCallSession(threadId) {
  const r = await q(
    `SELECT *
     FROM social_call_session
     WHERE thread_id = $1
       AND status IN ('ringing', 'active')
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [Number(threadId)]
  );
  return normalizeSocialCallSession(r.rows[0]);
}

export async function getThreadCallSessionById(sessionId) {
  const r = await q(
    `SELECT *
     FROM social_call_session
     WHERE id = $1
     LIMIT 1`,
    [Number(sessionId)]
  );
  return normalizeSocialCallSession(r.rows[0]);
}

export async function createThreadCallSession({
  threadId,
  callerUserId,
  calleeUserId,
}) {
  await q(
    `UPDATE social_call_session
     SET status = 'ended',
         ended_at = NOW(),
         end_reason = COALESCE(end_reason, 'replaced'),
         updated_at = NOW()
     WHERE thread_id = $1
       AND status IN ('ringing', 'active')`,
    [Number(threadId)]
  );

  const r = await q(
    `INSERT INTO social_call_session
      (
        thread_id,
        caller_user_id,
        callee_user_id,
        status,
        started_at,
        created_at,
        updated_at
      )
     VALUES ($1, $2, $3, 'ringing', NOW(), NOW(), NOW())
     RETURNING *`,
    [Number(threadId), Number(callerUserId), Number(calleeUserId)]
  );
  return normalizeSocialCallSession(r.rows[0]);
}

export async function markThreadCallAnswered({ sessionId }) {
  const r = await q(
    `UPDATE social_call_session
     SET status = 'active',
         answered_at = COALESCE(answered_at, NOW()),
         updated_at = NOW()
     WHERE id = $1
       AND status IN ('ringing', 'active')
     RETURNING *`,
    [Number(sessionId)]
  );
  return normalizeSocialCallSession(r.rows[0]);
}

export async function endThreadCallSession({
  sessionId,
  status = "ended",
  endReason = "hangup",
}) {
  const normalizedStatus = ["ended", "declined", "missed"].includes(
    String(status || "").trim().toLowerCase()
  )
    ? String(status || "").trim().toLowerCase()
    : "ended";
  const r = await q(
    `UPDATE social_call_session
     SET status = $2,
         ended_at = COALESCE(ended_at, NOW()),
         end_reason = $3,
         updated_at = NOW()
     WHERE id = $1
       AND status IN ('ringing', 'active')
     RETURNING *`,
    [Number(sessionId), normalizedStatus, endReason || null]
  );
  return normalizeSocialCallSession(r.rows[0]);
}

export async function insertThreadCallSignal({
  sessionId,
  threadId,
  senderUserId,
  signalType,
  signalPayload = null,
}) {
  const r = await q(
    `INSERT INTO social_call_signal
      (session_id, thread_id, sender_user_id, signal_type, signal_payload)
     VALUES ($1, $2, $3, $4, $5::jsonb)
     RETURNING *`,
    [
      Number(sessionId),
      Number(threadId),
      Number(senderUserId),
      String(signalType || "ice"),
      signalPayload == null ? null : JSON.stringify(signalPayload),
    ]
  );
  return normalizeSocialCallSignal(r.rows[0]);
}

export async function listThreadCallSignals(sessionId, { limit = 160 } = {}) {
  const r = await q(
    `SELECT *
     FROM social_call_signal
     WHERE session_id = $1
     ORDER BY id DESC
     LIMIT $2`,
    [Number(sessionId), Math.max(1, Math.min(800, Number(limit) || 160))]
  );
  return r.rows.map(normalizeSocialCallSignal);
}

export async function getThreadCallState(threadId, { signalLimit = 160 } = {}) {
  const session = await getActiveThreadCallSession(threadId);
  if (!session) return { session: null, signals: [] };
  const signals = await listThreadCallSignals(session.id, { limit: signalLimit });
  return { session, signals };
}

export async function listStaleRingingThreadCallSessions({
  timeoutSeconds = 35,
  limit = 120,
} = {}) {
  const safeTimeout = Math.max(10, Math.min(300, Number(timeoutSeconds) || 35));
  const safeLimit = Math.max(1, Math.min(500, Number(limit) || 120));

  const r = await q(
    `SELECT *
     FROM social_call_session
     WHERE status = 'ringing'
       AND started_at <= NOW() - ($1::text || ' seconds')::interval
     ORDER BY started_at ASC, id ASC
     LIMIT $2`,
    [String(safeTimeout), safeLimit]
  );

  return r.rows.map(normalizeSocialCallSession);
}

function resolveScopeAddressExpression(scopeType, alias = "u") {
  const safeAlias = String(alias || "u").replace(/[^\w]/g, "") || "u";
  const blockExpr = `
    CASE
      WHEN UPPER(TRIM(COALESCE(${safeAlias}.block, ''))) ~ '^[AB][1-9]$'
        THEN UPPER(LEFT(TRIM(${safeAlias}.block), 1))
      WHEN UPPER(TRIM(COALESCE(${safeAlias}.block, ''))) ~ '^[AB]$'
        THEN UPPER(TRIM(${safeAlias}.block))
      WHEN UPPER(TRIM(COALESCE(${safeAlias}.building_number, ''))) ~ '^[AB][1-9](0[1-9]|1[0-9]|2[0-2])$'
        THEN UPPER(LEFT(TRIM(${safeAlias}.building_number), 1))
      ELSE NULL
    END
  `;
  const compoundExpr = `
    CASE
      WHEN UPPER(TRIM(COALESCE(${safeAlias}.block, ''))) ~ '^[AB][1-9]$'
        THEN UPPER(TRIM(${safeAlias}.block))
      WHEN UPPER(TRIM(COALESCE(${safeAlias}.building_number, ''))) ~ '^[AB][1-9](0[1-9]|1[0-9]|2[0-2])$'
        THEN UPPER(LEFT(TRIM(${safeAlias}.building_number), 2))
      ELSE NULL
    END
  `;
  const buildingExpr = `
    CASE
      WHEN UPPER(TRIM(COALESCE(${safeAlias}.building_number, ''))) ~ '^[AB][1-9](0[1-9]|1[0-9]|2[0-2])$'
        THEN UPPER(TRIM(${safeAlias}.building_number))
      ELSE NULL
    END
  `;

  if (scopeType === "block") return blockExpr;
  if (scopeType === "compound") return compoundExpr;
  return buildingExpr;
}

export async function findUserAddressMeta(userId) {
  const r = await q(
    `SELECT
       id,
       full_name,
       phone,
       role,
       is_super_admin,
       is_account_disabled,
       block,
       building_number,
       apartment,
       image_url
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function updateUserRole({ userId, role }) {
  const safeRole = String(role || "").trim().toLowerCase();
  const r = await q(
    `UPDATE app_user
     SET role = $2,
         updated_at = NOW()
     WHERE id = $1
     RETURNING
       id,
       full_name,
       phone,
       role,
       is_super_admin,
       is_account_disabled,
       block,
       building_number,
       apartment,
       image_url`,
    [Number(userId), safeRole]
  );
  return r.rows[0] || null;
}

export async function setUserAccountDisabled({
  userId,
  disabled,
  note = null,
  actedByUserId = null,
}) {
  const normalizedNote = String(note || "").trim();
  const actorId = Number(actedByUserId) || null;
  const r = await q(
    `UPDATE app_user
     SET is_account_disabled = $2,
         account_disabled_note = CASE
           WHEN $2 = TRUE THEN $3
           ELSE NULL
         END,
         account_disabled_by_user_id = CASE
           WHEN $2 = TRUE THEN $4
           ELSE account_disabled_by_user_id
         END,
         account_disabled_at = CASE
           WHEN $2 = TRUE THEN NOW()
           ELSE account_disabled_at
         END,
         account_enabled_by_user_id = CASE
           WHEN $2 = FALSE THEN $4
           ELSE account_enabled_by_user_id
         END,
         account_enabled_at = CASE
           WHEN $2 = FALSE THEN NOW()
           ELSE account_enabled_at
         END,
         updated_at = NOW()
     WHERE id = $1
     RETURNING
       id,
       full_name,
       phone,
       role,
       is_super_admin,
       is_account_disabled,
       account_disabled_note,
       block,
       building_number,
       apartment,
       image_url`,
    [Number(userId), disabled === true, normalizedNote || null, actorId]
  );
  return r.rows[0] || null;
}

export async function listCommunityFeedPosts({
  viewerUserId,
  scopeType,
  scopeCode,
  limit = 20,
  beforeId = null,
  postKind = null,
}) {
  const safeScopeType = String(scopeType || "").trim().toLowerCase();
  const safeScopeCode = String(scopeCode || "").trim().toUpperCase();
  const scopeAddressExpr = resolveScopeAddressExpression(safeScopeType, "u");
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.shared_entity_type,
       p.shared_entity_id,
       p.shared_snapshot_json,
       p.merchant_id,
       p.review_rating,
       p.audience_scope_type,
       p.audience_scope_code,
       p.created_at,
       p.updated_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.image_url AS merchant_image_url,
       COALESCE(ps.likes_count, 0)::int AS likes_count,
       COALESCE(ps.comments_count, 0)::int AS comments_count,
       COALESCE(v.is_liked, FALSE) AS is_liked
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     LEFT JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN social_post_stats ps ON ps.post_id = p.id
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_liked
       FROM social_post_like lv
       WHERE lv.post_id = p.id
         AND lv.user_id = $1
       LIMIT 1
     ) v ON TRUE
     WHERE p.is_deleted = FALSE
        AND p.moderation_status = 'approved'
        AND COALESCE(u.is_account_disabled, FALSE) = FALSE
        AND (
          LOWER(COALESCE(u.role::text, '')) = 'user'
          OR (
            COALESCE(u.is_super_admin, FALSE) = TRUE
            AND COALESCE(p.audience_scope_type, 'global') = 'global'
          )
        )
        AND (
          (
            COALESCE(p.audience_scope_type, 'global') = 'global'
            AND (
              COALESCE(u.is_super_admin, FALSE) = TRUE
              OR (${scopeAddressExpr}) = $5::text
            )
          )
          OR (
            $4::text = 'block'
            AND COALESCE(p.audience_scope_type, '') = 'block'
            AND p.audience_scope_code = $5::text
          )
          OR (
            $4::text = 'compound'
            AND (
              (
                COALESCE(p.audience_scope_type, '') = 'block'
                AND p.audience_scope_code = SUBSTRING($5::text FROM 1 FOR 1)
              )
              OR (
                COALESCE(p.audience_scope_type, '') = 'compound'
                AND p.audience_scope_code = $5::text
              )
            )
          )
          OR (
            $4::text = 'building'
            AND (
              (
                COALESCE(p.audience_scope_type, '') = 'block'
                AND p.audience_scope_code = SUBSTRING($5::text FROM 1 FOR 1)
              )
              OR (
                COALESCE(p.audience_scope_type, '') = 'compound'
                AND p.audience_scope_code = SUBSTRING($5::text FROM 1 FOR 2)
              )
              OR (
                COALESCE(p.audience_scope_type, '') = 'building'
                AND p.audience_scope_code = $5::text
              )
            )
          )
        )
       AND ($2::bigint IS NULL OR p.id < $2::bigint)
       AND ($3::text IS NULL OR p.post_kind = $3::text)
     ORDER BY p.id DESC
     LIMIT $6`,
    [
      Number(viewerUserId),
      beforeId,
      postKind,
      safeScopeType,
      safeScopeCode,
      Number(limit),
    ]
  );
  return r.rows;
}

export async function listScopeManagers({ scopeType, scopeCode }) {
  const r = await q(
    `SELECT
       m.id,
       m.scope_type,
       m.scope_code,
       m.manager_user_id,
       m.assigned_by_user_id,
       m.created_at,
       u.full_name AS manager_full_name,
       u.phone AS manager_phone,
       u.role AS manager_role,
       u.image_url AS manager_image_url
     FROM social_scope_manager m
     JOIN app_user u ON u.id = m.manager_user_id
     WHERE m.scope_type = $1
       AND m.scope_code = $2
     ORDER BY m.created_at DESC, m.id DESC`,
    [scopeType, scopeCode]
  );
  return r.rows;
}

export async function isScopeManager({ scopeType, scopeCode, userId }) {
  const r = await q(
    `SELECT 1
     FROM social_scope_manager
     WHERE scope_type = $1
       AND scope_code = $2
       AND manager_user_id = $3
     LIMIT 1`,
    [scopeType, scopeCode, Number(userId)]
  );
  return (r.rowCount || 0) > 0;
}

export async function addScopeManager({
  scopeType,
  scopeCode,
  managerUserId,
  assignedByUserId,
}) {
  const r = await q(
    `INSERT INTO social_scope_manager
      (scope_type, scope_code, manager_user_id, assigned_by_user_id)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (scope_type, scope_code, manager_user_id)
     DO UPDATE SET assigned_by_user_id = EXCLUDED.assigned_by_user_id
     RETURNING *`,
    [scopeType, scopeCode, Number(managerUserId), Number(assignedByUserId)]
  );
  return r.rows[0] || null;
}

export async function removeScopeManager({ scopeType, scopeCode, managerUserId }) {
  const r = await q(
    `DELETE FROM social_scope_manager
     WHERE scope_type = $1
       AND scope_code = $2
       AND manager_user_id = $3
     RETURNING *`,
    [scopeType, scopeCode, Number(managerUserId)]
  );
  return r.rows[0] || null;
}

export async function listScopeAnnouncements({
  scopeType,
  scopeCode,
  limit = 40,
  beforeId = null,
}) {
  const r = await q(
    `SELECT
       a.id,
       a.scope_type,
       a.scope_code,
       a.title,
       a.body,
       a.created_by_user_id,
       a.created_at,
       u.full_name AS author_full_name,
       u.phone AS author_phone,
       u.role AS author_role,
       u.image_url AS author_image_url
     FROM social_scope_announcement a
     LEFT JOIN app_user u ON u.id = a.created_by_user_id
     WHERE a.scope_type = $1
       AND a.scope_code = $2
       AND ($3::bigint IS NULL OR a.id < $3::bigint)
     ORDER BY a.id DESC
     LIMIT $4`,
    [scopeType, scopeCode, beforeId, Number(limit)]
  );
  return r.rows;
}

export async function insertScopeAnnouncement({
  scopeType,
  scopeCode,
  createdByUserId,
  title,
  body,
}) {
  const r = await q(
    `INSERT INTO social_scope_announcement
      (scope_type, scope_code, title, body, created_by_user_id)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING *`,
    [scopeType, scopeCode, String(title || "").trim(), String(body || "").trim(), Number(createdByUserId)]
  );
  return r.rows[0] || null;
}

export async function getScopeChatSettings({ scopeType, scopeCode }) {
  const r = await q(
    `SELECT *
     FROM social_scope_chat_settings
     WHERE scope_type = $1
       AND scope_code = $2
     LIMIT 1`,
    [scopeType, scopeCode]
  );
  return r.rows[0] || null;
}

export async function upsertScopeChatLock({
  scopeType,
  scopeCode,
  locked,
  lockedByUserId,
}) {
  const r = await q(
    `INSERT INTO social_scope_chat_settings
      (scope_type, scope_code, chat_locked, locked_by_user_id, updated_at)
     VALUES ($1, $2, $3, $4, NOW())
     ON CONFLICT (scope_type, scope_code)
     DO UPDATE SET
       chat_locked = EXCLUDED.chat_locked,
       locked_by_user_id = EXCLUDED.locked_by_user_id,
       updated_at = NOW()
     RETURNING *`,
    [scopeType, scopeCode, locked === true, Number(lockedByUserId)]
  );
  return r.rows[0] || null;
}

export async function isScopeChatUserBanned({ scopeType, scopeCode, userId }) {
  const r = await q(
    `SELECT 1
     FROM social_scope_chat_ban
     WHERE scope_type = $1
       AND scope_code = $2
       AND user_id = $3
     LIMIT 1`,
    [scopeType, scopeCode, Number(userId)]
  );
  return (r.rowCount || 0) > 0;
}

export async function isScopeMemberRemoved({ scopeType, scopeCode, userId }) {
  const r = await q(
    `SELECT 1
     FROM social_scope_member_removal
     WHERE scope_type = $1
       AND scope_code = $2
       AND user_id = $3
     LIMIT 1`,
    [scopeType, scopeCode, Number(userId)]
  );
  return (r.rowCount || 0) > 0;
}

export async function listScopeChatBannedUserIds({ scopeType, scopeCode }) {
  const r = await q(
    `SELECT user_id
     FROM social_scope_chat_ban
     WHERE scope_type = $1
       AND scope_code = $2`,
    [scopeType, scopeCode]
  );
  return r.rows
    .map((row) => Number(row.user_id))
    .filter((value) => Number.isFinite(value) && value > 0);
}

export async function listScopeRemovedUserIds({ scopeType, scopeCode }) {
  const r = await q(
    `SELECT user_id
     FROM social_scope_member_removal
     WHERE scope_type = $1
       AND scope_code = $2`,
    [scopeType, scopeCode]
  );
  return r.rows
    .map((row) => Number(row.user_id))
    .filter((value) => Number.isFinite(value) && value > 0);
}

export async function listScopeChatBans({ scopeType, scopeCode, limit = 120 }) {
  const r = await q(
    `SELECT
       b.scope_type,
       b.scope_code,
       b.user_id,
       b.banned_by_user_id,
       b.reason,
       b.created_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.role AS user_role,
       u.image_url AS user_image_url
     FROM social_scope_chat_ban b
     JOIN app_user u ON u.id = b.user_id
     WHERE b.scope_type = $1
       AND b.scope_code = $2
     ORDER BY b.created_at DESC
     LIMIT $3`,
    [scopeType, scopeCode, Number(limit)]
  );
  return r.rows;
}

export async function upsertScopeMemberRemoval({
  scopeType,
  scopeCode,
  userId,
  removedByUserId,
  reason = null,
}) {
  const r = await q(
    `INSERT INTO social_scope_member_removal
      (scope_type, scope_code, user_id, removed_by_user_id, reason)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (scope_type, scope_code, user_id)
     DO UPDATE SET
       removed_by_user_id = EXCLUDED.removed_by_user_id,
       reason = EXCLUDED.reason,
       created_at = NOW()
     RETURNING *`,
    [scopeType, scopeCode, Number(userId), Number(removedByUserId), reason]
  );
  return r.rows[0] || null;
}

export async function removeScopeMemberRemoval({ scopeType, scopeCode, userId }) {
  const r = await q(
    `DELETE FROM social_scope_member_removal
     WHERE scope_type = $1
       AND scope_code = $2
       AND user_id = $3
     RETURNING *`,
    [scopeType, scopeCode, Number(userId)]
  );
  return r.rows[0] || null;
}

export async function upsertScopeChatBan({
  scopeType,
  scopeCode,
  userId,
  bannedByUserId,
  reason = null,
}) {
  const r = await q(
    `INSERT INTO social_scope_chat_ban
      (scope_type, scope_code, user_id, banned_by_user_id, reason)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (scope_type, scope_code, user_id)
     DO UPDATE SET
       banned_by_user_id = EXCLUDED.banned_by_user_id,
       reason = EXCLUDED.reason,
       created_at = NOW()
     RETURNING *`,
    [scopeType, scopeCode, Number(userId), Number(bannedByUserId), reason]
  );
  return r.rows[0] || null;
}

export async function removeScopeChatBan({ scopeType, scopeCode, userId }) {
  const r = await q(
    `DELETE FROM social_scope_chat_ban
     WHERE scope_type = $1
       AND scope_code = $2
       AND user_id = $3
     RETURNING *`,
    [scopeType, scopeCode, Number(userId)]
  );
  return r.rows[0] || null;
}

export async function listScopeChatMessages({
  scopeType,
  scopeCode,
  limit = 60,
  beforeId = null,
}) {
  const r = await q(
    `SELECT
       m.id,
       m.scope_type,
       m.scope_code,
       m.sender_user_id,
       m.body,
       m.client_message_id,
       m.reply_to_message_id,
       m.attachment_url,
       m.attachment_kind,
        m.attachment_name,
        m.attachment_mime_type,
        m.attachment_size_bytes,
        m.attachment_duration_ms,
        m.attachment_provider,
        m.attachment_preview_url,
        m.attachment_thumbnail_url,
        m.attachment_width,
        m.attachment_height,
        m.attachment_upload_state,
        m.attachment_trace_id,
        m.shared_entity_type,
        m.shared_entity_id,
        m.shared_snapshot_json,
        m.is_system,
        m.is_deleted,
       m.created_at,
       m.updated_at,
       m.edited_at,
       m.deleted_at,
       u.full_name AS sender_full_name,
       u.phone AS sender_phone,
       u.role AS sender_role,
       u.image_url AS sender_image_url,
       rm.id AS reply_message_id,
       rm.sender_user_id AS reply_sender_user_id,
       rm.body AS reply_body,
       rm.attachment_kind AS reply_attachment_kind,
       rm.attachment_name AS reply_attachment_name,
       ru.full_name AS reply_sender_full_name
     FROM social_scope_chat_message m
     LEFT JOIN app_user u ON u.id = m.sender_user_id
     LEFT JOIN social_scope_chat_message rm
       ON rm.id = m.reply_to_message_id
      AND rm.is_deleted = FALSE
     LEFT JOIN app_user ru ON ru.id = rm.sender_user_id
     WHERE m.scope_type = $1
       AND m.scope_code = $2
       AND ($3::bigint IS NULL OR m.id < $3::bigint)
     ORDER BY m.id DESC
     LIMIT $4`,
    [scopeType, scopeCode, beforeId, Number(limit)]
  );
  return r.rows;
}

export async function searchScopeChatMessages({
  scopeType,
  scopeCode,
  search,
  limit = 20,
  beforeId = null,
}) {
  const normalizedSearch = String(search || "").trim();
  const like = `%${normalizedSearch}%`;
  const r = await q(
    `SELECT
       m.id,
       m.scope_type,
       m.scope_code,
       m.sender_user_id,
       m.body,
       m.client_message_id,
       m.reply_to_message_id,
       m.attachment_url,
       m.attachment_kind,
        m.attachment_name,
        m.attachment_mime_type,
        m.attachment_size_bytes,
        m.attachment_duration_ms,
        m.attachment_provider,
        m.attachment_preview_url,
        m.attachment_thumbnail_url,
        m.attachment_width,
        m.attachment_height,
        m.attachment_upload_state,
        m.attachment_trace_id,
        m.shared_entity_type,
        m.shared_entity_id,
        m.shared_snapshot_json,
        m.is_system,
        m.is_deleted,
       m.created_at,
       m.updated_at,
       m.edited_at,
       m.deleted_at,
       u.full_name AS sender_full_name,
       u.phone AS sender_phone,
       u.role AS sender_role,
       u.image_url AS sender_image_url,
       rm.id AS reply_message_id,
       rm.sender_user_id AS reply_sender_user_id,
       rm.body AS reply_body,
       rm.attachment_kind AS reply_attachment_kind,
       rm.attachment_name AS reply_attachment_name,
       ru.full_name AS reply_sender_full_name
     FROM social_scope_chat_message m
     LEFT JOIN app_user u ON u.id = m.sender_user_id
     LEFT JOIN social_scope_chat_message rm
       ON rm.id = m.reply_to_message_id
      AND rm.is_deleted = FALSE
     LEFT JOIN app_user ru ON ru.id = rm.sender_user_id
     WHERE m.scope_type = $1
       AND m.scope_code = $2
       AND m.is_deleted = FALSE
       AND ($3::bigint IS NULL OR m.id < $3::bigint)
       AND (
         COALESCE(m.body, '') ILIKE $4
         OR COALESCE(m.attachment_name, '') ILIKE $4
         OR COALESCE(u.full_name, '') ILIKE $4
       )
     ORDER BY m.id DESC
     LIMIT $5`,
    [
      scopeType,
      scopeCode,
      beforeId,
      like,
      Math.max(1, Math.min(60, Number(limit) || 20)),
    ]
  );
  return r.rows;
}

export async function insertScopeChatMessage({
  scopeType,
  scopeCode,
  senderUserId = null,
  body,
  isSystem = false,
  replyToMessageId = null,
  attachment = null,
  sharedEntity = null,
  clientMessageId = null,
}) {
  const normalizedClientMessageId =
    clientMessageId == null ? null : String(clientMessageId).trim();
  if (normalizedClientMessageId) {
    const r = await q(
      `WITH inserted AS (
         INSERT INTO social_scope_chat_message
           (
             scope_type,
             scope_code,
             sender_user_id,
             body,
             is_system,
             reply_to_message_id,
             attachment_url,
             attachment_kind,
             attachment_name,
             attachment_mime_type,
             attachment_size_bytes,
             attachment_duration_ms,
             shared_entity_type,
             shared_entity_id,
             shared_snapshot_json,
             client_message_id
           )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
         ON CONFLICT (scope_type, scope_code, sender_user_id, client_message_id)
         WHERE client_message_id IS NOT NULL
         DO NOTHING
         RETURNING *, TRUE AS _inserted
       ),
       existing AS (
         SELECT m.*, FALSE AS _inserted
         FROM social_scope_chat_message m
         WHERE m.scope_type = $1
           AND m.scope_code = $2
           AND m.sender_user_id = $3
           AND m.client_message_id = $16
         LIMIT 1
       )
       SELECT *
       FROM inserted
       UNION ALL
       SELECT *
       FROM existing
       WHERE NOT EXISTS (SELECT 1 FROM inserted)
       LIMIT 1`,
      [
        scopeType,
        scopeCode,
        senderUserId == null ? null : Number(senderUserId),
        String(body || "").trim(),
        isSystem === true,
        replyToMessageId == null ? null : Number(replyToMessageId),
        attachment?.url || null,
        attachment?.kind || null,
        attachment?.name || null,
        attachment?.mimeType || null,
        attachment?.sizeBytes == null ? null : Number(attachment.sizeBytes),
        attachment?.durationMs == null ? null : Number(attachment.durationMs),
        sharedEntity?.type || null,
        sharedEntity?.id == null ? null : Number(sharedEntity.id),
        sharedEntity?.snapshot == null ? null : JSON.stringify(sharedEntity.snapshot),
        normalizedClientMessageId,
      ]
    );
    return r.rows[0] || null;
  }

  const r = await q(
    `INSERT INTO social_scope_chat_message
      (
        scope_type,
        scope_code,
        sender_user_id,
        body,
        is_system,
        reply_to_message_id,
        attachment_url,
        attachment_kind,
        attachment_name,
        attachment_mime_type,
        attachment_size_bytes,
        attachment_duration_ms,
        shared_entity_type,
        shared_entity_id,
        shared_snapshot_json
      )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
     RETURNING *`,
    [
      scopeType,
      scopeCode,
      senderUserId == null ? null : Number(senderUserId),
      String(body || "").trim(),
      isSystem === true,
      replyToMessageId == null ? null : Number(replyToMessageId),
      attachment?.url || null,
      attachment?.kind || null,
      attachment?.name || null,
      attachment?.mimeType || null,
      attachment?.sizeBytes == null ? null : Number(attachment.sizeBytes),
      attachment?.durationMs == null ? null : Number(attachment.durationMs),
      sharedEntity?.type || null,
      sharedEntity?.id == null ? null : Number(sharedEntity.id),
      sharedEntity?.snapshot == null ? null : JSON.stringify(sharedEntity.snapshot),
    ]
  );
  const row = r.rows[0] || null;
  return row ? { ...row, _inserted: true } : null;
}

export async function getScopeChatMessageById({
  scopeType,
  scopeCode,
  messageId,
  includeDeleted = false,
}) {
  const r = await q(
    `SELECT *
     FROM social_scope_chat_message
     WHERE id = $1
       AND scope_type = $2
       AND scope_code = $3
       AND ($4::boolean = TRUE OR is_deleted = FALSE)
     LIMIT 1`,
    [Number(messageId), scopeType, scopeCode, includeDeleted === true]
  );
  return r.rows[0] || null;
}

export async function getScopeChatMessageDetailsById({
  scopeType,
  scopeCode,
  messageId,
  includeDeleted = false,
}) {
  const r = await q(
    `SELECT
       m.id,
       m.scope_type,
       m.scope_code,
       m.sender_user_id,
       m.body,
       m.client_message_id,
       m.reply_to_message_id,
       m.attachment_url,
       m.attachment_kind,
       m.attachment_name,
       m.attachment_mime_type,
       m.attachment_size_bytes,
       m.attachment_duration_ms,
       m.attachment_provider,
       m.attachment_preview_url,
       m.attachment_thumbnail_url,
       m.attachment_width,
       m.attachment_height,
       m.attachment_upload_state,
       m.attachment_trace_id,
       m.shared_entity_type,
       m.shared_entity_id,
       m.shared_snapshot_json,
       m.is_system,
       m.is_deleted,
       m.created_at,
       m.updated_at,
       m.edited_at,
       m.deleted_at,
       u.full_name AS sender_full_name,
       u.phone AS sender_phone,
       u.role AS sender_role,
       u.image_url AS sender_image_url,
       rm.id AS reply_message_id,
       rm.sender_user_id AS reply_sender_user_id,
       rm.body AS reply_body,
       rm.attachment_kind AS reply_attachment_kind,
       rm.attachment_name AS reply_attachment_name,
       ru.full_name AS reply_sender_full_name
     FROM social_scope_chat_message m
     LEFT JOIN app_user u ON u.id = m.sender_user_id
     LEFT JOIN social_scope_chat_message rm
       ON rm.id = m.reply_to_message_id
      AND rm.is_deleted = FALSE
     LEFT JOIN app_user ru ON ru.id = rm.sender_user_id
     WHERE m.id = $1
       AND m.scope_type = $2
       AND m.scope_code = $3
       AND ($4::boolean = TRUE OR m.is_deleted = FALSE)
     LIMIT 1`,
    [Number(messageId), scopeType, scopeCode, includeDeleted === true]
  );
  return r.rows[0] || null;
}

export async function updateScopeChatMessage({
  scopeType,
  scopeCode,
  messageId,
  body,
}) {
  const r = await q(
    `UPDATE social_scope_chat_message
     SET body = $4,
         edited_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND scope_type = $2
       AND scope_code = $3
       AND is_deleted = FALSE
     RETURNING *`,
    [Number(messageId), scopeType, scopeCode, String(body || "").trim()]
  );
  return r.rows[0] || null;
}

export async function softDeleteScopeChatMessage({
  scopeType,
  scopeCode,
  messageId,
}) {
  const r = await q(
    `UPDATE social_scope_chat_message
     SET is_deleted = TRUE,
         body = '',
         attachment_url = NULL,
         attachment_kind = NULL,
         attachment_name = NULL,
         attachment_mime_type = NULL,
         attachment_size_bytes = NULL,
         attachment_duration_ms = NULL,
         deleted_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND scope_type = $2
       AND scope_code = $3
       AND is_deleted = FALSE
     RETURNING id`,
    [Number(messageId), scopeType, scopeCode]
  );
  return (r.rowCount || 0) > 0;
}

export async function listScopeChatMessageReactionsForMessages({
  messageIds,
  userId,
}) {
  const ids = Array.isArray(messageIds)
    ? [...new Set(messageIds.map((v) => Number(v)).filter((v) => Number.isFinite(v) && v > 0))]
    : [];
  if (ids.length <= 0) return {};

  const countsRes = await q(
    `SELECT
       message_id,
       reaction,
       COUNT(*)::int AS reaction_count
     FROM social_scope_chat_message_reaction
     WHERE message_id = ANY($1::bigint[])
     GROUP BY message_id, reaction`,
    [ids]
  );

  const mineRes = await q(
    `SELECT message_id, reaction
     FROM social_scope_chat_message_reaction
     WHERE user_id = $1
       AND message_id = ANY($2::bigint[])`,
    [Number(userId), ids]
  );

  const out = {};
  for (const id of ids) {
    out[id] = { counts: {}, myReaction: null, totalCount: 0 };
  }

  for (const row of countsRes.rows) {
    const messageId = Number(row.message_id);
    const reaction = String(row.reaction || "").trim();
    const count = Number(row.reaction_count || 0);
    if (!out[messageId] || !reaction) continue;
    out[messageId].counts[reaction] = count;
    out[messageId].totalCount += count;
  }

  for (const row of mineRes.rows) {
    const messageId = Number(row.message_id);
    const reaction = String(row.reaction || "").trim();
    if (!out[messageId] || !reaction) continue;
    out[messageId].myReaction = reaction;
  }

  return out;
}

export async function toggleScopeChatMessageReaction({
  messageId,
  userId,
  reaction,
}) {
  const targetReaction = String(reaction || "").trim().toLowerCase();
  const allowed = new Set(["like", "heart", "laugh", "fire"]);
  const safeReaction = allowed.has(targetReaction) ? targetReaction : "like";

  const existingRes = await q(
    `SELECT reaction
     FROM social_scope_chat_message_reaction
     WHERE message_id = $1
       AND user_id = $2
     LIMIT 1`,
    [Number(messageId), Number(userId)]
  );
  const existing = existingRes.rows[0] || null;

  if (existing && String(existing.reaction || "").trim().toLowerCase() === safeReaction) {
    await q(
      `DELETE FROM social_scope_chat_message_reaction
       WHERE message_id = $1
         AND user_id = $2`,
      [Number(messageId), Number(userId)]
    );
    return { active: false, reaction: null };
  }

  await q(
    `INSERT INTO social_scope_chat_message_reaction (message_id, user_id, reaction)
     VALUES ($1, $2, $3)
     ON CONFLICT (message_id, user_id)
     DO UPDATE SET
       reaction = EXCLUDED.reaction,
       created_at = NOW()`,
    [Number(messageId), Number(userId), safeReaction]
  );
  return { active: true, reaction: safeReaction };
}

export async function listScopeBills({
  scopeType,
  scopeCode,
  category = null,
  includeAllApartments = true,
  apartmentCode = null,
  limit = 60,
  beforeId = null,
}) {
  const safeApartmentCode =
    apartmentCode == null ? null : String(apartmentCode).trim().toUpperCase();
  const r = await q(
    `SELECT
       b.id,
       b.scope_type,
       b.scope_code,
       b.bill_category,
       b.title,
       b.amount,
       b.due_date,
       b.details,
       b.apartment_code,
       b.attachment_url,
       b.attachment_kind,
       b.attachment_name,
       b.issued_by_user_id,
       b.created_at,
       u.full_name AS issuer_full_name,
       u.phone AS issuer_phone,
       u.role AS issuer_role,
       u.image_url AS issuer_image_url
     FROM social_scope_bill b
     LEFT JOIN app_user u ON u.id = b.issued_by_user_id
     WHERE b.scope_type = $1
       AND b.scope_code = $2
       AND ($3::text IS NULL OR b.bill_category = $3::text)
       AND ($4::bigint IS NULL OR b.id < $4::bigint)
       AND (
         $6::boolean = TRUE
         OR (
           UPPER(TRIM(COALESCE(b.apartment_code, ''))) = ''
           OR (
             $7::text IS NOT NULL
             AND UPPER(TRIM(COALESCE(b.apartment_code, ''))) = $7::text
           )
         )
       )
     ORDER BY b.id DESC
     LIMIT $5`,
    [
      scopeType,
      scopeCode,
      category,
      beforeId,
      Number(limit),
      includeAllApartments === true,
      safeApartmentCode,
    ]
  );
  return r.rows;
}

export async function insertScopeBill({
  scopeType,
  scopeCode,
  category,
  title,
  amount = null,
  dueDate = null,
  details = null,
  apartmentCode = null,
  attachmentUrl = null,
  attachmentKind = null,
  attachmentName = null,
  issuedByUserId = null,
}) {
  const r = await q(
    `INSERT INTO social_scope_bill
      (
        scope_type,
        scope_code,
        bill_category,
        title,
        amount,
        due_date,
        details,
        apartment_code,
        attachment_url,
        attachment_kind,
        attachment_name,
        issued_by_user_id
      )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
     RETURNING *`,
    [
      scopeType,
      scopeCode,
      category,
      String(title || "").trim(),
      amount == null ? null : Number(amount),
      dueDate || null,
      details || null,
      apartmentCode == null ? null : String(apartmentCode).trim().toUpperCase(),
      attachmentUrl == null ? null : String(attachmentUrl).trim(),
      attachmentKind == null ? null : String(attachmentKind).trim().toLowerCase(),
      attachmentName == null ? null : String(attachmentName).trim().slice(0, 180),
      issuedByUserId == null ? null : Number(issuedByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function insertSocialMediaAsset({
  ownerUserId,
  sourceType,
  provider = "r2",
  streamUid = null,
  traceId = null,
  originalUrl,
  normalizedUrl = null,
  posterUrl = null,
  playbackUrl = null,
  thumbnailUrl = null,
  mimeType = null,
  mediaKind = null,
  durationMs = null,
  width = null,
  height = null,
  processingStatus = "ready",
}) {
  const normalizedStreamUid = streamUid == null ? null : String(streamUid).trim() || null;
  // Stream assets should always retain a trace identifier even if callers omit
  // traceId explicitly. Reuse the stream UID so persistence and diagnostics stay
  // aligned with the upload session.
  const normalizedTraceId =
    traceId == null ? normalizedStreamUid : String(traceId).trim() || normalizedStreamUid;
  const r = await q(
    `INSERT INTO social_media_asset
      (
        owner_user_id,
        source_type,
        provider,
        stream_uid,
        media_kind,
        original_url,
        normalized_url,
        poster_url,
        playback_url,
        thumbnail_url,
        trace_id,
        mime_type,
        duration_ms,
        width,
        height,
        processing_status
     )
     VALUES (
       $1, $2, $3, $4, $5,
       $6, $7, $8, $9, $10,
       $11, $12, $13, $14, $15,
       $16
     )
     RETURNING *`,
    [
      Number(ownerUserId),
      String(sourceType || "post").trim().toLowerCase(),
      String(provider || "r2").trim().toLowerCase(),
      normalizedStreamUid,
      mediaKind == null ? null : String(mediaKind).trim().toLowerCase(),
      String(originalUrl || "").trim(),
      normalizedUrl == null ? null : String(normalizedUrl).trim() || null,
      posterUrl == null ? null : String(posterUrl).trim() || null,
      playbackUrl == null ? null : String(playbackUrl).trim() || null,
      thumbnailUrl == null ? null : String(thumbnailUrl).trim() || null,
      normalizedTraceId,
      mimeType == null ? null : String(mimeType).trim() || null,
      durationMs == null ? null : Number(durationMs),
      width == null ? null : Number(width),
      height == null ? null : Number(height),
      String(processingStatus || "ready").trim().toLowerCase(),
    ]
  );
  return r.rows[0] || null;
}

export async function findSocialMediaAssetById(assetId) {
  const r = await q(
    `SELECT *
     FROM social_media_asset
     WHERE id = $1
     LIMIT 1`,
    [Number(assetId)]
  );
  return r.rows[0] || null;
}

export async function findSocialMediaAssetByStreamUid(streamUid) {
  const uid = String(streamUid || "").trim();
  if (!uid) return null;
  const r = await q(
    `SELECT *
     FROM social_media_asset
     WHERE stream_uid = $1
     LIMIT 1`,
    [uid]
  );
  return r.rows[0] || null;
}

export async function listPendingSocialMediaAssets({
  limit = 20,
  sourceType = null,
} = {}) {
  const r = await q(
    `SELECT *
     FROM social_media_asset
     WHERE provider = 'stream'
       AND processing_status IN ('pending', 'processing')
       AND ($2::text IS NULL OR source_type = $2::text)
     ORDER BY created_at ASC, id ASC
     LIMIT $1`,
    [Math.max(1, Math.min(100, Number(limit) || 20)), sourceType == null ? null : String(sourceType).trim().toLowerCase()]
  );
  return r.rows;
}

export async function updateSocialMediaAssetStatus({
  assetId = null,
  streamUid = null,
  processingStatus,
  processingError = null,
  normalizedUrl = null,
  posterUrl = null,
  playbackUrl = null,
  thumbnailUrl = null,
  durationMs = null,
  width = null,
  height = null,
}) {
  const hasAssetId = assetId != null;
  const hasStreamUid = String(streamUid || "").trim().length > 0;
  if (!hasAssetId && !hasStreamUid) return null;
  const r = await q(
    `UPDATE social_media_asset
     SET processing_status = COALESCE($3::text, processing_status),
         processing_error = $4,
         normalized_url = COALESCE($5::text, normalized_url),
         poster_url = COALESCE($6::text, poster_url),
         playback_url = COALESCE($7::text, playback_url),
         thumbnail_url = COALESCE($8::text, thumbnail_url),
         duration_ms = COALESCE($9::bigint, duration_ms),
         width = COALESCE($10::integer, width),
         height = COALESCE($11::integer, height),
         updated_at = NOW()
     WHERE ($1::bigint IS NULL OR id = $1::bigint)
       AND ($2::text IS NULL OR stream_uid = $2::text)
     RETURNING *`,
    [
      hasAssetId ? Number(assetId) : null,
      hasStreamUid ? String(streamUid).trim() : null,
      processingStatus == null ? null : String(processingStatus).trim().toLowerCase(),
      processingError == null ? null : String(processingError).trim() || null,
      normalizedUrl == null ? null : String(normalizedUrl).trim() || null,
      posterUrl == null ? null : String(posterUrl).trim() || null,
      playbackUrl == null ? null : String(playbackUrl).trim() || null,
      thumbnailUrl == null ? null : String(thumbnailUrl).trim() || null,
      durationMs == null ? null : Number(durationMs),
      width == null ? null : Number(width),
      height == null ? null : Number(height),
    ]
  );
  return r.rows[0] || null;
}

export async function insertSocialMediaProcessingJob({
  assetId,
  jobType,
  status = "pending",
  errorMessage = null,
}) {
  const r = await q(
    `INSERT INTO social_media_processing_job
      (
        asset_id,
        job_type,
        status,
        error_message
      )
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [
      Number(assetId),
      String(jobType || "").trim().toLowerCase(),
      String(status || "pending").trim().toLowerCase(),
      errorMessage == null ? null : String(errorMessage).trim() || null,
    ]
  );
  return r.rows[0] || null;
}

export async function replaceSocialContentLink({
  entityType,
  entityId,
  targetType = null,
  merchantId = null,
  productId = null,
  offerId = null,
  couponId = null,
}) {
  const normalizedEntityType = String(entityType || "").trim().toLowerCase();
  if (!targetType) {
    await q(
      `DELETE FROM social_content_link
       WHERE entity_type = $1
         AND entity_id = $2`,
      [normalizedEntityType, Number(entityId)]
    );
    return null;
  }
  const r = await q(
    `INSERT INTO social_content_link
      (
        entity_type,
        entity_id,
        target_type,
        merchant_id,
        product_id,
        offer_id,
        coupon_id
      )
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (entity_type, entity_id)
     DO UPDATE SET
       target_type = EXCLUDED.target_type,
       merchant_id = EXCLUDED.merchant_id,
       product_id = EXCLUDED.product_id,
       offer_id = EXCLUDED.offer_id,
       coupon_id = EXCLUDED.coupon_id,
       updated_at = NOW()
     RETURNING *`,
    [
      normalizedEntityType,
      Number(entityId),
      String(targetType).trim().toLowerCase(),
      merchantId == null ? null : Number(merchantId),
      productId == null ? null : Number(productId),
      offerId == null ? null : Number(offerId),
      couponId == null ? null : Number(couponId),
    ]
  );
  return r.rows[0] || null;
}

export async function getSocialContentLink({ entityType, entityId }) {
  const r = await q(
    `SELECT *
     FROM social_content_link
     WHERE entity_type = $1
       AND entity_id = $2
     LIMIT 1`,
    [String(entityType || "").trim().toLowerCase(), Number(entityId)]
  );
  return r.rows[0] || null;
}

export async function upsertThreadParticipantState({
  threadId,
  userId,
  muted = null,
  pinned = null,
  themeKey = undefined,
  lastReadMessageId = null,
  lastDeliveredMessageId = null,
  inboxBucket = undefined,
  requestStatus = undefined,
  acceptedAt = undefined,
  rejectedAt = undefined,
}) {
  const r = await q(
    `INSERT INTO social_chat_thread_participant_state
      (
        thread_id,
        user_id,
        inbox_bucket,
        request_status,
        accepted_at,
        rejected_at,
        muted_until,
        pinned_at,
        theme_key,
        last_read_message_id,
        last_read_at,
        last_delivered_message_id,
        last_delivered_at
      )
     VALUES (
       $1,
       $2,
       COALESCE($3::text, 'primary'),
       COALESCE($4::text, 'accepted'),
       CASE
         WHEN $5::timestamptz IS NOT NULL THEN $5::timestamptz
         WHEN COALESCE($4::text, 'accepted') = 'accepted' THEN NOW()
         ELSE NULL
       END,
       $6::timestamptz,
       CASE WHEN $7::boolean = TRUE THEN NOW() + INTERVAL '3650 days' ELSE NULL END,
       CASE WHEN $8::boolean = TRUE THEN NOW() ELSE NULL END,
       COALESCE($9::text, 'default'),
       $10,
       CASE WHEN $10::bigint IS NULL THEN NULL ELSE NOW() END,
       $11,
       CASE WHEN $11::bigint IS NULL THEN NULL ELSE NOW() END
     )
     ON CONFLICT (thread_id, user_id)
     DO UPDATE SET
       inbox_bucket = COALESCE(EXCLUDED.inbox_bucket, social_chat_thread_participant_state.inbox_bucket),
       request_status = COALESCE(EXCLUDED.request_status, social_chat_thread_participant_state.request_status),
       accepted_at = CASE
         WHEN $5::timestamptz IS NOT NULL THEN $5::timestamptz
         WHEN $4::text = 'accepted'
           AND social_chat_thread_participant_state.accepted_at IS NULL
           THEN NOW()
         ELSE social_chat_thread_participant_state.accepted_at
       END,
       rejected_at = CASE
         WHEN $6::timestamptz IS NOT NULL THEN $6::timestamptz
         WHEN $4::text = 'rejected'
           AND social_chat_thread_participant_state.rejected_at IS NULL
           THEN NOW()
         ELSE social_chat_thread_participant_state.rejected_at
       END,
       muted_until = CASE
         WHEN $7::boolean IS NULL
           THEN social_chat_thread_participant_state.muted_until
         WHEN $7::boolean = TRUE
           THEN NOW() + INTERVAL '3650 days'
         ELSE NULL
       END,
       pinned_at = CASE
         WHEN $8::boolean IS NULL
           THEN social_chat_thread_participant_state.pinned_at
         WHEN $8::boolean = TRUE
           THEN COALESCE(social_chat_thread_participant_state.pinned_at, NOW())
         ELSE NULL
       END,
       theme_key = COALESCE(EXCLUDED.theme_key, social_chat_thread_participant_state.theme_key),
       last_read_message_id = CASE
         WHEN EXCLUDED.last_read_message_id IS NULL
           THEN social_chat_thread_participant_state.last_read_message_id
         WHEN social_chat_thread_participant_state.last_read_message_id IS NULL
           THEN EXCLUDED.last_read_message_id
         ELSE GREATEST(
           social_chat_thread_participant_state.last_read_message_id,
           EXCLUDED.last_read_message_id
         )
       END,
       last_read_at = CASE
         WHEN EXCLUDED.last_read_message_id IS NULL
           THEN social_chat_thread_participant_state.last_read_at
         ELSE NOW()
       END,
       last_delivered_message_id = CASE
         WHEN EXCLUDED.last_delivered_message_id IS NULL
           THEN social_chat_thread_participant_state.last_delivered_message_id
         WHEN social_chat_thread_participant_state.last_delivered_message_id IS NULL
           THEN EXCLUDED.last_delivered_message_id
         ELSE GREATEST(
           social_chat_thread_participant_state.last_delivered_message_id,
           EXCLUDED.last_delivered_message_id
         )
       END,
       last_delivered_at = CASE
         WHEN EXCLUDED.last_delivered_message_id IS NULL
           THEN social_chat_thread_participant_state.last_delivered_at
         ELSE NOW()
       END,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(threadId),
      Number(userId),
      inboxBucket === undefined ? null : String(inboxBucket || "").trim().toLowerCase() || null,
      requestStatus === undefined ? null : String(requestStatus || "").trim().toLowerCase() || null,
      acceptedAt === undefined || acceptedAt == null ? null : new Date(acceptedAt).toISOString(),
      rejectedAt === undefined || rejectedAt == null ? null : new Date(rejectedAt).toISOString(),
      muted == null ? null : muted === true,
      pinned == null ? null : pinned === true,
      themeKey === undefined ? null : String(themeKey || "").trim().toLowerCase() || "default",
      lastReadMessageId == null ? null : Number(lastReadMessageId),
      lastDeliveredMessageId == null ? null : Number(lastDeliveredMessageId),
    ]
  );
  return r.rows[0] || null;
}

export async function getThreadParticipantState({ threadId, userId }) {
  const r = await q(
    `SELECT *
     FROM social_chat_thread_participant_state
     WHERE thread_id = $1
       AND user_id = $2
     LIMIT 1`,
    [Number(threadId), Number(userId)]
  );
  return r.rows[0] || null;
}

export async function listThreadParticipantStatesForUser({ userId, threadIds = [] }) {
  const normalizedThreadIds = Array.isArray(threadIds)
    ? [...new Set(threadIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))]
    : [];
  if (normalizedThreadIds.length <= 0) return [];
  const r = await q(
    `SELECT *
     FROM social_chat_thread_participant_state
     WHERE user_id = $1
       AND thread_id = ANY($2::bigint[])`,
    [Number(userId), normalizedThreadIds]
  );
  return r.rows;
}

export async function getThreadMessageTranslation({
  messageId,
  targetLanguage,
}) {
  const r = await q(
    `SELECT *
     FROM social_chat_message_translation
     WHERE message_id = $1
       AND target_language = $2
     LIMIT 1`,
    [Number(messageId), String(targetLanguage || "").trim().toLowerCase()]
  );
  return r.rows[0] || null;
}

export async function upsertThreadMessageTranslation({
  messageId,
  targetLanguage,
  sourceLanguage = null,
  translatedText,
  provider = "openai",
  modelName = null,
  sourceVersionAt,
}) {
  const r = await q(
    `INSERT INTO social_chat_message_translation
      (
        message_id,
        target_language,
        source_language,
        translated_text,
        provider,
        model_name,
        source_version_at
      )
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (message_id, target_language)
     DO UPDATE SET
       source_language = EXCLUDED.source_language,
       translated_text = EXCLUDED.translated_text,
       provider = EXCLUDED.provider,
       model_name = EXCLUDED.model_name,
       source_version_at = EXCLUDED.source_version_at,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(messageId),
      String(targetLanguage || "").trim().toLowerCase(),
      sourceLanguage == null ? null : String(sourceLanguage).trim().toLowerCase() || null,
      String(translatedText || "").trim(),
      String(provider || "openai").trim().toLowerCase() || "openai",
      modelName == null ? null : String(modelName).trim() || null,
      new Date(sourceVersionAt).toISOString(),
    ]
  );
  return r.rows[0] || null;
}

export async function countPinnedThreadsForUser({ userId }) {
  const r = await q(
    `SELECT COUNT(*)::int AS pinned_count
     FROM social_chat_thread_participant_state
     WHERE user_id = $1
       AND pinned_at IS NOT NULL`,
    [Number(userId)]
  );
  return Number(r.rows[0]?.pinned_count || 0);
}

export async function isThreadPinnedForUser({ threadId, userId }) {
  const r = await q(
    `SELECT pinned_at
     FROM social_chat_thread_participant_state
     WHERE thread_id = $1
       AND user_id = $2
       AND pinned_at IS NOT NULL
     LIMIT 1`,
    [Number(threadId), Number(userId)]
  );
  return Boolean(r.rows[0]?.pinned_at);
}

export async function listUnreadCountsForThreads({ userId, threadIds = [] }) {
  const normalizedThreadIds = Array.isArray(threadIds)
    ? [...new Set(threadIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))]
    : [];
  if (normalizedThreadIds.length <= 0) return [];
  const r = await q(
    `SELECT
       t.id AS thread_id,
       COALESCE(COUNT(m.id), 0)::int AS unread_count
     FROM social_chat_thread t
     LEFT JOIN social_chat_thread_participant_state s
       ON s.thread_id = t.id
      AND s.user_id = $1
     LEFT JOIN social_chat_message m
       ON m.thread_id = t.id
      AND m.is_deleted = FALSE
      AND m.sender_user_id <> $1
      AND (
        s.last_read_message_id IS NULL
        OR m.id > s.last_read_message_id
      )
     WHERE t.id = ANY($2::bigint[])
     GROUP BY t.id`,
    [Number(userId), normalizedThreadIds]
  );
  return r.rows;
}

export async function listThreadMedia({
  threadId,
  limit = 60,
  beforeId = null,
}) {
  const r = await q(
    `SELECT
       id,
       thread_id,
       sender_user_id,
       attachment_url,
       attachment_kind,
       attachment_name,
       attachment_mime_type,
       attachment_size_bytes,
       attachment_duration_ms,
       attachment_provider,
       attachment_preview_url,
       attachment_thumbnail_url,
       attachment_width,
       attachment_height,
       attachment_upload_state,
       attachment_trace_id,
       created_at
     FROM social_chat_message
     WHERE thread_id = $1
       AND is_deleted = FALSE
       AND attachment_url IS NOT NULL
       AND ($2::bigint IS NULL OR id < $2::bigint)
     ORDER BY id DESC
     LIMIT $3`,
    [
      Number(threadId),
      beforeId == null ? null : Number(beforeId),
      Math.max(1, Math.min(120, Number(limit) || 60)),
    ]
  );
  return r.rows;
}
