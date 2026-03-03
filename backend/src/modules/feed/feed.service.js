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
      phone: row.user_phone || "",
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
      phone: row.user_phone || "",
      role: row.user_role || "user",
    },
  };
}

function mapStoryRow(row, viewerUserId) {
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    caption: row.caption || "",
    mediaUrl: row.media_url || null,
    mediaKind: row.media_kind || null,
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
      phone: row.user_phone || "",
    },
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

  const [audienceUserIds, actor] = await Promise.all([
    repo.listStoryAudienceUserIds({
      excludeUserId: userId,
      limit: 1500,
    }),
    repo.findUserPublicProfile(userId),
  ]);

  dispatchStoryNotifications({
    audienceUserIds,
    actor,
    story: mapped,
  });

  return mapped;
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

export async function listComments(postId, query) {
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true || post.moderation_status !== "approved") {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
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
