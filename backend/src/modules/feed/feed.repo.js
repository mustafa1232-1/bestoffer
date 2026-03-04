import { q } from "../../config/db.js";

export async function listFeedPosts({
  viewerUserId,
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
       p.merchant_id,
       p.review_rating,
       p.created_at,
     p.updated_at,
     u.full_name AS user_full_name,
     u.phone AS user_phone,
     u.image_url AS user_image_url,
     u.role AS user_role,
       m.name AS merchant_name,
       COALESCE(l.likes_count, 0)::int AS likes_count,
       COALESCE(c.comments_count, 0)::int AS comments_count,
       COALESCE(v.is_liked, FALSE) AS is_liked
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     LEFT JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS likes_count
       FROM social_post_like l
       WHERE l.post_id = p.id
     ) l ON TRUE
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS comments_count
       FROM social_post_comment c
       WHERE c.post_id = p.id
         AND c.is_deleted = FALSE
         AND c.moderation_status = 'approved'
     ) c ON TRUE
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_liked
       FROM social_post_like lv
       WHERE lv.post_id = p.id
         AND lv.user_id = $1
       LIMIT 1
     ) v ON TRUE
     WHERE p.is_deleted = FALSE
       AND p.moderation_status = 'approved'
       AND (u.social_posts_public = TRUE OR p.user_id = $1)
       AND ($2::bigint IS NULL OR p.id < $2::bigint)
       AND ($3::text IS NULL OR p.post_kind = $3::text)
     ORDER BY p.id DESC
     LIMIT $4`,
    [Number(viewerUserId), beforeId, postKind, Number(limit)]
  );
  return r.rows;
}

export async function listUserFeedPosts({
  viewerUserId,
  userId,
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
       p.merchant_id,
       p.review_rating,
       p.created_at,
       p.updated_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       m.name AS merchant_name,
       COALESCE(l.likes_count, 0)::int AS likes_count,
       COALESCE(c.comments_count, 0)::int AS comments_count,
       COALESCE(v.is_liked, FALSE) AS is_liked
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     LEFT JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS likes_count
       FROM social_post_like l
       WHERE l.post_id = p.id
     ) l ON TRUE
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS comments_count
       FROM social_post_comment c
       WHERE c.post_id = p.id
         AND c.is_deleted = FALSE
         AND c.moderation_status = 'approved'
     ) c ON TRUE
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_liked
       FROM social_post_like lv
       WHERE lv.post_id = p.id
         AND lv.user_id = $1
       LIMIT 1
     ) v ON TRUE
     WHERE p.user_id = $2
       AND p.is_deleted = FALSE
       AND p.moderation_status = 'approved'
       AND ($3::bigint IS NULL OR p.id < $3::bigint)
       AND ($4::text IS NULL OR p.post_kind = $4::text)
     ORDER BY p.id DESC
     LIMIT $5`,
    [Number(viewerUserId), Number(userId), beforeId, postKind, Number(limit)]
  );
  return r.rows;
}

export async function findFeedPostById({ viewerUserId, postId }) {
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.post_kind,
       p.caption,
       p.media_url,
       p.media_kind,
       p.merchant_id,
       p.review_rating,
       p.created_at,
       p.updated_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       m.name AS merchant_name,
       COALESCE(l.likes_count, 0)::int AS likes_count,
       COALESCE(c.comments_count, 0)::int AS comments_count,
       COALESCE(v.is_liked, FALSE) AS is_liked
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     LEFT JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS likes_count
       FROM social_post_like l
       WHERE l.post_id = p.id
     ) l ON TRUE
     LEFT JOIN LATERAL (
       SELECT COUNT(*)::int AS comments_count
       FROM social_post_comment c
       WHERE c.post_id = p.id
         AND c.is_deleted = FALSE
         AND c.moderation_status = 'approved'
     ) c ON TRUE
     LEFT JOIN LATERAL (
       SELECT TRUE AS is_liked
       FROM social_post_like lv
       WHERE lv.post_id = p.id
         AND lv.user_id = $1
       LIMIT 1
     ) v ON TRUE
     WHERE p.id = $2
       AND p.is_deleted = FALSE
       AND p.moderation_status = 'approved'
       AND (u.social_posts_public = TRUE OR p.user_id = $1)
     LIMIT 1`,
    [Number(viewerUserId), Number(postId)]
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
       s.story_style,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       COALESCE(v.story_id IS NOT NULL, FALSE) AS is_viewed
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_story_view v
       ON v.story_id = s.id
      AND v.user_id = $1
     WHERE s.is_deleted = FALSE
       AND s.moderation_status = 'approved'
       AND s.expires_at > NOW()
       AND (u.social_stories_public = TRUE OR s.user_id = $1)
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
       s.story_style,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       COALESCE(v.story_id IS NOT NULL, FALSE) AS is_viewed
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_story_view v
       ON v.story_id = s.id
      AND v.user_id = $1
     WHERE s.user_id = $2
       AND s.is_deleted = FALSE
       AND s.moderation_status = 'approved'
       AND s.expires_at <= NOW()
       AND ($3::bigint IS NULL OR s.id < $3::bigint)
     ORDER BY s.id DESC
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
       s.story_style,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       COALESCE(v.story_id IS NOT NULL, FALSE) AS is_viewed
     FROM social_story_highlight h
     JOIN social_story s ON s.id = h.story_id
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_story_view v
       ON v.story_id = s.id
      AND v.user_id = $1
     WHERE h.owner_user_id = $2
       AND s.is_deleted = FALSE
       AND s.moderation_status = 'approved'
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
  const r = await q(
    `INSERT INTO social_story_highlight
      (owner_user_id, story_id, title)
     VALUES ($1, $2, $3)
     ON CONFLICT (owner_user_id, story_id)
     DO UPDATE SET
       title = COALESCE(NULLIF(EXCLUDED.title, ''), social_story_highlight.title),
       updated_at = NOW()
     RETURNING *`,
    [Number(ownerUserId), Number(storyId), title || null]
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
       s.story_style,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       COALESCE(v.story_id IS NOT NULL, FALSE) AS is_viewed
     FROM social_story_highlight h
     JOIN social_story s ON s.id = h.story_id
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_story_view v
       ON v.story_id = s.id
      AND v.user_id = $1
     WHERE h.id = $2
       AND s.is_deleted = FALSE
       AND s.moderation_status = 'approved'
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
  storyStyle = {},
}) {
  const r = await q(
    `INSERT INTO social_story
      (user_id, caption, media_url, media_kind, story_style, moderation_status)
     VALUES ($1, $2, $3, $4, $5::jsonb, 'approved')
     RETURNING *`,
    [
      Number(userId),
      caption || null,
      mediaUrl,
      mediaKind,
      JSON.stringify(storyStyle && typeof storyStyle === "object" ? storyStyle : {}),
    ]
  );
  return r.rows[0] || null;
}

export async function findStoryById({ viewerUserId, storyId }) {
  const r = await q(
    `SELECT
       s.id,
       s.user_id,
       s.caption,
       s.media_url,
       s.media_kind,
       s.story_style,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role,
       COALESCE(v.story_id IS NOT NULL, FALSE) AS is_viewed
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     LEFT JOIN social_story_view v
       ON v.story_id = s.id
      AND v.user_id = $1
     WHERE s.id = $2
       AND s.is_deleted = FALSE
       AND s.moderation_status = 'approved'
       AND s.expires_at > NOW()
     LIMIT 1`,
    [Number(viewerUserId), Number(storyId)]
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
       s.story_style,
       s.created_at,
       s.updated_at,
       s.expires_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.image_url AS user_image_url,
       u.role AS user_role
     FROM social_story s
     JOIN app_user u ON u.id = s.user_id
     WHERE s.id = $1
       AND s.user_id = $2
       AND s.is_deleted = FALSE
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

export async function listStoryAudienceUserIds({
  excludeUserId,
  limit = 1500,
}) {
  const r = await q(
    `SELECT id
     FROM app_user
     WHERE id <> $1
     ORDER BY id DESC
     LIMIT $2`,
    [Number(excludeUserId), Number(limit)]
  );
  return r.rows.map((row) => Number(row.id)).filter((id) => id > 0);
}

export async function insertPost({
  userId,
  postKind,
  caption,
  mediaUrl = null,
  mediaKind = null,
  merchantId = null,
  reviewRating = null,
}) {
  const r = await q(
    `INSERT INTO social_post
      (user_id, post_kind, caption, media_url, media_kind, merchant_id, review_rating, moderation_status)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'approved')
     RETURNING *`,
    [
      Number(userId),
      postKind,
      caption || null,
      mediaUrl,
      mediaKind,
      merchantId == null ? null : Number(merchantId),
      reviewRating == null ? null : Number(reviewRating),
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
     u.social_posts_public AS user_posts_public
     FROM social_post p
     JOIN app_user u ON u.id = p.user_id
     WHERE p.id = $1
       AND p.is_deleted = FALSE
     LIMIT 1`,
    [Number(postId)]
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

export async function listPostComments({ postId, limit = 40, beforeId = null }) {
  const r = await q(
    `SELECT
       c.id,
       c.post_id,
       c.user_id,
       c.body,
       c.created_at,
       c.updated_at,
       u.full_name AS user_full_name,
       u.phone AS user_phone,
       u.role AS user_role,
       u.image_url AS user_image_url
     FROM social_post_comment c
     JOIN app_user u ON u.id = c.user_id
     WHERE c.post_id = $1
       AND c.is_deleted = FALSE
       AND c.moderation_status = 'approved'
       AND ($2::bigint IS NULL OR c.id < $2::bigint)
     ORDER BY c.id DESC
     LIMIT $3`,
    [Number(postId), beforeId, Number(limit)]
  );
  return r.rows;
}

export async function insertComment({ postId, userId, body }) {
  const r = await q(
    `INSERT INTO social_post_comment (post_id, user_id, body, moderation_status)
     VALUES ($1, $2, $3, 'approved')
     RETURNING *`,
    [Number(postId), Number(userId), String(body || "").trim()]
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

export async function listMerchantOptions({ search = "", limit = 120 }) {
  const searchQuery = String(search || "").trim();
  const r = await q(
    `SELECT
       id,
       name,
       type,
       phone,
       image_url
     FROM merchant
     WHERE COALESCE(is_disabled, FALSE) = FALSE
       AND COALESCE(is_approved, TRUE) = TRUE
       AND COALESCE(TRIM(LOWER(type)), '') NOT IN ('car', 'cars', 'automotive', 'vehicles')
       AND (
         $1::text = ''
         OR name ILIKE ('%' || $1 || '%')
         OR phone ILIKE ('%' || $1 || '%')
       )
     ORDER BY
       CASE WHEN is_open THEN 0 ELSE 1 END ASC,
       name ASC
     LIMIT $2`,
    [searchQuery, Number(limit)]
  );
  return r.rows;
}

export async function findUserPublicProfile(userId) {
  const r = await q(
    `SELECT
       id,
       full_name,
       phone,
       role,
       image_url,
       social_age,
       social_show_phone,
       social_posts_public,
       social_stories_public
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function findUserSocialProfile(userId) {
  const r = await q(
    `SELECT
       id,
       full_name,
       phone,
       role,
       image_url,
       social_age,
       social_bio,
       social_show_phone,
       social_posts_public,
       social_stories_public,
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
  fullName,
  bio,
  age,
  imageUrl,
  showPhone,
  postsPublic,
  storiesPublic,
}) {
  const sets = [];
  const params = [];

  if (fullName !== undefined) {
    params.push(String(fullName).trim());
    sets.push(`full_name = $${params.length}`);
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
  if (showPhone !== undefined) {
    params.push(showPhone === true);
    sets.push(`social_show_phone = $${params.length}`);
  }
  if (postsPublic !== undefined) {
    params.push(postsPublic === true);
    sets.push(`social_posts_public = $${params.length}`);
  }
  if (storiesPublic !== undefined) {
    params.push(storiesPublic === true);
    sets.push(`social_stories_public = $${params.length}`);
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
       full_name,
       phone,
       role,
       image_url,
       social_age,
       social_bio,
       social_show_phone,
       social_posts_public,
       social_stories_public,
       created_at`,
    params
  );
  return r.rows[0] || null;
}

export async function getUserSocialStats(userId) {
  const r = await q(
    `SELECT
       COUNT(*)::int AS total_posts,
       COUNT(*) FILTER (WHERE post_kind = 'image')::int AS image_posts,
       COUNT(*) FILTER (WHERE post_kind = 'video')::int AS video_posts,
       COUNT(*) FILTER (WHERE post_kind = 'merchant_review')::int AS review_posts,
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
       AND moderation_status = 'approved'`,
    [Number(userId)]
  );
  return r.rows[0] || {
    total_posts: 0,
    image_posts: 0,
    video_posts: 0,
    review_posts: 0,
    likes_received: 0,
    comments_received: 0,
    active_stories: 0,
    highlights_count: 0,
  };
}

export async function createOrGetThread({ userAId, userBId }) {
  const a = Math.min(Number(userAId), Number(userBId));
  const b = Math.max(Number(userAId), Number(userBId));

  const r = await q(
    `INSERT INTO social_chat_thread
      (user_a_id, user_b_id, last_message_at)
     VALUES ($1, $2, NOW())
     ON CONFLICT (user_a_id, user_b_id)
     DO UPDATE SET updated_at = NOW()
     RETURNING *`,
    [a, b]
  );
  return r.rows[0] || null;
}

export async function getThreadForUser({ threadId, userId }) {
  const r = await q(
    `SELECT
       t.*,
       CASE WHEN t.user_a_id = $2 THEN t.user_b_id ELSE t.user_a_id END AS peer_user_id,
       peer.full_name AS peer_full_name,
       peer.phone AS peer_phone,
       peer.role AS peer_role,
       peer.image_url AS peer_image_url
      FROM social_chat_thread t
      JOIN social_user_relation rel
        ON rel.user_a_id = t.user_a_id
       AND rel.user_b_id = t.user_b_id
       AND rel.status = 'accepted'
      JOIN app_user peer ON peer.id = CASE WHEN t.user_a_id = $2 THEN t.user_b_id ELSE t.user_a_id END
      WHERE t.id = $1
        AND (t.user_a_id = $2 OR t.user_b_id = $2)
      LIMIT 1`,
    [Number(threadId), Number(userId)]
  );
  return r.rows[0] || null;
}

export async function listThreadsForUser({ userId, limit = 50 }) {
  const r = await q(
    `SELECT
        t.id,
        t.user_a_id,
       t.user_b_id,
       t.created_at,
       t.updated_at,
       t.last_message_at,
       CASE WHEN t.user_a_id = $1 THEN t.user_b_id ELSE t.user_a_id END AS peer_user_id,
       peer.full_name AS peer_full_name,
       peer.phone AS peer_phone,
       peer.role AS peer_role,
       peer.image_url AS peer_image_url,
        lm.id AS last_message_id,
        lm.sender_user_id AS last_message_sender_user_id,
        lm.body AS last_message_body,
        lm.created_at AS last_message_created_at
      FROM social_chat_thread t
      JOIN social_user_relation rel
        ON rel.user_a_id = t.user_a_id
       AND rel.user_b_id = t.user_b_id
       AND rel.status = 'accepted'
      JOIN app_user peer ON peer.id = CASE WHEN t.user_a_id = $1 THEN t.user_b_id ELSE t.user_a_id END
      LEFT JOIN LATERAL (
        SELECT m.id, m.sender_user_id, m.body, m.created_at
       FROM social_chat_message m
       WHERE m.thread_id = t.id
         AND m.is_deleted = FALSE
       ORDER BY m.id DESC
       LIMIT 1
     ) lm ON TRUE
     WHERE t.user_a_id = $1 OR t.user_b_id = $1
     ORDER BY COALESCE(lm.created_at, t.last_message_at) DESC, t.id DESC
     LIMIT $2`,
    [Number(userId), Number(limit)]
  );
  return r.rows;
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
       m.created_at,
       m.updated_at,
       u.full_name AS sender_full_name,
       u.phone AS sender_phone,
       u.role AS sender_role,
       u.image_url AS sender_image_url
     FROM social_chat_message m
     JOIN app_user u ON u.id = m.sender_user_id
     WHERE m.thread_id = $1
       AND m.is_deleted = FALSE
       AND ($2::bigint IS NULL OR m.id < $2::bigint)
     ORDER BY m.id DESC
     LIMIT $3`,
    [Number(threadId), beforeId, Number(limit)]
  );
  return r.rows;
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

export async function insertThreadMessage({ threadId, senderUserId, body }) {
  const r = await q(
    `INSERT INTO social_chat_message (thread_id, sender_user_id, body)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [Number(threadId), Number(senderUserId), String(body || "").trim()]
  );
  return r.rows[0] || null;
}

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
     SET status = $3,
         requested_at = CASE WHEN $3 = 'pending' THEN NOW() ELSE requested_at END,
         responded_at = CASE WHEN $3 = 'pending' THEN NULL ELSE NOW() END
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
