import { AppError } from "../../shared/utils/errors.js";
import { emitToUser } from "../../shared/realtime/live-events.js";
import { createNotification } from "../notifications/notifications.repo.js";
import * as repo from "./feed.repo.js";

const moderationLexicon = {
  violence: [
    "اقتل",
    "قتل",
    "تفجير",
    "انفجار",
    "سلاح",
    "ارهابي",
    "ارهاب",
    "ذبح",
    "داعش",
    "kill",
    "bomb",
    "weapon",
    "terror",
  ],
  insults: [
    "كلب",
    "حمار",
    "قذر",
    "وسخ",
    "لعنة",
    "تافه",
    "stupid",
    "idiot",
    "fuck",
    "shit",
    "bitch",
  ],
  politics: [
    "انتخابات",
    "حزب",
    "سياسة",
    "مرشح",
    "مجلس النواب",
    "رئيس الجمهورية",
    "رئيس الوزراء",
    "politics",
    "election",
    "government",
    "parliament",
  ],
};

function normalizeModerationText(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[\u064B-\u065F\u0670]/g, "")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function detectModerationCategories(value) {
  const normalized = normalizeModerationText(value);
  if (!normalized) return [];

  const categories = [];
  for (const [category, keywords] of Object.entries(moderationLexicon)) {
    if (keywords.some((keyword) => normalized.includes(keyword))) {
      categories.push(category);
    }
  }
  return categories;
}

function assertContentAllowed(value) {
  const categories = detectModerationCategories(value);
  if (categories.length <= 0) return;
  throw new AppError("CONTENT_NOT_ALLOWED", {
    status: 400,
    details: { categories },
  });
}

function mapPostRow(row) {
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    postKind: row.post_kind,
    caption: row.caption || "",
    mediaUrl: row.media_url || null,
    mediaKind: row.media_kind || null,
    merchantId: row.merchant_id == null ? null : Number(row.merchant_id),
    merchantName: row.merchant_name || null,
    reviewRating: row.review_rating == null ? null : Number(row.review_rating),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    author: {
      id: Number(row.user_id),
      fullName: row.user_full_name || "",
      imageUrl: row.user_image_url || null,
      role: row.user_role || "user",
      phone: "",
    },
    likesCount: Number(row.likes_count || 0),
    commentsCount: Number(row.comments_count || 0),
    isLiked: row.is_liked === true,
  };
}

function mapCommentRow(row) {
  return {
    id: Number(row.id),
    postId: Number(row.post_id),
    userId: Number(row.user_id),
    body: row.body || "",
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    author: {
      id: Number(row.user_id),
      fullName: row.user_full_name || "",
      imageUrl: row.user_image_url || null,
      phone: "",
      role: row.user_role || "user",
    },
  };
}

function mapStoryRow(row, viewerUserId) {
  const storyStyle =
    row.story_style && typeof row.story_style === "object" && !Array.isArray(row.story_style)
      ? row.story_style
      : {};
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    caption: row.caption || "",
    mediaUrl: row.media_url || null,
    mediaKind: row.media_kind || null,
    storyStyle,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    expiresAt: row.expires_at,
    isViewed: row.is_viewed === true,
    isMine: Number(row.user_id) === Number(viewerUserId),
    author: {
      id: Number(row.user_id),
      fullName: row.user_full_name || "",
      imageUrl: row.user_image_url || null,
      role: row.user_role || "user",
      phone: "",
    },
  };
}

function canViewPosts({ viewerUserId, owner }) {
  return (
    Number(owner?.id || 0) === Number(viewerUserId) ||
    owner?.social_posts_public === true
  );
}

function canViewStories({ viewerUserId, owner }) {
  return (
    Number(owner?.id || 0) === Number(viewerUserId) ||
    owner?.social_stories_public === true
  );
}

function canViewPhone({ viewerUserId, owner }) {
  return (
    Number(owner?.id || 0) === Number(viewerUserId) ||
    owner?.social_show_phone === true
  );
}

function mapStoryHighlightRow(row, viewerUserId) {
  return {
    id: Number(row.highlight_id),
    ownerUserId: Number(row.owner_user_id),
    title: row.highlight_title || "",
    createdAt: row.highlight_created_at,
    story: mapStoryRow(row, viewerUserId),
  };
}

function mapThreadRow(row, viewerUserId) {
  const peerId = Number(row.peer_user_id);
  return {
    id: Number(row.id),
    userAId: Number(row.user_a_id),
    userBId: Number(row.user_b_id),
    peerPhone: row.peer_phone || "",
    peer: {
      id: peerId,
      fullName: row.peer_full_name || "",
      phone: row.peer_phone || "",
      imageUrl: row.peer_image_url || null,
      role: row.peer_role || "user",
    },
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    lastMessageAt: row.last_message_at,
    lastMessage: row.last_message_id
      ? {
          id: Number(row.last_message_id),
          threadId: Number(row.id),
          senderUserId: Number(row.last_message_sender_user_id),
          body: row.last_message_body || "",
          createdAt: row.last_message_created_at,
          isMine:
            Number(row.last_message_sender_user_id) === Number(viewerUserId),
        }
      : null,
  };
}

function mapMessageRow(row, viewerUserId) {
  return {
    id: Number(row.id),
    threadId: Number(row.thread_id),
    senderUserId: Number(row.sender_user_id),
    body: row.body || "",
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    isMine: Number(row.sender_user_id) === Number(viewerUserId),
    sender: {
      id: Number(row.sender_user_id),
      fullName: row.sender_full_name || "",
      imageUrl: row.sender_image_url || null,
      phone: row.sender_phone || "",
      role: row.sender_role || "user",
    },
  };
}

function resolveMediaKindFromMime(mimeType) {
  const mime = String(mimeType || "").toLowerCase();
  if (!mime) return null;
  if (mime.startsWith("image/")) return "image";
  if (mime.startsWith("video/")) return "video";
  return null;
}

function compactMessagePreview(value) {
  const text = String(value || "").trim().replace(/\s+/g, " ");
  if (text.length <= 80) return text;
  return `${text.slice(0, 80)}...`;
}

function dispatchStoryNotifications({ audienceUserIds, actor, story }) {
  if (!Array.isArray(audienceUserIds) || audienceUserIds.length <= 0) return;
  setImmediate(async () => {
    try {
      const safeTitle = "ستوري جديدة في شديصير بسماية";
      const safeBody = `${actor?.full_name || "مستخدم"} نشر ستوري جديدة`;
      await Promise.allSettled(
        audienceUserIds.map((userId) =>
          createNotification({
            userId: Number(userId),
            type: "social.story.new",
            title: safeTitle,
            body: safeBody,
            payload: {
              storyId: Number(story.id),
              actorUserId: Number(actor?.id || story.userId),
              target: "social_feed",
            },
          })
        )
      );
    } catch (error) {
      console.error("Failed to dispatch story notifications", error);
    }
  });
}

export async function listPosts(viewerUserId, query) {
  const rows = await repo.listFeedPosts({
    viewerUserId,
    limit: query.limit,
    beforeId: query.beforeId,
    postKind: query.kind,
  });
  return {
    posts: rows.map(mapPostRow),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function listUserPosts(viewerUserId, userId, query) {
  const owner = await repo.findUserSocialProfile(userId);
  if (!owner) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  const privateForViewer = !canViewPosts({ viewerUserId, owner });

  const rows = privateForViewer
    ? []
    : await repo.listUserFeedPosts({
        viewerUserId,
        userId,
        limit: query.limit,
        beforeId: query.beforeId,
        postKind: query.kind,
      });
  return {
    user: {
      id: Number(owner.id),
      fullName: owner.full_name || "",
      imageUrl: owner.image_url || null,
      role: owner.role || "user",
      phone: canViewPhone({ viewerUserId, owner }) ? owner.phone || "" : "",
      privacy: {
        showPhone: owner.social_show_phone === true,
        postsPublic: owner.social_posts_public === true,
        storiesPublic: owner.social_stories_public === true,
      },
    },
    postsPrivate: privateForViewer,
    posts: rows.map(mapPostRow),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function getUserProfile(viewerUserId, userId) {
  const profile = await repo.findUserSocialProfile(userId);
  if (!profile) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  const isMe = Number(profile.id) === Number(viewerUserId);
  const phoneVisible = canViewPhone({ viewerUserId, owner: profile });
  const stats = await repo.getUserSocialStats(userId);
  return {
    profile: {
      id: Number(profile.id),
      fullName: profile.full_name || "",
      imageUrl: profile.image_url || null,
      bio: profile.social_bio || "",
      phone: phoneVisible ? profile.phone || "" : "",
      role: profile.role || "user",
      joinedAt: profile.created_at || null,
      isMe,
      privacy: {
        showPhone: profile.social_show_phone === true,
        postsPublic: profile.social_posts_public === true,
        storiesPublic: profile.social_stories_public === true,
      },
      stats: {
        totalPosts: Number(stats.total_posts || 0),
        imagePosts: Number(stats.image_posts || 0),
        videoPosts: Number(stats.video_posts || 0),
        reviewPosts: Number(stats.review_posts || 0),
        likesReceived: Number(stats.likes_received || 0),
        commentsReceived: Number(stats.comments_received || 0),
        activeStories: Number(stats.active_stories || 0),
        highlightsCount: Number(stats.highlights_count || 0),
      },
    },
  };
}

export async function updateMyProfile(userId, dto) {
  if (
    dto.fullName === undefined &&
    dto.bio === undefined &&
    dto.imageUrl === undefined &&
    dto.showPhone === undefined &&
    dto.postsPublic === undefined &&
    dto.storiesPublic === undefined
  ) {
    throw new AppError("NO_CHANGES", { status: 400 });
  }

  if (dto.fullName) {
    assertContentAllowed(dto.fullName);
  }
  if (dto.bio) {
    assertContentAllowed(dto.bio);
  }

  const updated = await repo.updateUserSocialProfile({
    userId,
    fullName: dto.fullName,
    bio: dto.bio,
    imageUrl: dto.imageUrl,
    showPhone: dto.showPhone,
    postsPublic: dto.postsPublic,
    storiesPublic: dto.storiesPublic,
  });
  if (!updated) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  const stats = await repo.getUserSocialStats(userId);

  return {
    profile: {
      id: Number(updated.id),
      fullName: updated.full_name || "",
      imageUrl: updated.image_url || null,
      bio: updated.social_bio || "",
      phone: updated.phone || "",
      role: updated.role || "user",
      joinedAt: updated.created_at || null,
      isMe: true,
      privacy: {
        showPhone: updated.social_show_phone === true,
        postsPublic: updated.social_posts_public === true,
        storiesPublic: updated.social_stories_public === true,
      },
      stats: {
        totalPosts: Number(stats.total_posts || 0),
        imagePosts: Number(stats.image_posts || 0),
        videoPosts: Number(stats.video_posts || 0),
        reviewPosts: Number(stats.review_posts || 0),
        likesReceived: Number(stats.likes_received || 0),
        commentsReceived: Number(stats.comments_received || 0),
        activeStories: Number(stats.active_stories || 0),
        highlightsCount: Number(stats.highlights_count || 0),
      },
    },
  };
}

export async function listUserHighlights(viewerUserId, userId) {
  const profile = await repo.findUserSocialProfile(userId);
  if (!profile) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  const privateForViewer = !canViewStories({ viewerUserId, owner: profile });

  const rows = privateForViewer
    ? []
    : await repo.listUserHighlightsRaw({
        viewerUserId,
        ownerUserId: userId,
        limit: 80,
      });
  return {
    storiesPrivate: privateForViewer,
    highlights: rows.map((row) => mapStoryHighlightRow(row, viewerUserId)),
  };
}

export async function listStories(viewerUserId, query) {
  const safeLimitUsers = Math.max(1, Math.min(80, Number(query.limitUsers) || 30));
  const safeMaxPerUser = Math.max(1, Math.min(20, Number(query.maxPerUser) || 8));
  const rows = await repo.listActiveStoriesRaw({
    viewerUserId,
    limitRows: Math.max(80, safeLimitUsers * safeMaxPerUser * 2),
  });

  const grouped = new Map();
  for (const row of rows) {
    const userId = Number(row.user_id);
    if (!Number.isFinite(userId) || userId <= 0) continue;

    let group = grouped.get(userId);
    if (!group) {
      group = {
        userId,
        author: {
          id: userId,
          fullName: row.user_full_name || "",
          imageUrl: row.user_image_url || null,
          role: row.user_role || "user",
          phone: row.user_phone || "",
        },
        latestAt: row.created_at,
        hasUnviewed: false,
        stories: [],
      };
      grouped.set(userId, group);
    }

    if (group.stories.length >= safeMaxPerUser) continue;
    const story = mapStoryRow(row, viewerUserId);
    group.stories.push(story);
    if (!story.isViewed && !story.isMine) {
      group.hasUnviewed = true;
    }
    if (!group.latestAt || new Date(story.createdAt) > new Date(group.latestAt)) {
      group.latestAt = story.createdAt;
    }
  }

  const stories = [...grouped.values()]
    .map((group) => ({
      ...group,
      stories: [...group.stories].reverse(),
    }))
    .sort((a, b) => new Date(b.latestAt).getTime() - new Date(a.latestAt).getTime())
    .slice(0, safeLimitUsers);

  return {
    stories,
    generatedAt: new Date().toISOString(),
  };
}

export async function listMyStoryArchive(userId, query) {
  const safeLimit = Math.max(1, Math.min(100, Number(query?.limit) || 40));
  const beforeId =
    Number.isInteger(Number(query?.beforeId)) && Number(query.beforeId) > 0
      ? Number(query.beforeId)
      : null;

  const rows = await repo.listArchivedStoriesRaw({
    viewerUserId: userId,
    ownerUserId: userId,
    beforeId,
    limit: safeLimit,
  });

  const stories = rows.map((row) => mapStoryRow(row, userId));
  return {
    stories,
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function getPostById(viewerUserId, postId) {
  const row = await repo.findFeedPostById({
    viewerUserId,
    postId,
  });
  if (!row) {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  return { post: mapPostRow(row) };
}

export async function createPost(userId, dto, media) {
  assertContentAllowed(dto.caption || "");

  const mediaKind = resolveMediaKindFromMime(media?.mimetype);
  const mediaUrl = media?.url || null;

  let postKind = dto.postKind;
  if (mediaKind && postKind !== "merchant_review") {
    postKind = mediaKind;
  }

  if (!mediaKind && (postKind === "image" || postKind === "video")) {
    throw new AppError("MEDIA_REQUIRED", { status: 400 });
  }

  if (!dto.caption && !mediaUrl && postKind !== "merchant_review") {
    throw new AppError("EMPTY_POST", {
      status: 400,
      details: { fields: ["caption", "media"] },
    });
  }

  if (postKind === "merchant_review") {
    if (dto.merchantId == null || dto.reviewRating == null) {
      throw new AppError("MERCHANT_REVIEW_INCOMPLETE", { status: 400 });
    }
  }

  const inserted = await repo.insertPost({
    userId,
    postKind,
    caption: dto.caption,
    mediaUrl,
    mediaKind,
    merchantId: dto.merchantId,
    reviewRating: dto.reviewRating,
  });
  const created = await repo.findPostById(inserted?.id);
  if (!created) throw new AppError("POST_CREATE_FAILED", { status: 500 });

  const mapped = mapPostRow({
    ...created,
    likes_count: 0,
    comments_count: 0,
    is_liked: false,
    merchant_name: created.merchant_name || null,
  });
  emitToUser(Number(userId), "social_post_created", { post: mapped });
  return mapped;
}

export async function createStory(userId, dto, media) {
  assertContentAllowed(dto.caption || "");

  const mediaKind = resolveMediaKindFromMime(media?.mimetype);
  const mediaUrl = media?.url || null;
  if (!dto.caption && !mediaUrl) {
    throw new AppError("EMPTY_STORY", {
      status: 400,
      details: { fields: ["caption", "media"] },
    });
  }

  const inserted = await repo.insertStory({
    userId,
    caption: dto.caption,
    mediaUrl,
    mediaKind,
    storyStyle: dto.storyStyle,
  });
  if (!inserted?.id) {
    throw new AppError("STORY_CREATE_FAILED", { status: 500 });
  }
  const created = await repo.findStoryById({
    viewerUserId: userId,
    storyId: inserted.id,
  });
  if (!created) throw new AppError("STORY_CREATE_FAILED", { status: 500 });
  const mapped = mapStoryRow(created, userId);

  emitToUser(Number(userId), "social_story_created", { story: mapped });

  const actor = await repo.findUserPublicProfile(userId);
  if (actor?.social_stories_public === true) {
    const audienceUserIds = await repo.listStoryAudienceUserIds({
      excludeUserId: userId,
      limit: 1500,
    });
    dispatchStoryNotifications({
      audienceUserIds,
      actor,
      story: mapped,
    });
  }

  return mapped;
}

export async function highlightStory({ userId, storyId, title }) {
  const story = await repo.findStoryForHighlight({
    ownerUserId: userId,
    storyId,
  });
  if (!story) {
    throw new AppError("STORY_NOT_FOUND", { status: 404 });
  }

  const inserted = await repo.upsertStoryHighlight({
    ownerUserId: userId,
    storyId,
    title,
  });
  if (!inserted?.id) {
    throw new AppError("HIGHLIGHT_CREATE_FAILED", { status: 500 });
  }

  const row = await repo.findHighlightById({
    viewerUserId: userId,
    highlightId: inserted.id,
  });
  if (!row) {
    throw new AppError("HIGHLIGHT_CREATE_FAILED", { status: 500 });
  }

  return { highlight: mapStoryHighlightRow(row, userId) };
}

export async function removeHighlight({ userId, highlightId }) {
  const deleted = await repo.deleteStoryHighlight({
    ownerUserId: userId,
    highlightId,
  });
  if (!deleted) {
    throw new AppError("HIGHLIGHT_NOT_FOUND", { status: 404 });
  }
  return { ok: true };
}

export async function markStoryViewed({ storyId, userId }) {
  const story = await repo.findStoryById({
    viewerUserId: userId,
    storyId,
  });
  if (!story) {
    throw new AppError("STORY_NOT_FOUND", { status: 404 });
  }
  await repo.markStoryViewed({ storyId, userId });
  return { ok: true };
}

export async function toggleLike({ postId, userId }) {
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true || post.moderation_status !== "approved") {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const owner = await repo.findUserSocialProfile(post.user_id);
  if (owner && !canViewPosts({ viewerUserId: userId, owner })) {
    throw new AppError("PROFILE_POSTS_PRIVATE", { status: 403 });
  }

  const existed = await repo.hasLike(postId, userId);
  if (existed) await repo.removeLike(postId, userId);
  else await repo.addLike(postId, userId);

  const likesCount = await repo.countPostLikes(postId);
  const liked = !existed;

  if (liked && Number(post.user_id) !== Number(userId)) {
    const actor = await repo.findUserPublicProfile(userId);
    await createNotification({
      userId: Number(post.user_id),
      type: "social.post.like",
      title: "إعجاب جديد على منشورك",
      body: `${actor?.full_name || "مستخدم"} أعجب بمنشورك`,
      payload: {
        postId: Number(postId),
        actorUserId: Number(userId),
        target: "social_feed",
      },
    });
  }

  return { liked, likesCount };
}

export async function listComments({ postId, userId, query }) {
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true || post.moderation_status !== "approved") {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const owner = await repo.findUserSocialProfile(post.user_id);
  if (owner && !canViewPosts({ viewerUserId: userId, owner })) {
    throw new AppError("PROFILE_POSTS_PRIVATE", { status: 403 });
  }

  const rows = await repo.listPostComments({
    postId,
    limit: query.limit,
    beforeId: query.beforeId,
  });
  return {
    comments: rows.map(mapCommentRow),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function addComment({ postId, userId, body }) {
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true || post.moderation_status !== "approved") {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const owner = await repo.findUserSocialProfile(post.user_id);
  if (owner && !canViewPosts({ viewerUserId: userId, owner })) {
    throw new AppError("PROFILE_POSTS_PRIVATE", { status: 403 });
  }

  assertContentAllowed(body);
  const inserted = await repo.insertComment({ postId, userId, body });
  const commentsCount = await repo.countPostComments(postId);
  const actor = await repo.findUserPublicProfile(userId);

  if (Number(post.user_id) !== Number(userId)) {
    await createNotification({
      userId: Number(post.user_id),
      type: "social.post.comment",
      title: "تعليق جديد على منشورك",
      body: `${actor?.full_name || "مستخدم"} علّق على منشورك`,
      payload: {
        postId: Number(postId),
        commentId: Number(inserted.id),
        actorUserId: Number(userId),
        target: "social_feed",
      },
    });
  }

  return {
    comment: mapCommentRow({
      ...inserted,
      user_full_name: actor?.full_name || "",
      user_image_url: actor?.image_url || null,
      user_phone: actor?.phone || "",
      user_role: actor?.role || "user",
    }),
    commentsCount,
  };
}

export async function listMerchantOptions(query) {
  const rows = await repo.listMerchantOptions({
    search: query.search,
    limit: query.limit,
  });
  return {
    merchants: rows.map((row) => ({
      id: Number(row.id),
      name: row.name || "",
      type: row.type || "market",
      phone: row.phone || "",
      imageUrl: row.image_url || null,
    })),
  };
}

export async function createThread({ userId, otherUserId }) {
  if (Number(userId) === Number(otherUserId)) {
    throw new AppError("THREAD_SELF_NOT_ALLOWED", { status: 400 });
  }

  const other = await repo.findUserPublicProfile(otherUserId);
  if (!other) throw new AppError("USER_NOT_FOUND", { status: 404 });

  const baseThread = await repo.createOrGetThread({
    userAId: userId,
    userBId: otherUserId,
  });
  const thread = await repo.getThreadForUser({
    threadId: baseThread.id,
    userId,
  });
  if (!thread) throw new AppError("THREAD_CREATE_FAILED", { status: 500 });

  return mapThreadRow(thread, userId);
}

export async function listThreads(userId) {
  const rows = await repo.listThreadsForUser({ userId, limit: 80 });
  return { threads: rows.map((row) => mapThreadRow(row, userId)) };
}

export async function listMessages({ userId, threadId, query }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });

  const rows = await repo.listMessagesForThread({
    threadId,
    limit: query.limit,
    beforeId: query.beforeId,
  });
  const messages = rows.map((row) => mapMessageRow(row, userId)).reverse();

  return {
    thread: mapThreadRow(thread, userId),
    messages,
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function sendMessage({ userId, threadId, body }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });

  assertContentAllowed(body);
  const inserted = await repo.insertThreadMessage({
    threadId,
    senderUserId: userId,
    body,
  });
  await repo.touchThreadLastMessage(threadId);

  const sender = await repo.findUserPublicProfile(userId);
  const mapped = mapMessageRow(
    {
      ...inserted,
      sender_full_name: sender?.full_name || "",
      sender_image_url: sender?.image_url || null,
      sender_phone: sender?.phone || "",
      sender_role: sender?.role || "user",
    },
    userId
  );

  const peerUserId = Number(thread.peer_user_id);
  emitToUser(Number(userId), "social_chat_message", {
    threadId: Number(threadId),
    message: mapped,
  });
  emitToUser(peerUserId, "social_chat_message", {
    threadId: Number(threadId),
    message: mapped,
  });

  if (peerUserId !== Number(userId)) {
    await createNotification({
      userId: peerUserId,
      type: "social.chat.message",
      title: `رسالة جديدة من ${sender?.full_name || "مستخدم"}`,
      body: compactMessagePreview(body),
      payload: {
        threadId: Number(threadId),
        senderUserId: Number(userId),
        target: "social_chat",
      },
    });
  }

  return {
    message: mapped,
    threadId: Number(threadId),
  };
}
