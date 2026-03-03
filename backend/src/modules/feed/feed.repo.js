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
     u.image_url AS user_image_url
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
     WHERE is_disabled = FALSE
       AND is_approved = TRUE
       AND COALESCE(LOWER(type), '') NOT IN ('car', 'cars', 'automotive', 'vehicles')
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
    `SELECT id, full_name, phone, role, image_url
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
       created_at
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function getUserSocialStats(userId) {
  const r = await q(
    `SELECT
       COUNT(*)::int AS total_posts,
       COUNT(*) FILTER (WHERE post_kind = 'image')::int AS image_posts,
       COUNT(*) FILTER (WHERE post_kind = 'video')::int AS video_posts,
       COUNT(*) FILTER (WHERE post_kind = 'merchant_review')::int AS review_posts
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
