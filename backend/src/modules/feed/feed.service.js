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
    reactions: {
      counts: row.reaction_counts || {},
      totalCount: Number(row.reaction_total_count || 0),
      myReaction: row.my_reaction || null,
    },
    sender: {
      id: Number(row.sender_user_id),
      fullName: row.sender_full_name || "",
      imageUrl: row.sender_image_url || null,
      phone: row.sender_phone || "",
      role: row.sender_role || "user",
    },
  };
}

function mapRelationRow(row, viewerUserId, otherUserId) {
  const fallbackOtherId = Number(otherUserId || 0);
  if (!row) {
    return {
      state: "none",
      rawStatus: null,
      requestDirection: null,
      canChat: false,
      canCall: false,
      canSendRequest: fallbackOtherId > 0 && fallbackOtherId !== Number(viewerUserId),
      blockedByMe: false,
      blockedByOther: false,
      otherUserId: fallbackOtherId > 0 ? fallbackOtherId : null,
      initiatorUserId: null,
      requestedAt: null,
      respondedAt: null,
      updatedAt: null,
    };
  }

  const viewer = Number(viewerUserId);
  const relationStatus = String(row.status || "").trim().toLowerCase();
  const initiatorUserId = Number(row.initiator_user_id || 0);
  const userA = Number(row.user_a_id || 0);
  const userB = Number(row.user_b_id || 0);
  const resolvedOtherId = userA === viewer ? userB : userA;
  const outgoingPending = relationStatus === "pending" && initiatorUserId === viewer;
  const incomingPending = relationStatus === "pending" && initiatorUserId !== viewer;
  const accepted = relationStatus === "accepted";
  const blockedByMe = relationStatus === "blocked" && initiatorUserId === viewer;
  const blockedByOther = relationStatus === "blocked" && initiatorUserId !== viewer;

  return {
    state:
      accepted
        ? "accepted"
        : outgoingPending
        ? "pending_outgoing"
        : incomingPending
        ? "pending_incoming"
        : blockedByMe
        ? "blocked_by_me"
        : blockedByOther
        ? "blocked_by_other"
        : "none",
    rawStatus: relationStatus || null,
    requestDirection: outgoingPending
      ? "outgoing"
      : incomingPending
      ? "incoming"
      : null,
    canChat: accepted,
    canCall: accepted,
    canSendRequest:
      !accepted &&
      !outgoingPending &&
      !incomingPending &&
      !blockedByMe &&
      !blockedByOther &&
      resolvedOtherId !== viewer,
    blockedByMe,
    blockedByOther,
    otherUserId: resolvedOtherId > 0 ? resolvedOtherId : null,
    initiatorUserId: initiatorUserId > 0 ? initiatorUserId : null,
    requestedAt: row.requested_at || null,
    respondedAt: row.responded_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapCallSession(session, viewerUserId) {
  if (!session) return null;
  const viewer = Number(viewerUserId || 0);
  return {
    id: Number(session.id),
    threadId: Number(session.threadId),
    callerUserId: Number(session.callerUserId),
    calleeUserId: Number(session.calleeUserId),
    status: session.status || "ringing",
    startedAt: session.startedAt || null,
    answeredAt: session.answeredAt || null,
    endedAt: session.endedAt || null,
    endReason: session.endReason || null,
    isCaller: Number(session.callerUserId) === viewer,
    isCallee: Number(session.calleeUserId) === viewer,
  };
}

function mapCallSignal(signal) {
  if (!signal) return null;
  return {
    id: Number(signal.id),
    sessionId: Number(signal.sessionId),
    threadId: Number(signal.threadId),
    senderUserId: Number(signal.senderUserId),
    signalType: signal.signalType || "ice",
    signalPayload: signal.signalPayload || {},
    createdAt: signal.createdAt || null,
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

async function ensureUsersCanConnect({ userId, otherUserId }) {
  if (Number(userId) === Number(otherUserId)) {
    throw new AppError("THREAD_SELF_NOT_ALLOWED", { status: 400 });
  }
  const relation = await repo.getUserRelation({ userId, otherUserId });
  const mapped = mapRelationRow(relation, userId, otherUserId);
  if (mapped.blockedByMe || mapped.blockedByOther) {
    throw new AppError("RELATION_BLOCKED", {
      status: 403,
      details: { relation: mapped },
    });
  }
  if (mapped.state !== "accepted") {
    throw new AppError("RELATION_REQUIRED", {
      status: 403,
      details: { relation: mapped },
    });
  }
  return mapped;
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
  const [stats, relationRow, relationStats] = await Promise.all([
    repo.getUserSocialStats(userId),
    Number(viewerUserId) === Number(userId)
      ? Promise.resolve(null)
      : repo.getUserRelation({ userId: viewerUserId, otherUserId: userId }),
    repo.getUserRelationStats(userId),
  ]);
  const relation = mapRelationRow(relationRow, viewerUserId, userId);
  return {
    profile: {
      id: Number(profile.id),
      fullName: profile.full_name || "",
      imageUrl: profile.image_url || null,
      bio: profile.social_bio || "",
      age:
        profile.social_age == null || !Number.isFinite(Number(profile.social_age))
          ? null
          : Number(profile.social_age),
      phone: phoneVisible ? profile.phone || "" : "",
      role: profile.role || "user",
      joinedAt: profile.created_at || null,
      isMe,
      privacy: {
        showPhone: profile.social_show_phone === true,
        postsPublic: profile.social_posts_public === true,
        storiesPublic: profile.social_stories_public === true,
      },
      relation,
      stats: {
        totalPosts: Number(stats.total_posts || 0),
        imagePosts: Number(stats.image_posts || 0),
        videoPosts: Number(stats.video_posts || 0),
        reviewPosts: Number(stats.review_posts || 0),
        likesReceived: Number(stats.likes_received || 0),
        commentsReceived: Number(stats.comments_received || 0),
        activeStories: Number(stats.active_stories || 0),
        highlightsCount: Number(stats.highlights_count || 0),
        connectionsCount: Number(relationStats.accepted_count || 0),
        friendsCount: Number(relationStats.accepted_count || 0),
        followersCount: Number(relationStats.followers_count || 0),
        followingCount: Number(relationStats.following_count || 0),
        pendingIncomingCount: Number(relationStats.pending_incoming_count || 0),
        pendingOutgoingCount: Number(relationStats.pending_outgoing_count || 0),
      },
    },
  };
}

export async function updateMyProfile(userId, dto) {
  if (
    dto.fullName === undefined &&
    dto.bio === undefined &&
    dto.age === undefined &&
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
    age: dto.age,
    imageUrl: dto.imageUrl,
    showPhone: dto.showPhone,
    postsPublic: dto.postsPublic,
    storiesPublic: dto.storiesPublic,
  });
  if (!updated) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  const [stats, relationStats] = await Promise.all([
    repo.getUserSocialStats(userId),
    repo.getUserRelationStats(userId),
  ]);

  return {
    profile: {
      id: Number(updated.id),
      fullName: updated.full_name || "",
      imageUrl: updated.image_url || null,
      bio: updated.social_bio || "",
      age:
        updated.social_age == null || !Number.isFinite(Number(updated.social_age))
          ? null
          : Number(updated.social_age),
      phone: updated.phone || "",
      role: updated.role || "user",
      joinedAt: updated.created_at || null,
      isMe: true,
      privacy: {
        showPhone: updated.social_show_phone === true,
        postsPublic: updated.social_posts_public === true,
        storiesPublic: updated.social_stories_public === true,
      },
      relation: mapRelationRow(null, userId, userId),
      stats: {
        totalPosts: Number(stats.total_posts || 0),
        imagePosts: Number(stats.image_posts || 0),
        videoPosts: Number(stats.video_posts || 0),
        reviewPosts: Number(stats.review_posts || 0),
        likesReceived: Number(stats.likes_received || 0),
        commentsReceived: Number(stats.comments_received || 0),
        activeStories: Number(stats.active_stories || 0),
        highlightsCount: Number(stats.highlights_count || 0),
        connectionsCount: Number(relationStats.accepted_count || 0),
        friendsCount: Number(relationStats.accepted_count || 0),
        followersCount: Number(relationStats.followers_count || 0),
        followingCount: Number(relationStats.following_count || 0),
        pendingIncomingCount: Number(relationStats.pending_incoming_count || 0),
        pendingOutgoingCount: Number(relationStats.pending_outgoing_count || 0),
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
  const other = await repo.findUserPublicProfile(otherUserId);
  if (!other) throw new AppError("USER_NOT_FOUND", { status: 404 });
  await ensureUsersCanConnect({ userId, otherUserId });

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
  await ensureUsersCanConnect({
    userId,
    otherUserId: Number(thread.peer_user_id),
  });

  const rows = await repo.listMessagesForThread({
    threadId,
    limit: query.limit,
    beforeId: query.beforeId,
  });
  const messageIds = rows
    .map((row) => Number(row.id))
    .filter((v) => Number.isFinite(v) && v > 0);
  const reactionsByMessage = await repo.listMessageReactionsForMessages({
    messageIds,
    userId,
  });
  const messages = rows
    .map((row) => ({
      ...row,
      reaction_counts: reactionsByMessage[Number(row.id)]?.counts || {},
      reaction_total_count: Number(reactionsByMessage[Number(row.id)]?.totalCount || 0),
      my_reaction: reactionsByMessage[Number(row.id)]?.myReaction || null,
    }))
    .map((row) => mapMessageRow(row, userId))
    .reverse();

  return {
    thread: mapThreadRow(thread, userId),
    messages,
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function sendMessage({ userId, threadId, body }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  await ensureUsersCanConnect({
    userId,
    otherUserId: Number(thread.peer_user_id),
  });

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

export async function toggleMessageReaction({ userId, threadId, messageId, reaction }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  await ensureUsersCanConnect({
    userId,
    otherUserId: Number(thread.peer_user_id),
  });

  const message = await repo.getThreadMessageById({ threadId, messageId });
  if (!message) throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });

  const toggled = await repo.toggleMessageReaction({
    messageId,
    userId,
    reaction,
  });
  const summary = await repo.listMessageReactionsForMessages({
    messageIds: [messageId],
    userId,
  });
  const details = summary[Number(messageId)] || {
    counts: {},
    totalCount: 0,
    myReaction: null,
  };

  const peerUserId = Number(thread.peer_user_id);
  const payload = {
    threadId: Number(threadId),
    messageId: Number(messageId),
    reaction: toggled.reaction,
    active: toggled.active === true,
    reactions: details,
  };
  emitToUser(Number(userId), "social_chat_message", payload);
  emitToUser(peerUserId, "social_chat_message", payload);

  return {
    messageId: Number(messageId),
    reaction: toggled.reaction,
    active: toggled.active === true,
    reactions: details,
  };
}

export async function getUserRelationState({ userId, otherUserId }) {
  const other = await repo.findUserPublicProfile(otherUserId);
  if (!other) throw new AppError("USER_NOT_FOUND", { status: 404 });
  const relation = await repo.getUserRelation({ userId, otherUserId });
  return {
    relation: mapRelationRow(relation, userId, otherUserId),
  };
}

export async function sendUserRelationRequest({ userId, otherUserId }) {
  if (Number(userId) === Number(otherUserId)) {
    throw new AppError("RELATION_SELF_NOT_ALLOWED", { status: 400 });
  }

  const [other, actor] = await Promise.all([
    repo.findUserPublicProfile(otherUserId),
    repo.findUserPublicProfile(userId),
  ]);
  if (!other) throw new AppError("USER_NOT_FOUND", { status: 404 });

  const current = await repo.getUserRelation({ userId, otherUserId });
  const currentMapped = mapRelationRow(current, userId, otherUserId);

  if (currentMapped.state === "accepted") {
    return { relation: currentMapped };
  }

  if (current?.status === "blocked") {
    throw new AppError("RELATION_BLOCKED", { status: 403 });
  }

  let updated = null;
  let acceptedByReply = false;
  if (currentMapped.state === "pending_incoming") {
    updated = await repo.updateRelationStatus({
      userId,
      otherUserId,
      status: "accepted",
    });
    acceptedByReply = true;
  } else {
    updated = await repo.upsertPendingRelation({
      fromUserId: userId,
      toUserId: otherUserId,
    });
  }

  const mapped = mapRelationRow(updated, userId, otherUserId);

  if (mapped.state === "pending_outgoing") {
    await createNotification({
      userId: Number(otherUserId),
      type: "social.relation.request",
      title: "طلب متابعة جديد",
      body: `${actor?.full_name || "مستخدم"} أرسل لك طلب متابعة.`,
      payload: {
        actorUserId: Number(userId),
        target: "social_feed",
      },
    });
  } else if (acceptedByReply) {
    await createNotification({
      userId: Number(otherUserId),
      type: "social.relation.accepted",
      title: "تم قبول طلب المتابعة",
      body: `${actor?.full_name || "مستخدم"} قبل طلب المتابعة.`,
      payload: {
        actorUserId: Number(userId),
        target: "social_feed",
      },
    });
  }

  emitToUser(Number(userId), "social_relation_update", { relation: mapped });
  emitToUser(Number(otherUserId), "social_relation_update", {
    relation: mapRelationRow(updated, otherUserId, userId),
  });
  return { relation: mapped };
}

export async function acceptUserRelationRequest({ userId, otherUserId }) {
  const current = await repo.getUserRelation({ userId, otherUserId });
  if (!current) throw new AppError("RELATION_REQUEST_NOT_FOUND", { status: 404 });

  const mapped = mapRelationRow(current, userId, otherUserId);
  if (mapped.state !== "pending_incoming") {
    throw new AppError("RELATION_ACCEPT_NOT_ALLOWED", { status: 409 });
  }

  const updated = await repo.updateRelationStatus({
    userId,
    otherUserId,
    status: "accepted",
  });
  const next = mapRelationRow(updated, userId, otherUserId);

  await createNotification({
    userId: Number(otherUserId),
    type: "social.relation.accepted",
    title: "تم قبول طلب المتابعة",
    body: "تم قبول طلب المتابعة ويمكنكم الآن المراسلة والاتصال.",
    payload: {
      actorUserId: Number(userId),
      target: "social_feed",
    },
  });

  emitToUser(Number(userId), "social_relation_update", { relation: next });
  emitToUser(Number(otherUserId), "social_relation_update", {
    relation: mapRelationRow(updated, otherUserId, userId),
  });

  return { relation: next };
}

export async function rejectUserRelationRequest({ userId, otherUserId }) {
  const current = await repo.getUserRelation({ userId, otherUserId });
  if (!current) throw new AppError("RELATION_REQUEST_NOT_FOUND", { status: 404 });

  const mapped = mapRelationRow(current, userId, otherUserId);
  if (mapped.state !== "pending_incoming") {
    throw new AppError("RELATION_REJECT_NOT_ALLOWED", { status: 409 });
  }

  const updated = await repo.updateRelationStatus({
    userId,
    otherUserId,
    status: "rejected",
  });
  const next = mapRelationRow(updated, userId, otherUserId);

  emitToUser(Number(userId), "social_relation_update", { relation: next });
  emitToUser(Number(otherUserId), "social_relation_update", {
    relation: mapRelationRow(updated, otherUserId, userId),
  });

  return { relation: next };
}

export async function cancelUserRelationRequest({ userId, otherUserId }) {
  const current = await repo.getUserRelation({ userId, otherUserId });
  if (!current) throw new AppError("RELATION_REQUEST_NOT_FOUND", { status: 404 });

  const mapped = mapRelationRow(current, userId, otherUserId);
  if (mapped.state !== "pending_outgoing") {
    throw new AppError("RELATION_CANCEL_NOT_ALLOWED", { status: 409 });
  }

  const updated = await repo.updateRelationStatus({
    userId,
    otherUserId,
    status: "cancelled",
  });
  const next = mapRelationRow(updated, userId, otherUserId);

  emitToUser(Number(userId), "social_relation_update", { relation: next });
  emitToUser(Number(otherUserId), "social_relation_update", {
    relation: mapRelationRow(updated, otherUserId, userId),
  });

  return { relation: next };
}

export async function removeUserRelation({ userId, otherUserId }) {
  const current = await repo.getUserRelation({ userId, otherUserId });
  if (!current) return { relation: mapRelationRow(null, userId, otherUserId) };

  await repo.deleteRelation({ userId, otherUserId });
  const emptyRelation = mapRelationRow(null, userId, otherUserId);

  emitToUser(Number(userId), "social_relation_update", { relation: emptyRelation });
  emitToUser(Number(otherUserId), "social_relation_update", {
    relation: mapRelationRow(null, otherUserId, userId),
  });

  return { relation: emptyRelation };
}

export async function blockUserRelation({ userId, otherUserId }) {
  if (Number(userId) === Number(otherUserId)) {
    throw new AppError("RELATION_SELF_NOT_ALLOWED", { status: 400 });
  }
  const other = await repo.findUserPublicProfile(otherUserId);
  if (!other) throw new AppError("USER_NOT_FOUND", { status: 404 });

  let current = await repo.getUserRelation({ userId, otherUserId });
  if (!current) {
    await repo.upsertPendingRelation({
      fromUserId: userId,
      toUserId: otherUserId,
    });
  }
  const updated = await repo.updateRelationStatus({
    userId,
    otherUserId,
    status: "blocked",
    initiatorUserId: userId,
  });
  const next = mapRelationRow(updated, userId, otherUserId);

  emitToUser(Number(userId), "social_relation_update", { relation: next });
  emitToUser(Number(otherUserId), "social_relation_update", {
    relation: mapRelationRow(updated, otherUserId, userId),
  });

  return { relation: next };
}

export async function unblockUserRelation({ userId, otherUserId }) {
  const current = await repo.getUserRelation({ userId, otherUserId });
  if (!current) {
    return { relation: mapRelationRow(null, userId, otherUserId) };
  }
  if (String(current.status || "").trim().toLowerCase() !== "blocked") {
    throw new AppError("RELATION_UNBLOCK_NOT_ALLOWED", { status: 409 });
  }
  if (Number(current.initiator_user_id) !== Number(userId)) {
    throw new AppError("RELATION_UNBLOCK_NOT_ALLOWED", { status: 403 });
  }

  await repo.deleteRelation({ userId, otherUserId });
  const next = mapRelationRow(null, userId, otherUserId);

  emitToUser(Number(userId), "social_relation_update", { relation: next });
  emitToUser(Number(otherUserId), "social_relation_update", {
    relation: mapRelationRow(null, otherUserId, userId),
  });

  return { relation: next };
}

export async function listIncomingRelationRequests({ userId, query }) {
  const rows = await repo.listIncomingRelationRequests({
    userId,
    limit: query.limit,
  });
  return {
    requests: rows.map((row) => ({
      relation: mapRelationRow(row, userId),
      user: {
        id: Number(row.requester_user_id),
        fullName: row.requester_full_name || "",
        phone: row.requester_phone || "",
        role: row.requester_role || "user",
        imageUrl: row.requester_image_url || null,
      },
      requestedAt: row.requested_at || null,
    })),
  };
}

export async function listOutgoingRelationRequests({ userId, query }) {
  const rows = await repo.listOutgoingRelationRequests({
    userId,
    limit: query.limit,
  });
  return {
    requests: rows.map((row) => ({
      relation: mapRelationRow(row, userId),
      user: {
        id: Number(row.target_user_id),
        fullName: row.target_full_name || "",
        phone: row.target_phone || "",
        role: row.target_role || "user",
        imageUrl: row.target_image_url || null,
      },
      requestedAt: row.requested_at || null,
    })),
  };
}

export async function getThreadCallState({ userId, threadId, signalLimit }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });

  const state = await repo.getThreadCallState(threadId, { signalLimit });
  return {
    thread: mapThreadRow(thread, userId),
    session: mapCallSession(state.session, userId),
    signals: [...(state.signals || [])].reverse().map(mapCallSignal),
  };
}

export async function startThreadCall({ userId, threadId }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });

  const peerUserId = Number(thread.peer_user_id);
  if (!Number.isFinite(peerUserId) || peerUserId <= 0 || peerUserId === Number(userId)) {
    throw new AppError("SOCIAL_CALL_PEER_NOT_AVAILABLE", { status: 409 });
  }

  const session = await repo.createThreadCallSession({
    threadId,
    callerUserId: userId,
    calleeUserId: peerUserId,
  });
  const signal = await repo.insertThreadCallSignal({
    sessionId: session.id,
    threadId,
    senderUserId: userId,
    signalType: "ringing",
    signalPayload: {
      callerUserId: Number(userId),
      calleeUserId: peerUserId,
    },
  });

  const mappedSession = mapCallSession(session, userId);
  const mappedSignal = mapCallSignal(signal);
  const incomingPayload = {
    eventType: "incoming_call",
    threadId: Number(threadId),
    session: mapCallSession(session, peerUserId),
    signal: mappedSignal,
  };

  emitToUser(peerUserId, "social_call_update", incomingPayload);
  emitToUser(Number(userId), "social_call_update", {
    eventType: "outgoing_call",
    threadId: Number(threadId),
    session: mappedSession,
    signal: mappedSignal,
  });

  const caller = await repo.findUserPublicProfile(userId);
  await createNotification({
    userId: peerUserId,
    type: "social.call.incoming",
    title: `مكالمة واردة من ${caller?.full_name || "مستخدم"}`,
    body: "اضغط للرد على المكالمة داخل التطبيق.",
    payload: {
      threadId: Number(threadId),
      sessionId: Number(session.id),
      senderUserId: Number(userId),
      target: "social_call",
    },
  });

  return {
    session: mappedSession,
    signal: mappedSignal,
  };
}

export async function sendThreadCallSignal({ userId, threadId, dto }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });

  let session = dto.sessionId
    ? await repo.getThreadCallSessionById(dto.sessionId)
    : await repo.getActiveThreadCallSession(threadId);
  if (!session) {
    throw new AppError("SOCIAL_CALL_SESSION_NOT_FOUND", { status: 404 });
  }

  if (Number(session.threadId) !== Number(threadId)) {
    throw new AppError("SOCIAL_CALL_SESSION_NOT_FOUND", { status: 404 });
  }

  const participantIds = new Set([
    Number(session.callerUserId),
    Number(session.calleeUserId),
  ]);
  if (!participantIds.has(Number(userId))) {
    throw new AppError("SOCIAL_CALL_FORBIDDEN", { status: 403 });
  }

  const signal = await repo.insertThreadCallSignal({
    sessionId: session.id,
    threadId,
    senderUserId: userId,
    signalType: dto.signalType,
    signalPayload: dto.signalPayload || null,
  });

  if (dto.signalType === "accept" || dto.signalType === "answer") {
    const answered = await repo.markThreadCallAnswered({ sessionId: session.id });
    if (answered) session = answered;
  } else if (dto.signalType === "decline") {
    const ended = await repo.endThreadCallSession({
      sessionId: session.id,
      status: "declined",
      endReason: "declined_by_user",
    });
    if (ended) session = ended;
  } else if (dto.signalType === "hangup") {
    const ended = await repo.endThreadCallSession({
      sessionId: session.id,
      status: "ended",
      endReason: "hangup",
    });
    if (ended) session = ended;
  }

  const mappedSession = mapCallSession(session, userId);
  const mappedSignal = mapCallSignal(signal);
  const updatePayload = {
    eventType: "call_signal",
    threadId: Number(threadId),
    session: mappedSession,
    signal: mappedSignal,
  };

  emitToUser(Number(session.callerUserId), "social_call_update", updatePayload);
  emitToUser(Number(session.calleeUserId), "social_call_update", updatePayload);

  return {
    session: mappedSession,
    signal: mappedSignal,
  };
}

export async function endThreadCall({ userId, threadId, dto }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });

  const active = await repo.getActiveThreadCallSession(threadId);
  if (!active) {
    return { session: null, signal: null };
  }

  const participantIds = new Set([
    Number(active.callerUserId),
    Number(active.calleeUserId),
  ]);
  if (!participantIds.has(Number(userId))) {
    throw new AppError("SOCIAL_CALL_FORBIDDEN", { status: 403 });
  }

  const ended = await repo.endThreadCallSession({
    sessionId: active.id,
    status: dto.status,
    endReason: dto.reason || "hangup",
  });
  const signalType = dto.status === "declined" ? "decline" : "hangup";
  const signal = await repo.insertThreadCallSignal({
    sessionId: active.id,
    threadId,
    senderUserId: userId,
    signalType,
    signalPayload: {
      reason: dto.reason || null,
      status: dto.status,
    },
  });

  const payload = {
    eventType: "call_ended",
    threadId: Number(threadId),
    session: mapCallSession(ended || active, userId),
    signal: mapCallSignal(signal),
  };
  emitToUser(Number(active.callerUserId), "social_call_update", payload);
  emitToUser(Number(active.calleeUserId), "social_call_update", payload);

  return {
    session: mapCallSession(ended || active, userId),
    signal: mapCallSignal(signal),
  };
}
