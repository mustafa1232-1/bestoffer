import { AppError } from "../../shared/utils/errors.js";
import { emitRealtimeToUser as emitToUser } from "../../shared/realtime/realtime-gateway.js";
import {
  invalidateSessionAccessCacheForUser,
  markUserSessionsRevokedAfter,
} from "../../shared/middleware/access-auth.js";
import {
  deriveBasmayaHierarchy,
  normalizeCommunityScope,
  validateBasmayaAddress,
} from "../../shared/utils/basmaya-address.js";
import { revokeAllUserSessions } from "../auth/auth.repo.js";
import { translateSocialText } from "../assistant/assistant.ai.service.js";
import {
  createManyNotifications,
  createNotification,
} from "../notifications/notifications.repo.js";
import { hasPaidUpgrade } from "../paid-upgrades/paid-upgrades.repo.js";
import * as carsRepo from "../cars/cars.repo.js";
import * as realEstateRepo from "../real-estate/real-estate.repo.js";
import * as servicesRepo from "../services/services.repo.js";
import * as analyticsRepo from "./feed.analytics.repo.js";
import * as discoveryRepo from "./feed.discovery.repo.js";
import * as discoveryService from "./feed.discovery.service.js";
import * as insightsService from "./feed.insights.service.js";
import * as mediaService from "./feed.media.service.js";
import { mapSocialPostProductRow } from "./feed.product.mappers.js";
import * as recommendationsService from "./feed.recommendations.service.js";
import * as reelsService from "./feed.reels.service.js";
import * as repo from "./feed.repo.js";
import * as savedService from "./feed.saved.service.js";
import * as searchService from "./feed.search.service.js";
import * as tagsService from "./feed.tags.service.js";
import { buildPreferenceWeightMap, rankFeedRows } from "./feed.ranking.service.js";

/**
 * Purpose:
 * طبقة الخدمة المركزية لميزات المجتمع والمراسلة اللحظية. تجمع منطق
 * المحادثات، الرسائل، الحضور، typing indicators، read receipts، وإدارة
 * مكالمات المجتمع القصيرة.
 *
 * Used by:
 * - `feed.controller.js`
 * - SSE/notification flows
 * - واجهات community/chat/social call في Flutter
 *
 * Critical notes:
 * - هذا الملف يجمع business rules وrealtime side effects معاً، لذلك أي
 *   تعديل يجب أن يراجع ترتيب الكتابة في DB ثم البث اللحظي.
 *
 * Maintenance notes:
 * - عند ضياع رسالة أو تأخر read receipt افحص أولاً repo write ثم
 *   `feed.events.js`/SSE ثم controller الذي استدعى الدالة.
 */
const SOCIAL_CALL_RING_TIMEOUT_SECONDS = 35;
const SOCIAL_CHAT_EDIT_DELETE_WINDOW_MS = 5 * 60 * 1000;
const SOCIAL_PRESENCE_ONLINE_WINDOW_MS = 90 * 1000;
let socialCallLifecycleWorker = null;
let socialCallLifecycleRunning = false;
let socialScheduledMessageWorker = null;
let socialScheduledMessageRunning = false;
const FEED_TRANSIENT_CACHE_TTL_MS = 10000;
const transientFeedCache = new Map();
const viewerScopeCache = new Map();

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
  const mapped = mapSocialPostProductRow(row);
  return {
    ...mapped,
    author: {
      ...mapped.author,
      phone: "",
    },
  };
}

function mapPostMediaItemRow(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    sortOrder: Number(row.sort_order || 0),
    mediaUrl: row.asset_normalized_url || row.media_url || null,
    mediaKind: row.media_kind || null,
    asset:
      row.media_asset_id || row.asset_poster_url || row.asset_normalized_url
        ? {
            id: row.media_asset_id == null ? null : Number(row.media_asset_id),
            normalizedUrl: row.asset_normalized_url || row.media_url || null,
            posterUrl: row.asset_poster_url || null,
            durationMs:
              row.asset_duration_ms == null ? null : Number(row.asset_duration_ms),
            processingStatus: row.asset_processing_status || null,
          }
        : null,
  };
}

async function attachPostMediaRows(rows) {
  if (!Array.isArray(rows) || rows.length <= 0) return rows;
  const postIds = [
    ...new Set(
      rows
        .map((row) => Number(row?.id))
        .filter((value) => Number.isFinite(value) && value > 0)
    ),
  ];
  if (postIds.length <= 0) return rows;
  const mediaRows = await repo.listPostMediaItemsByPostIds(postIds);
  const mediaByPostId = new Map();
  for (const row of mediaRows) {
    const postId = Number(row.post_id);
    const mapped = mapPostMediaItemRow(row);
    if (!mapped || postId <= 0) continue;
    const current = mediaByPostId.get(postId) || [];
    current.push(mapped);
    mediaByPostId.set(postId, current);
  }
  return rows.map((row) => ({
    ...row,
    media_gallery: mediaByPostId.get(Number(row.id)) || [],
  }));
}

async function attachPostMediaRow(row) {
  if (!row) return row;
  const enriched = await attachPostMediaRows([row]);
  return enriched[0] || row;
}

function buildTransientFeedCacheKey(prefix, viewerUserId, query = {}) {
  const parts = Object.entries(query || {})
    .filter(([, value]) => value !== undefined)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${JSON.stringify(value)}`);
  return `${prefix}:${Number(viewerUserId)}:${parts.join("&")}`;
}

function readTransientFeedCache(key) {
  const cached = transientFeedCache.get(key);
  if (!cached) return null;
  if (cached.expiresAt <= Date.now()) {
    transientFeedCache.delete(key);
    return null;
  }
  return cached.value;
}

function writeTransientFeedCache(key, value) {
  transientFeedCache.set(key, {
    value,
    expiresAt: Date.now() + FEED_TRANSIENT_CACHE_TTL_MS,
  });
  return value;
}

function readViewerScopeCache(viewerUserId) {
  const cached = viewerScopeCache.get(Number(viewerUserId));
  if (!cached) return null;
  if (cached.expiresAt <= Date.now()) {
    viewerScopeCache.delete(Number(viewerUserId));
    return null;
  }
  return cached.value;
}

function writeViewerScopeCache(viewerUserId, value) {
  viewerScopeCache.set(Number(viewerUserId), {
    value,
    expiresAt: Date.now() + FEED_TRANSIENT_CACHE_TTL_MS,
  });
  return value;
}

function mapCommentRow(row) {
  const isDeleted = row.is_deleted === true;
  return {
    id: Number(row.id),
    postId: Number(row.post_id),
    userId: Number(row.user_id),
    parentCommentId:
      row.parent_comment_id == null ? null : Number(row.parent_comment_id),
    body: isDeleted ? "تم حذف التعليق" : row.body || "",
    isDeleted,
    editedAt: row.edited_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    likesCount: Number(row.likes_count || 0),
    isLiked: row.is_liked === true,
    author: {
      id: Number(row.user_id),
      username: row.user_username || null,
      fullName: row.user_full_name || "",
      imageUrl: row.user_image_url || null,
      phone: "",
      role: row.user_role || "user",
      isPremiumCreator: row.user_has_premium === true,
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
    archivedAt: row.archived_by_owner_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    expiresAt: row.expires_at,
    likesCount: Number(row.likes_count || 0),
    commentsCount: Number(row.comments_count || 0),
    isLiked: row.is_liked === true,
    isViewed: row.is_viewed === true,
    isMine: Number(row.user_id) === Number(viewerUserId),
    moderationStatus: row.moderation_status || null,
    moderationNote: row.moderation_note || null,
    moderationRequestedAt: row.moderation_requested_at || null,
    author: {
      id: Number(row.user_id),
      username: row.user_username || null,
      fullName: row.user_full_name || "",
      imageUrl: row.user_image_url || null,
      role: row.user_role || "user",
      phone: "",
    },
  };
}

function normalizeThreadKind(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized === "business") return "business";
  if (normalized === "group") return "group";
  return "private";
}

function normalizeThreadContextType(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized === "car_listing") return "car_listing";
  if (normalized === "real_estate_listing") return "real_estate_listing";
  if (normalized === "service_offering") return "service_offering";
  if (normalized === "service_provider") return "service_provider";
  if (normalized === "service_request") return "service_request";
  return "none";
}

function parseJsonObject(value) {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value;
  }
  if (typeof value !== "string" || !value.trim()) return {};
  try {
    const parsed = JSON.parse(value);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed;
    }
  } catch {
    // ignore invalid JSON payloads
  }
  return {};
}

function canExposePresenceField(visibility, { relationStatus, threadKind }) {
  const normalized = String(visibility || "").trim().toLowerCase() || "connections";
  if (normalized === "nobody") return false;
  if (normalized === "everyone") return true;
  return relationStatus === "accepted" || normalizeThreadKind(threadKind) === "business";
}

function buildThreadPresence(row) {
  const relationStatus = String(row?.relation_status || "").trim().toLowerCase();
  const threadKind = normalizeThreadKind(row?.thread_kind);
  if (threadKind === "group") {
    return {
      isOnline: false,
      lastSeenAt: null,
      canSeeOnlineStatus: false,
      canSeeLastSeen: false,
      canSeeReadReceipts: false,
      canSeeTypingIndicators: true,
    };
  }
  const canSeeOnlineStatus = canExposePresenceField(row?.peer_online_visibility, {
    relationStatus,
    threadKind,
  });
  const canSeeLastSeen = canExposePresenceField(row?.peer_last_seen_visibility, {
    relationStatus,
    threadKind,
  });
  const heartbeatAt = row?.peer_presence_heartbeat_at
    ? new Date(row.peer_presence_heartbeat_at)
    : null;
  const heartbeatTime = heartbeatAt?.getTime?.() || 0;
  const isOnline =
    canSeeOnlineStatus &&
    heartbeatTime > 0 &&
    Date.now() - heartbeatTime <= SOCIAL_PRESENCE_ONLINE_WINDOW_MS;
  const canSeeConversationSignals =
    relationStatus === "accepted" || threadKind === "business";
  return {
    isOnline,
    lastSeenAt: canSeeLastSeen ? row?.peer_presence_last_seen_at || null : null,
    canSeeOnlineStatus,
    canSeeLastSeen,
    canSeeReadReceipts:
      canSeeConversationSignals && row?.peer_read_receipts_enabled !== false,
    canSeeTypingIndicators:
      canSeeConversationSignals && row?.peer_typing_indicators_enabled !== false,
  };
}

function canViewPosts({ viewerUserId, owner, viewerIsSuperAdmin = false }) {
  return (
    Number(owner?.id || 0) === Number(viewerUserId) ||
    viewerIsSuperAdmin === true ||
    owner?.is_super_admin === true ||
    owner?.social_posts_public === true
  );
}

function canViewStories({ viewerUserId, owner, viewerIsSuperAdmin = false }) {
  return (
    Number(owner?.id || 0) === Number(viewerUserId) ||
    viewerIsSuperAdmin === true ||
    owner?.is_super_admin === true ||
    owner?.social_stories_public === true
  );
}

function canViewPhone({ viewerUserId, owner }) {
  return (
    Number(owner?.id || 0) === Number(viewerUserId) ||
    owner?.social_show_phone === true
  );
}

function canViewRelationLists({ viewerUserId, viewer, owner }) {
  return (
    Number(owner?.id || 0) === Number(viewerUserId) ||
    isSuperAdminUser(viewer) ||
    owner?.social_relations_public === true
  );
}

function emitThreadStateUpdate({
  threadId,
  actorUserId,
  peerUserId,
  lastReadMessageId,
  lastDeliveredMessageId,
}) {
  const payload = {
    threadId: Number(threadId),
    readerUserId: Number(actorUserId),
    lastReadMessageId:
      lastReadMessageId == null ? null : Number(lastReadMessageId),
    lastDeliveredMessageId:
      lastDeliveredMessageId == null ? null : Number(lastDeliveredMessageId),
  };
  emitToUser(Number(actorUserId), "social_chat_state", payload);
  emitToUser(Number(peerUserId), "social_chat_state", payload);
}

const RESERVED_USERNAMES = new Set([
  "admin",
  "support",
  "help",
  "api",
  "system",
  "owner",
  "merchant",
  "taxi",
  "jobs",
  "social",
  "notifications",
  "settings",
  "messages",
  "message",
  "chat",
  "reels",
  "stories",
  "story",
  "profile",
  "login",
  "signup",
  "register",
  "me",
  "null",
  "undefined",
]);

function normalizeUsername(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._]/g, "");
}

function assertUsernameValid(username) {
  const normalized = normalizeUsername(username);
  if (normalized.length < 4 || normalized.length > 24) {
    throw new AppError("USERNAME_INVALID", {
      status: 400,
      details: { fields: ["username"] },
    });
  }
  if (!/^[a-z0-9](?:[a-z0-9._]{2,22})[a-z0-9]$/.test(normalized)) {
    throw new AppError("USERNAME_INVALID", {
      status: 400,
      details: { fields: ["username"] },
    });
  }
  if (normalized.includes("..") || normalized.includes("__")) {
    throw new AppError("USERNAME_INVALID", {
      status: 400,
      details: { fields: ["username"] },
    });
  }
  if (RESERVED_USERNAMES.has(normalized)) {
    throw new AppError("USERNAME_RESERVED", {
      status: 409,
      details: { fields: ["username"] },
    });
  }
  return normalized;
}

function relationAllowsPrivateAccess(relationRow, viewerUserId, ownerUserId) {
  const relation = mapRelationRow(relationRow, viewerUserId, ownerUserId);
  return relation.isAccepted || relation.otherUserId == null && false;
}

async function resolveProfileAccess({ viewerUserId, ownerUserId, viewer = null, owner = null }) {
  const [resolvedViewer, resolvedOwner, relationRow] = await Promise.all([
    viewer ?? repo.findUserAddressMeta(viewerUserId),
    owner ?? repo.findUserSocialProfile(ownerUserId),
    Number(viewerUserId) === Number(ownerUserId)
      ? Promise.resolve(null)
      : repo.getUserRelation({ userId: viewerUserId, otherUserId: ownerUserId }),
  ]);
  if (!resolvedViewer) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  if (!resolvedOwner) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  const ownerId = Number(resolvedOwner.id || 0);
  const isOwner = ownerId === Number(viewerUserId);
  const viewerIsSuperAdmin = isSuperAdminUser(resolvedViewer);
  const privateAccount =
    resolvedOwner.social_account_private === true && !isOwner && !viewerIsSuperAdmin;
  const relationAccepted = relationAllowsPrivateAccess(
    relationRow,
    viewerUserId,
    ownerId
  );
  const hasPrivateAccess = !privateAccount || relationAccepted;
  return {
    viewer: resolvedViewer,
    owner: resolvedOwner,
    relationRow,
    isOwner,
    viewerIsSuperAdmin,
    privateAccount,
    hasPrivateAccess,
  };
}

async function assertViewerCanAccessPosts({ viewerUserId, ownerUserId, owner = null }) {
  const access = await resolveProfileAccess({
    viewerUserId,
    ownerUserId,
    owner,
  });
  if (
    !access.hasPrivateAccess ||
    !canViewPosts({
      viewerUserId,
      owner: access.owner,
      viewerIsSuperAdmin: access.viewerIsSuperAdmin,
    })
  ) {
    throw new AppError("PROFILE_POSTS_PRIVATE", { status: 403 });
  }
  return access.owner;
}

async function assertViewerCanAccessStories({ viewerUserId, ownerUserId, owner = null }) {
  const access = await resolveProfileAccess({
    viewerUserId,
    ownerUserId,
    owner,
  });
  if (
    !access.hasPrivateAccess ||
    !canViewStories({
      viewerUserId,
      owner: access.owner,
      viewerIsSuperAdmin: access.viewerIsSuperAdmin,
    })
  ) {
    throw new AppError("PROFILE_STORIES_PRIVATE", { status: 403 });
  }
  return access.owner;
}

function mapLocalContextLabel(localContext) {
  if (!localContext?.type) return null;
  switch (String(localContext.type).trim().toLowerCase()) {
    case "same_building":
      return `نفس البناية${localContext.code ? ` • ${localContext.code}` : ""}`;
    case "same_compound":
      return `نفس المجمع${localContext.code ? ` • ${localContext.code}` : ""}`;
    case "same_block":
      return `نفس البلوك${localContext.code ? ` • ${localContext.code}` : ""}`;
    default:
      return null;
  }
}

function buildProfileBadgeKeys({
  isResidentVerified,
  isMerchantVerified,
  isPremiumMember,
  isCarSeller,
  isPropertySeller,
}) {
  const keys = [];
  if (isResidentVerified) keys.push("resident_verified");
  if (isMerchantVerified) keys.push("merchant_verified");
  if (isCarSeller) keys.push("car_seller");
  if (isPropertySeller) keys.push("property_seller");
  if (isPremiumMember) keys.push("premium_creator");
  return keys;
}

function isGrayZoneTier(value) {
  return String(value || "").trim().toLowerCase() === "gray_zone";
}

const socialCapabilityErrorCodeByKey = {
  post_create: "SOCIAL_POST_CREATE_RESTRICTED",
  story_create: "SOCIAL_STORY_CREATE_RESTRICTED",
  reel_create: "SOCIAL_REEL_CREATE_RESTRICTED",
  comment_create: "SOCIAL_COMMENT_CREATE_RESTRICTED",
  community_post_create: "SOCIAL_COMMUNITY_POST_CREATE_RESTRICTED",
};

function mapSocialCapabilityErrorCode(capabilityKey) {
  return (
    socialCapabilityErrorCodeByKey[String(capabilityKey || "").trim().toLowerCase()] ||
    "SOCIAL_CAPABILITY_RESTRICTED"
  );
}

function normalizeSaveEntityType(postKind) {
  const normalized = String(postKind || "").trim().toLowerCase();
  if (normalized === "reel" || normalized === "video") return "reel";
  if (normalized === "merchant_review" || normalized === "review") return "review";
  return "post";
}

function isReelPostKind(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return normalized === "reel" || normalized === "video";
}

function normalizeRequestedPostKind(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (!normalized) return null;
  if (normalized === "video") return "reel";
  if (normalized === "review") return "merchant_review";
  return normalized;
}

function buildPostNotificationPayload({ post, postId, actorUserId = null, extra = {} }) {
  const normalizedPostId = Number(postId ?? post?.id ?? 0);
  const normalizedActorUserId = Number(actorUserId || post?.userId || post?.user_id || 0);
  const isReel = isReelPostKind(post?.postKind ?? post?.post_kind);
  return {
    postId: normalizedPostId > 0 ? normalizedPostId : null,
    reelId: isReel && normalizedPostId > 0 ? normalizedPostId : null,
    actorUserId: normalizedActorUserId > 0 ? normalizedActorUserId : null,
    target: isReel ? "social_reel" : "social_post",
    ...extra,
  };
}

function normalizeContentLinkPayload(dto = {}) {
  const targetType = String(
    dto.targetType ??
      dto.target_type ??
      dto.contentLinkTargetType ??
      dto.content_link_target_type ??
      ""
  )
    .trim()
    .toLowerCase();
  if (!targetType) return null;
  const allowedTargetTypes = new Set(["merchant", "product", "offer", "coupon"]);
  if (!allowedTargetTypes.has(targetType)) {
    throw new AppError("INVALID_SOCIAL_CONTENT_LINK_TARGET", { status: 400 });
  }
  const merchantId =
    dto.merchantId == null && dto.merchant_id == null
      ? null
      : Number(dto.merchantId ?? dto.merchant_id);
  const productId =
    dto.productId == null && dto.product_id == null
      ? null
      : Number(dto.productId ?? dto.product_id);
  const offerId =
    dto.offerId == null && dto.offer_id == null ? null : Number(dto.offerId ?? dto.offer_id);
  const couponId =
    dto.couponId == null && dto.coupon_id == null
      ? null
      : Number(dto.couponId ?? dto.coupon_id);
  return {
    targetType,
    merchantId: Number.isInteger(merchantId) && merchantId > 0 ? merchantId : null,
    productId: Number.isInteger(productId) && productId > 0 ? productId : null,
    offerId: Number.isInteger(offerId) && offerId > 0 ? offerId : null,
    couponId: Number.isInteger(couponId) && couponId > 0 ? couponId : null,
  };
}

async function attachPostDerivedState(rows = [], viewerUserId) {
  if (!Array.isArray(rows) || rows.length <= 0) return [];
  const ids = rows.map((row) => Number(row.id)).filter((value) => Number.isInteger(value) && value > 0);
  const [recentRows, lifetimeRows] = await Promise.all([
    analyticsRepo.listRecentEngagementStatsForPosts({ postIds: ids }),
    analyticsRepo.listLifetimeEngagementStatsForPosts({ postIds: ids, viewerUserId }),
  ]);
  const recentByPostId = new Map(recentRows.map((row) => [Number(row.post_id), row]));
  const lifetimeByPostId = new Map(lifetimeRows.map((row) => [Number(row.post_id), row]));
  return rows.map((row) => {
    const recent = recentByPostId.get(Number(row.id)) || {};
    const lifetime = lifetimeByPostId.get(Number(row.id)) || {};
    return {
      ...row,
      likes_recent: Number(recent.likes_recent || 0),
      comments_recent: Number(recent.comments_recent || 0),
      saves_recent: Number(recent.saves_recent || 0),
      impressions_recent: Number(recent.impressions_recent || 0),
      reel_views_recent: Number(recent.reel_views_recent || 0),
      likes_count: Number(lifetime.likes_count ?? row.likes_count ?? 0),
      comments_count: Number(lifetime.comments_count ?? row.comments_count ?? 0),
      saves_count: Number(lifetime.saves_count ?? row.saves_count ?? 0),
      impressions_count: Number(lifetime.impressions_count ?? row.impressions_count ?? 0),
      reel_views_count: Number(lifetime.reel_views_count ?? row.reel_views_count ?? 0),
      is_liked: lifetime.is_liked === true || row.is_liked === true,
      is_saved: lifetime.is_saved === true || row.is_saved === true,
    };
  });
}

async function listRankedVisiblePosts({
  viewerUserId,
  query,
  viewerScopeCodes,
  kinds = null,
  authorUserId = null,
  hashtagId = null,
  mentionedUserId = null,
  search = "",
  includeCommunityScoped = true,
}) {
  const rows = await discoveryRepo.listVisiblePostCandidates({
    viewerUserId,
    viewerBlockCode: viewerScopeCodes.blockCode,
    viewerCompoundCode: viewerScopeCodes.compoundCode,
    viewerBuildingCode: viewerScopeCodes.buildingCode,
    limit: Math.max((Number(query.limit) || 20) * 4, 48),
    beforeId: query.beforeId,
    authorUserId,
    postKinds: kinds,
    search,
    hashtagId,
    mentionedUserId,
    includeCommunityScoped,
  });
  const enriched = await attachPostDerivedState(rows, viewerUserId);
  const preferenceRows = await analyticsRepo.listViewerContentPreferenceSignals({
    viewerUserId,
  });
  const ranked = rankFeedRows(enriched, {
    viewerScopeCodes,
    preferenceWeights: buildPreferenceWeightMap(preferenceRows),
  }).slice(0, Number(query.limit) || 20);
  return ranked;
}

async function recordImpressionsForRows({
  viewerUserId,
  rows = [],
  context = "feed",
}) {
  const items = Array.isArray(rows) ? rows : [];
  if (items.length <= 0) return;
  void Promise.allSettled(
    items
      .map((row) => ({
        contentType:
          String(row.post_kind || row.postKind || "").trim().toLowerCase() === "reel"
            ? "reel"
            : "post",
        contentId: Number(row.id),
      }))
      .filter((item) => item.contentId > 0)
      .map((item) =>
        analyticsRepo.recordContentImpression({
          contentType: item.contentType,
          contentId: item.contentId,
          viewerUserId,
          context,
        })
      )
  );
}

function normalizeResidenceChangePayload(dto = {}) {
  const validation = validateBasmayaAddress({
    block: dto.block,
    buildingNumber: dto.buildingNumber,
    apartment: dto.apartment ?? dto.apartmentNumber ?? dto.apartment_number,
  });
  if (!validation.ok) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: validation.errors },
    });
  }

  const note =
    dto.note === undefined || dto.note === null ? null : String(dto.note).trim() || null;
  const documentImageUrl =
    dto.documentImageUrl === undefined || dto.documentImageUrl === null
      ? null
      : String(dto.documentImageUrl).trim() || null;

  return {
    block: validation.normalized.block,
    town: validation.normalized.block,
    buildingNumber: validation.normalized.buildingNumber,
    apartment: validation.normalized.apartment,
    apartmentNumber: validation.normalized.apartment,
    note,
    documentImageUrl,
  };
}

function mapResidenceSnapshot(snapshot = {}) {
  return {
    block: snapshot.block || snapshot.town || null,
    town: snapshot.town || snapshot.block || null,
    buildingNumber:
      snapshot.buildingNumber || snapshot.building_number || snapshot.residence_building_number || null,
    apartment:
      snapshot.apartment || snapshot.apartmentNumber || snapshot.apartment_number || null,
    apartmentNumber:
      snapshot.apartmentNumber || snapshot.apartment_number || snapshot.apartment || null,
    floorNumber: snapshot.floorNumber || snapshot.floor_number || null,
    contractNumber: snapshot.contractNumber || snapshot.contract_number || null,
    issueDate: snapshot.issueDate || snapshot.issue_date || null,
    documentType: snapshot.documentType || snapshot.document_type || null,
    documentImageUrl:
      snapshot.documentImageUrl || snapshot.document_image_url || snapshot.residence_document_image_url || null,
  };
}

function mapResidenceChangeRequestRow(row = {}) {
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    status: String(row.status || "pending").trim().toLowerCase(),
    currentSnapshot: row.current_snapshot_json || {},
    requestedSnapshot: row.requested_snapshot_json || {},
    note: row.note || null,
    documentImageUrl: row.document_image_url || null,
    reviewNote: row.review_note || null,
    reviewedByUserId:
      row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedAt: row.reviewed_at || null,
    cancelledAt: row.cancelled_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapProfileCoreChangeRequestRow(row = {}) {
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    changeKind: String(row.change_kind || "core_identity").trim().toLowerCase(),
    status: String(row.status || "pending").trim().toLowerCase(),
    currentSnapshot: row.current_snapshot_json || {},
    requestedSnapshot: row.requested_snapshot_json || {},
    reviewNote: row.review_note || null,
    reviewedByUserId:
      row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedAt: row.reviewed_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapSocialCapabilityRestrictionRow(row = {}) {
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    capabilityKey: String(row.capability_key || "").trim().toLowerCase(),
    reason: row.reason || null,
    startsAt: row.starts_at || null,
    endsAt: row.ends_at || null,
    createdByUserId:
      row.created_by_user_id == null ? null : Number(row.created_by_user_id),
    revokedAt: row.revoked_at || null,
    revokedByUserId:
      row.revoked_by_user_id == null ? null : Number(row.revoked_by_user_id),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function resolvePostCapabilityKey({ postKind, audienceScopeType }) {
  const normalizedKind = String(postKind || "").trim().toLowerCase();
  const normalizedScope = String(audienceScopeType || "global").trim().toLowerCase();
  if (normalizedScope && normalizedScope !== "global") {
    return "community_post_create";
  }
  if (normalizedKind === "video" || normalizedKind === "reel" || normalizedKind === "reels") {
    return "reel_create";
  }
  return "post_create";
}

async function assertSocialCapabilityAllowed(userId, capabilityKey) {
  const restriction = await repo.findActiveSocialCapabilityRestriction({
    userId,
    capabilityKey,
  });
  if (!restriction) return;
  throw new AppError(mapSocialCapabilityErrorCode(capabilityKey), {
    status: 403,
    details: {
      capabilityKey: String(capabilityKey || "").trim().toLowerCase(),
      restrictionId: Number(restriction.id),
      reason: restriction.reason || null,
      startsAt: restriction.starts_at || null,
      endsAt: restriction.ends_at || null,
      },
    });
}

async function assertSocialWriteAllowed(userId, capabilityKey = null) {
  const state = await repo.findUserSocialModerationState(userId);
  if (!state) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  if (state.is_account_disabled === true) {
    throw new AppError("ACCOUNT_DISABLED", { status: 403 });
  }
  const blockUntil = state.social_write_block_until
    ? new Date(state.social_write_block_until)
    : null;
  if (blockUntil && blockUntil.getTime() > Date.now()) {
    throw new AppError("SOCIAL_WRITE_BLOCKED", {
      status: 403,
      details: { blockUntil: blockUntil.toISOString() },
    });
  }
  if (capabilityKey) {
    await assertSocialCapabilityAllowed(userId, capabilityKey);
  }
}

async function assertReportingAllowed(userId) {
  const state = await repo.findUserSocialModerationState(userId);
  if (!state) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  if (state.is_account_disabled === true) {
    throw new AppError("ACCOUNT_DISABLED", { status: 403 });
  }
  if (state.social_reports_blocked === true) {
    throw new AppError("REPORTING_BLOCKED", { status: 403 });
  }
}

export async function getMyResidenceChangeRequest(userId) {
  const [current, latest] = await Promise.all([
    repo.findUserResidenceSnapshot(userId),
    repo.findLatestResidenceChangeRequestByUser(userId),
  ]);
  if (!current) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  return {
    currentSnapshot: mapResidenceSnapshot(current),
    request: latest ? mapResidenceChangeRequestRow(latest) : null,
  };
}

export async function listMyActiveSocialCapabilityRestrictions(userId) {
  const rows = await repo.listActiveSocialCapabilityRestrictionsForUser(userId);
  return {
    items: rows.map(mapSocialCapabilityRestrictionRow),
  };
}

export async function submitResidenceChangeRequest(userId, dto = {}) {
  const current = await repo.findUserResidenceSnapshot(userId);
  if (!current) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }

  const latest = await repo.findLatestResidenceChangeRequestByUser(userId);
  if (latest && String(latest.status || "").trim().toLowerCase() === "pending") {
    throw new AppError("RESIDENCE_CHANGE_ALREADY_PENDING", {
      status: 409,
      details: { requestId: Number(latest.id) },
    });
  }

  const requested = normalizeResidenceChangePayload(dto);
  const currentSnapshot = mapResidenceSnapshot(current);
  if (
    currentSnapshot.block === requested.block &&
    currentSnapshot.buildingNumber === requested.buildingNumber &&
    currentSnapshot.apartmentNumber === requested.apartmentNumber
  ) {
    throw new AppError("RESIDENCE_CHANGE_NO_DIFF", {
      status: 400,
      details: {
        fields: ["block", "buildingNumber", "apartmentNumber"],
      },
    });
  }

  const created = await repo.createResidenceChangeRequest({
    userId,
    currentSnapshotJson: currentSnapshot,
    requestedSnapshotJson: requested,
    note: requested.note,
    documentImageUrl: requested.documentImageUrl,
  });
  if (!created) {
    throw new AppError("RESIDENCE_CHANGE_CREATE_FAILED", { status: 500 });
  }

  const adminIds = await repo.listAdminUserIds(240);
  await createManyNotifications(
    adminIds
      .filter((adminId) => Number(adminId) !== Number(userId))
      .map((adminId) => ({
        userId: Number(adminId),
        type: "residence.change.request_submitted",
        title: "طلب جديد لتعديل السكن",
        body: "يوجد طلب جديد بانتظار مراجعة بيانات السكن.",
        payload: {
          requestId: Number(created.id),
          userId: Number(userId),
          target: "admin_residence_requests",
        },
      }))
  );

  return {
    currentSnapshot,
    request: mapResidenceChangeRequestRow(created),
  };
}

export async function cancelMyResidenceChangeRequest({ userId, requestId }) {
  const cancelled = await repo.cancelResidenceChangeRequest({ requestId, userId });
  if (!cancelled) {
    throw new AppError("RESIDENCE_CHANGE_REQUEST_NOT_FOUND", { status: 404 });
  }
  return {
    request: mapResidenceChangeRequestRow(cancelled),
  };
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
  const threadKind = normalizeThreadKind(row.thread_kind);
  const peerId = threadKind === "group" ? 0 : Number(row.peer_user_id);
  const lastMessageAttachment = mapMessageAttachment({
    attachment_url: row.last_message_attachment_url,
    attachment_kind: row.last_message_attachment_kind,
    attachment_name: row.last_message_attachment_name,
  });
  const mutedUntil = row.muted_until || null;
  const muted =
    mutedUntil != null && new Date(mutedUntil).getTime() > Date.now();
  const contextType = normalizeThreadContextType(row.context_type);
  const contextSnapshot = parseJsonObject(row.context_snapshot_json);
  const presence = buildThreadPresence(row);
  const group =
    threadKind !== "group"
      ? null
      : {
          ownerUserId: Number(row.group_owner_user_id || 0),
          title: String(row.group_title || row.peer_full_name || "").trim(),
          imageUrl: row.group_image_url || row.peer_image_url || null,
          memberCount: Math.max(0, Number(row.group_member_count || 0)),
          adminCount: Math.max(0, Number(row.group_admin_count || 0)),
          memberRole:
            String(row.group_member_role || "member").trim().toLowerCase() || "member",
        };
  return {
    id: Number(row.id),
    userAId: Number(row.user_a_id),
    userBId: Number(row.user_b_id),
    threadKind,
    contextType,
    contextId: Math.max(0, Number(row.context_id || 0)),
    contextStatus:
      String(row.context_status || "").trim().toLowerCase() || "active",
    contextSnapshot,
    context: row.context || null,
    group,
    peerPhone: threadKind === "group" ? "" : row.peer_phone || "",
    peer: {
      id: peerId,
      username: threadKind === "group" ? null : row.peer_username || null,
      fullName:
        threadKind === "group"
          ? group?.title || row.peer_full_name || ""
          : row.peer_full_name || "",
      phone: threadKind === "group" ? "" : row.peer_phone || "",
      imageUrl:
        threadKind === "group"
          ? group?.imageUrl || null
          : row.peer_image_url || null,
      role: threadKind === "group" ? "group" : row.peer_role || "user",
      isPremiumCreator: threadKind === "group" ? false : row.peer_has_premium === true,
    },
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    lastMessageAt: row.last_message_at,
    presence,
    lastMessage: row.last_message_id
      ? {
          id: Number(row.last_message_id),
          threadId: Number(row.id),
          senderUserId: Number(row.last_message_sender_user_id),
          body: row.last_message_body || "",
          createdAt: row.last_message_created_at,
          attachment: lastMessageAttachment,
          sharedEntity:
            row.last_message_shared_entity_type == null
                ? null
                : {
                    type: row.last_message_shared_entity_type,
                    id: Number(row.last_message_shared_entity_id || 0),
                    snapshot: row.last_message_shared_snapshot_json || null,
                  },
          isMine:
            Number(row.last_message_sender_user_id) === Number(viewerUserId),
        }
      : null,
    state: {
      muted,
      mutedUntil,
      pinnedAt: row.pinned_at || null,
      themeKey:
        String(row.theme_key || "default").trim().toLowerCase() || "default",
      inboxBucket: row.inbox_bucket || "primary",
      requestStatus: row.request_status || "accepted",
      acceptedAt: row.accepted_at || null,
      rejectedAt: row.rejected_at || null,
      lastReadMessageId:
        row.last_read_message_id == null ? null : Number(row.last_read_message_id),
      lastDeliveredMessageId:
        row.last_delivered_message_id == null
          ? null
          : Number(row.last_delivered_message_id),
      unreadCount: Number(row.unread_count || 0),
    },
  };
}

function mapGroupThreadMemberRow(row) {
  const heartbeatAt = row?.presence_heartbeat_at
    ? new Date(row.presence_heartbeat_at)
    : null;
  const heartbeatTime = heartbeatAt?.getTime?.() || 0;
  const canSeeOnlineStatus = canExposePresenceField(row?.social_online_visibility, {
    relationStatus: "accepted",
    threadKind: "private",
  });
  const canSeeLastSeen = canExposePresenceField(row?.social_last_seen_visibility, {
    relationStatus: "accepted",
    threadKind: "private",
  });
  const isOnline =
    canSeeOnlineStatus &&
    heartbeatTime > 0 &&
    Date.now() - heartbeatTime <= SOCIAL_PRESENCE_ONLINE_WINDOW_MS;
  return {
    userId: Number(row.user_id),
    memberRole: String(row.member_role || "member").trim().toLowerCase() || "member",
    addedByUserId:
      row.added_by_user_id == null ? null : Number(row.added_by_user_id),
    addedAt: row.member_created_at || null,
    presence: {
      isOnline,
      lastSeenAt: canSeeLastSeen ? row?.presence_last_seen_at || null : null,
      canSeeOnlineStatus,
      canSeeLastSeen,
      canSeeReadReceipts: false,
      canSeeTypingIndicators: false,
    },
    user: {
      id: Number(row.user_id),
      username: row.username || null,
      fullName: row.full_name || "",
      phone: row.phone || "",
      imageUrl: row.image_url || null,
      role: row.role || "user",
      isPremiumCreator: row.has_premium === true,
    },
  };
}

function assertGroupThread(thread) {
  if (!thread || normalizeThreadKind(thread.thread_kind) !== "group") {
    throw new AppError("GROUP_THREAD_NOT_FOUND", { status: 404 });
  }
}

function assertGroupManagePermission(thread) {
  const role = String(thread?.group_member_role || "member").trim().toLowerCase();
  if (role !== "owner" && role !== "admin") {
    throw new AppError("GROUP_THREAD_MANAGE_FORBIDDEN", { status: 403 });
  }
  return role;
}

function mapMessageAttachment(row) {
  if (row?.is_deleted === true) return null;
  const url = row?.attachment_url || row?.attachmentUrl || null;
  if (!url) return null;
  return {
    url,
    kind: row?.attachment_kind || row?.attachmentKind || "file",
    name: row?.attachment_name || row?.attachmentName || "attachment",
    mimeType: row?.attachment_mime_type || row?.attachmentMimeType || null,
    sizeBytes:
      row?.attachment_size_bytes == null && row?.attachmentSizeBytes == null
        ? null
        : Number(row?.attachment_size_bytes ?? row?.attachmentSizeBytes),
    durationMs:
      row?.attachment_duration_ms == null && row?.attachmentDurationMs == null
        ? null
        : Number(row?.attachment_duration_ms ?? row?.attachmentDurationMs),
  };
}

function mapMessageReply(row) {
  if (!row?.reply_message_id) return null;
  return {
    id: Number(row.reply_message_id),
    senderUserId: Number(row.reply_sender_user_id),
    senderUsername: row.reply_sender_username || null,
    senderFullName: row.reply_sender_full_name || "",
    body: row.reply_body || "",
    attachmentKind: row.reply_attachment_kind || null,
    attachmentName: row.reply_attachment_name || null,
  };
}

function mapMessageRow(row, viewerUserId) {
  const isDeleted = row.is_deleted === true;
  return {
    id: Number(row.id),
    threadId: Number(row.thread_id),
    senderUserId: Number(row.sender_user_id),
    body: isDeleted ? "" : row.body || "",
    clientMessageId: row.client_message_id || row.clientMessageId || null,
    replyToMessage: mapMessageReply(row),
    attachment: mapMessageAttachment(row),
    sharedEntity:
      row.shared_entity_type == null
        ? null
        : {
            type: row.shared_entity_type,
            id: Number(row.shared_entity_id || 0),
            snapshot: row.shared_snapshot_json || null,
          },
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    editedAt: row.edited_at || null,
    deletedAt: row.deleted_at || null,
    pinnedAt: row.pinned_at || null,
    pinnedByUserId:
      row.pinned_by_user_id == null ? null : Number(row.pinned_by_user_id),
    isDeleted,
    isMine: Number(row.sender_user_id) === Number(viewerUserId),
    deliveredToPeer: row.delivered_to_peer === true,
    readByPeer: row.read_by_peer === true,
    reactions: {
      counts: row.reaction_counts || {},
      totalCount: Number(row.reaction_total_count || 0),
      myReaction: row.my_reaction || null,
    },
    sender: {
      id: Number(row.sender_user_id),
      username: row.sender_username || null,
      fullName: row.sender_full_name || "",
      imageUrl: row.sender_image_url || null,
      phone: row.sender_phone || "",
      role: row.sender_role || "user",
      isPremiumCreator: row.sender_has_premium === true,
    },
  };
}

function mapScheduledMessageRow(row) {
  return {
    id: Number(row.id),
    threadId: Number(row.thread_id),
    senderUserId: Number(row.sender_user_id),
    body: row.body || "",
    replyToMessage: mapMessageReply(row),
    attachment: mapMessageAttachment(row),
    sharedEntity:
      row.shared_entity_type == null
        ? null
        : {
            type: row.shared_entity_type,
            id: Number(row.shared_entity_id || 0),
            snapshot: row.shared_snapshot_json || null,
          },
    scheduledFor: row.scheduled_for || null,
    createdAt: row.created_at || null,
    sentAt: row.sent_at || null,
    sentMessageId:
      row.sent_message_id == null ? null : Number(row.sent_message_id),
    status: String(row.status || "scheduled").trim().toLowerCase() || "scheduled",
    attempts: Math.max(0, Number(row.attempts || 0)),
    lastErrorCode: row.last_error_code || null,
  };
}

function mapThreadMessageTranslationRow(row) {
  return {
    id: Number(row.id),
    messageId: Number(row.message_id),
    targetLanguage:
      String(row.target_language || "").trim().toLowerCase() || "en",
    sourceLanguage:
      row.source_language == null
        ? null
        : String(row.source_language).trim().toLowerCase() || null,
    translatedText: row.translated_text || "",
    provider: String(row.provider || "openai").trim().toLowerCase() || "openai",
    modelName: row.model_name || null,
    sourceVersionAt: row.source_version_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
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

function mapStoryCommentRow(row) {
  const isDeleted = row.is_deleted === true;
  return {
    id: Number(row.id),
    storyId: Number(row.story_id),
    userId: Number(row.user_id),
    body: isDeleted ? "تم حذف التعليق" : row.body || "",
    isDeleted,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    editedAt: row.edited_at || null,
    author: {
      id: Number(row.user_id),
      fullName: row.user_full_name || "",
      imageUrl: row.user_image_url || null,
      phone: "",
      role: row.user_role || "user",
    },
  };
}

function isMessageWithinEditDeleteWindow(messageRow) {
  if (!messageRow?.created_at) return false;
  const createdAt = new Date(messageRow.created_at);
  if (Number.isNaN(createdAt.getTime())) return false;
  return Date.now() - createdAt.getTime() <= SOCIAL_CHAT_EDIT_DELETE_WINDOW_MS;
}

function buildThreadCallRealtimePayload({
  eventType,
  threadId,
  session,
  signal,
  viewerUserId,
}) {
  return {
    eventType,
    threadId: Number(threadId),
    session: mapCallSession(session, viewerUserId),
    signal: mapCallSignal(signal),
  };
}

async function processSocialRingingCallTimeoutsAndEmit() {
  const staleCalls = await repo.listStaleRingingThreadCallSessions({
    timeoutSeconds: SOCIAL_CALL_RING_TIMEOUT_SECONDS,
    limit: 120,
  });

  for (const call of staleCalls) {
    const ended = await repo.endThreadCallSession({
      sessionId: call.id,
      status: "missed",
      endReason: "timeout",
    });
    if (!ended) continue;

    const signal = await repo.insertThreadCallSignal({
      sessionId: ended.id,
      threadId: ended.threadId,
      senderUserId: ended.callerUserId,
      signalType: "decline",
      signalPayload: {
        reason: "timeout",
        status: "missed",
      },
    });

    emitToUser(
      Number(ended.callerUserId),
      "social_call_update",
      buildThreadCallRealtimePayload({
        eventType: "call_missed",
        threadId: ended.threadId,
        session: ended,
        signal,
        viewerUserId: Number(ended.callerUserId),
      })
    );
    emitToUser(
      Number(ended.calleeUserId),
      "social_call_update",
      buildThreadCallRealtimePayload({
        eventType: "call_missed",
        threadId: ended.threadId,
        session: ended,
        signal,
        viewerUserId: Number(ended.calleeUserId),
      })
    );

    await createNotification({
      userId: Number(ended.callerUserId),
      type: "social.call.missed",
      title: "لم يتم الرد على المكالمة",
      body: "انتهت مهلة الرنين. يمكنك إعادة المحاولة من داخل المحادثة.",
      payload: {
        threadId: Number(ended.threadId),
        sessionId: Number(ended.id),
        target: "social_call",
      },
    });
  }
}

async function processSocialCallLifecycle() {
  if (socialCallLifecycleRunning) return;
  socialCallLifecycleRunning = true;
  try {
    await processSocialRingingCallTimeoutsAndEmit();
  } catch (error) {
    console.warn(
      "[social] call lifecycle processing failed",
      error?.message || error
    );
  } finally {
    socialCallLifecycleRunning = false;
  }
}

/**
 * يبدأ worker دوري لمعالجة مكالمات المجتمع العالقة في حالة ringing.
 *
 * Side effects:
 * - يشغل `setInterval`
 * - يغير حالات مكالمات منتهية المهلة
 * - يبث أحداث realtime للأطراف المرتبطة
 *
 * Maintenance notes:
 * - إذا ظلت مكالمات `ringing` بلا نهاية افحص هذا worker أولاً ثم جداول
 *   call state وtimestamps المستخدمة في repo.
 */
export function startSocialCallLifecycleWorker({ intervalMs = 5000 } = {}) {
  if (socialCallLifecycleWorker) return;

  socialCallLifecycleWorker = setInterval(() => {
    processSocialCallLifecycle().catch((error) => {
      console.warn(
        "[social] call lifecycle worker tick failed",
        error?.message || error
      );
    });
  }, Math.max(5000, Number(intervalMs) || 20000));

  socialCallLifecycleWorker.unref?.();
  void processSocialCallLifecycle();
}

const communityAdminRoles = new Set(["admin", "deputy_admin"]);
const communityUnsupportedRoles = new Set(["owner"]);
const communityManagerEligibleRoles = new Set(["user"]);

function isCommunityAdminRole(role) {
  const normalized = String(role || "").trim().toLowerCase();
  return communityAdminRoles.has(normalized);
}

function isCommunityUnsupportedRole(role) {
  const normalized = String(role || "").trim().toLowerCase();
  return communityUnsupportedRoles.has(normalized);
}

function isCommunityManagerEligibleRole(role) {
  const normalized = String(role || "").trim().toLowerCase();
  return communityManagerEligibleRoles.has(normalized);
}

function isSuperAdminUser(user) {
  return user?.is_super_admin === true;
}

function buildAllCommunityScopes() {
  const out = [];
  for (const block of ["A", "B"]) {
    out.push(buildScopeMeta("block", block));
  }

  for (let sector = 1; sector <= 9; sector += 1) {
    out.push(buildScopeMeta("compound", `A${sector}`));
  }
  for (let sector = 1; sector <= 8; sector += 1) {
    out.push(buildScopeMeta("compound", `B${sector}`));
  }

  for (let sector = 1; sector <= 9; sector += 1) {
    for (let buildingNo = 1; buildingNo <= 12; buildingNo += 1) {
      out.push(
        buildScopeMeta(
          "building",
          `A${sector}${String(buildingNo).padStart(2, "0")}`
        )
      );
    }
  }
  for (let sector = 1; sector <= 8; sector += 1) {
    for (let buildingNo = 1; buildingNo <= 22; buildingNo += 1) {
      out.push(
        buildScopeMeta(
          "building",
          `B${sector}${String(buildingNo).padStart(2, "0")}`
        )
      );
    }
  }

  return out;
}

function buildScopeMeta(scopeType, scopeCode) {
  if (scopeType === "block") {
    return {
      scopeType,
      scopeCode,
      title: `بلوك ${scopeCode}`,
      subtitle: `مجتمع البلوك ${scopeCode}`,
    };
  }
  if (scopeType === "compound") {
    return {
      scopeType,
      scopeCode,
      title: `مجمع ${scopeCode}`,
      subtitle: `مجتمع المجمع ${scopeCode}`,
    };
  }
  return {
    scopeType,
    scopeCode,
    title: `عمارة ${scopeCode}`,
    subtitle: `مجتمع العمارة ${scopeCode}`,
  };
}

function mapScopeManagerRow(row) {
  return {
    id: Number(row.id),
    scopeType: row.scope_type,
    scopeCode: row.scope_code,
    managerUserId: Number(row.manager_user_id),
    assignedByUserId:
      row.assigned_by_user_id == null ? null : Number(row.assigned_by_user_id),
    createdAt: row.created_at || null,
    manager: {
      id: Number(row.manager_user_id),
      fullName: row.manager_full_name || "",
      phone: row.manager_phone || "",
      role: row.manager_role || "user",
      imageUrl: row.manager_image_url || null,
    },
  };
}

function mapScopeAnnouncementRow(row) {
  return {
    id: Number(row.id),
    scopeType: row.scope_type,
    scopeCode: row.scope_code,
    title: row.title || "",
    body: row.body || "",
    createdAt: row.created_at || null,
    createdByUserId: Number(row.created_by_user_id),
    author: {
      id: Number(row.created_by_user_id),
      fullName: row.author_full_name || "",
      phone: row.author_phone || "",
      role: row.author_role || "user",
      imageUrl: row.author_image_url || null,
    },
  };
}

function mapScopeChatMessageRow(row, viewerUserId) {
  const isDeleted = row.is_deleted === true;
  return {
    id: Number(row.id),
    scopeType: row.scope_type,
    scopeCode: row.scope_code,
    senderUserId:
      row.sender_user_id == null ? null : Number(row.sender_user_id),
    body: isDeleted ? "" : row.body || "",
    clientMessageId: row.client_message_id || row.clientMessageId || null,
    replyToMessage: mapMessageReply(row),
    attachment: mapMessageAttachment(row),
    sharedEntity:
      row.shared_entity_type == null
        ? null
        : {
            type: row.shared_entity_type,
            id: Number(row.shared_entity_id || 0),
            snapshot: row.shared_snapshot_json || null,
          },
    isSystem: row.is_system === true,
    isDeleted,
    isMine:
      row.sender_user_id != null &&
      Number(row.sender_user_id) === Number(viewerUserId),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
    editedAt: row.edited_at || null,
    deletedAt: row.deleted_at || null,
    reactions: {
      counts: row.reaction_counts || {},
      totalCount: Number(row.reaction_total_count || 0),
      myReaction: row.my_reaction || null,
    },
    sender:
      row.sender_user_id == null
        ? null
        : {
            id: Number(row.sender_user_id),
            fullName: row.sender_full_name || "",
            phone: row.sender_phone || "",
            role: row.sender_role || "user",
            imageUrl: row.sender_image_url || null,
          },
  };
}

function mapScopeBanRow(row) {
  return {
    userId: Number(row.user_id),
    bannedByUserId:
      row.banned_by_user_id == null ? null : Number(row.banned_by_user_id),
    reason: row.reason || null,
    createdAt: row.created_at || null,
    user: {
      id: Number(row.user_id),
      fullName: row.user_full_name || "",
      phone: row.user_phone || "",
      role: row.user_role || "user",
      imageUrl: row.user_image_url || null,
    },
  };
}

function mapScopeBillRow(row) {
  return {
    id: Number(row.id),
    scopeType: row.scope_type,
    scopeCode: row.scope_code,
    category: row.bill_category || "other",
    title: row.title || "",
    amount:
      row.amount == null || Number.isNaN(Number(row.amount))
        ? null
        : Number(row.amount),
    dueDate: row.due_date || null,
    details: row.details || null,
    apartmentCode:
      row.apartment_code == null ? null : String(row.apartment_code).trim().toUpperCase(),
    attachment:
      row.attachment_url == null
        ? null
        : {
            url: String(row.attachment_url || "").trim(),
            kind:
              String(row.attachment_kind || "").trim().toLowerCase() === "image"
                ? "image"
                : "file",
            name:
              row.attachment_name == null ? null : String(row.attachment_name).trim(),
          },
    createdAt: row.created_at || null,
    issuedByUserId:
      row.issued_by_user_id == null ? null : Number(row.issued_by_user_id),
    issuer:
      row.issued_by_user_id == null
        ? null
        : {
            id: Number(row.issued_by_user_id),
            fullName: row.issuer_full_name || "",
            phone: row.issuer_phone || "",
            role: row.issuer_role || "user",
            imageUrl: row.issuer_image_url || null,
          },
  };
}

function hierarchyFromUserRow(user) {
  return deriveBasmayaHierarchy({
    block: user?.block,
    buildingNumber: user?.building_number,
    apartment: user?.apartment,
  });
}

function doesHierarchyMatchScope(hierarchy, scopeType, scopeCode) {
  if (!hierarchy) return false;
  if (scopeType === "block") return hierarchy.block === scopeCode;
  if (scopeType === "compound") return hierarchy.compound === scopeCode;
  return hierarchy.building === scopeCode;
}

function normalizeApartmentCode(value) {
  const normalized = String(value || "").trim().toUpperCase();
  if (!normalized) return null;
  if (/^G(0[1-9]|1[0-2])$/.test(normalized)) return normalized;
  if (/^[1-9](0[1-9]|1[0-2])$/.test(normalized)) return normalized;
  return null;
}

function normalizePostAudienceScope(dto = {}) {
  const requestedType = String(
    dto.audienceScopeType ?? dto.audience_scope_type ?? dto.scopeType ?? dto.scope_type ?? ""
  )
    .trim()
    .toLowerCase();
  const requestedCode = String(
    dto.audienceScopeCode ?? dto.audience_scope_code ?? dto.scopeCode ?? dto.scope_code ?? ""
  )
    .trim()
    .toUpperCase();

  if (!requestedType) {
    return {
      scopeType: "global",
      scopeCode: null,
    };
  }

  if (requestedType === "global") {
    return {
      scopeType: "global",
      scopeCode: null,
    };
  }

  const normalized = normalizeCommunityScope(requestedType, requestedCode);
  if (!normalized.ok) {
    throw new AppError("COMMUNITY_SCOPE_INVALID", {
      status: 400,
      details: { fields: ["audienceScopeType", "audienceScopeCode"] },
    });
  }
  return {
    scopeType: normalized.scopeType,
    scopeCode: normalized.scopeCode,
  };
}

function buildAudienceScopesForCommunityFeeds({ scopeType, scopeCode }) {
  if (scopeType === "global") return [];
  const scopes = [];

  if (scopeType === "building") {
    scopes.push({ scopeType: "building", scopeCode });
    return scopes;
  }

  if (scopeType === "compound") {
    scopes.push({ scopeType: "compound", scopeCode });
    const compoundCode = String(scopeCode || "").trim().toUpperCase();
    const match = /^([AB])([1-9])$/.exec(compoundCode);
    if (!match) return scopes;
    const letter = match[1];
    const sector = match[2];
    const maxBuildings = letter === "A" ? 12 : 22;
    for (let buildingNo = 1; buildingNo <= maxBuildings; buildingNo += 1) {
      scopes.push({
        scopeType: "building",
        scopeCode: `${letter}${sector}${String(buildingNo).padStart(2, "0")}`,
      });
    }
    return scopes;
  }

  if (scopeType === "block") {
    scopes.push({ scopeType: "block", scopeCode });
    const blockCode = String(scopeCode || "").trim().toUpperCase();
    if (!/^[AB]$/.test(blockCode)) return scopes;
    const maxCompounds = blockCode === "A" ? 9 : 8;
    const maxBuildings = blockCode === "A" ? 12 : 22;
    for (let sector = 1; sector <= maxCompounds; sector += 1) {
      const compoundCode = `${blockCode}${sector}`;
      scopes.push({ scopeType: "compound", scopeCode: compoundCode });
      for (let buildingNo = 1; buildingNo <= maxBuildings; buildingNo += 1) {
        scopes.push({
          scopeType: "building",
          scopeCode: `${blockCode}${sector}${String(buildingNo).padStart(2, "0")}`,
        });
      }
    }
  }

  return scopes;
}

function viewerScopeCodesFromUserRow(user) {
  const hierarchy = hierarchyFromUserRow(user);
  return {
    blockCode: hierarchy.block || null,
    compoundCode: hierarchy.compound || null,
    buildingCode: hierarchy.building || null,
  };
}

async function resolveViewerScopeCodes(viewerUserId) {
  const cached = readViewerScopeCache(viewerUserId);
  if (cached) return cached;
  const viewer = await repo.findUserAddressMeta(viewerUserId);
  if (!viewer) {
    return writeViewerScopeCache(viewerUserId, {
      blockCode: null,
      compoundCode: null,
      buildingCode: null,
    });
  }
  return writeViewerScopeCache(
    viewerUserId,
    viewerScopeCodesFromUserRow(viewer)
  );
}

function buildCommunityScopePayload(scope, extra = {}) {
  return {
    target: "social_community",
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    scopeTitle: scope.title,
    scopeSubtitle: scope.subtitle,
    ...extra,
  };
}

function mapMonitoredThreadRow(row) {
  const userAId = Number(row.user_a_id);
  const userBId = Number(row.user_b_id);
  const userA = {
    id: userAId,
    fullName: row.user_a_full_name || "",
    phone: row.user_a_phone || "",
    imageUrl: row.user_a_image_url || null,
    role: row.user_a_role || "user",
  };
  const userB = {
    id: userBId,
    fullName: row.user_b_full_name || "",
    phone: row.user_b_phone || "",
    imageUrl: row.user_b_image_url || null,
    role: row.user_b_role || "user",
  };
  const lastMessageAttachment = mapMessageAttachment({
    attachment_url: row.last_message_attachment_url,
    attachment_kind: row.last_message_attachment_kind,
    attachment_name: row.last_message_attachment_name,
  });
  return {
    id: Number(row.id),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
    lastMessageAt: row.last_message_at || row.last_message_created_at || null,
    participantLabel: `${userA.fullName} / ${userB.fullName}`,
    participants: [userA, userB],
    lastMessage: row.last_message_id
      ? {
          id: Number(row.last_message_id),
          senderUserId: Number(row.last_message_sender_user_id),
          body: row.last_message_body || "",
          createdAt: row.last_message_created_at || null,
          attachment: lastMessageAttachment,
        }
      : null,
  };
}

async function emitCommunityRealtimeEvent({
  scopeType,
  scopeCode,
  event,
  data,
  apartmentCode = null,
  excludeUserIds = [],
}) {
  const scope = buildScopeMeta(scopeType, scopeCode);
  const audienceUserIds = await repo.listScopeAudienceUserIds({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    apartmentCode,
    excludeUserIds,
    includeBackoffice: true,
    limit: 12000,
  });
  if (audienceUserIds.length === 0) return;
  for (const audienceUserId of audienceUserIds) {
    emitToUser(Number(audienceUserId), event, {
      scope,
      ...data,
    });
  }
}

async function notifyCommunityScopeUsers({
  scopeType,
  scopeCode,
  type,
  title,
  body,
  excludeUserIds = [],
  apartmentCode = null,
  payload = {},
}) {
  const scope = buildScopeMeta(scopeType, scopeCode);
  const audienceUserIds = await repo.listScopeAudienceUserIds({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    excludeUserIds,
    includeBackoffice: true,
    apartmentCode,
    limit: 12000,
  });
  if (audienceUserIds.length === 0) return;
  await createManyNotifications(
    audienceUserIds.map((audienceUserId) => ({
      userId: Number(audienceUserId),
      type,
      title,
      body,
      payload: buildCommunityScopePayload(scope, payload),
    }))
  );
}

async function notifySingleCommunityUser({
  userId,
  scopeType,
  scopeCode,
  type,
  title,
  body,
  payload = {},
}) {
  const scope = buildScopeMeta(scopeType, scopeCode);
  await createNotification({
    userId: Number(userId),
    type,
    title,
    body,
    payload: buildCommunityScopePayload(scope, payload),
  });
}

function hasManagerAssignableRole(role) {
  const normalized = String(role || "").trim().toLowerCase();
  return !["owner", "delivery", "call_center"].includes(normalized);
}

function mapNotificationPreferenceRow(row) {
  const muted = row?.muted === true;
  return {
    enabled: !muted,
    muted,
    updatedAt: row?.updated_at || null,
    createdAt: row?.created_at || null,
  };
}

async function buildSuperAdminControlsForTarget(targetUser) {
  const hierarchy = hierarchyFromUserRow(targetUser);
  const blockCode = hierarchy.block || null;
  const compoundCode = hierarchy.compound || null;
  const buildingCode = hierarchy.building || null;

  const checks = await Promise.all([
    blockCode
      ? repo.isScopeManager({
          scopeType: "block",
          scopeCode: blockCode,
          userId: targetUser.id,
        })
      : Promise.resolve(false),
    compoundCode
      ? repo.isScopeManager({
          scopeType: "compound",
          scopeCode: compoundCode,
          userId: targetUser.id,
        })
      : Promise.resolve(false),
    buildingCode
      ? repo.isScopeManager({
          scopeType: "building",
          scopeCode: buildingCode,
          userId: targetUser.id,
        })
      : Promise.resolve(false),
  ]);

  return {
    canManage: true,
    role: targetUser.role || "user",
    accountDisabled: targetUser.is_account_disabled === true,
    targetIsSuperAdmin: targetUser.is_super_admin === true,
    hierarchy: {
      block: blockCode,
      compound: compoundCode,
      building: buildingCode,
      apartment: hierarchy.apartment || null,
    },
    managers: {
      block: checks[0] === true,
      compound: checks[1] === true,
      building: checks[2] === true,
    },
  };
}

async function resolveScopeAccess({ userId, userRole, scopeType, scopeCode }) {
  const normalizedScope = normalizeCommunityScope(scopeType, scopeCode);
  if (!normalizedScope.ok) {
    throw new AppError("COMMUNITY_SCOPE_INVALID", {
      status: 400,
      details: { fields: normalizedScope.errors || ["scopeType", "scopeCode"] },
    });
  }

  const viewer = await repo.findUserAddressMeta(userId);
  if (!viewer) throw new AppError("USER_NOT_FOUND", { status: 404 });
  if (viewer.is_account_disabled === true) {
    throw new AppError("ACCOUNT_DISABLED", { status: 403 });
  }

  const viewerRole = String(userRole || viewer.role || "")
    .trim()
    .toLowerCase();
  const isAdmin = isSuperAdminUser(viewer) || isCommunityAdminRole(viewerRole);
  if (!isAdmin && isCommunityUnsupportedRole(viewerRole)) {
    throw new AppError("COMMUNITY_ROLE_UNSUPPORTED", { status: 403 });
  }
  const viewerHierarchy = hierarchyFromUserRow(viewer);

  if (!isAdmin) {
    const allowed = doesHierarchyMatchScope(
      viewerHierarchy,
      normalizedScope.scopeType,
      normalizedScope.scopeCode
    );
    if (!allowed) {
      throw new AppError("COMMUNITY_SCOPE_FORBIDDEN", { status: 403 });
    }
    const removed = await repo.isScopeMemberRemoved({
      scopeType: normalizedScope.scopeType,
      scopeCode: normalizedScope.scopeCode,
      userId,
    });
    if (removed) {
      throw new AppError("COMMUNITY_MEMBER_REMOVED", { status: 403 });
    }
  }

  const base = buildScopeMeta(
    normalizedScope.scopeType,
    normalizedScope.scopeCode
  );
  return {
    ...base,
    isAdmin,
    viewer,
    viewerRole,
    viewerHierarchy,
  };
}

async function resolveCommunityPermissions({
  scopeType,
  scopeCode,
  userId,
  isAdmin,
}) {
  if (isAdmin) {
    return {
      isManager: true,
      canManageAnnouncements: true,
      canManageChat: true,
      canManageBills: true,
      canManageManagers: true,
    };
  }
  const isManager = await repo.isScopeManager({ scopeType, scopeCode, userId });
  return {
    isManager,
    canManageAnnouncements: isManager,
    canManageChat: isManager,
    canManageBills: isManager,
    canManageManagers: false,
  };
}

async function ensureScopeManagerAction({
  scopeType,
  scopeCode,
  userId,
  isAdmin,
  errorCode = "COMMUNITY_MANAGER_REQUIRED",
}) {
  if (isAdmin) return true;
  const allowed = await repo.isScopeManager({ scopeType, scopeCode, userId });
  if (!allowed) {
    throw new AppError(errorCode, { status: 403 });
  }
  return true;
}

function resolveMediaKindFromMime(mimeType) {
  const mime = String(mimeType || "").toLowerCase();
  if (!mime) return null;
  if (mime.startsWith("image/")) return "image";
  if (mime.startsWith("video/")) return "video";
  if (mime.startsWith("audio/")) return "audio";
  return null;
}

function resolveChatAttachmentKind({
  mimeType,
  url,
  name,
}) {
  const fromMime = resolveMediaKindFromMime(mimeType);
  if (fromMime) return fromMime;
  const source = `${name || ""} ${url || ""}`.toLowerCase();
  if (/\.(jpg|jpeg|png|webp|gif)\b/.test(source)) return "image";
  if (/\.(mp4|mov|webm|mkv|3gp)\b/.test(source)) return "video";
  if (/\.(m4a|aac|mp3|wav|ogg|opus|webm)\b/.test(source)) return "audio";
  return "file";
}

function buildChatAttachmentPreviewLabel(attachment) {
  if (!attachment) return "";
  const kind = String(attachment.kind || "").trim().toLowerCase();
  const name = String(attachment.name || "").trim();
  if (name) return name;
  if (kind === "image") return "\u0635\u0648\u0631\u0629";
  if (kind === "video") return "\u0641\u064A\u062F\u064A\u0648";
  if (kind === "audio") return "\u0631\u0633\u0627\u0644\u0629 \u0635\u0648\u062A\u064A\u0629";
  return "\u0645\u0644\u0641";
}

function compactMessagePreview(value, attachment = null, sharedEntity = null) {
  const text = String(value || "").trim().replace(/\s+/g, " ");
  if (text.length > 0) {
    if (text.length <= 80) return text;
    return `${text.slice(0, 80)}...`;
  }
  const attachmentLabel = buildChatAttachmentPreviewLabel(attachment);
  if (attachmentLabel) {
    return `\u0623\u0631\u0633\u0644 ${attachmentLabel}`;
  }
  const sharedType = String(sharedEntity?.type || "").trim().toLowerCase();
  if (sharedType === "location") {
    return "\u0623\u0631\u0633\u0644 \u0645\u0648\u0642\u0639\u064b\u0627";
  }
  if (sharedType) {
    return "\u0631\u0633\u0627\u0644\u0629 \u0645\u0634\u0627\u0631\u0643\u0629";
  }
  return "\u0631\u0633\u0627\u0644\u0629 \u062C\u062F\u064A\u062F\u0629";
}

function buildFriendshipWelcomeBody({ userFullName, otherFullName }) {
  const first = String(userFullName || "").trim() || "مستخدم";
  const second = String(otherFullName || "").trim() || "مستخدم";
  return `رسالة من التطبيق: مرحباً ${first}، لقد أصبحت أنت و${second} أصدقاء.`;
}

async function sendFriendshipWelcomeMessage({ userId, otherUserId }) {
  try {
    const [user, other] = await Promise.all([
      repo.findUserPublicProfile(userId),
      repo.findUserPublicProfile(otherUserId),
    ]);
    if (!user || !other) return;

    const thread = await repo.createOrGetThread({
      userAId: userId,
      userBId: otherUserId,
    });
    if (!thread?.id) return;

    const threadId = Number(thread.id);
    const body = buildFriendshipWelcomeBody({
      userFullName: user.full_name,
      otherFullName: other.full_name,
    });
    const inserted = await repo.insertThreadMessage({
      threadId,
      senderUserId: Number(userId),
      body,
    });
    if (!inserted) return;

    await repo.touchThreadLastMessage(threadId);
    const mapped = mapMessageRow(
      {
        ...inserted,
        sender_full_name: user.full_name || "",
        sender_image_url: user.image_url || null,
        sender_phone: user.phone || "",
        sender_role: user.role || "user",
      },
      Number(userId)
    );

    emitToUser(Number(userId), "social_chat_message", {
      threadId,
      message: mapped,
    });
    emitToUser(Number(otherUserId), "social_chat_message", {
      threadId,
      message: mapped,
    });
  } catch (error) {
    console.warn("[feed] failed to create friendship welcome message", error?.message || error);
  }
}

function dispatchStoryNotifications({ audienceUserIds, actor, story }) {
  if (!Array.isArray(audienceUserIds) || audienceUserIds.length <= 0) return;
  setImmediate(async () => {
    try {
      const actorName = actor?.full_name || "مستخدم";
      const actorId = Number(actor?.id || story.userId || 0);
      await createManyNotifications(
        audienceUserIds.map((userId) => ({
          userId: Number(userId),
          type: "social.story.new",
          title: "ستوري جديدة في مَسْلَكي",
          body: `${actorName} نشر ستوري جديدة`,
          payload: {
            storyId: Number(story.id),
            actorUserId: actorId > 0 ? actorId : null,
            target: "social_story",
          },
        }))
      );
    } catch (error) {
      console.error("Failed to dispatch story notifications", error);
    }
  });
}

function dispatchPostNotifications({ audienceUserIds, actor, post }) {
  if (!Array.isArray(audienceUserIds) || audienceUserIds.length <= 0) return;
  setImmediate(async () => {
    try {
      const actorName = actor?.full_name || "User";
      const actorId = Number(actor?.id || post.userId || 0);
      const isReel = isReelPostKind(post?.postKind ?? post?.post_kind);
      await createManyNotifications(
        audienceUserIds.map((userId) => ({
          userId: Number(userId),
          type: isReel ? "social.reel.new" : "social.post.new",
          title: isReel ? "New reel on Maslaki" : "New post on Maslaki",
          body: isReel
            ? `${actorName} posted a new reel`
            : `${actorName} posted new content`,
          payload: buildPostNotificationPayload({
            post,
            postId: Number(post.id),
            actorUserId: actorId,
          }),
        }))
      );
    } catch (error) {
      console.error("Failed to dispatch post notifications", error);
    }
  });
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
  const hasOrderAccess = await repo.hasActiveOrderChatAccess({
    userId,
    otherUserId,
  });
  if (mapped.state !== "accepted" && !hasOrderAccess) {
    throw new AppError("RELATION_REQUIRED", {
      status: 403,
      details: { relation: mapped },
    });
  }
  return mapped;
}

async function resolveMessagingAccess({ userId, otherUserId }) {
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
  const hasOrderAccess = await repo.hasActiveOrderChatAccess({
    userId,
    otherUserId,
  });
  const isPrimary = mapped.state === "accepted" || hasOrderAccess;
  return {
    relation: mapped,
    hasOrderAccess,
    isPrimary,
  };
}

function resolveBusinessContextStatus(contextType, listing) {
  const normalizedType = normalizeThreadContextType(contextType);
  if (!listing) return "unavailable";
  if (
    normalizedType === "service_offering" ||
    normalizedType === "service_provider" ||
    normalizedType === "service_request"
  ) {
    return String(listing.status || "unavailable").trim().toLowerCase();
  }
  const status = String(listing.status || "").trim().toLowerCase();
  if (status === "active") return "active";
  if (status === "sold") return "sold";
  if (normalizedType === "real_estate_listing" && status === "rented") {
    return "rented";
  }
  if (status === "archived") return "archived";
  return status || "unavailable";
}

function resolveListingPreviewImage(listing) {
  const media = Array.isArray(listing?.media) ? listing.media : [];
  for (const item of media) {
    const imageUrl = String(item?.imageUrl || item?.url || "").trim();
    if (imageUrl) return imageUrl;
  }
  return null;
}

function buildBusinessContextSnapshot({ contextType, listing }) {
  const normalizedType = normalizeThreadContextType(contextType);
  const status = resolveBusinessContextStatus(normalizedType, listing);
  if (normalizedType === "service_offering") {
    return {
      type: normalizedType,
      id: Number(listing.id),
      ownerId: Number(listing.ownerUserId),
      title: listing.title || "",
      subtitle: listing.subtitle || listing.city || "",
      price: null,
      status,
      imageUrl: null,
      posterUrl: null,
      city: listing.city || null,
    };
  }
  if (normalizedType === "service_provider") {
    return {
      type: normalizedType,
      id: Number(listing.id),
      ownerId: Number(listing.ownerUserId),
      title: listing.title || "",
      subtitle: listing.subtitle || listing.city || "",
      price: null,
      status,
      imageUrl: null,
      posterUrl: null,
      city: listing.city || null,
    };
  }
  if (normalizedType === "service_request") {
    return {
      type: normalizedType,
      id: Number(listing.id),
      ownerId: Number(listing.providerUserId),
      title: listing.title || "",
      subtitle: listing.subtitle || listing.city || "",
      price: null,
      status,
      imageUrl: null,
      posterUrl: null,
      city: listing.city || null,
      customerUserId: Number(listing.customerUserId || 0) || null,
    };
  }
  if (normalizedType === "car_listing") {
    return {
      type: normalizedType,
      id: Number(listing.id),
      ownerId: Number(listing.ownerId),
      title: listing.title || "",
      subtitle:
        [
          String(listing.brand || "").trim(),
          String(listing.model || "").trim(),
          Number(listing.modelYear || 0) > 0 ? String(listing.modelYear) : "",
        ].filter(Boolean).join(" ") || String(listing.city || "").trim(),
      price: Number(listing.price || 0),
      status,
      imageUrl: resolveListingPreviewImage(listing),
      posterUrl: resolveListingPreviewImage(listing),
      city: listing.city || null,
    };
  }
  return {
    type: normalizedType,
    id: Number(listing.id),
    ownerId: Number(listing.ownerId),
    title: listing.title || "",
    subtitle:
      [
        String(listing.purpose || "").trim(),
        String(listing.city || "").trim(),
        String(listing.block || "").trim(),
      ].filter(Boolean).join(" • "),
    price: Number(listing.price || 0),
    status,
    imageUrl: resolveListingPreviewImage(listing),
    posterUrl: resolveListingPreviewImage(listing),
    city: listing.city || null,
    block: listing.block || null,
  };
}

function buildBusinessContextView({
  contextType,
  contextId,
  contextStatus,
  snapshot,
}) {
  const safeSnapshot = parseJsonObject(snapshot);
  return {
    type: normalizeThreadContextType(contextType),
    id: Number(contextId || safeSnapshot.id || 0),
    status: String(contextStatus || safeSnapshot.status || "unavailable")
      .trim()
      .toLowerCase(),
    isAvailable:
      String(contextStatus || safeSnapshot.status || "").trim().toLowerCase() ===
      "active",
    ownerId:
      safeSnapshot.ownerId == null ? null : Number(safeSnapshot.ownerId),
    title: safeSnapshot.title || "",
    subtitle: safeSnapshot.subtitle || null,
    price:
      safeSnapshot.price == null ? null : Number(safeSnapshot.price || 0),
    imageUrl: safeSnapshot.imageUrl || safeSnapshot.posterUrl || null,
    posterUrl: safeSnapshot.posterUrl || safeSnapshot.imageUrl || null,
  };
}

async function resolveBusinessThreadSeed({ userId, otherUserId, context }) {
  const contextType = normalizeThreadContextType(context?.type);
  const contextId = Number(context?.id || 0);
  if (contextType === "none" || contextId <= 0) {
    throw new AppError("THREAD_CONTEXT_REQUIRED", {
      status: 400,
      details: { fields: ["contextType", "contextId"] },
    });
  }

  let listing = null;
  if (contextType === "car_listing") {
    listing = await carsRepo.getListingById(contextId, { viewerUserId: userId });
  } else if (contextType === "real_estate_listing") {
    listing = await realEstateRepo.getListingById(contextId, {
      viewerUserId: userId,
    });
  } else if (contextType === "service_offering") {
    listing = await servicesRepo.getServiceOfferingByIdForContext(contextId);
  } else if (contextType === "service_provider") {
    listing = await servicesRepo.getServiceProviderByIdForContext(contextId);
  } else if (contextType === "service_request") {
    listing = await servicesRepo.getServiceRequestByIdForContext(contextId);
  }

  if (!listing) {
    throw new AppError("LISTING_NOT_AVAILABLE", {
      status: 404,
      details: { fields: ["contextId"] },
    });
  }
  if (contextType === "service_request") {
    const providerUserId = Number(listing.providerUserId || 0);
    const customerUserId = Number(listing.customerUserId || 0);
    const participants = new Set([providerUserId, customerUserId]);
    if (!participants.has(Number(userId)) || !participants.has(Number(otherUserId))) {
      throw new AppError("THREAD_CONTEXT_OWNER_MISMATCH", {
        status: 409,
        details: { fields: ["userId", "contextId"] },
      });
    }
  } else if (Number(listing.ownerId) !== Number(otherUserId)) {
    throw new AppError("THREAD_CONTEXT_OWNER_MISMATCH", {
      status: 409,
      details: { fields: ["userId", "contextId"] },
    });
  }

  const snapshot = buildBusinessContextSnapshot({
    contextType,
    listing,
  });
  return {
    contextType,
    contextId,
    contextStatus: resolveBusinessContextStatus(contextType, listing),
    contextSnapshot: snapshot,
  };
}

async function hydrateBusinessThreadContext(row) {
  const threadKind = normalizeThreadKind(row?.thread_kind);
  if (threadKind !== "business") {
    return row;
  }
  const contextType = normalizeThreadContextType(row?.context_type);
  const contextId = Number(row?.context_id || 0);
  const snapshot = parseJsonObject(row?.context_snapshot_json);
  const ownerId =
    snapshot.ownerId == null ? null : Number(snapshot.ownerId || 0);

  let nextSnapshot = snapshot;
  let nextStatus = String(row?.context_status || snapshot.status || "unavailable")
    .trim()
    .toLowerCase();

  if (ownerId != null && ownerId > 0 && contextId > 0) {
    try {
      let listing = null;
      if (contextType === "car_listing") {
        listing = await carsRepo.getListingById(contextId, { viewerUserId: ownerId });
      } else if (contextType === "real_estate_listing") {
        listing = await realEstateRepo.getListingById(contextId, {
          viewerUserId: ownerId,
        });
      } else if (contextType === "service_offering") {
        listing = await servicesRepo.getServiceOfferingByIdForContext(contextId);
      } else if (contextType === "service_provider") {
        listing = await servicesRepo.getServiceProviderByIdForContext(contextId);
      } else if (contextType === "service_request") {
        listing = await servicesRepo.getServiceRequestByIdForContext(contextId);
      }
      if (listing) {
        nextSnapshot = buildBusinessContextSnapshot({ contextType, listing });
        nextStatus = resolveBusinessContextStatus(contextType, listing);
      } else if (!nextStatus || nextStatus === "active") {
        nextStatus = "unavailable";
      }
    } catch {
      // keep stored snapshot when live refresh fails
    }
  }

  return {
    ...row,
    context_status: nextStatus,
    context_snapshot_json: nextSnapshot,
    context: buildBusinessContextView({
      contextType,
      contextId,
      contextStatus: nextStatus,
      snapshot: nextSnapshot,
    }),
  };
}

async function hydrateBusinessThreadRows(rows) {
  return Promise.all(
    (Array.isArray(rows) ? rows : []).map((row) => hydrateBusinessThreadContext(row))
  );
}

export async function listUserPosts(viewerUserId, userId, query) {
  const access = await resolveProfileAccess({
    viewerUserId,
    ownerUserId: userId,
  });
  const owner = access.owner;
  const privateForViewer =
    !access.hasPrivateAccess ||
    !canViewPosts({
      viewerUserId,
      owner,
      viewerIsSuperAdmin: access.viewerIsSuperAdmin,
    });
  const viewerScopeCodes = privateForViewer
    ? { blockCode: null, compoundCode: null, buildingCode: null }
    : await resolveViewerScopeCodes(viewerUserId);

  const rows = privateForViewer
    ? []
    : await repo.listUserFeedPosts({
        viewerUserId,
        userId,
        viewerBlockCode: viewerScopeCodes.blockCode,
        viewerCompoundCode: viewerScopeCodes.compoundCode,
        viewerBuildingCode: viewerScopeCodes.buildingCode,
        limit: query.limit,
        beforeId: query.beforeId,
        postKind: normalizeRequestedPostKind(query.kind),
      });
  const enrichedRows = await attachPostMediaRows(rows);
  return {
    user: {
      id: Number(owner.id),
      username: owner.username || null,
      fullName: owner.full_name || "",
      imageUrl: owner.image_url || null,
      role: owner.role || "user",
      phone: canViewPhone({ viewerUserId, owner }) ? owner.phone || "" : "",
      privacy: {
        showPhone: owner.social_show_phone === true,
        accountPrivate: owner.social_account_private === true,
        postsPublic: owner.social_posts_public === true,
        storiesPublic: owner.social_stories_public === true,
        relationsPublic: owner.social_relations_public === true,
      },
    },
    postsPrivate: privateForViewer,
    posts: enrichedRows.map(mapPostRow),
    nextCursor:
      enrichedRows.length > 0
        ? Number(enrichedRows[enrichedRows.length - 1].id)
        : null,
  };
}

export async function listMyReportedPosts({ userId, query = {} }) {
  const rows = await repo.listMyReportedPosts({
    userId,
    limit: query.limit,
    beforeId: query.beforeId,
  });

  const enrichedRows = await attachPostMediaRows(rows);
  return {
    posts: enrichedRows.map(mapPostRow),
    nextCursor:
      enrichedRows.length > 0
        ? Number(enrichedRows[enrichedRows.length - 1].id)
        : null,
  };
}

export async function listMyReportedStories({ userId, query = {} }) {
  const rows = await repo.listMyReportedStories({
    userId,
    limit: query.limit,
    beforeId: query.beforeId,
  });

  return {
    stories: rows.map((row) => mapStoryRow(row, userId)),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function getUserProfile(viewerUserId, userId) {
  const access = await resolveProfileAccess({
    viewerUserId,
    ownerUserId: userId,
  });
  const viewer = access.viewer;
  const profile = access.owner;
  if (viewer.is_account_disabled === true) {
    throw new AppError("ACCOUNT_DISABLED", { status: 403 });
  }
  const isMe = access.isOwner;
  const viewerIsSuperAdmin = access.viewerIsSuperAdmin;
  const canSuperAdminManage = viewerIsSuperAdmin && !isMe;
  const phoneVisible = canViewPhone({ viewerUserId, owner: profile });
  const [
    stats,
    relationRow,
    relationStats,
    preferenceRow,
    superAdminControls,
    premiumActive,
    carSellerActive,
    propertySellerActive,
    savedCount,
    taggedCount,
    coreChangeRequest,
  ] =
    await Promise.all([
      repo.getUserSocialStats(userId),
      Promise.resolve(access.relationRow),
      repo.getUserRelationStats(userId),
      isMe
        ? Promise.resolve(null)
        : repo.getUserNotificationPreference({
            userId: viewerUserId,
            actorUserId: userId,
          }),
      canSuperAdminManage
        ? buildSuperAdminControlsForTarget(profile)
        : Promise.resolve(null),
      hasPaidUpgrade(userId, "premium_monthly").catch(() => false),
      hasPaidUpgrade(userId, "car_seller_monthly").catch(() => false),
      hasPaidUpgrade(userId, "property_seller_monthly").catch(() => false),
      isMe ? repo.countSavedItemsByUser(userId).catch(() => 0) : Promise.resolve(0),
      repo.countTaggedPostsByUser(userId).catch(() => 0),
      isMe
        ? repo.findLatestProfileCoreChangeRequestByUser(userId).catch(() => null)
        : Promise.resolve(null),
    ]);
  const relation = mapRelationRow(relationRow, viewerUserId, userId);
  const viewerScopes = viewerScopeCodesFromUserRow(viewer);
  const profileScopes = viewerScopeCodesFromUserRow(profile);
  const localContextMeta =
    viewerScopes.buildingCode && viewerScopes.buildingCode === profileScopes.buildingCode
      ? { type: "same_building", code: profileScopes.buildingCode }
      : viewerScopes.compoundCode && viewerScopes.compoundCode === profileScopes.compoundCode
        ? { type: "same_compound", code: profileScopes.compoundCode }
        : viewerScopes.blockCode && viewerScopes.blockCode === profileScopes.blockCode
          ? { type: "same_block", code: profileScopes.blockCode }
          : null;
  const isResidentVerified =
    String(profile.block || "").trim().length > 0 &&
    String(profile.building_number || "").trim().length > 0;
  const isMerchantVerified = String(profile.role || "").trim().toLowerCase() === "owner";
  const badges = buildProfileBadgeKeys({
    isResidentVerified,
    isMerchantVerified,
    isPremiumMember: premiumActive === true,
    isCarSeller: carSellerActive === true,
    isPropertySeller: propertySellerActive === true,
  });
  const accountLabelKey = premiumActive === true ? "premium_member" : "user";
  return {
    profile: {
      id: Number(profile.id),
      username: profile.username || null,
      fullName: profile.full_name || "",
      imageUrl: profile.image_url || null,
      bio: profile.social_bio || "",
      workTitle: profile.work_title || null,
      workCompany: profile.work_company || null,
      age:
        profile.social_age == null || !Number.isFinite(Number(profile.social_age))
          ? null
          : Number(profile.social_age),
      preferredLocale: profile.preferred_locale || "ar",
      phone: phoneVisible ? profile.phone || "" : "",
      role: profile.role || "user",
      isSuperAdmin: profile.is_super_admin === true,
      accountDisabled: profile.is_account_disabled === true,
      joinedAt: profile.created_at || null,
      coreProfileLockedUntil: null,
      coreProfileChangeRequest:
        isMe && coreChangeRequest
          ? mapProfileCoreChangeRequestRow(coreChangeRequest)
          : null,
      isMe,
      viewerIsSuperAdmin,
      privacy: {
        showPhone: profile.social_show_phone === true,
        accountPrivate: profile.social_account_private === true,
        postsPublic: profile.social_posts_public === true,
        storiesPublic: profile.social_stories_public === true,
        relationsPublic: profile.social_relations_public === true,
        onlineStatusVisibility: profile.social_online_visibility || "connections",
        lastSeenVisibility: profile.social_last_seen_visibility || "connections",
        readReceiptsEnabled: profile.social_read_receipts_enabled !== false,
        typingIndicatorsEnabled: profile.social_typing_indicators_enabled !== false,
      },
      contentPrivate: access.privateAccount === true && access.hasPrivateAccess !== true,
      notificationPreference: isMe
        ? null
        : mapNotificationPreferenceRow(preferenceRow),
      superAdminControls: canSuperAdminManage ? superAdminControls : null,
      relation,
      localContext: mapLocalContextLabel(localContextMeta),
      localContextMeta,
      accountLabelKey,
      isResidentVerified,
      isMerchantVerified,
      isPremiumMember: premiumActive === true,
      isCarSeller: carSellerActive === true,
      isPropertySeller: propertySellerActive === true,
      premiumBadgeVisible: premiumActive === true,
      badges,
      tabs: {
        posts: Number(stats.total_posts || 0),
        reels: Number(stats.video_posts || 0),
        tagged: Number(taggedCount || 0),
        saved: isMe ? Number(savedCount || 0) : 0,
        reviews: Number(stats.review_posts || 0),
        insights:
          isMe || viewerIsSuperAdmin || premiumActive === true ? 1 : 0,
      },
      stats: {
        totalPosts: Number(stats.total_posts || 0),
        imagePosts: Number(stats.image_posts || 0),
        videoPosts: Number(stats.video_posts || 0),
        reviewPosts: Number(stats.review_posts || 0),
        likesGiven: Number(stats.likes_given || 0),
        commentsMade: Number(stats.comments_made || 0),
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
    dto.username === undefined &&
    dto.fullName === undefined &&
    dto.bio === undefined &&
    dto.age === undefined &&
    dto.imageUrl === undefined &&
    dto.workTitle === undefined &&
    dto.workCompany === undefined &&
    dto.showPhone === undefined &&
    dto.accountPrivate === undefined &&
    dto.postsPublic === undefined &&
    dto.storiesPublic === undefined &&
    dto.relationsPublic === undefined &&
    dto.onlineStatusVisibility === undefined &&
    dto.lastSeenVisibility === undefined &&
    dto.readReceiptsEnabled === undefined &&
    dto.typingIndicatorsEnabled === undefined &&
    dto.preferredLocale === undefined
  ) {
    throw new AppError("NO_CHANGES", { status: 400 });
  }

  if (dto.fullName) {
    assertContentAllowed(dto.fullName);
  }
  if (dto.username !== undefined) {
    dto.username = assertUsernameValid(dto.username);
    const taken = await repo.isUsernameTaken({
      username: dto.username,
      excludeUserId: userId,
    });
    if (taken) {
      throw new AppError("USERNAME_TAKEN", {
        status: 409,
        details: { fields: ["username"] },
      });
    }
  }
  if (dto.bio) {
    assertContentAllowed(dto.bio);
  }

  const identityFieldsTouched = [
    dto.fullName,
    dto.username,
  ].some((value) => value !== undefined);
  let coreChangeRequest = null;
  if (identityFieldsTouched) {
    const current = await repo.findUserSocialProfile(userId);
    if (!current) {
      throw new AppError("USER_NOT_FOUND", { status: 404 });
    }
    const currentSnapshot = {
      fullName: String(current.full_name || "").trim() || null,
      username: String(current.username || "")
        .trim()
        .toLowerCase() || null,
    };
    const requestedSnapshot = {
      fullName:
        dto.fullName !== undefined
          ? String(dto.fullName || "").trim() || null
          : currentSnapshot.fullName,
      username:
        dto.username !== undefined
          ? String(dto.username || "").trim().toLowerCase() || null
          : currentSnapshot.username,
    };
    const hasCoreDiff =
      requestedSnapshot.fullName !== currentSnapshot.fullName ||
      requestedSnapshot.username !== currentSnapshot.username;
    if (hasCoreDiff) {
      const pending = await repo.findPendingProfileCoreChangeRequestByUser(userId);
      coreChangeRequest = pending
        ? await repo.updatePendingProfileCoreChangeRequest({
            requestId: Number(pending.id),
            userId,
            currentSnapshotJson: currentSnapshot,
            requestedSnapshotJson: requestedSnapshot,
          })
        : await repo.createProfileCoreChangeRequest({
            userId,
            currentSnapshotJson: currentSnapshot,
            requestedSnapshotJson: requestedSnapshot,
          });

      if (coreChangeRequest) {
        const adminIds = await repo.listSuperAdminUserIds(240);
        await createManyNotifications(
          adminIds
            .filter((adminId) => Number(adminId) !== Number(userId))
            .map((adminId) => ({
              userId: Number(adminId),
              type: "profile.change.request_submitted",
              title: "طلب تعديل بيانات أساسية",
              body: "يوجد طلب بانتظار مراجعة تعديل الاسم أو اسم المستخدم.",
              payload: {
                requestId: Number(coreChangeRequest.id),
                userId: Number(userId),
                target: "admin_profile_change_requests",
              },
            }))
        );
      }
    }

    // Core identity fields now follow admin approval flow.
    dto.fullName = undefined;
    dto.username = undefined;
  }

  const updated = await repo.updateUserSocialProfile({
    userId,
    username: dto.username,
    fullName: dto.fullName,
    bio: dto.bio,
    age: dto.age,
    imageUrl: dto.imageUrl,
    workTitle: dto.workTitle,
    workCompany: dto.workCompany,
    showPhone: dto.showPhone,
    accountPrivate: dto.accountPrivate,
    postsPublic: dto.postsPublic,
    storiesPublic: dto.storiesPublic,
    relationsPublic: dto.relationsPublic,
    onlineStatusVisibility: dto.onlineStatusVisibility,
    lastSeenVisibility: dto.lastSeenVisibility,
    readReceiptsEnabled: dto.readReceiptsEnabled,
    typingIndicatorsEnabled: dto.typingIndicatorsEnabled,
    preferredLocale: dto.preferredLocale,
    touchCoreProfileUpdateAt: false,
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
      username: updated.username || null,
      fullName: updated.full_name || "",
      imageUrl: updated.image_url || null,
      bio: updated.social_bio || "",
      workTitle: updated.work_title || null,
      workCompany: updated.work_company || null,
      age:
        updated.social_age == null || !Number.isFinite(Number(updated.social_age))
          ? null
          : Number(updated.social_age),
      preferredLocale: updated.preferred_locale || "ar",
      phone: updated.phone || "",
      role: updated.role || "user",
      joinedAt: updated.created_at || null,
      coreProfileLockedUntil: null,
      coreProfileChangeRequest: coreChangeRequest
        ? mapProfileCoreChangeRequestRow(coreChangeRequest)
        : null,
      isMe: true,
      privacy: {
        showPhone: updated.social_show_phone === true,
        accountPrivate: updated.social_account_private === true,
        postsPublic: updated.social_posts_public === true,
        storiesPublic: updated.social_stories_public === true,
        relationsPublic: updated.social_relations_public === true,
        onlineStatusVisibility: updated.social_online_visibility || "connections",
        lastSeenVisibility: updated.social_last_seen_visibility || "connections",
        readReceiptsEnabled: updated.social_read_receipts_enabled !== false,
        typingIndicatorsEnabled: updated.social_typing_indicators_enabled !== false,
      },
      relation: mapRelationRow(null, userId, userId),
      stats: {
        totalPosts: Number(stats.total_posts || 0),
        imagePosts: Number(stats.image_posts || 0),
        videoPosts: Number(stats.video_posts || 0),
        reviewPosts: Number(stats.review_posts || 0),
        likesGiven: Number(stats.likes_given || 0),
        commentsMade: Number(stats.comments_made || 0),
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

function mapCommunityMonitoredChatRow(row) {
  const scopeMeta = buildScopeMeta(row.scope_type, row.scope_code);
  const mutedUntil = row?.muted_until || null;
  const muted =
    mutedUntil != null && new Date(mutedUntil).getTime() > Date.now();
  const lastSender =
    row.last_message_sender_user_id == null
      ? null
      : {
          id: Number(row.last_message_sender_user_id),
          fullName: row.last_sender_full_name || "",
          phone: row.last_sender_phone || "",
          imageUrl: row.last_sender_image_url || null,
          role: row.last_sender_role || "user",
        };
  return {
    kind: "community",
    monitorKey: `community:${row.scope_type}:${row.scope_code}`,
    id: 0,
    threadId: null,
    scopeType: row.scope_type,
    scopeCode: row.scope_code,
    scopeTitle: scopeMeta.title,
    scopeSubtitle: scopeMeta.subtitle,
    participantLabel: scopeMeta.title,
    participants: lastSender ? [lastSender] : [],
    participantCount: Number(row.participant_count || 0),
    createdAt: null,
    updatedAt: null,
    lastMessageAt: row.last_message_created_at || null,
    lastMessage: row.last_message_id
      ? {
          id: Number(row.last_message_id),
          senderUserId: Number(row.last_message_sender_user_id),
          body: row.last_message_body || "",
          createdAt: row.last_message_created_at || null,
          attachment: null,
        }
      : null,
    state: {
      muted,
      mutedUntil,
      lastReadMessageId:
        row.last_read_message_id == null ? null : Number(row.last_read_message_id),
      lastDeliveredMessageId:
        row.last_delivered_message_id == null
          ? null
          : Number(row.last_delivered_message_id),
      unreadCount: Number(row.unread_count || 0),
    },
  };
}

export async function listUserHighlights(viewerUserId, userId) {
  const profile = await repo.findUserSocialProfile(userId);
  if (!profile) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  const access = await resolveProfileAccess({
    viewerUserId,
    ownerUserId: userId,
    owner: profile,
  });
  const privateForViewer =
    !access.hasPrivateAccess ||
    !canViewStories({
      viewerUserId,
      owner: access.owner,
      viewerIsSuperAdmin: access.viewerIsSuperAdmin,
    });

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

export async function listPosts(viewerUserId, query) {
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  const normalizedKind = normalizeRequestedPostKind(query.kind);
  const rows = await listRankedVisiblePosts({
    viewerUserId,
    query,
    viewerScopeCodes,
    kinds: normalizedKind ? [normalizedKind] : null,
    includeCommunityScoped: false,
  });
  await recordImpressionsForRows({
    viewerUserId,
    rows,
    context: "home_feed",
  });
  const enrichedRows = await attachPostMediaRows(rows);
  return {
    posts: enrichedRows.map(mapPostRow),
    nextCursor:
      enrichedRows.length > 0
        ? Number(enrichedRows[enrichedRows.length - 1].id)
        : null,
  };
}

export async function listExplore(viewerUserId, query) {
  const cacheKey = buildTransientFeedCacheKey("explore", viewerUserId, query);
  const cached = readTransientFeedCache(cacheKey);
  if (cached) return cached;
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  const out = await discoveryService.listExplore({
    viewerUserId,
    query,
    viewerScopeCodes,
  });
  await recordImpressionsForRows({
    viewerUserId,
    rows: out.sections?.forYou || [],
    context: "explore_for_you",
  });
  return writeTransientFeedCache(cacheKey, out);
}

export async function listTrending(viewerUserId, query) {
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  return discoveryService.listTrending({
    viewerUserId,
    query,
    viewerScopeCodes,
  });
}

export async function listExploreReels(viewerUserId, query) {
  const cacheKey = buildTransientFeedCacheKey("explore_reels", viewerUserId, query);
  const cached = readTransientFeedCache(cacheKey);
  if (cached) return cached;
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  const preferenceRows = await analyticsRepo.listViewerContentPreferenceSignals({
    viewerUserId,
  });
  const out = await reelsService.listExploreReels({
    viewerUserId,
    query,
    viewerScopeCodes,
    rankFeedRows,
    preferenceWeights: buildPreferenceWeightMap(preferenceRows),
  });
  await recordImpressionsForRows({
    viewerUserId,
    rows: out.reels || [],
    context: "reels_explore",
  });
  return writeTransientFeedCache(cacheKey, out);
}

export async function listSuggestedPeople(viewerUserId, query) {
  return recommendationsService.listSuggestedPeople({
    viewerUserId,
    limit: query.limit,
  });
}

export async function searchSocialCatalog(viewerUserId, query) {
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  return searchService.searchSocial({
    viewerUserId,
    query,
    viewerScopeCodes,
    searchUsers,
  });
}

export async function listHashtagPosts(viewerUserId, tag, query) {
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  return tagsService.listHashtagFeed({
    viewerUserId,
    tag,
    query,
    viewerScopeCodes,
  });
}

export async function listTrendingTags(query) {
  return tagsService.listTrendingHashtags({ limit: query.limit });
}

export async function listMentionUsers(viewerUserId, query) {
  return tagsService.listMentionSuggestions({
    viewerUserId,
    query,
    searchUsers,
  });
}

export async function listSavedCollectionsForUser(userId) {
  return savedService.listSavedCollections(userId);
}

export async function createSavedCollectionForUser(userId, dto) {
  return savedService.createSavedCollection(userId, dto);
}

export async function updateSavedCollectionForUser({ userId, collectionId, dto }) {
  return savedService.updateSavedCollection({ userId, collectionId, dto });
}

export async function deleteSavedCollectionForUser({ userId, collectionId }) {
  return savedService.deleteSavedCollection({ userId, collectionId });
}

export async function toggleSavedContentForUser({ userId, dto }) {
  const viewerScopeCodes = await resolveViewerScopeCodes(userId);
  return savedService.toggleSavedContent({ userId, dto, viewerScopeCodes });
}

export async function listSavedContentForUser(userId, query) {
  const viewerScopeCodes = await resolveViewerScopeCodes(userId);
  return savedService.listSavedContent({ userId, query, viewerScopeCodes });
}

export async function getSocialProfileInsights({ viewerUserId, targetUserId }) {
  const viewer = await repo.findUserAddressMeta(viewerUserId);
  if (!viewer) throw new AppError("USER_NOT_FOUND", { status: 404 });
  return insightsService.getProfileInsights({
    viewerUserId,
    targetUserId,
    isSuperAdmin: isSuperAdminUser(viewer),
  });
}

export async function listProfileReels(viewerUserId, userId, query) {
  return listUserPosts(viewerUserId, userId, { ...query, kind: "reel" });
}

export async function listProfileTaggedPosts(viewerUserId, userId, query) {
  const access = await resolveProfileAccess({
    viewerUserId,
    ownerUserId: userId,
  });
  if (!access.hasPrivateAccess) {
    return { posts: [] };
  }
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  return tagsService.listTaggedPosts({
    viewerUserId,
    targetUserId: userId,
    viewerScopeCodes,
    limit: query.limit,
  });
}

export async function createReel(userId, dto, media) {
  return createPost(userId, { ...dto, postKind: "reel" }, media);
}

export async function recordReelView({ viewerUserId, reelId, dto }) {
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  const visibleRows = await discoveryRepo.listVisiblePostsByIds({
    viewerUserId,
    viewerBlockCode: viewerScopeCodes.blockCode,
    viewerCompoundCode: viewerScopeCodes.compoundCode,
    viewerBuildingCode: viewerScopeCodes.buildingCode,
    postIds: [reelId],
  });
  if (
    visibleRows.length <= 0 ||
    String(visibleRows[0].post_kind || "").trim().toLowerCase() !== "reel"
  ) {
    throw new AppError("REEL_NOT_FOUND", { status: 404 });
  }
  return reelsService.recordReelView({
    viewerUserId,
    reelId,
    dto,
  });
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

export async function listMyArchivedPosts(userId, query) {
  const postKind = normalizeRequestedPostKind(query?.kind);
  const rows = await repo.listArchivedPostsRaw({
    viewerUserId: userId,
    ownerUserId: userId,
    beforeId: query?.beforeId ?? null,
    limit: query?.limit ?? 24,
    postKind,
  });
  const enrichedRows = await attachPostMediaRows(rows);
  return {
    posts: enrichedRows.map(mapPostRow),
    nextCursor:
      enrichedRows.length > 0
        ? Number(enrichedRows[enrichedRows.length - 1].id)
        : null,
  };
}

export async function setPostArchivedState({
  userId,
  postId,
  archived,
}) {
  const existing = await repo.findPostByIdForViewer({
    postId,
    viewerUserId: userId,
    includeArchivedForOwner: true,
  });
  if (!existing || Number(existing.user_id) !== Number(userId)) {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const updated = await repo.setPostArchivedState({ postId, userId, archived });
  if (!updated?.id) {
    throw new AppError("POST_ARCHIVE_UPDATE_FAILED", { status: 500 });
  }
  const mappedRow = await repo.findPostByIdForViewer({
    postId,
    viewerUserId: userId,
    includeArchivedForOwner: true,
  });
  const enrichedRow = await attachPostMediaRow(mappedRow);
  return {
    ok: true,
    archived: archived === true,
    post: enrichedRow ? mapPostRow(enrichedRow) : null,
  };
}

export async function deletePost({ userId, postId }) {
  const existing = await repo.findPostByIdForViewer({
    postId,
    viewerUserId: userId,
    includeArchivedForOwner: true,
  });
  if (!existing || Number(existing.user_id) !== Number(userId)) {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const deleted = await repo.softDeletePost({ postId, userId });
  if (!deleted?.id) {
    throw new AppError("POST_DELETE_FAILED", { status: 500 });
  }
  return {
    ok: true,
    postId: Number(postId),
  };
}

export async function setStoryArchivedState({
  userId,
  storyId,
  archived,
}) {
  const existing = await repo.findStoryById({
    viewerUserId: userId,
    storyId,
    includeArchivedForOwner: true,
  });
  if (!existing || Number(existing.user_id) !== Number(userId)) {
    throw new AppError("STORY_NOT_FOUND", { status: 404 });
  }
  const updated = await repo.setStoryArchivedState({ storyId, userId, archived });
  if (!updated?.id) {
    throw new AppError("STORY_ARCHIVE_UPDATE_FAILED", { status: 500 });
  }
  const mappedRow = await repo.findStoryById({
    viewerUserId: userId,
    storyId,
    includeArchivedForOwner: true,
  });
  return {
    ok: true,
    archived: archived === true,
    story: mappedRow ? mapStoryRow(mappedRow, userId) : null,
  };
}

export async function getPostById(viewerUserId, postId) {
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  let row = await repo.findFeedPostById({
    viewerUserId,
    postId,
    viewerBlockCode: viewerScopeCodes.blockCode,
    viewerCompoundCode: viewerScopeCodes.compoundCode,
    viewerBuildingCode: viewerScopeCodes.buildingCode,
  });
  if (!row) {
    const archivedOwnerRow = await repo.findPostByIdForViewer({
      postId,
      viewerUserId,
      includeArchivedForOwner: true,
    });
    if (archivedOwnerRow && Number(archivedOwnerRow.user_id) === Number(viewerUserId)) {
      row = archivedOwnerRow;
    }
  }
  if (!row) {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const access = await resolveProfileAccess({
    viewerUserId,
    ownerUserId: Number(row.user_id),
  });
  if (!access.hasPrivateAccess) {
    throw new AppError("POST_NOT_AVAILABLE", { status: 403 });
  }
  if (!row.archived_by_owner_at) {
    await recordImpressionsForRows({
      viewerUserId,
      rows: [row],
      context: "post_detail",
    });
  }
  return { post: mapPostRow(await attachPostMediaRow(row)) };
}

export async function getReelById(viewerUserId, reelId) {
  const out = await getPostById(viewerUserId, reelId);
  if (!isReelPostKind(out?.post?.postKind)) {
    throw new AppError("REEL_NOT_FOUND", { status: 404 });
  }
  return { reel: out.post };
}

export async function createPost(userId, dto, media) {
  await assertSocialWriteAllowed(
    userId,
    resolvePostCapabilityKey({
      postKind: dto?.postKind,
      audienceScopeType: dto?.audienceScopeType,
    })
  );
  assertContentAllowed(dto.caption || "");
  const [actor, actorAddress] = await Promise.all([
    repo.findUserPublicProfile(userId),
    repo.findUserAddressMeta(userId),
  ]);
  if (!actor || !actorAddress) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  if (actorAddress.is_account_disabled === true) {
    throw new AppError("ACCOUNT_DISABLED", { status: 403 });
  }

  const audienceScope = normalizePostAudienceScope(dto);
  const actorRole = String(actorAddress.role || "").trim().toLowerCase();
  const actorIsBackoffice =
    isSuperAdminUser(actorAddress) || isCommunityAdminRole(actorRole);
  if (audienceScope.scopeType !== "global" && !actorIsBackoffice) {
    const hierarchy = hierarchyFromUserRow(actorAddress);
    const allowed = doesHierarchyMatchScope(
      hierarchy,
      audienceScope.scopeType,
      audienceScope.scopeCode
    );
    if (!allowed) {
      throw new AppError("COMMUNITY_SCOPE_FORBIDDEN", { status: 403 });
    }
  }
  if (audienceScope.scopeType !== "global") {
    const isMutedInScope = await repo.isScopeChatUserBanned({
      scopeType: audienceScope.scopeType,
      scopeCode: audienceScope.scopeCode,
      userId,
    });
    const isRemovedInScope = await repo.isScopeMemberRemoved({
      scopeType: audienceScope.scopeType,
      scopeCode: audienceScope.scopeCode,
      userId,
    });
    if (isRemovedInScope) {
      throw new AppError("COMMUNITY_MEMBER_REMOVED", { status: 403 });
    }
    if (isMutedInScope) {
      throw new AppError("COMMUNITY_MEMBER_MUTED", { status: 403 });
    }
  }

  const uploadedMediaList = Array.isArray(media)
    ? media.filter((item) => item?.url)
    : media?.url
      ? [media]
      : [];
  const requestedPostKind = String(dto.postKind || "text").trim().toLowerCase();
  const requestedIsReel = requestedPostKind === "reel";
  if (requestedIsReel && uploadedMediaList.length > 1) {
    throw new AppError("REEL_SINGLE_MEDIA_ONLY", { status: 400 });
  }
  if (uploadedMediaList.length > 10) {
    throw new AppError("POST_MEDIA_LIMIT_EXCEEDED", { status: 400 });
  }
  const preparedMediaItems = [];
  for (const mediaItem of uploadedMediaList) {
    const uploadedMediaKind = resolveMediaKindFromMime(mediaItem?.mimetype);
    const preparedMedia = await mediaService.prepareSocialMediaAsset({
      userId,
      media: mediaItem,
      preferredKind: requestedIsReel ? "reel" : uploadedMediaKind,
      sourceType: requestedIsReel ? "reel" : "post",
    });
    preparedMediaItems.push(preparedMedia);
  }
  const primaryMedia = preparedMediaItems[0] || null;
  const mediaKind = primaryMedia?.mediaKind || null;
  const mediaUrl = primaryMedia?.mediaUrl || null;
  const contentLink = normalizeContentLinkPayload(dto);

  let postKind = dto.postKind;
  if (requestedIsReel) {
    postKind = "reel";
  } else if (preparedMediaItems.length > 0 && postKind !== "merchant_review") {
    const hasVideo = preparedMediaItems.some((item) => {
      const normalized = String(item?.mediaKind || "").trim().toLowerCase();
      return normalized === "video" || normalized === "reel";
    });
    postKind = hasVideo ? "video" : "image";
  }

  if (!mediaKind && (postKind === "image" || postKind === "video" || postKind === "reel")) {
    throw new AppError("MEDIA_REQUIRED", { status: 400 });
  }

  if (!dto.caption && preparedMediaItems.length <= 0 && postKind !== "merchant_review") {
    throw new AppError("EMPTY_POST", {
      status: 400,
      details: { fields: ["caption", "media"] },
    });
  }

  if (postKind === "merchant_review") {
    if (dto.merchantId == null || dto.reviewRating == null) {
      throw new AppError("MERCHANT_REVIEW_INCOMPLETE", { status: 400 });
    }
    const eligibility = await repo.getMerchantReviewEligibility({
      customerUserId: userId,
      merchantId: dto.merchantId,
    });
    if (eligibility?.can_review !== true) {
      throw new AppError("MERCHANT_REVIEW_ORDER_REQUIRED", { status: 403 });
    }
  }

  const inserted = await repo.insertPost({
    userId,
    postKind,
    caption: dto.caption,
    mediaUrl,
    mediaKind,
    mediaAssetId: primaryMedia?.mediaAssetId,
    merchantId: dto.merchantId,
    reviewRating: dto.reviewRating,
    audienceScopeType: audienceScope.scopeType,
    audienceScopeCode: audienceScope.scopeCode,
  });
  if (preparedMediaItems.length > 0) {
    await repo.replacePostMediaItems({
      postId: Number(inserted.id),
      items: preparedMediaItems.map((item) => ({
        mediaUrl: item.mediaUrl,
        mediaKind: item.mediaKind,
        mediaAssetId: item.mediaAssetId,
      })),
    });
  }
  if (contentLink) {
    await repo.replaceSocialContentLink({
      entityType: postKind === "reel" ? "reel" : "post",
      entityId: Number(inserted.id),
      ...contentLink,
    });
  }
  await tagsService.syncTagsAndMentionsForEntity({
    entityType: "post",
    entityId: Number(inserted.id),
    text: dto.caption || "",
    actorUserId: userId,
    notificationTarget: postKind === "reel" ? "social_reel" : "social_post",
  });
  await tagsService.syncExplicitContentTags({
    entityType: postKind === "reel" ? "reel" : "post",
    entityId: Number(inserted.id),
    taggedUserIds: dto.taggedUserIds || [],
    actorUserId: userId,
  });
  const created = await attachPostMediaRow(await repo.findPostById(inserted?.id));
  if (!created) throw new AppError("POST_CREATE_FAILED", { status: 500 });

  const mapped = mapPostRow({
    ...created,
    likes_count: 0,
    comments_count: 0,
    is_liked: false,
    merchant_name: created.merchant_name || null,
    merchant_type: created.merchant_type || null,
    merchant_image_url: created.merchant_image_url || null,
  });
  emitToUser(Number(userId), "social_post_created", { post: mapped });

  const isActorSuperAdmin = isSuperAdminUser(actor);
  if (audienceScope.scopeType === "global") {
    if (isActorSuperAdmin || actor?.social_posts_public === true) {
      const audienceUserIds = await repo.listAudienceUserIdsForActor({
        actorUserId: userId,
        broadcastToAll: isActorSuperAdmin,
        limit: isActorSuperAdmin ? 12000 : 6000,
      });
      dispatchPostNotifications({
        audienceUserIds,
        actor,
        post: mapped,
      });
    }
  } else {
    await notifyCommunityScopeUsers({
      scopeType: audienceScope.scopeType,
      scopeCode: audienceScope.scopeCode,
      type: "social.community.post.created",
      title: `منشور جديد في ${buildScopeMeta(audienceScope.scopeType, audienceScope.scopeCode).title}`,
      body: String(dto.caption || "").trim().slice(0, 180) || "تم نشر منشور جديد",
      excludeUserIds: [],
      payload: {
        postId: mapped.id,
        scopeType: audienceScope.scopeType,
        scopeCode: audienceScope.scopeCode,
      },
    });
  }

  const realtimeScopes = buildAudienceScopesForCommunityFeeds({
    scopeType: audienceScope.scopeType,
    scopeCode: audienceScope.scopeCode,
  });
  await Promise.all(
    realtimeScopes.map((scope) =>
      emitCommunityRealtimeEvent({
        scopeType: scope.scopeType,
        scopeCode: scope.scopeCode,
        event: "social_community_post_created",
        data: { post: mapped },
        excludeUserIds: [],
      })
    )
  );


  return mapped;
}

export async function createStory(userId, dto, media) {
  await assertSocialWriteAllowed(userId, "story_create");
  assertContentAllowed(dto.caption || "");

  const uploadedMediaKind = resolveMediaKindFromMime(media?.mimetype);
  const preparedMedia = await mediaService.prepareSocialMediaAsset({
    userId,
    media,
    preferredKind: uploadedMediaKind,
    sourceType: "story",
  });
  const mediaKind = preparedMedia.mediaKind;
  const mediaUrl = preparedMedia.mediaUrl;
  const contentLink = normalizeContentLinkPayload(dto);
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
    mediaAssetId: preparedMedia.mediaAssetId,
    storyStyle: dto.storyStyle,
  });
  if (!inserted?.id) {
    throw new AppError("STORY_CREATE_FAILED", { status: 500 });
  }
  if (contentLink) {
    await repo.replaceSocialContentLink({
      entityType: "story",
      entityId: Number(inserted.id),
      ...contentLink,
    });
  }
  const storyTextForTagSync = tagsService.buildStoryTextForTagSync({
    text: dto.caption || "",
    storyStyle: dto.storyStyle,
  });
  await tagsService.syncTagsAndMentionsForEntity({
    entityType: "story",
    entityId: Number(inserted.id),
    text: storyTextForTagSync,
    actorUserId: userId,
  });
  const created = await repo.findStoryById({
    viewerUserId: userId,
    storyId: inserted.id,
  });
  if (!created) throw new AppError("STORY_CREATE_FAILED", { status: 500 });
  const mapped = mapStoryRow(created, userId);

  emitToUser(Number(userId), "social_story_created", { story: mapped });

  const actor = await repo.findUserPublicProfile(userId);
  const isActorSuperAdmin = isSuperAdminUser(actor);
  if (isActorSuperAdmin || actor?.social_stories_public === true) {
    const audienceUserIds = await repo.listAudienceUserIdsForActor({
      actorUserId: userId,
      broadcastToAll: isActorSuperAdmin,
      limit: isActorSuperAdmin ? 12000 : 6000,
    });
    dispatchStoryNotifications({
      audienceUserIds,
      actor,
      story: mapped,
    });
  }

  return mapped;
}

async function getStoryForViewerOrThrow({ storyId, viewerUserId }) {
  const story = await repo.findStoryById({
    viewerUserId,
    storyId,
  });
  if (!story) {
    throw new AppError("STORY_NOT_FOUND", { status: 404 });
  }
  const owner = await assertViewerCanAccessStories({
    viewerUserId,
    ownerUserId: story.user_id,
  });
  return { story, owner };
}

export async function highlightStory({ userId, storyId, title = null }) {
  const story = await repo.findStoryForHighlight({
    ownerUserId: userId,
    storyId,
  });
  if (!story) {
    throw new AppError("STORY_NOT_FOUND", { status: 404 });
  }
  const highlight = await repo.upsertStoryHighlight({
    ownerUserId: userId,
    storyId,
    title,
  });
  if (!highlight?.id) {
    throw new AppError("HIGHLIGHT_CREATE_FAILED", { status: 500 });
  }
  const view = await repo.findHighlightById({
    viewerUserId: userId,
    highlightId: Number(highlight.id),
  });
  return {
    highlight: mapStoryHighlightRow(
      view || {
        ...story,
        highlight_id: Number(highlight.id),
        highlight_title: highlight.title || null,
        highlight_created_at: highlight.created_at || new Date().toISOString(),
      },
      userId
    ),
  };
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
  const { story } = await getStoryForViewerOrThrow({
    storyId,
    viewerUserId: userId,
  });
  if (Number(userId) !== Number(story.user_id || 0)) {
    await repo.markStoryViewed({ storyId, userId });
  }
  const updated = await repo.findStoryById({
    viewerUserId: userId,
    storyId,
  });
  return {
    ok: true,
    story: mapStoryRow(updated, userId),
  };
}

export async function toggleStoryLike({ storyId, userId }) {
  await assertSocialWriteAllowed(userId);
  const { story } = await getStoryForViewerOrThrow({
    storyId,
    viewerUserId: userId,
  });
  const existed = await repo.hasStoryLike({ storyId, userId });
  if (existed) {
    await repo.removeStoryLike({ storyId, userId });
  } else {
    await repo.addStoryLike({ storyId, userId });
  }
  const likesCount = await repo.countStoryLikes(storyId);
  if (!existed && Number(story.user_id) !== Number(userId)) {
    const actor = await repo.findUserPublicProfile(userId);
    await createNotification({
      userId: Number(story.user_id),
      type: "social.story.like",
      title: "New story like",
      body: `${actor?.full_name || "Someone"} liked your story`,
      payload: {
        storyId: Number(storyId),
        actorUserId: Number(userId),
        target: "social_story",
      },
    });
  }
  return {
    liked: !existed,
    likesCount,
  };
}

export async function listStoryComments({ storyId, userId, query }) {
  await getStoryForViewerOrThrow({
    storyId,
    viewerUserId: userId,
  });
  const rows = await repo.listStoryComments({
    storyId,
    viewerUserId: userId,
    limit: query.limit,
    beforeId: query.beforeId,
  });
  return {
    comments: rows.map(mapStoryCommentRow),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function addStoryComment({ storyId, userId, body }) {
  await assertSocialWriteAllowed(userId, "comment_create");
  const { story } = await getStoryForViewerOrThrow({
    storyId,
    viewerUserId: userId,
  });
  assertContentAllowed(body);
  const inserted = await repo.insertStoryComment({
    storyId,
    userId,
    body,
  });
  await tagsService.syncTagsAndMentionsForEntity({
    entityType: "story_comment",
    entityId: Number(inserted.id),
    text: body,
    actorUserId: userId,
  });
  const commentsCount = await repo.countStoryComments(storyId);
  const actor = await repo.findUserPublicProfile(userId);
  if (Number(story.user_id) !== Number(userId)) {
    await createNotification({
      userId: Number(story.user_id),
      type: "social.story.comment",
      title: "New story comment",
      body: `${actor?.full_name || "Someone"} commented on your story`,
      payload: {
        storyId: Number(storyId),
        actorUserId: Number(userId),
        commentId: Number(inserted.id),
        target: "social_story",
      },
    });
  }
  return {
    comment: mapStoryCommentRow({
      ...inserted,
      user_full_name: actor?.full_name || "",
      user_image_url: actor?.image_url || null,
      user_phone: actor?.phone || "",
      user_role: actor?.role || "user",
    }),
    commentsCount,
  };
}

export async function reportStory({ storyId, reporterUserId, reason, details }) {
  await assertReportingAllowed(reporterUserId);
  const { story } = await getStoryForViewerOrThrow({
    storyId,
    viewerUserId: reporterUserId,
  });
  const inserted = await repo.insertStoryReport({
    storyId,
    reporterUserId,
    reason,
    details,
  });
  if (!inserted?.id) {
    throw new AppError("REPORT_CREATE_FAILED", { status: 500 });
  }
  const reporter = await repo.findUserPublicProfile(reporterUserId);
  const adminIds = await repo.listSuperAdminUserIds(240);
  await createManyNotifications(
    adminIds
      .filter((id) => id !== Number(reporterUserId))
      .map((adminId) => ({
        userId: adminId,
        type: "social.report.story.created",
        title: "New story report",
        body: `${reporter?.full_name || "User"} reported a story`,
        payload: {
          reportId: Number(inserted.id),
          storyId: Number(storyId),
          reporterUserId: Number(reporterUserId),
          reportedUserId: Number(story.user_id),
          reason: String(reason || "").trim(),
          target: "admin_social_reports",
        },
      }))
  );
  return { ok: true, reportId: Number(inserted.id) };
}

export async function resubmitModeratedPost({
  postId,
  userId,
  caption,
  clearMedia = false,
  media = null,
}) {
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true) {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  if (Number(post.user_id) !== Number(userId)) {
    throw new AppError("FORBIDDEN_POST_OWNER_ONLY", { status: 403 });
  }
  if (String(post.moderation_status || "").trim().toLowerCase() !== "pending") {
    throw new AppError("POST_RESUBMIT_NOT_ALLOWED", { status: 409 });
  }

  if (caption != null) {
    assertContentAllowed(caption);
  }

  const uploadedMediaKind = resolveMediaKindFromMime(media?.mimetype);
  const preparedMedia = media
    ? await mediaService.prepareSocialMediaAsset({
        userId,
        media,
        preferredKind: uploadedMediaKind,
        sourceType: "post",
      })
    : { mediaUrl: null, mediaKind: null };

  const nextMediaUrl = media
    ? preparedMedia.mediaUrl
    : clearMedia
      ? null
      : post.media_url || null;
  const nextMediaKind = media
    ? preparedMedia.mediaKind
    : clearMedia
      ? null
      : post.media_kind || null;

  let nextPostKind = String(post.post_kind || "text").trim().toLowerCase();
  if (isReelPostKind(nextPostKind)) {
    nextPostKind = nextMediaKind === "video" ? "reel" : "text";
  } else if (nextPostKind !== "merchant_review") {
    if (nextMediaKind === "video") nextPostKind = "reel";
    else if (nextMediaKind === "image") nextPostKind = "image";
    else if (!nextMediaKind) nextPostKind = "text";
  }

  const updated = await repo.updatePostAfterEditRequest({
    postId,
    userId,
    caption,
    mediaUrl: nextMediaUrl,
    mediaKind: nextMediaKind,
    postKind: nextPostKind,
  });
  if (!updated) {
    throw new AppError("POST_RESUBMIT_FAILED", { status: 409 });
  }

  await tagsService.syncTagsAndMentionsForEntity({
    entityType: "post",
    entityId: Number(postId),
    text: caption || "",
    actorUserId: userId,
  });

  const view = await repo.findPostById(postId);
  return {
    post: mapPostRow(view || updated),
  };
}

export async function resubmitModeratedStory({
  storyId,
  userId,
  caption,
  clearMedia = false,
  media = null,
}) {
  const story = await repo.findStoryForOwnerEdit({ storyId, ownerUserId: userId });
  if (!story || story.is_deleted === true) {
    throw new AppError("STORY_NOT_FOUND", { status: 404 });
  }
  if (String(story.moderation_status || "").trim().toLowerCase() !== "pending") {
    throw new AppError("STORY_RESUBMIT_NOT_ALLOWED", { status: 409 });
  }

  if (caption != null) {
    assertContentAllowed(caption);
  }

  const uploadedMediaKind = resolveMediaKindFromMime(media?.mimetype);
  const preparedMedia = media
    ? await mediaService.prepareSocialMediaAsset({
        userId,
        media,
        preferredKind: uploadedMediaKind,
        sourceType: "story",
      })
    : { mediaUrl: null, mediaKind: null };

  const nextMediaUrl = media
    ? preparedMedia.mediaUrl
    : clearMedia
      ? null
      : story.media_url || null;
  const nextMediaKind = media
    ? preparedMedia.mediaKind
    : clearMedia
      ? null
      : story.media_kind || null;

  const updated = await repo.updateStoryAfterEditRequest({
    storyId,
    userId,
    caption,
    mediaUrl: nextMediaUrl,
    mediaKind: nextMediaKind,
  });
  if (!updated) {
    throw new AppError("STORY_RESUBMIT_FAILED", { status: 409 });
  }

  const storyTextForTagSync = tagsService.buildStoryTextForTagSync({
    text: caption || "",
    storyStyle: story.story_style || {},
  });
  await tagsService.syncTagsAndMentionsForEntity({
    entityType: "story",
    entityId: Number(storyId),
    text: storyTextForTagSync,
    actorUserId: userId,
  });

  const view = await repo.findStoryById({
    viewerUserId: userId,
    storyId,
  });
  return {
    story: mapStoryRow(view || updated, userId),
  };
}

export async function listComments({ postId, userId, query }) {
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true || post.moderation_status !== "approved") {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  await assertViewerCanAccessPosts({
    viewerUserId: userId,
    ownerUserId: post.user_id,
  });

  const rows = await repo.listPostComments({
    postId,
    viewerUserId: userId,
    limit: query.limit,
    beforeId: query.beforeId,
  });
  return {
    comments: rows.map(mapCommentRow),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function addComment({ postId, userId, body, parentCommentId = null }) {
  await assertSocialWriteAllowed(userId, "comment_create");
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true || post.moderation_status !== "approved") {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  await assertViewerCanAccessPosts({
    viewerUserId: userId,
    ownerUserId: post.user_id,
  });

  if (parentCommentId != null) {
    const parent = await repo.findPostCommentById({
      postId,
      commentId: parentCommentId,
    });
    if (!parent || parent.is_deleted === true) {
      throw new AppError("COMMENT_NOT_FOUND", { status: 404 });
    }
  }

  assertContentAllowed(body);
  const inserted = await repo.insertComment({
    postId,
    userId,
    body,
    parentCommentId,
  });
  await tagsService.syncTagsAndMentionsForEntity({
    entityType: "comment",
    entityId: Number(inserted.id),
    text: body,
    actorUserId: userId,
  });
  const commentsCount = await repo.countPostComments(postId);
  const actor = await repo.findUserPublicProfile(userId);

  if (Number(post.user_id) !== Number(userId)) {
    const isReel = isReelPostKind(post.post_kind);
    await createNotification({
      userId: Number(post.user_id),
      type: isReel ? "social.reel.comment" : "social.post.comment",
      title: isReel ? "تعليق جديد على ريلك" : "تعليق جديد على منشورك",
      body: isReel
        ? `${actor?.full_name || "مستخدم"} علّق على ريلك`
        : `${actor?.full_name || "مستخدم"} علّق على منشورك`,
      payload: buildPostNotificationPayload({
        post,
        postId: Number(postId),
        actorUserId: Number(userId),
        extra: {
          commentId: Number(inserted.id),
        },
      }),
    });
  }

  const realtimeScopes = buildAudienceScopesForCommunityFeeds({
    scopeType: String(post.audience_scope_type || "global").trim().toLowerCase(),
    scopeCode:
      post.audience_scope_code == null
        ? null
        : String(post.audience_scope_code).trim().toUpperCase(),
  });
  await Promise.all(
    realtimeScopes.map((scope) =>
      emitCommunityRealtimeEvent({
        scopeType: scope.scopeType,
        scopeCode: scope.scopeCode,
        event: "social_community_post_commented",
        data: {
          postId: Number(postId),
          commentsCount,
          comment: mapCommentRow({
            ...inserted,
            user_full_name: actor?.full_name || "",
            user_image_url: actor?.image_url || null,
            user_phone: actor?.phone || "",
            user_role: actor?.role || "user",
          }),
        },
        excludeUserIds: [],
      })
    )
  );

  return {
    comment: mapCommentRow(
      (
        await repo.findPostCommentViewById({
          postId,
          commentId: inserted.id,
          viewerUserId: userId,
        })
      ) || {
        ...inserted,
        user_full_name: actor?.full_name || "",
        user_image_url: actor?.image_url || null,
        user_phone: actor?.phone || "",
        user_role: actor?.role || "user",
      }
    ),
    commentsCount,
  };
}

export async function updateComment({ postId, commentId, userId, body }) {
  await assertSocialWriteAllowed(userId);
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true || post.moderation_status !== "approved") {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const existing = await repo.findPostCommentById({ postId, commentId });
  if (!existing) {
    throw new AppError("COMMENT_NOT_FOUND", { status: 404 });
  }
  if (Number(existing.user_id) !== Number(userId)) {
    throw new AppError("FORBIDDEN_COMMENT_OWNER_ONLY", { status: 403 });
  }
  assertContentAllowed(body);
  const updated = await repo.updatePostCommentBody({ commentId, body });
  if (!updated) {
    throw new AppError("COMMENT_UPDATE_FAILED", { status: 500 });
  }
  await tagsService.syncTagsAndMentionsForEntity({
    entityType: "comment",
    entityId: Number(commentId),
    text: body,
    actorUserId: userId,
  });
  const viewRow = await repo.findPostCommentViewById({
    postId,
    commentId,
    viewerUserId: userId,
  });
  return {
    comment: mapCommentRow(viewRow || updated),
  };
}

export async function deleteComment({ postId, commentId, userId }) {
  await assertSocialWriteAllowed(userId);
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true || post.moderation_status !== "approved") {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const existing = await repo.findPostCommentById({ postId, commentId });
  if (!existing) {
    throw new AppError("COMMENT_NOT_FOUND", { status: 404 });
  }
  const allowed =
    Number(existing.user_id) === Number(userId) ||
    Number(post.user_id) === Number(userId);
  if (!allowed) {
    throw new AppError("FORBIDDEN_COMMENT_DELETE", { status: 403 });
  }
  const deleted = await repo.softDeletePostComment({ commentId });
  if (!deleted) {
    throw new AppError("COMMENT_DELETE_FAILED", { status: 500 });
  }
  const commentsCount = await repo.countPostComments(postId);
  const viewRow = await repo.findPostCommentViewById({
    postId,
    commentId,
    viewerUserId: userId,
  });
  return {
    comment: mapCommentRow(viewRow || deleted),
    commentsCount,
  };
}

export async function toggleCommentLike({ postId, commentId, userId }) {
  await assertSocialWriteAllowed(userId);
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true || post.moderation_status !== "approved") {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const existing = await repo.findPostCommentById({ postId, commentId });
  if (!existing) {
    throw new AppError("COMMENT_NOT_FOUND", { status: 404 });
  }
  const existed = await repo.hasPostCommentLike({ commentId, userId });
  if (existed) await repo.removePostCommentLike({ commentId, userId });
  else await repo.addPostCommentLike({ commentId, userId });
  const likesCount = await repo.countPostCommentLikes(commentId);
  return {
    liked: !existed,
    likesCount,
  };
}

export async function reportPost({ postId, reporterUserId, reason, details }) {
  await assertReportingAllowed(reporterUserId);
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true || post.moderation_status !== "approved") {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const inserted = await repo.insertPostReport({
    postId,
    reporterUserId,
    reason,
    details,
  });
  if (!inserted?.id) {
    throw new AppError("REPORT_CREATE_FAILED", { status: 500 });
  }
  const reporter = await repo.findUserPublicProfile(reporterUserId);
  const adminIds = await repo.listSuperAdminUserIds(240);
  await createManyNotifications(
    adminIds
      .filter((id) => id !== Number(reporterUserId))
      .map((adminId) => ({
        userId: adminId,
        type: "social.report.post.created",
        title: "تبليغ جديد على منشور",
        body: `تم إرسال تبليغ على منشور من ${reporter?.full_name || "مستخدم"}`,
        payload: {
          reportId: Number(inserted.id),
          postId: Number(postId),
          reporterUserId: Number(reporterUserId),
          reason: String(reason || "").trim(),
          target: "admin_social_reports",
        },
      }))
  );
  return { ok: true, reportId: Number(inserted.id) };
}

export async function reportUser({
  reportedUserId,
  reporterUserId,
  reason,
  details,
}) {
  await assertReportingAllowed(reporterUserId);
  if (Number(reportedUserId) === Number(reporterUserId)) {
    throw new AppError("REPORT_SELF_FORBIDDEN", { status: 400 });
  }
  const target = await repo.findUserPublicProfile(reportedUserId);
  if (!target || target.is_account_disabled === true) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  const inserted = await repo.insertUserReport({
    reportedUserId,
    reporterUserId,
    reason,
    details,
  });
  if (!inserted?.id) {
    throw new AppError("REPORT_CREATE_FAILED", { status: 500 });
  }
  const reporter = await repo.findUserPublicProfile(reporterUserId);
  const adminIds = await repo.listSuperAdminUserIds(240);
  await createManyNotifications(
    adminIds
      .filter((id) => id !== Number(reporterUserId))
      .map((adminId) => ({
        userId: adminId,
        type: "social.report.user.created",
        title: "تبليغ جديد على مستخدم",
        body: `${reporter?.full_name || "مستخدم"} أبلغ عن ${target.full_name || "مستخدم"}`,
        payload: {
          reportId: Number(inserted.id),
          reportedUserId: Number(reportedUserId),
          reporterUserId: Number(reporterUserId),
          reason: String(reason || "").trim(),
          target: "admin_social_reports",
        },
      }))
  );
  return { ok: true, reportId: Number(inserted.id) };
}

export async function listMerchantOptions(viewerUserId, query) {
  const rows = await repo.listMerchantOptions({
    viewerUserId,
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
      ordersCount: Number(row.orders_count || 0),
      lastOrderedAt: row.last_ordered_at || null,
      canReview: Number(row.eligible_orders_count || 0) > 0,
      eligibleOrdersCount: Number(row.eligible_orders_count || 0),
      lastEligibleOrderAt: row.last_eligible_order_at || null,
      eligibilityLabel:
        Number(row.eligible_orders_count || 0) > 0
          ? "يمكنك المراجعة"
          : "يتطلب طلبًا مكتملًا",
      eligibilityReason:
        Number(row.eligible_orders_count || 0) > 0
          ? "لديك طلب مكتمل مع هذا المتجر"
          : "اكتب مراجعتك بعد إكمال طلب حقيقي من هذا المتجر",
    })),
  };
}

export async function searchUsers(viewerUserId, query) {
  const rows = await repo.listUsersForSearch({
    viewerUserId,
    search: query.search,
    limit: query.limit,
  });
  return {
    users: rows.map((row) => {
      const userId = Number(row.id);
      return {
        id: userId,
        username: row.username || null,
        fullName: row.full_name || "",
        imageUrl: row.image_url || null,
        role: row.role || "user",
        phone: canViewPhone({ viewerUserId, owner: row }) ? row.phone || "" : "",
        privacy: {
          accountPrivate: row.social_account_private === true,
        },
        relation: mapRelationRow(row, viewerUserId, userId),
      };
    }),
  };
}

export async function checkMyUsernameAvailability({ userId, username }) {
  const viewer = await repo.findUserAddressMeta(userId);
  if (!viewer) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  const normalized = assertUsernameValid(username);
  const taken = await repo.isUsernameTaken({
    username: normalized,
    excludeUserId: userId,
  });
  return {
    username: normalized,
    available: taken !== true,
  };
}

export async function updateMyUsername({ userId, username }) {
  const normalized = assertUsernameValid(username);
  const taken = await repo.isUsernameTaken({
    username: normalized,
    excludeUserId: userId,
  });
  if (taken) {
    throw new AppError("USERNAME_TAKEN", {
      status: 409,
      details: { fields: ["username"] },
    });
  }
  return updateMyProfile(userId, { username: normalized });
}

export async function listHashtagSuggestions(query) {
  return tagsService.listHashtagSuggestions({
    query: query.search,
    limit: query.limit,
  });
}

function mapUserWithRelationForViewer(row, viewerUserId) {
  const otherUserId = Number(row.id);
  return {
    user: {
      id: otherUserId,
      username: row.username || null,
      fullName: row.full_name || "",
      imageUrl: row.image_url || null,
      role: row.role || "user",
      phone: canViewPhone({ viewerUserId, owner: row }) ? row.phone || "" : "",
    },
    relation: mapRelationRow(row, viewerUserId, otherUserId),
    relatedAt: row.related_at || null,
  };
}

async function listRelationUsers({
  viewerUserId,
  targetUserId,
  relationType,
  limit,
}) {
  const [viewer, owner] = await Promise.all([
    repo.findUserAddressMeta(viewerUserId),
    repo.findUserSocialProfile(targetUserId),
  ]);
  if (!viewer) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  if (viewer.is_account_disabled === true) {
    throw new AppError("ACCOUNT_DISABLED", { status: 403 });
  }
  if (!owner) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  if (!canViewRelationLists({ viewerUserId, viewer, owner })) {
    throw new AppError("RELATION_LIST_PRIVATE", { status: 403 });
  }

  const rows = await repo.listUserRelationsByType({
    viewerUserId,
    targetUserId,
    relationType,
    limit,
  });

  return {
    users: rows.map((row) => mapUserWithRelationForViewer(row, viewerUserId)),
  };
}

export async function listUserFollowers({ viewerUserId, targetUserId, query }) {
  return listRelationUsers({
    viewerUserId,
    targetUserId,
    relationType: "followers",
    limit: query.limit,
  });
}

export async function listUserFollowing({ viewerUserId, targetUserId, query }) {
  return listRelationUsers({
    viewerUserId,
    targetUserId,
    relationType: "following",
    limit: query.limit,
  });
}

export async function listUserFriends({ viewerUserId, targetUserId, query }) {
  return listRelationUsers({
    viewerUserId,
    targetUserId,
    relationType: "friends",
    limit: query.limit,
  });
}

export async function toggleLike({ postId, userId }) {
  await assertSocialWriteAllowed(userId);
  const post = await repo.findPostById(postId);
  if (!post || post.is_deleted === true || post.moderation_status !== "approved") {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  await assertViewerCanAccessPosts({
    viewerUserId: userId,
    ownerUserId: post.user_id,
  });

  const existed = await repo.hasLike(postId, userId);
  if (existed) await repo.removeLike(postId, userId);
  else await repo.addLike(postId, userId);

  const likesCount = await repo.countPostLikes(postId);
  const liked = !existed;

  if (liked && Number(post.user_id) !== Number(userId)) {
    const actor = await repo.findUserPublicProfile(userId);
    const isReel = isReelPostKind(post.post_kind);
    await createNotification({
      userId: Number(post.user_id),
      type: isReel ? "social.reel.like" : "social.post.like",
      title: isReel ? "New like on your reel" : "New like on your post",
      body: isReel
        ? `${actor?.full_name || "User"} liked your reel`
        : `${actor?.full_name || "User"} liked your post`,
      payload: buildPostNotificationPayload({
        post,
        postId: Number(postId),
        actorUserId: Number(userId),
      }),
    });
  }

  return { liked, likesCount };
}

export async function listPostLikers({ viewerUserId, postId, query }) {
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  const post = await repo.findFeedPostById({
    viewerUserId,
    postId,
    viewerBlockCode: viewerScopeCodes.blockCode,
    viewerCompoundCode: viewerScopeCodes.compoundCode,
    viewerBuildingCode: viewerScopeCodes.buildingCode,
  });
  if (!post) {
    throw new AppError("POST_NOT_FOUND", { status: 404 });
  }
  const rows = await repo.listPostLikers({
    viewerUserId,
    postId,
    limit: query.limit,
  });
  return {
    likes: rows.map((row) => ({
      ...mapUserWithRelationForViewer(row, viewerUserId),
      likedAt: row.liked_at || null,
    })),
  };
}

export async function listUserLikedPosts({ viewerUserId, targetUserId, query }) {
  const owner = await repo.findUserSocialProfile(targetUserId);
  if (!owner) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  const rows = await repo.listPostsLikedByUser({
    viewerUserId,
    targetUserId,
    viewerBlockCode: viewerScopeCodes.blockCode,
    viewerCompoundCode: viewerScopeCodes.compoundCode,
    viewerBuildingCode: viewerScopeCodes.buildingCode,
    limit: query.limit,
    beforeId: query.beforeId,
    postKind: normalizeRequestedPostKind(query.kind),
  });
  const enrichedRows = await attachPostMediaRows(rows);
  return {
    posts: enrichedRows.map(mapPostRow),
    nextCursor:
      enrichedRows.length > 0
        ? Number(enrichedRows[enrichedRows.length - 1].id)
        : null,
  };
}

export async function listUserCommentedPosts({
  viewerUserId,
  targetUserId,
  query,
}) {
  const owner = await repo.findUserSocialProfile(targetUserId);
  if (!owner) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  const viewerScopeCodes = await resolveViewerScopeCodes(viewerUserId);
  const rows = await repo.listPostsCommentedByUser({
    viewerUserId,
    targetUserId,
    viewerBlockCode: viewerScopeCodes.blockCode,
    viewerCompoundCode: viewerScopeCodes.compoundCode,
    viewerBuildingCode: viewerScopeCodes.buildingCode,
    limit: query.limit,
    beforeId: query.beforeId,
    postKind: normalizeRequestedPostKind(query.kind),
  });
  const enrichedRows = await attachPostMediaRows(rows);
  return {
    posts: enrichedRows.map(mapPostRow),
    nextCursor:
      enrichedRows.length > 0
        ? Number(enrichedRows[enrichedRows.length - 1].id)
        : null,
  };
}

export async function createThread({
  userId,
  otherUserId,
  kind = "private",
  title = null,
  imageUrl = null,
  memberIds = [],
  context = null,
}) {
  await repo.touchUserPresence(userId);

  const threadKind = normalizeThreadKind(kind);
  if (threadKind === "group") {
    const normalizedTitle = String(title || "").trim();
    const requestedMemberIds = Array.isArray(memberIds)
      ? [
          ...new Set(
            memberIds
              .map((value) => Number(value))
              .filter((value) => Number.isInteger(value) && value > 0 && value !== Number(userId))
          ),
        ]
      : [];
    if (!normalizedTitle || normalizedTitle.length > 80) {
      throw new AppError("GROUP_THREAD_TITLE_INVALID", { status: 400 });
    }
    if (requestedMemberIds.length < 1 || requestedMemberIds.length > 32) {
      throw new AppError("GROUP_THREAD_MEMBER_COUNT_INVALID", { status: 400 });
    }
    const memberProfiles = await repo.listUserPublicProfiles(requestedMemberIds);
    if (memberProfiles.length !== requestedMemberIds.length) {
      throw new AppError("GROUP_THREAD_MEMBER_NOT_FOUND", { status: 404 });
    }
    const disabledMember = memberProfiles.find(
      (profile) => profile?.is_account_disabled === true
    );
    if (disabledMember) {
      throw new AppError("GROUP_THREAD_MEMBER_UNAVAILABLE", { status: 403 });
    }
    const created = await repo.createGroupThread({
      ownerUserId: userId,
      title: normalizedTitle,
      imageUrl,
      memberUserIds: requestedMemberIds,
    });
    const thread = await repo.getThreadForUser({
      threadId: created.id,
      userId,
    });
    if (!thread) throw new AppError("THREAD_CREATE_FAILED", { status: 500 });
    return mapThreadRow(thread, userId);
  }

  const other = await repo.findUserPublicProfile(otherUserId);
  if (!other) throw new AppError("USER_NOT_FOUND", { status: 404 });
  let baseThread = null;

  if (threadKind === "business") {
    const relation = await repo.getUserRelation({ userId, otherUserId });
    const mapped = mapRelationRow(relation, userId, otherUserId);
    if (mapped.blockedByMe || mapped.blockedByOther) {
      throw new AppError("RELATION_BLOCKED", {
        status: 403,
        details: { relation: mapped },
      });
    }
    const contextSeed = await resolveBusinessThreadSeed({
      userId,
      otherUserId,
      context,
    });
    baseThread = await repo.createOrGetThread({
      userAId: userId,
      userBId: otherUserId,
      threadKind,
      contextType: contextSeed.contextType,
      contextId: contextSeed.contextId,
      contextStatus: contextSeed.contextStatus,
      contextSnapshot: contextSeed.contextSnapshot,
    });
    await Promise.all([
      repo.upsertThreadParticipantState({
        threadId: Number(baseThread.id),
        userId,
        inboxBucket: "primary",
        requestStatus: "accepted",
      }),
      repo.upsertThreadParticipantState({
        threadId: Number(baseThread.id),
        userId: otherUserId,
        inboxBucket: "primary",
        requestStatus: "accepted",
      }),
    ]);
  } else {
    const access = await resolveMessagingAccess({ userId, otherUserId });
    baseThread = await repo.createOrGetThread({
      userAId: userId,
      userBId: otherUserId,
      threadKind,
    });
    if (access.isPrimary) {
      await Promise.all([
        repo.upsertThreadParticipantState({
          threadId: Number(baseThread.id),
          userId,
          inboxBucket: "primary",
          requestStatus: "accepted",
        }),
        repo.upsertThreadParticipantState({
          threadId: Number(baseThread.id),
          userId: otherUserId,
          inboxBucket: "primary",
          requestStatus: "accepted",
        }),
      ]);
    } else {
      await Promise.all([
        repo.upsertThreadParticipantState({
          threadId: Number(baseThread.id),
          userId,
          inboxBucket: "primary",
          requestStatus: "accepted",
        }),
        repo.upsertThreadParticipantState({
          threadId: Number(baseThread.id),
          userId: otherUserId,
          inboxBucket: "requests",
          requestStatus: "pending",
        }),
      ]);
    }
  }

  let thread = await repo.getThreadForUser({
    threadId: baseThread.id,
    userId,
  });
  if (!thread) throw new AppError("THREAD_CREATE_FAILED", { status: 500 });
  thread = await hydrateBusinessThreadContext(thread);

  return mapThreadRow(thread, userId);
}

export async function listThreads(userId) {
  await repo.touchUserPresence(userId);
  const rows = await repo.listThreadsForUser({
    userId,
    limit: 80,
    inboxBucket: "primary",
  });
  const hydratedRows = await hydrateBusinessThreadRows(rows);
  const threadIds = hydratedRows
    .map((row) => Number(row.id))
    .filter((value) => value > 0);
  const [stateRows, unreadRows] = await Promise.all([
    repo.listThreadParticipantStatesForUser({ userId, threadIds }),
    repo.listUnreadCountsForThreads({ userId, threadIds }),
  ]);
  const statesByThreadId = new Map(stateRows.map((row) => [Number(row.thread_id), row]));
  const unreadByThreadId = new Map(unreadRows.map((row) => [Number(row.thread_id), Number(row.unread_count || 0)]));
  return {
    threads: hydratedRows.map((row) =>
      mapThreadRow(
        {
          ...row,
          ...(statesByThreadId.get(Number(row.id)) || {}),
          unread_count: unreadByThreadId.get(Number(row.id)) || 0,
        },
        userId
      )
    ),
  };
}

export async function listChatRequests(userId) {
  await repo.touchUserPresence(userId);
  const rows = await repo.listThreadsForUser({
    userId,
    limit: 80,
    inboxBucket: "requests",
    requestStatuses: ["pending"],
  });
  const hydratedRows = await hydrateBusinessThreadRows(rows);
  const threadIds = hydratedRows.map((row) => Number(row.id)).filter((value) => value > 0);
  const [stateRows, unreadRows] = await Promise.all([
    repo.listThreadParticipantStatesForUser({ userId, threadIds }),
    repo.listUnreadCountsForThreads({ userId, threadIds }),
  ]);
  const statesByThreadId = new Map(stateRows.map((row) => [Number(row.thread_id), row]));
  const unreadByThreadId = new Map(
    unreadRows.map((row) => [Number(row.thread_id), Number(row.unread_count || 0)])
  );
  return {
    threads: hydratedRows.map((row) =>
      mapThreadRow(
        {
          ...row,
          ...(statesByThreadId.get(Number(row.id)) || {}),
          unread_count: unreadByThreadId.get(Number(row.id)) || 0,
        },
        userId
      )
    ),
  };
}

export async function getGroupThreadDetails({ userId, threadId }) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  assertGroupThread(thread);
  const members = await repo.listGroupThreadMembers({ threadId });
  return {
    thread: mapThreadRow(thread, userId),
    members: members.map(mapGroupThreadMemberRow),
  };
}

export async function updateGroupThread({ userId, threadId, title }) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  assertGroupThread(thread);
  assertGroupManagePermission(thread);
  await repo.updateGroupThreadMetadata({
    threadId,
    title,
  });
  const updatedThread = await repo.getThreadForUser({ threadId, userId });
  const targetUserIds = await repo.listThreadMemberUserIds({ threadId });
  for (const targetUserId of targetUserIds) {
    emitToUser(targetUserId, "social_chat_thread_updated", {
      threadId: Number(threadId),
      action: "metadata_updated",
      actorUserId: Number(userId),
    });
  }
  return {
    thread: mapThreadRow(updatedThread, userId),
  };
}

export async function addGroupThreadMembers({ userId, threadId, memberIds = [] }) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  assertGroupThread(thread);
  assertGroupManagePermission(thread);

  const existingMembers = await repo.listGroupThreadMembers({ threadId });
  const existingIds = new Set(existingMembers.map((row) => Number(row.user_id)));
  const requestedMemberIds = Array.isArray(memberIds)
    ? [
        ...new Set(
          memberIds
            .map((value) => Number(value))
            .filter(
              (value) =>
                Number.isInteger(value) &&
                value > 0 &&
                !existingIds.has(value)
            )
        ),
      ]
    : [];
  if (requestedMemberIds.length <= 0) {
    throw new AppError("GROUP_THREAD_NO_NEW_MEMBERS", { status: 409 });
  }
  if (existingIds.size + requestedMemberIds.length > 64) {
    throw new AppError("GROUP_THREAD_MEMBER_COUNT_INVALID", { status: 400 });
  }
  const memberProfiles = await repo.listUserPublicProfiles(requestedMemberIds);
  if (memberProfiles.length !== requestedMemberIds.length) {
    throw new AppError("GROUP_THREAD_MEMBER_NOT_FOUND", { status: 404 });
  }
  const disabledMember = memberProfiles.find(
    (profile) => profile?.is_account_disabled === true
  );
  if (disabledMember) {
    throw new AppError("GROUP_THREAD_MEMBER_UNAVAILABLE", { status: 403 });
  }

  const addedUserIds = await repo.addGroupThreadMembers({
    threadId,
    memberUserIds: requestedMemberIds,
    addedByUserId: userId,
  });
  const updatedThread = await repo.getThreadForUser({ threadId, userId });
  const members = await repo.listGroupThreadMembers({ threadId });
  const targetUserIds = await repo.listThreadMemberUserIds({ threadId });
  for (const targetUserId of targetUserIds) {
    emitToUser(targetUserId, "social_chat_thread_updated", {
      threadId: Number(threadId),
      action: "members_added",
      actorUserId: Number(userId),
      memberUserIds: addedUserIds,
    });
  }
  if (addedUserIds.length > 0) {
    await createManyNotifications(
      addedUserIds.map((targetUserId) => ({
        userId: Number(targetUserId),
        type: "social.chat.group_added",
        title: `تمت إضافتك إلى ${String(thread.group_title || "المجموعة").trim()}`,
        body: "يمكنك الآن المشاركة في المحادثة الجماعية.",
        payload: {
          threadId: Number(threadId),
          target: "social_chat",
        },
      }))
    );
  }
  return {
    thread: mapThreadRow(updatedThread, userId),
    members: members.map(mapGroupThreadMemberRow),
    addedUserIds,
  };
}

export async function removeGroupThreadMember({
  userId,
  threadId,
  memberUserId,
}) {
  await repo.touchUserPresence(userId);
  if (Number(userId) === Number(memberUserId)) {
    return leaveGroupThread({ userId, threadId });
  }
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  assertGroupThread(thread);
  const actorRole = assertGroupManagePermission(thread);
  const targetMember = await repo.getGroupThreadMember({
    threadId,
    userId: memberUserId,
  });
  if (!targetMember) {
    throw new AppError("GROUP_THREAD_MEMBER_NOT_FOUND", { status: 404 });
  }
  const targetRole = String(targetMember.member_role || "member").trim().toLowerCase();
  if (targetRole === "owner") {
    throw new AppError("GROUP_THREAD_OWNER_REMOVE_FORBIDDEN", { status: 403 });
  }
  if (actorRole === "admin" && targetRole !== "member") {
    throw new AppError("GROUP_THREAD_ADMIN_REMOVE_FORBIDDEN", { status: 403 });
  }

  await repo.removeGroupThreadMember({ threadId, userId: memberUserId });
  const updatedThread = await repo.getThreadForUser({ threadId, userId });
  const members = await repo.listGroupThreadMembers({ threadId });
  const remainingUserIds = await repo.listThreadMemberUserIds({ threadId });
  for (const targetUserId of [...new Set([...remainingUserIds, Number(memberUserId)])]) {
    emitToUser(targetUserId, "social_chat_thread_updated", {
      threadId: Number(threadId),
      action: "member_removed",
      actorUserId: Number(userId),
      memberUserIds: [Number(memberUserId)],
    });
  }
  return {
    ok: true,
    thread: updatedThread ? mapThreadRow(updatedThread, userId) : null,
    members: members.map(mapGroupThreadMemberRow),
    removedUserId: Number(memberUserId),
  };
}

export async function leaveGroupThread({ userId, threadId }) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  assertGroupThread(thread);
  const role = String(thread.group_member_role || "member").trim().toLowerCase();
  if (role === "owner") {
    throw new AppError("GROUP_THREAD_OWNER_CANNOT_LEAVE", { status: 409 });
  }
  await repo.removeGroupThreadMember({ threadId, userId });
  const remainingUserIds = await repo.listThreadMemberUserIds({ threadId });
  for (const targetUserId of [...new Set([...remainingUserIds, Number(userId)])]) {
    emitToUser(targetUserId, "social_chat_thread_updated", {
      threadId: Number(threadId),
      action: "member_left",
      actorUserId: Number(userId),
      memberUserIds: [Number(userId)],
    });
  }
  return {
    ok: true,
    left: true,
    threadId: Number(threadId),
  };
}

export async function updateGroupThreadMemberRole({
  userId,
  threadId,
  memberUserId,
  memberRole,
}) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  assertGroupThread(thread);
  const actorRole = assertGroupManagePermission(thread);
  if (actorRole !== "owner") {
    throw new AppError("GROUP_THREAD_ROLE_MANAGE_FORBIDDEN", { status: 403 });
  }
  const normalizedRole = String(memberRole || "member").trim().toLowerCase();
  if (normalizedRole !== "admin" && normalizedRole !== "member") {
    throw new AppError("GROUP_THREAD_MEMBER_ROLE_INVALID", { status: 400 });
  }
  if (Number(memberUserId) === Number(userId)) {
    throw new AppError("GROUP_THREAD_OWNER_ROLE_CHANGE_FORBIDDEN", {
      status: 403,
    });
  }
  const targetMember = await repo.getGroupThreadMember({
    threadId,
    userId: memberUserId,
  });
  if (!targetMember) {
    throw new AppError("GROUP_THREAD_MEMBER_NOT_FOUND", { status: 404 });
  }
  const currentRole = String(targetMember.member_role || "member")
    .trim()
    .toLowerCase();
  if (currentRole === "owner") {
    throw new AppError("GROUP_THREAD_OWNER_ROLE_CHANGE_FORBIDDEN", {
      status: 403,
    });
  }
  if (currentRole !== normalizedRole) {
    await repo.updateGroupThreadMemberRole({
      threadId,
      userId: memberUserId,
      memberRole: normalizedRole,
    });
  }
  const updatedThread = await repo.getThreadForUser({ threadId, userId });
  const members = await repo.listGroupThreadMembers({ threadId });
  const targetUserIds = await repo.listThreadMemberUserIds({ threadId });
  for (const targetUserId of targetUserIds) {
    emitToUser(targetUserId, "social_chat_thread_updated", {
      threadId: Number(threadId),
      action: "member_role_updated",
      actorUserId: Number(userId),
      memberUserIds: [Number(memberUserId)],
      memberRole: normalizedRole,
    });
  }
  return {
    thread: updatedThread ? mapThreadRow(updatedThread, userId) : null,
    members: members.map(mapGroupThreadMemberRow),
    memberUserId: Number(memberUserId),
    memberRole: normalizedRole,
  };
}

export async function listShareRecipients({ userId, query }) {
  const [threadsOut, usersOut] = await Promise.all([
    listThreads(userId),
    searchUsers(userId, query),
  ]);
  const threadByPeerId = new Map(
    threadsOut.threads
      .filter((thread) => thread.threadKind === "private")
      .map((thread) => [Number(thread.peer.id), thread])
  );
  return {
    recentThreads: threadsOut.threads
      .filter((thread) => thread.threadKind === "private")
      .slice(0, 16),
    recipients: usersOut.users.map((user) => ({
      user,
      relation: user.relation,
      threadId: threadByPeerId.get(Number(user.id))?.id || null,
      inboxBucket: threadByPeerId.get(Number(user.id))?.state.inboxBucket || "primary",
      canSend:
        user.relation?.blockedByMe != true && user.relation?.blockedByOther != true,
    })),
  };
}

export async function getMyChatQualityReviewConsent({ userId }) {
  const row = await repo.getUserChatQualityReviewConsent(userId);
  if (!row) throw new AppError("USER_NOT_FOUND", { status: 404 });
  return {
    enabled: row.chat_quality_review_consent === true,
  };
}

export async function setMyChatQualityReviewConsent({ userId, enabled }) {
  const row = await repo.getUserChatQualityReviewConsent(userId);
  if (!row) throw new AppError("USER_NOT_FOUND", { status: 404 });
  throw new AppError("CHAT_QUALITY_REVIEW_CONSENT_MANAGED_BY_SIGNUP", {
    status: 409,
    details: {
      enabled: row.chat_quality_review_consent === true,
      requested: enabled === true,
    },
  });
}

export async function listAdminMonitoredThreads({
  userId,
  isSuperAdmin,
  query,
}) {
  if (isSuperAdmin !== true) {
    throw new AppError("FORBIDDEN_SUPER_ADMIN_ONLY", { status: 403 });
  }
  const [directRows, communityRows] = await Promise.all([
    query.kind === "community"
      ? Promise.resolve([])
      : repo.listMonitorableThreadsForSuperAdmin({
          search: query.search,
          limit: query.limit,
        }),
    query.kind === "direct"
      ? Promise.resolve([])
      : repo.listMonitorableCommunityChatsForSuperAdmin({
          search: query.search,
          limit: query.limit,
        }),
  ]);
  const items = [
    ...directRows.map((row) => ({
      kind: "direct",
      monitorKey: `direct:${Number(row.id)}`,
      threadId: Number(row.id),
      scopeType: null,
      scopeCode: null,
      scopeTitle: null,
      scopeSubtitle: null,
      participantCount: 2,
      ...mapMonitoredThreadRow(row),
    })),
    ...communityRows.map(mapCommunityMonitoredChatRow),
  ].sort((a, b) => {
    const aTime = a.lastMessageAt ? new Date(a.lastMessageAt).getTime() : 0;
    const bTime = b.lastMessageAt ? new Date(b.lastMessageAt).getTime() : 0;
    if (bTime !== aTime) return bTime - aTime;
    return String(a.monitorKey).localeCompare(String(b.monitorKey));
  });
  return {
    threads: items.slice(0, query.limit),
  };
}

export async function listAdminMonitoredThreadMessages({
  userId,
  isSuperAdmin,
  threadId,
  query,
}) {
  if (isSuperAdmin !== true) {
    throw new AppError("FORBIDDEN_SUPER_ADMIN_ONLY", { status: 403 });
  }
  const thread = await repo.getMonitorableThreadForSuperAdmin(threadId);
  if (!thread) {
    throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  }

  const rows = await repo.listMessagesForThread({
    threadId,
    limit: query.limit,
    beforeId: query.beforeId,
  });
  const messageIds = rows
    .map((row) => Number(row.id))
    .filter((value) => Number.isFinite(value) && value > 0);
  const reactionsByMessage = await repo.listMessageReactionsForMessages({
    messageIds,
    userId,
  });

  return {
    thread: mapMonitoredThreadRow(thread),
    messages: rows
      .map((row) => ({
        ...row,
        reaction_counts: reactionsByMessage[Number(row.id)]?.counts || {},
        reaction_total_count: Number(
          reactionsByMessage[Number(row.id)]?.totalCount || 0
        ),
        my_reaction: reactionsByMessage[Number(row.id)]?.myReaction || null,
      }))
      .map((row) => mapMessageRow(row, userId))
      .reverse(),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function listMessages({ userId, threadId, query }) {
  await repo.touchUserPresence(userId);
  let thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const threadKind = normalizeThreadKind(thread.thread_kind);
  if (threadKind === "private") {
    await ensureUsersCanConnect({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
  } else if (threadKind === "business") {
    const relation = await repo.getUserRelation({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
    const mapped = mapRelationRow(relation, userId, Number(thread.peer_user_id));
    if (mapped.blockedByMe || mapped.blockedByOther) {
      throw new AppError("RELATION_BLOCKED", {
        status: 403,
        details: { relation: mapped },
      });
    }
  }

  thread = await hydrateBusinessThreadContext(thread);
  const presence = buildThreadPresence(thread);

  const rows = await repo.listMessagesForThread({
    threadId,
    limit: query.limit,
    beforeId: query.beforeId,
  });
  const pinnedRows =
    query.beforeId == null
      ? await repo.listPinnedMessagesForThread({ threadId, limit: 3 })
      : [];
  const messageIds = rows
    .map((row) => Number(row.id))
    .concat(pinnedRows.map((row) => Number(row.id)))
    .filter((v) => Number.isFinite(v) && v > 0);
  const reactionsByMessage = await repo.listMessageReactionsForMessages({
    messageIds,
    userId,
  });
  const latestMessageId = rows.length > 0 ? Number(rows[0].id) : null;
  if (latestMessageId != null && query.beforeId == null) {
    await repo.upsertThreadParticipantState({
      threadId,
      userId,
      lastReadMessageId: latestMessageId,
      lastDeliveredMessageId: latestMessageId,
    });
    thread = {
      ...thread,
      last_read_message_id: latestMessageId,
      last_delivered_message_id: latestMessageId,
    };
    if (Number(thread.peer_user_id || 0) > 0) {
      emitThreadStateUpdate({
        threadId,
        actorUserId: userId,
        peerUserId: Number(thread.peer_user_id),
        lastReadMessageId: latestMessageId,
        lastDeliveredMessageId: latestMessageId,
      });
    }
  }
  const peerLastDeliveredMessageId = Number(
    thread.peer_last_delivered_message_id || 0
  );
  const peerLastReadMessageId = Number(thread.peer_last_read_message_id || 0);
  const messages = rows
    .map((row) => ({
      ...row,
      reaction_counts: reactionsByMessage[Number(row.id)]?.counts || {},
      reaction_total_count: Number(reactionsByMessage[Number(row.id)]?.totalCount || 0),
      my_reaction: reactionsByMessage[Number(row.id)]?.myReaction || null,
      delivered_to_peer:
        Number(row.sender_user_id) === Number(userId)
          ? peerLastDeliveredMessageId >= Number(row.id)
          : true,
      read_by_peer:
        Number(row.sender_user_id) === Number(userId)
          ? presence.canSeeReadReceipts && peerLastReadMessageId >= Number(row.id)
          : true,
    }))
    .map((row) => mapMessageRow(row, userId))
    .reverse();
  const pinnedMessages = pinnedRows
    .map((row) => ({
      ...row,
      reaction_counts: reactionsByMessage[Number(row.id)]?.counts || {},
      reaction_total_count: Number(
        reactionsByMessage[Number(row.id)]?.totalCount || 0
      ),
      my_reaction: reactionsByMessage[Number(row.id)]?.myReaction || null,
      delivered_to_peer:
        Number(row.sender_user_id) === Number(userId)
          ? peerLastDeliveredMessageId >= Number(row.id)
          : true,
      read_by_peer:
        Number(row.sender_user_id) === Number(userId)
          ? presence.canSeeReadReceipts && peerLastReadMessageId >= Number(row.id)
          : true,
    }))
    .map((row) => mapMessageRow(row, userId));

  return {
    thread: mapThreadRow(thread, userId),
    messages,
    pinnedMessages,
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function searchThreadMessages({ userId, threadId, query }) {
  await repo.touchUserPresence(userId);
  let thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const threadKind = normalizeThreadKind(thread.thread_kind);
  if (threadKind === "private") {
    await ensureUsersCanConnect({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
  } else if (threadKind === "business") {
    const relation = await repo.getUserRelation({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
    const mapped = mapRelationRow(relation, userId, Number(thread.peer_user_id));
    if (mapped.blockedByMe || mapped.blockedByOther) {
      throw new AppError("RELATION_BLOCKED", {
        status: 403,
        details: { relation: mapped },
      });
    }
  }

  thread = await hydrateBusinessThreadContext(thread);
  const presence = buildThreadPresence(thread);
  const rows = await repo.searchMessagesInThread({
    threadId,
    search: query.search,
    limit: query.limit,
    beforeId: query.beforeId,
  });
  const messageIds = rows
    .map((row) => Number(row.id))
    .filter((value) => Number.isFinite(value) && value > 0);
  const reactionsByMessage = await repo.listMessageReactionsForMessages({
    messageIds,
    userId,
  });
  const peerLastDeliveredMessageId = Number(
    thread.peer_last_delivered_message_id || 0
  );
  const peerLastReadMessageId = Number(thread.peer_last_read_message_id || 0);
  const messages = rows
    .map((row) => ({
      ...row,
      reaction_counts: reactionsByMessage[Number(row.id)]?.counts || {},
      reaction_total_count: Number(
        reactionsByMessage[Number(row.id)]?.totalCount || 0
      ),
      my_reaction: reactionsByMessage[Number(row.id)]?.myReaction || null,
      delivered_to_peer:
        Number(row.sender_user_id) === Number(userId)
          ? peerLastDeliveredMessageId >= Number(row.id)
          : true,
      read_by_peer:
        Number(row.sender_user_id) === Number(userId)
          ? presence.canSeeReadReceipts &&
            peerLastReadMessageId >= Number(row.id)
          : true,
    }))
    .map((row) => mapMessageRow(row, userId));

  return {
    thread: mapThreadRow(thread, userId),
    messages,
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function translateThreadMessage({
  userId,
  threadId,
  messageId,
  targetLanguage,
  refresh = false,
}) {
  const { thread } = await resolveThreadSendAccess({
    userId,
    threadId,
    touchPresence: true,
  });
  const target = String(targetLanguage || "").trim().toLowerCase();
  const message = await repo.getThreadMessageById({ threadId, messageId });
  if (!message) {
    throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  }
  if (message.is_deleted === true || !String(message.body || "").trim()) {
    throw new AppError("THREAD_MESSAGE_TRANSLATION_UNAVAILABLE", {
      status: 409,
    });
  }
  const sourceVersionAt = message.updated_at || message.created_at || new Date().toISOString();
  if (refresh !== true) {
    const cached = await repo.getThreadMessageTranslation({
      messageId,
      targetLanguage: target,
    });
    if (
      cached &&
      new Date(cached.source_version_at).getTime() ===
        new Date(sourceVersionAt).getTime()
    ) {
      return {
        threadId: Number(threadId),
        messageId: Number(messageId),
        cached: true,
        translation: mapThreadMessageTranslationRow(cached),
      };
    }
  }
  const translated = await translateSocialText({
    text: String(message.body || ""),
    targetLanguage: target,
  });
  if (!translated?.ok) {
    throw new AppError("THREAD_MESSAGE_TRANSLATION_UNAVAILABLE", {
      status: 503,
      details: { reason: translated?.reason || "TRANSLATION_FAILED" },
    });
  }
  const stored = await repo.upsertThreadMessageTranslation({
    messageId,
    targetLanguage: translated.targetLanguage || target,
    sourceLanguage: translated.sourceLanguage,
    translatedText: translated.translatedText,
    provider: translated.provider || "openai",
    modelName: translated.model || null,
    sourceVersionAt,
  });
  return {
    threadId: Number(threadId),
    messageId: Number(messageId),
    cached: false,
    translation: mapThreadMessageTranslationRow(stored),
    thread: mapThreadRow(thread, userId),
  };
}

async function resolveThreadSendAccess({ userId, threadId, touchPresence = true }) {
  if (touchPresence) {
    await repo.touchUserPresence(userId);
  }
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const threadKind = normalizeThreadKind(thread.thread_kind);
  let messaging = null;
  if (threadKind === "business") {
    const relation = await repo.getUserRelation({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
    const mapped = mapRelationRow(relation, userId, Number(thread.peer_user_id));
    if (mapped.blockedByMe || mapped.blockedByOther) {
      throw new AppError("RELATION_BLOCKED", {
        status: 403,
        details: { relation: mapped },
      });
    }
    messaging = { isPrimary: true, relation: mapped, hasOrderAccess: false };
  } else if (threadKind === "private") {
    messaging = await resolveMessagingAccess({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
  } else {
    messaging = { isPrimary: true, relation: null, hasOrderAccess: false };
  }
  if (String(thread.request_status || "accepted") === "blocked") {
    throw new AppError("CHAT_REQUEST_BLOCKED", { status: 403 });
  }
  if (String(thread.request_status || "accepted") === "rejected") {
    throw new AppError("CHAT_REQUEST_REJECTED", { status: 403 });
  }
  if (
    threadKind !== "business" &&
    threadKind !== "group" &&
    !messaging.isPrimary &&
    String(thread.request_status || "accepted") === "pending"
  ) {
    throw new AppError("CHAT_REQUEST_PENDING", { status: 403 });
  }
  if (
    threadKind !== "group" &&
    (
      String(thread.peer_request_status || "accepted") === "blocked" ||
      String(thread.peer_request_status || "accepted") === "rejected"
    )
  ) {
    throw new AppError("CHAT_REQUEST_UNAVAILABLE", { status: 403 });
  }
  return { thread, threadKind, messaging };
}

function normalizeOutgoingThreadMessagePayload({
  body,
  attachmentDurationMs = null,
  attachment = null,
  sharedEntity = null,
}) {
  const text = String(body || "").trim();
  const attachmentMeta = attachment?.url
    ? {
        url: attachment.url,
        name: String(attachment.name || "").trim() || "attachment",
        mimeType:
          String(attachment.mimeType || "").trim() || "application/octet-stream",
        sizeBytes:
          attachment.sizeBytes == null ? null : Number(attachment.sizeBytes),
        durationMs:
          attachmentDurationMs == null
            ? attachment.durationMs == null
              ? null
              : Number(attachment.durationMs)
            : Number(attachmentDurationMs),
      }
    : null;

  const normalizedSharedEntity =
    sharedEntity?.type && Number(sharedEntity?.id || 0) > 0
      ? {
          type: String(sharedEntity.type).trim().toLowerCase(),
          id: Number(sharedEntity.id),
          snapshot:
            sharedEntity.snapshot &&
            typeof sharedEntity.snapshot === "object" &&
            !Array.isArray(sharedEntity.snapshot)
              ? sharedEntity.snapshot
              : null,
        }
      : null;

  if (!text && !attachmentMeta && !normalizedSharedEntity) {
    throw new AppError("EMPTY_MESSAGE", { status: 400 });
  }
  if (text) {
    assertContentAllowed(text);
  }

  return {
    text,
    normalizedAttachment:
      attachmentMeta == null
        ? null
        : {
            ...attachmentMeta,
            kind: resolveChatAttachmentKind(attachmentMeta),
          },
    normalizedSharedEntity,
  };
}

async function resolveReplyMessage({ threadId, replyToMessageId = null }) {
  if (replyToMessageId == null) return null;
  const replyTo = await repo.getThreadMessageById({
    threadId,
    messageId: replyToMessageId,
  });
  if (!replyTo) {
    throw new AppError("REPLY_MESSAGE_NOT_FOUND", { status: 404 });
  }
  return replyTo;
}

async function insertAndDispatchThreadMessage({
  userId,
  threadId,
  thread,
  threadKind,
  messaging,
  text,
  replyTo = null,
  normalizedAttachment = null,
  normalizedSharedEntity = null,
  clientMessageId = null,
}) {
  const inserted = await repo.insertThreadMessage({
    threadId,
    senderUserId: userId,
    body: text,
    replyToMessageId: replyTo == null ? null : Number(replyTo.id),
    attachment: normalizedAttachment,
    sharedEntity: normalizedSharedEntity,
    clientMessageId,
  });
  const wasInserted = inserted?._inserted !== false;
  if (wasInserted) {
    await repo.touchThreadLastMessage(threadId);
  }

  const [sender, insertedDetails] = await Promise.all([
    repo.findUserPublicProfile(userId),
    inserted?.id
      ? repo.getThreadMessageDetailsById({
          threadId,
          messageId: Number(inserted.id),
        })
      : Promise.resolve(null),
  ]);

  const mapped = mapMessageRow(
    insertedDetails || {
      ...inserted,
      sender_full_name: sender?.full_name || "",
      sender_image_url: sender?.image_url || null,
      sender_phone: sender?.phone || "",
      sender_role: sender?.role || "user",
      sender_username: sender?.username || null,
      sender_has_premium: false,
      reply_message_id: replyTo == null ? null : Number(replyTo.id),
      reply_sender_user_id: replyTo == null ? null : Number(replyTo.sender_user_id),
      reply_body: replyTo?.body || "",
      reply_attachment_kind: replyTo?.attachment_kind || null,
      reply_attachment_name: replyTo?.attachment_name || null,
      reply_sender_full_name: "",
      attachment_url: normalizedAttachment?.url || null,
      attachment_kind: normalizedAttachment?.kind || null,
      attachment_name: normalizedAttachment?.name || null,
      attachment_mime_type: normalizedAttachment?.mimeType || null,
      attachment_size_bytes: normalizedAttachment?.sizeBytes || null,
      attachment_duration_ms: normalizedAttachment?.durationMs || null,
      shared_entity_type: normalizedSharedEntity?.type || null,
      shared_entity_id: normalizedSharedEntity?.id || null,
      shared_snapshot_json: normalizedSharedEntity?.snapshot || null,
      client_message_id: inserted?.client_message_id || clientMessageId || null,
    },
    userId
  );

  if (wasInserted) {
    const peerUserId = Number(thread.peer_user_id || 0);
  const targetUserIds =
    threadKind === "group"
      ? await repo.listThreadMemberUserIds({
          threadId,
          excludeUserId: userId,
        })
      : peerUserId > 0 && peerUserId !== Number(userId)
      ? [peerUserId]
      : [];
  await repo.upsertThreadParticipantState({
    threadId,
    userId,
    lastReadMessageId: Number(inserted.id),
    lastDeliveredMessageId: Number(inserted.id),
  });
  emitToUser(Number(userId), "social_chat_message", {
    threadId: Number(threadId),
    message: mapped,
  });
  for (const targetUserId of targetUserIds) {
    emitToUser(targetUserId, "social_chat_message", {
      threadId: Number(threadId),
      message: mapped,
    });
  }

  if (targetUserIds.length > 0) {
    if (threadKind === "private" && !messaging.isPrimary) {
      await repo.upsertThreadParticipantState({
        threadId,
        userId: targetUserIds[0],
        inboxBucket: "requests",
        requestStatus: "pending",
      });
    }
    await createManyNotifications(
      targetUserIds.map((targetUserId) => ({
        userId: targetUserId,
        type: "social.chat.message",
        title:
          threadKind === "group"
            ? `رسالة جديدة في ${String(thread.group_title || thread.peer_full_name || "المجموعة").trim()}`
            : `رسالة جديدة من ${sender?.full_name || "مستخدم"}`,
        body: compactMessagePreview(text, normalizedAttachment),
        payload: {
          threadId: Number(threadId),
          senderUserId: Number(userId),
          target: "social_chat",
        },
      }))
    );
  }

  }

  return {
    message: mapped,
    threadId: Number(threadId),
  };
}

/**
 * يرسل رسالة داخل thread بعد التحقق من صلاحية العلاقة وحالة الطلبات
 * وحالة الحظر/القبول للطرفين.
 *
 * Side effects:
 * - يحدّث presence للمرسل
 * - يكتب الرسالة في DB
 * - يحدّث last message metadata
 * - يبث event realtime للطرف الآخر
 * - قد ينشئ notification خارجية حسب إعدادات الطرف المتلقي
 *
 * Critical notes:
 * - هذه الدالة هي نقطة الحقيقة لإرسال الرسائل. لا تضف path بديل يكتب
 *   مباشرة إلى repo بدون المرور بنفس checks.
 */
export async function sendMessage({
  userId,
  threadId,
  body,
  replyToMessageId = null,
  clientMessageId = null,
  attachmentDurationMs = null,
  attachment = null,
  sharedEntity = null,
}) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const threadKind = normalizeThreadKind(thread.thread_kind);
  let messaging = null;
  if (threadKind === "business") {
    const relation = await repo.getUserRelation({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
    const mapped = mapRelationRow(relation, userId, Number(thread.peer_user_id));
    if (mapped.blockedByMe || mapped.blockedByOther) {
      throw new AppError("RELATION_BLOCKED", {
        status: 403,
        details: { relation: mapped },
      });
    }
    messaging = { isPrimary: true, relation: mapped, hasOrderAccess: false };
  } else if (threadKind === "private") {
    messaging = await resolveMessagingAccess({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
  } else {
    messaging = { isPrimary: true, relation: null, hasOrderAccess: false };
  }
  if (String(thread.request_status || "accepted") === "blocked") {
    throw new AppError("CHAT_REQUEST_BLOCKED", { status: 403 });
  }
  if (String(thread.request_status || "accepted") === "rejected") {
    throw new AppError("CHAT_REQUEST_REJECTED", { status: 403 });
  }
  if (
    threadKind !== "business" &&
    threadKind !== "group" &&
    !messaging.isPrimary &&
    String(thread.request_status || "accepted") === "pending"
  ) {
    throw new AppError("CHAT_REQUEST_PENDING", { status: 403 });
  }
  if (
    threadKind !== "group" &&
    (
      String(thread.peer_request_status || "accepted") === "blocked" ||
      String(thread.peer_request_status || "accepted") === "rejected"
    )
  ) {
    throw new AppError("CHAT_REQUEST_UNAVAILABLE", { status: 403 });
  }

  const text = String(body || "").trim();
  const attachmentMeta = attachment?.url
    ? {
        url: attachment.url,
        name: String(attachment.name || "").trim() || "attachment",
        mimeType:
          String(attachment.mimeType || "").trim() || "application/octet-stream",
        sizeBytes:
          attachment.sizeBytes == null ? null : Number(attachment.sizeBytes),
        durationMs:
          attachmentDurationMs == null
            ? attachment.durationMs == null
              ? null
              : Number(attachment.durationMs)
            : Number(attachmentDurationMs),
      }
    : null;

  const normalizedSharedEntity =
    sharedEntity?.type && Number(sharedEntity?.id || 0) > 0
      ? {
          type: String(sharedEntity.type).trim().toLowerCase(),
          id: Number(sharedEntity.id),
          snapshot:
            sharedEntity.snapshot &&
            typeof sharedEntity.snapshot === "object" &&
            !Array.isArray(sharedEntity.snapshot)
              ? sharedEntity.snapshot
              : null,
        }
      : null;

  if (!text && !attachmentMeta && !normalizedSharedEntity) {
    throw new AppError("EMPTY_MESSAGE", { status: 400 });
  }
  if (text) {
    assertContentAllowed(text);
  }

  let replyTo = null;
  if (replyToMessageId != null) {
    replyTo = await repo.getThreadMessageById({
      threadId,
      messageId: replyToMessageId,
    });
    if (!replyTo) {
      throw new AppError("REPLY_MESSAGE_NOT_FOUND", { status: 404 });
    }
  }

  const normalizedAttachment =
    attachmentMeta == null
      ? null
      : {
          ...attachmentMeta,
          kind: resolveChatAttachmentKind(attachmentMeta),
        };

  const inserted = await repo.insertThreadMessage({
    threadId,
    senderUserId: userId,
    body: text,
    replyToMessageId: replyTo == null ? null : Number(replyTo.id),
    attachment: normalizedAttachment,
    sharedEntity: normalizedSharedEntity,
    clientMessageId,
  });
  const wasInserted = inserted?._inserted !== false;
  if (wasInserted) {
    await repo.touchThreadLastMessage(threadId);
  }

  const [sender, insertedDetails] = await Promise.all([
    repo.findUserPublicProfile(userId),
    inserted?.id
      ? repo.getThreadMessageDetailsById({
          threadId,
          messageId: Number(inserted.id),
        })
      : Promise.resolve(null),
  ]);

  const mapped = mapMessageRow(
    insertedDetails || {
      ...inserted,
      sender_full_name: sender?.full_name || "",
      sender_image_url: sender?.image_url || null,
      sender_phone: sender?.phone || "",
      sender_role: sender?.role || "user",
      sender_username: sender?.username || null,
      sender_has_premium: false,
      reply_message_id: replyTo == null ? null : Number(replyTo.id),
      reply_sender_user_id: replyTo == null ? null : Number(replyTo.sender_user_id),
      reply_body: replyTo?.body || "",
      reply_attachment_kind: replyTo?.attachment_kind || null,
      reply_attachment_name: replyTo?.attachment_name || null,
      reply_sender_full_name: "",
      attachment_url: normalizedAttachment?.url || null,
      attachment_kind: normalizedAttachment?.kind || null,
      attachment_name: normalizedAttachment?.name || null,
      attachment_mime_type: normalizedAttachment?.mimeType || null,
      attachment_size_bytes: normalizedAttachment?.sizeBytes || null,
      attachment_duration_ms: normalizedAttachment?.durationMs || null,
      shared_entity_type: normalizedSharedEntity?.type || null,
      shared_entity_id: normalizedSharedEntity?.id || null,
      shared_snapshot_json: normalizedSharedEntity?.snapshot || null,
    },
    userId
  );

  if (!wasInserted) {
    return {
      message: mapped,
      threadId: Number(threadId),
    };
  }

  const peerUserId = Number(thread.peer_user_id || 0);
  const targetUserIds =
    threadKind === "group"
      ? await repo.listThreadMemberUserIds({
          threadId,
          excludeUserId: userId,
        })
      : peerUserId > 0 && peerUserId !== Number(userId)
      ? [peerUserId]
      : [];
  await repo.upsertThreadParticipantState({
    threadId,
    userId,
    lastReadMessageId: Number(inserted.id),
    lastDeliveredMessageId: Number(inserted.id),
  });
  emitToUser(Number(userId), "social_chat_message", {
    threadId: Number(threadId),
    message: mapped,
  });
  for (const targetUserId of targetUserIds) {
    emitToUser(targetUserId, "social_chat_message", {
      threadId: Number(threadId),
      message: mapped,
    });
  }

  if (targetUserIds.length > 0) {
    if (threadKind === "private" && threadKind !== "business" && !messaging.isPrimary) {
      await repo.upsertThreadParticipantState({
        threadId,
        userId: targetUserIds[0],
        inboxBucket: "requests",
        requestStatus: "pending",
      });
    }
    await createManyNotifications(
      targetUserIds.map((targetUserId) => ({
        userId: targetUserId,
        type: "social.chat.message",
        title:
          threadKind === "group"
            ? `رسالة جديدة في ${String(thread.group_title || thread.peer_full_name || "المجموعة").trim()}`
            : `\u0631\u0633\u0627\u0644\u0629 \u062C\u062F\u064A\u062F\u0629 \u0645\u0646 ${sender?.full_name || "\u0645\u0633\u062A\u062E\u062F\u0645"}`,
        body: compactMessagePreview(text, normalizedAttachment),
        payload: {
          threadId: Number(threadId),
          senderUserId: Number(userId),
          target: "social_chat",
        },
      }))
    );
  }

  return {
    message: mapped,
    threadId: Number(threadId),
  };
}

export async function listScheduledMessages({ userId, threadId, query }) {
  await resolveThreadSendAccess({ userId, threadId });
  const rows = await repo.listScheduledMessagesForUserThread({
    threadId,
    userId,
    limit: query.limit,
  });
  const items = rows.map((row) => mapScheduledMessageRow(row));
  return {
    threadId: Number(threadId),
    items,
    scheduledMessages: items,
  };
}

export async function scheduleMessage({
  userId,
  threadId,
  body,
  scheduledFor,
  replyToMessageId = null,
  attachmentDurationMs = null,
  attachment = null,
  sharedEntity = null,
}) {
  await resolveThreadSendAccess({ userId, threadId });
  const { text, normalizedAttachment, normalizedSharedEntity } =
    normalizeOutgoingThreadMessagePayload({
      body,
      attachmentDurationMs,
      attachment,
      sharedEntity,
    });
  const replyTo = await resolveReplyMessage({ threadId, replyToMessageId });
  const inserted = await repo.insertScheduledThreadMessage({
    threadId,
    senderUserId: userId,
    body: text,
    scheduledFor,
    replyToMessageId: replyTo == null ? null : Number(replyTo.id),
    attachment: normalizedAttachment,
    sharedEntity: normalizedSharedEntity,
  });
  const mapped = mapScheduledMessageRow({
    ...inserted,
    reply_message_id: replyTo == null ? null : Number(replyTo.id),
    reply_sender_user_id: replyTo == null ? null : Number(replyTo.sender_user_id),
    reply_body: replyTo?.body || "",
    reply_attachment_kind: replyTo?.attachment_kind || null,
    reply_attachment_name: replyTo?.attachment_name || null,
    reply_sender_username: null,
    reply_sender_full_name: "",
  });
  emitToUser(Number(userId), "social_chat_scheduled_message", {
    action: "scheduled",
    threadId: Number(threadId),
    item: mapped,
  });
  return {
    threadId: Number(threadId),
    item: mapped,
  };
}

export async function cancelScheduledMessage({
  userId,
  threadId,
  scheduledMessageId,
}) {
  await resolveThreadSendAccess({ userId, threadId, touchPresence: false });
  const cancelled = await repo.cancelScheduledThreadMessage({
    threadId,
    scheduledMessageId,
    senderUserId: userId,
  });
  if (!cancelled) {
    throw new AppError("SCHEDULED_MESSAGE_NOT_FOUND", { status: 404 });
  }
  const mapped = mapScheduledMessageRow(cancelled);
  emitToUser(Number(userId), "social_chat_scheduled_message", {
    action: "cancelled",
    threadId: Number(threadId),
    scheduledMessageId: Number(scheduledMessageId),
  });
  return {
    ok: true,
    threadId: Number(threadId),
    item: mapped,
  };
}

async function processScheduledThreadMessages() {
  if (socialScheduledMessageRunning) return;
  socialScheduledMessageRunning = true;
  try {
    const rows = await repo.listDueScheduledThreadMessages({ limit: 20 });
    for (const row of rows) {
      const claimed = await repo.claimScheduledThreadMessage({
        scheduledMessageId: Number(row.id),
      });
      if (!claimed) continue;
      try {
        const result = await sendMessage({
          userId: Number(claimed.sender_user_id),
          threadId: Number(claimed.thread_id),
          body: claimed.body || "",
          replyToMessageId:
            claimed.reply_to_message_id == null
              ? null
              : Number(claimed.reply_to_message_id),
          attachmentDurationMs:
            claimed.attachment_duration_ms == null
              ? null
              : Number(claimed.attachment_duration_ms),
          attachment: claimed.attachment_url
            ? {
                url: claimed.attachment_url,
                name: claimed.attachment_name || "attachment",
                mimeType:
                  claimed.attachment_mime_type || "application/octet-stream",
                sizeBytes:
                  claimed.attachment_size_bytes == null
                    ? null
                    : Number(claimed.attachment_size_bytes),
                durationMs:
                  claimed.attachment_duration_ms == null
                    ? null
                    : Number(claimed.attachment_duration_ms),
              }
            : null,
          sharedEntity:
            claimed.shared_entity_type == null
              ? null
              : {
                  type: claimed.shared_entity_type,
                  id: Number(claimed.shared_entity_id || 0),
                  snapshot: claimed.shared_snapshot_json || null,
                },
        });
        await repo.markScheduledThreadMessageSent({
          scheduledMessageId: Number(claimed.id),
          sentMessageId: Number(result.message.id),
        });
        emitToUser(
          Number(claimed.sender_user_id),
          "social_chat_scheduled_message",
          {
            action: "sent",
            threadId: Number(claimed.thread_id),
            scheduledMessageId: Number(claimed.id),
            sentMessageId: Number(result.message.id),
          }
        );
      } catch (error) {
        const updated = await repo.rescheduleScheduledThreadMessageFailure({
          scheduledMessageId: Number(claimed.id),
          errorCode: error?.code || error?.message || "SCHEDULED_SEND_FAILED",
        });
        emitToUser(
          Number(claimed.sender_user_id),
          "social_chat_scheduled_message",
          {
            action: updated?.status === "failed" ? "failed" : "retrying",
            threadId: Number(claimed.thread_id),
            scheduledMessageId: Number(claimed.id),
            errorCode: updated?.last_error_code || null,
          }
        );
      }
    }
  } catch (error) {
    console.warn(
      "[social] scheduled message processing failed",
      error?.message || error
    );
  } finally {
    socialScheduledMessageRunning = false;
  }
}

export function startSocialScheduledMessageWorker({ intervalMs = 5000 } = {}) {
  if (socialScheduledMessageWorker) return;
  socialScheduledMessageWorker = setInterval(() => {
    processScheduledThreadMessages().catch((error) => {
      console.warn(
        "[social] scheduled message worker tick failed",
        error?.message || error
      );
    });
  }, Math.max(5000, Number(intervalMs) || 10000));
  socialScheduledMessageWorker.unref?.();
  void processScheduledThreadMessages();
}

export async function acceptChatRequest({ userId, threadId }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  if (String(thread.inbox_bucket || "primary") !== "requests") {
    throw new AppError("CHAT_REQUEST_NOT_FOUND", { status: 404 });
  }
  await repo.upsertThreadParticipantState({
    threadId,
    userId,
    inboxBucket: "primary",
    requestStatus: "accepted",
  });
  return {
    ok: true,
    thread: mapThreadRow(
      {
        ...thread,
        inbox_bucket: "primary",
        request_status: "accepted",
        accepted_at: new Date().toISOString(),
      },
      userId
    ),
  };
}

export async function rejectChatRequest({ userId, threadId }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  await repo.upsertThreadParticipantState({
    threadId,
    userId,
    inboxBucket: "requests",
    requestStatus: "rejected",
    rejectedAt: new Date().toISOString(),
  });
  return { ok: true, threadId: Number(threadId), status: "rejected" };
}

export async function blockChatRequest({ userId, threadId }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  await repo.upsertThreadParticipantState({
    threadId,
    userId,
    inboxBucket: "requests",
    requestStatus: "blocked",
  });
  return { ok: true, threadId: Number(threadId), status: "blocked" };
}

export async function setThreadMute({ userId, threadId, enabled }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const state = await repo.upsertThreadParticipantState({
    threadId,
    userId,
    muted: enabled === true,
  });
  return {
    threadId: Number(threadId),
    muted: state?.muted_until != null && new Date(state.muted_until).getTime() > Date.now(),
    mutedUntil: state?.muted_until || null,
  };
}

export async function setThreadPinned({ userId, threadId, enabled }) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const alreadyPinned = await repo.isThreadPinnedForUser({ threadId, userId });
  if (enabled === true && !alreadyPinned) {
    const pinnedCount = await repo.countPinnedThreadsForUser({ userId });
    if (pinnedCount >= 3) {
      throw new AppError("THREAD_PIN_LIMIT_REACHED", { status: 409 });
    }
  }
  const state = await repo.upsertThreadParticipantState({
    threadId,
    userId,
    pinned: enabled === true,
  });
  emitToUser(Number(userId), "social_chat_thread_updated", {
    threadId: Number(threadId),
    action: enabled === true ? "thread_pinned" : "thread_unpinned",
    actorUserId: Number(userId),
  });
  return {
    threadId: Number(threadId),
    pinned: state?.pinned_at != null,
    pinnedAt: state?.pinned_at || null,
  };
}

export async function setThreadTheme({ userId, threadId, themeKey }) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const state = await repo.upsertThreadParticipantState({
    threadId,
    userId,
    themeKey,
  });
  emitToUser(Number(userId), "social_chat_thread_updated", {
    threadId: Number(threadId),
    action: "theme_updated",
    actorUserId: Number(userId),
    themeKey:
      String(state?.theme_key || themeKey || "default").trim().toLowerCase() ||
      "default",
  });
  return {
    threadId: Number(threadId),
    themeKey:
      String(state?.theme_key || themeKey || "default").trim().toLowerCase() ||
      "default",
  };
}

/**
 * يعلّم thread كمقروء للمستخدم الحالي ويحدث counters/read receipts.
 *
 * Maintenance notes:
 * - عند عدم اختفاء unread badge افحص هذه الدالة ثم `repo.markThreadRead`
 *   ثم consumer الواجهة الذي يلتقط الحدث.
 */
export async function markThreadRead({ userId, threadId }) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const latestMessageId = await repo.getLatestThreadMessageId(threadId);
  if (latestMessageId != null) {
    await repo.upsertThreadParticipantState({
      threadId,
      userId,
      lastReadMessageId: latestMessageId,
      lastDeliveredMessageId: latestMessageId,
    });
    if (normalizeThreadKind(thread.thread_kind) !== "group" && Number(thread.peer_user_id || 0) > 0) {
      emitThreadStateUpdate({
        threadId,
        actorUserId: userId,
        peerUserId: Number(thread.peer_user_id),
        lastReadMessageId: latestMessageId,
        lastDeliveredMessageId: latestMessageId,
      });
    }
  }
  return { ok: true, threadId: Number(threadId), lastReadMessageId: latestMessageId };
}

export async function pinThreadMessage({ userId, threadId, messageId }) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const target = await repo.getThreadMessageById({ threadId, messageId });
  if (!target) throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  const alreadyPinned = await repo.isThreadMessagePinned({ threadId, messageId });
  if (!alreadyPinned) {
    const pinnedCount = await repo.countPinnedMessagesForThread({ threadId });
    if (pinnedCount >= 3) {
      throw new AppError("THREAD_MESSAGE_PIN_LIMIT_REACHED", { status: 409 });
    }
  }
  await repo.pinThreadMessage({
    threadId,
    messageId,
    pinnedByUserId: userId,
  });
  const [details, summary, pinnedRows, targetUserIds] = await Promise.all([
    repo.getThreadMessageDetailsById({ threadId, messageId }),
    repo.listMessageReactionsForMessages({
      messageIds: [Number(messageId)],
      userId,
    }),
    repo.listPinnedMessagesForThread({ threadId, limit: 3 }),
    repo.listThreadMemberUserIds({ threadId }),
  ]);
  if (!details) throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  const message = mapMessageRow(
    {
      ...details,
      reaction_counts: summary[Number(messageId)]?.counts || {},
      reaction_total_count: Number(summary[Number(messageId)]?.totalCount || 0),
      my_reaction: summary[Number(messageId)]?.myReaction || null,
    },
    userId
  );
  const payload = {
    threadId: Number(threadId),
    action: "message_pinned",
    actorUserId: Number(userId),
    messageId: Number(messageId),
  };
  for (const targetUserId of targetUserIds) {
    emitToUser(targetUserId, "social_chat_thread_updated", payload);
  }
  return {
    threadId: Number(threadId),
    message,
    pinnedMessages: pinnedRows.map((row) => mapMessageRow(row, userId)),
  };
}

export async function unpinThreadMessage({ userId, threadId, messageId }) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const removed = await repo.unpinThreadMessage({ threadId, messageId });
  if (!removed) {
    throw new AppError("THREAD_MESSAGE_PIN_NOT_FOUND", { status: 404 });
  }
  const [details, summary, pinnedRows, targetUserIds] = await Promise.all([
    repo.getThreadMessageDetailsById({ threadId, messageId }),
    repo.listMessageReactionsForMessages({
      messageIds: [Number(messageId)],
      userId,
    }),
    repo.listPinnedMessagesForThread({ threadId, limit: 3 }),
    repo.listThreadMemberUserIds({ threadId }),
  ]);
  const message =
    details == null
      ? null
      : mapMessageRow(
          {
            ...details,
            reaction_counts: summary[Number(messageId)]?.counts || {},
            reaction_total_count: Number(
              summary[Number(messageId)]?.totalCount || 0
            ),
            my_reaction: summary[Number(messageId)]?.myReaction || null,
          },
          userId
        );
  const payload = {
    threadId: Number(threadId),
    action: "message_unpinned",
    actorUserId: Number(userId),
    messageId: Number(messageId),
  };
  for (const targetUserId of targetUserIds) {
    emitToUser(targetUserId, "social_chat_thread_updated", payload);
  }
  return {
    threadId: Number(threadId),
    message,
    pinnedMessages: pinnedRows.map((row) => mapMessageRow(row, userId)),
  };
}

export async function listThreadMedia({ userId, threadId, query }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const rows = await repo.listThreadMedia({
    threadId,
    limit: query.limit,
    beforeId: query.beforeId,
  });
  return {
    items: rows.map((row) => ({
      id: Number(row.id),
      threadId: Number(row.thread_id),
      senderUserId: Number(row.sender_user_id),
      createdAt: row.created_at || null,
      attachment: mapMessageAttachment(row),
    })),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

/**
 * يبث حالة الكتابة اللحظية للطرف الآخر مع touch للحضور الحالي.
 *
 * Critical notes:
 * - typing event intentionally ephemeral؛ لا يعتمد عليه كحالة دائمة.
 * - أي زيادة مفرطة في النداءات هنا قد تسبب load غير ضروري على SSE/Redis.
 */
export async function emitThreadTyping({ userId, threadId, typing }) {
  await repo.touchUserPresence(userId);
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  if (thread.self_typing_indicators_enabled === false) {
    return { ok: true, suppressed: true };
  }
  const threadKind = normalizeThreadKind(thread.thread_kind);
  const presence = buildThreadPresence(thread);
  if (threadKind !== "group" && !presence.canSeeTypingIndicators) {
    return { ok: true, suppressed: true };
  }
  const sender = await repo.findUserPublicProfile(userId);
  const targetUserIds =
    threadKind === "group"
      ? await repo.listThreadMemberUserIds({
          threadId,
          excludeUserId: userId,
        })
      : [Number(thread.peer_user_id || 0)].filter((value) => value > 0);
  for (const targetUserId of targetUserIds) {
    emitToUser(targetUserId, "social_chat_typing", {
      threadId: Number(threadId),
      actorUserId: Number(userId),
      actorDisplayName: sender?.full_name || "",
      typing: typing === true,
    });
  }
  return { ok: true };
}

export async function listAdminMonitoredCommunityMessages({
  userId,
  isSuperAdmin,
  scopeType,
  scopeCode,
  query,
}) {
  if (isSuperAdmin !== true) {
    throw new AppError("FORBIDDEN_SUPER_ADMIN_ONLY", { status: 403 });
  }

  const chat = await repo.getMonitorableCommunityChatForSuperAdmin({
    scopeType,
    scopeCode,
  });
  if (!chat) {
    throw new AppError("COMMUNITY_CHAT_NOT_FOUND", { status: 404 });
  }

  const rows = await repo.listScopeChatMessages({
    scopeType,
    scopeCode,
    limit: query.limit,
    beforeId: query.beforeId,
  });
  const messageIds = rows
    .map((row) => Number(row.id))
    .filter((value) => Number.isFinite(value) && value > 0);
  const reactionsByMessage = await repo.listScopeChatMessageReactionsForMessages({
    messageIds,
    userId,
  });

  return {
    chat: mapCommunityMonitoredChatRow(chat),
    messages: rows
      .map((row) => ({
        ...row,
        reaction_counts: reactionsByMessage[Number(row.id)]?.counts || {},
        reaction_total_count: Number(
          reactionsByMessage[Number(row.id)]?.totalCount || 0
        ),
        my_reaction: reactionsByMessage[Number(row.id)]?.myReaction || null,
      }))
      .map((row) => mapScopeChatMessageRow(row, userId))
      .reverse(),
    nextCursor:
      rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function updateMessage({
  userId,
  threadId,
  messageId,
  body,
}) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const threadKind = normalizeThreadKind(thread.thread_kind);
  if (threadKind === "private") {
    await ensureUsersCanConnect({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
  } else if (threadKind === "business") {
    const relation = await repo.getUserRelation({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
    const mapped = mapRelationRow(relation, userId, Number(thread.peer_user_id));
    if (mapped.blockedByMe || mapped.blockedByOther) {
      throw new AppError("RELATION_BLOCKED", {
        status: 403,
        details: { relation: mapped },
      });
    }
  }

  const target = await repo.getThreadMessageById({ threadId, messageId });
  if (!target) throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  if (Number(target.sender_user_id) !== Number(userId)) {
    throw new AppError("THREAD_CHAT_EDIT_FORBIDDEN", { status: 403 });
  }
  if (!isMessageWithinEditDeleteWindow(target)) {
    throw new AppError("THREAD_CHAT_EDIT_WINDOW_EXPIRED", { status: 409 });
  }

  const text = String(body || "").trim();
  if (!text) {
    throw new AppError("EMPTY_MESSAGE", { status: 400 });
  }
  assertContentAllowed(text);
  await repo.updateThreadMessage({
    threadId,
    messageId,
    body: text,
  });

  const details = await repo.getThreadMessageDetailsById({
    threadId,
    messageId,
  });
  if (!details) throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  const summary = await repo.listMessageReactionsForMessages({
    messageIds: [Number(messageId)],
    userId,
  });
  const message = mapMessageRow(
    {
      ...details,
      reaction_counts: summary[Number(messageId)]?.counts || {},
      reaction_total_count: Number(summary[Number(messageId)]?.totalCount || 0),
      my_reaction: summary[Number(messageId)]?.myReaction || null,
    },
    userId
  );

  const payload = {
    threadId: Number(threadId),
    messageId: Number(messageId),
    message,
  };
  emitToUser(Number(userId), "social_chat_message", payload);
  const targetUserIds =
    threadKind === "group"
      ? await repo.listThreadMemberUserIds({
          threadId,
          excludeUserId: userId,
        })
      : [Number(thread.peer_user_id || 0)].filter((value) => value > 0);
  for (const targetUserId of targetUserIds) {
    emitToUser(targetUserId, "social_chat_message", payload);
  }

  return {
    threadId: Number(threadId),
    message,
  };
}

export async function deleteMessage({
  userId,
  threadId,
  messageId,
}) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const threadKind = normalizeThreadKind(thread.thread_kind);
  if (threadKind === "private") {
    await ensureUsersCanConnect({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
  } else if (threadKind === "business") {
    const relation = await repo.getUserRelation({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
    const mapped = mapRelationRow(relation, userId, Number(thread.peer_user_id));
    if (mapped.blockedByMe || mapped.blockedByOther) {
      throw new AppError("RELATION_BLOCKED", {
        status: 403,
        details: { relation: mapped },
      });
    }
  }

  const target = await repo.getThreadMessageById({ threadId, messageId });
  if (!target) throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  if (Number(target.sender_user_id) !== Number(userId)) {
    throw new AppError("THREAD_CHAT_DELETE_FORBIDDEN", { status: 403 });
  }
  if (!isMessageWithinEditDeleteWindow(target)) {
    throw new AppError("THREAD_CHAT_DELETE_WINDOW_EXPIRED", { status: 409 });
  }

  const deleted = await repo.softDeleteThreadMessage({
    threadId,
    messageId,
  });
  if (!deleted) throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });

  const details = await repo.getThreadMessageDetailsById({
    threadId,
    messageId,
    includeDeleted: true,
  });
  if (!details) throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  const message = mapMessageRow(
    {
      ...details,
      reaction_counts: {},
      reaction_total_count: 0,
      my_reaction: null,
    },
    userId
  );

  const payload = {
    threadId: Number(threadId),
    messageId: Number(messageId),
    message,
  };
  emitToUser(Number(userId), "social_chat_message", payload);
  const targetUserIds =
    threadKind === "group"
      ? await repo.listThreadMemberUserIds({
          threadId,
          excludeUserId: userId,
        })
      : [Number(thread.peer_user_id || 0)].filter((value) => value > 0);
  for (const targetUserId of targetUserIds) {
    emitToUser(targetUserId, "social_chat_message", payload);
  }

  return {
    threadId: Number(threadId),
    message,
    deleted: true,
  };
}

export async function toggleMessageReaction({ userId, threadId, messageId, reaction }) {
  const thread = await repo.getThreadForUser({ threadId, userId });
  if (!thread) throw new AppError("THREAD_NOT_FOUND", { status: 404 });
  const threadKind = normalizeThreadKind(thread.thread_kind);
  if (threadKind === "private") {
    await ensureUsersCanConnect({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
  } else if (threadKind === "business") {
    const relation = await repo.getUserRelation({
      userId,
      otherUserId: Number(thread.peer_user_id),
    });
    const mapped = mapRelationRow(relation, userId, Number(thread.peer_user_id));
    if (mapped.blockedByMe || mapped.blockedByOther) {
      throw new AppError("RELATION_BLOCKED", {
        status: 403,
        details: { relation: mapped },
      });
    }
  }

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

  const payload = {
    threadId: Number(threadId),
    messageId: Number(messageId),
    reaction: toggled.reaction,
    active: toggled.active === true,
    reactions: details,
  };
  emitToUser(Number(userId), "social_chat_message", payload);
  const targetUserIds =
    threadKind === "group"
      ? await repo.listThreadMemberUserIds({
          threadId,
          excludeUserId: userId,
        })
      : [Number(thread.peer_user_id || 0)].filter((value) => value > 0);
  for (const targetUserId of targetUserIds) {
    emitToUser(targetUserId, "social_chat_message", payload);
  }

  return {
    messageId: Number(messageId),
    reaction: toggled.reaction,
    active: toggled.active === true,
    reactions: details,
  };
}

export async function setUserNotificationPreference({
  userId,
  otherUserId,
  enabled,
}) {
  if (Number(userId) === Number(otherUserId)) {
    throw new AppError("NOTIFICATION_PREF_SELF_NOT_ALLOWED", { status: 400 });
  }
  const other = await repo.findUserPublicProfile(otherUserId);
  if (!other) throw new AppError("USER_NOT_FOUND", { status: 404 });

  const updated = await repo.upsertUserNotificationPreference({
    userId,
    actorUserId: otherUserId,
    enabled: enabled === true,
    updatedByUserId: userId,
  });

  return {
    userId: Number(otherUserId),
    notificationPreference: mapNotificationPreferenceRow(updated),
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
        target: "social_profile",
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
        target: "social_profile",
      },
    });
  }

  emitToUser(Number(userId), "social_relation_update", { relation: mapped });
  emitToUser(Number(otherUserId), "social_relation_update", {
    relation: mapRelationRow(updated, otherUserId, userId),
  });
  if (mapped.state === "accepted") {
    await sendFriendshipWelcomeMessage({ userId, otherUserId });
  }
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
      target: "social_profile",
    },
  });

  emitToUser(Number(userId), "social_relation_update", { relation: next });
  emitToUser(Number(otherUserId), "social_relation_update", {
    relation: mapRelationRow(updated, otherUserId, userId),
  });
  await sendFriendshipWelcomeMessage({ userId, otherUserId });

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
  const caller = await repo.findUserPublicProfile(userId);
  const callerDisplayName = caller?.full_name || "مستخدم";
  const calleeDisplayName = thread.peer_full_name || "الطرف الآخر";
  const incomingPayload = {
    eventType: "incoming_call",
    threadId: Number(threadId),
    session: mapCallSession(session, peerUserId),
    signal: mappedSignal,
    remoteDisplayName: callerDisplayName,
    caller: {
      userId: Number(userId),
      fullName: callerDisplayName,
    },
  };

  emitToUser(peerUserId, "social_call_update", incomingPayload);
  emitToUser(Number(userId), "social_call_update", {
    eventType: "outgoing_call",
    threadId: Number(threadId),
    session: mappedSession,
    signal: mappedSignal,
    remoteDisplayName: calleeDisplayName,
  });

  await createNotification({
    userId: peerUserId,
    type: "social.call.incoming",
    title: `\u0645\u0643\u0627\u0644\u0645\u0629 \u0648\u0627\u0631\u062F\u0629 \u0645\u0646 ${callerDisplayName}`, 
    body: "\u0627\u0636\u063A\u0637 \u0644\u0644\u0631\u062F \u0639\u0644\u0649 \u0627\u0644\u0645\u0643\u0627\u0644\u0645\u0629 \u062F\u0627\u062E\u0644 \u0627\u0644\u062A\u0637\u0628\u064A\u0642.",
    payload: {
      threadId: Number(threadId),
      sessionId: Number(session.id),
      senderUserId: Number(userId),
      remoteDisplayName: callerDisplayName,
      target: "social_call",
      requiresAction: true,
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

async function resolveScopeTargetUser({ targetUserId, scopeType, scopeCode }) {
  const target = await repo.findUserAddressMeta(targetUserId);
  if (!target) throw new AppError("USER_NOT_FOUND", { status: 404 });
  const hierarchy = hierarchyFromUserRow(target);
  const inScope = doesHierarchyMatchScope(hierarchy, scopeType, scopeCode);
  if (!inScope) {
    throw new AppError("COMMUNITY_TARGET_OUT_OF_SCOPE", { status: 409 });
  }
  return target;
}

const superAdminUserActions = new Set([
  "disable_account",
  "enable_account",
  "promote_admin",
  "demote_user",
  "grant_block_manager",
  "revoke_block_manager",
  "grant_compound_manager",
  "revoke_compound_manager",
  "grant_building_manager",
  "revoke_building_manager",
]);

async function ensureSuperAdminActor(userId) {
  const actor = await repo.findUserAddressMeta(userId);
  if (!actor) throw new AppError("USER_NOT_FOUND", { status: 404 });
  if (!isSuperAdminUser(actor)) {
    throw new AppError("FORBIDDEN_SUPER_ADMIN_ONLY", { status: 403 });
  }
  return actor;
}

async function resolveManagerTargetScope(action, targetUser) {
  const hierarchy = hierarchyFromUserRow(targetUser);
  if (action.includes("block")) {
    if (!hierarchy.block) {
      throw new AppError("COMMUNITY_SCOPE_INVALID", {
        status: 409,
        details: { fields: ["block"] },
      });
    }
    return { scopeType: "block", scopeCode: hierarchy.block };
  }
  if (action.includes("compound")) {
    if (!hierarchy.compound) {
      throw new AppError("COMMUNITY_SCOPE_INVALID", {
        status: 409,
        details: { fields: ["compound"] },
      });
    }
    return { scopeType: "compound", scopeCode: hierarchy.compound };
  }
  if (!hierarchy.building) {
    throw new AppError("COMMUNITY_SCOPE_INVALID", {
      status: 409,
      details: { fields: ["building"] },
    });
  }
  return { scopeType: "building", scopeCode: hierarchy.building };
}

export async function runSuperAdminUserAction({
  userId,
  targetUserId,
  action,
  note = null,
}) {
  await ensureSuperAdminActor(userId);
  const normalizedAction = String(action || "").trim().toLowerCase();
  const normalizedNote = String(note || "").trim();
  if (!superAdminUserActions.has(normalizedAction)) {
    throw new AppError("SUPER_ADMIN_ACTION_INVALID", { status: 400 });
  }

  if (Number(userId) === Number(targetUserId)) {
    throw new AppError("SUPER_ADMIN_ACTION_SELF_NOT_ALLOWED", { status: 400 });
  }

  const target = await repo.findUserAddressMeta(targetUserId);
  if (!target) throw new AppError("USER_NOT_FOUND", { status: 404 });
  if (target.is_super_admin === true) {
    throw new AppError("SUPER_ADMIN_TARGET_FORBIDDEN", { status: 403 });
  }

  if (
    normalizedAction.includes("manager") &&
    !hasManagerAssignableRole(target.role || "")
  ) {
    throw new AppError("COMMUNITY_MANAGER_ROLE_NOT_ALLOWED", { status: 409 });
  }

  if (normalizedAction === "disable_account") {
    await repo.setUserAccountDisabled({
      userId: targetUserId,
      disabled: true,
      note: normalizedNote || null,
      actedByUserId: userId,
    });
    await revokeAllUserSessions({
      userId: Number(targetUserId),
      reason: "account_disabled_by_super_admin",
    });
    await markUserSessionsRevokedAfter(Number(targetUserId));
    invalidateSessionAccessCacheForUser({
      userId: Number(targetUserId),
    });
  } else if (normalizedAction === "enable_account") {
    await repo.setUserAccountDisabled({
      userId: targetUserId,
      disabled: false,
      note: null,
      actedByUserId: userId,
    });
  } else if (normalizedAction === "promote_admin") {
    await repo.updateUserRole({ userId: targetUserId, role: "admin" });
  } else if (normalizedAction === "demote_user") {
    await repo.updateUserRole({ userId: targetUserId, role: "user" });
  } else if (normalizedAction.startsWith("grant_")) {
    const scope = await resolveManagerTargetScope(normalizedAction, target);
    await repo.addScopeManager({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      managerUserId: targetUserId,
      assignedByUserId: userId,
    });
  } else if (normalizedAction.startsWith("revoke_")) {
    const scope = await resolveManagerTargetScope(normalizedAction, target);
    await repo.removeScopeManager({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      managerUserId: targetUserId,
    });
  }

  const refreshedTarget = await repo.findUserAddressMeta(targetUserId);
  const controls = await buildSuperAdminControlsForTarget(refreshedTarget || target);
  return {
    targetUserId: Number(targetUserId),
    action: normalizedAction,
    superAdminControls: controls,
  };
}

export async function getMyCommunityScopes({ userId, userRole }) {
  const viewer = await repo.findUserAddressMeta(userId);
  if (!viewer) throw new AppError("USER_NOT_FOUND", { status: 404 });
  if (viewer.is_account_disabled === true) {
    throw new AppError("ACCOUNT_DISABLED", { status: 403 });
  }

  const role = String(userRole || viewer.role || "").trim().toLowerCase();
  const isSuperAdmin = isSuperAdminUser(viewer);
  const isAdmin = isSuperAdmin || isCommunityAdminRole(role);
  if (!isAdmin && isCommunityUnsupportedRole(role)) {
    return { scopes: [] };
  }
  if (isSuperAdmin) {
    const scopes = buildAllCommunityScopes();
    return {
      scopes: scopes.map((scope) => ({
        ...scope,
        isAdmin: true,
        isManager: true,
        canManageAnnouncements: true,
        canManageChat: true,
        canManageBills: true,
        canManageManagers: true,
      })),
    };
  }
  const hierarchy = hierarchyFromUserRow(viewer);
  const scopes = [
    hierarchy.block
      ? buildScopeMeta("block", hierarchy.block)
      : null,
    hierarchy.compound
      ? buildScopeMeta("compound", hierarchy.compound)
      : null,
    hierarchy.building
      ? buildScopeMeta("building", hierarchy.building)
      : null,
  ].filter(Boolean);

  const removalChecks = await Promise.all(
    scopes.map((scope) =>
      isAdmin
        ? Promise.resolve(false)
        : repo.isScopeMemberRemoved({
            scopeType: scope.scopeType,
            scopeCode: scope.scopeCode,
            userId,
          })
    )
  );
  const visibleScopes = scopes.filter((_, idx) => removalChecks[idx] !== true);

  const permissionChecks = await Promise.all(
    visibleScopes.map((scope) =>
      isAdmin
        ? Promise.resolve(true)
        : repo.isScopeManager({
            scopeType: scope.scopeType,
            scopeCode: scope.scopeCode,
            userId,
          })
    )
  );

  return {
    scopes: visibleScopes.map((scope, idx) => ({
      ...scope,
      isAdmin,
      isManager: permissionChecks[idx] === true,
      canManageAnnouncements: isAdmin || permissionChecks[idx] === true,
      canManageChat: isAdmin || permissionChecks[idx] === true,
      canManageBills: isAdmin || permissionChecks[idx] === true,
      canManageManagers: isAdmin,
    })),
  };
}

export async function listCommunityFeed({
  userId,
  userRole,
  scopeType,
  scopeCode,
  query,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  const [rows, bannedUserIds, removedUserIds] = await Promise.all([
    repo.listCommunityFeedPosts({
      viewerUserId: userId,
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      limit: query.limit,
      beforeId: query.beforeId,
      postKind: query.kind,
    }),
    repo.listScopeChatBannedUserIds({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
    }),
    repo.listScopeRemovedUserIds({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
    }),
  ]);
  const hiddenSet = new Set(
    [...(bannedUserIds || []), ...(removedUserIds || [])]
      .map((value) => Number(value))
      .filter((value) => Number.isFinite(value) && value > 0)
  );
  const visibleRows =
    hiddenSet.size <= 0
      ? rows
      : rows.filter((row) => !hiddenSet.has(Number(row.user_id)));
  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    posts: visibleRows.map(mapPostRow),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function listCommunityAnnouncements({
  userId,
  userRole,
  scopeType,
  scopeCode,
  query,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  const permissions = await resolveCommunityPermissions({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  const rows = await repo.listScopeAnnouncements({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    limit: query.limit,
    beforeId: query.beforeId,
  });
  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    canManageAnnouncements: permissions.canManageAnnouncements,
    announcements: rows.map(mapScopeAnnouncementRow),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function createCommunityAnnouncement({
  userId,
  userRole,
  scopeType,
  scopeCode,
  dto,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  await ensureScopeManagerAction({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  assertContentAllowed(dto.title);
  assertContentAllowed(dto.body);

  const inserted = await repo.insertScopeAnnouncement({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    createdByUserId: userId,
    title: dto.title,
    body: dto.body,
  });
  const rows = await repo.listScopeAnnouncements({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    limit: 1,
    beforeId: null,
  });
  const latest = rows[0] || inserted;
  const announcement = mapScopeAnnouncementRow(latest);

  await Promise.all([
    emitCommunityRealtimeEvent({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      event: "social_community_announcement_created",
      data: {
        announcement,
      },
      excludeUserIds: [],
    }),
    notifyCommunityScopeUsers({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      type: "social.community.announcement.created",
      title: `تبليغ جديد في ${buildScopeMeta(scope.scopeType, scope.scopeCode).title}`,
      body: dto.title,
      excludeUserIds: [],
      payload: {
        announcementId: announcement.id,
      },
    }),
  ]);

  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    announcement,
  };
}

export async function listCommunityChat({
  userId,
  userRole,
  scopeType,
  scopeCode,
  query,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  const permissions = await resolveCommunityPermissions({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  const [settings, isBanned, rows, bans, bannedUserIdsRaw, removedUserIds] =
    await Promise.all([
      repo.getScopeChatSettings({
        scopeType: scope.scopeType,
        scopeCode: scope.scopeCode,
      }),
      repo.isScopeChatUserBanned({
        scopeType: scope.scopeType,
        scopeCode: scope.scopeCode,
        userId,
      }),
      repo.listScopeChatMessages({
        scopeType: scope.scopeType,
        scopeCode: scope.scopeCode,
        limit: query.limit,
        beforeId: query.beforeId,
      }),
      permissions.canManageChat
        ? repo.listScopeChatBans({
            scopeType: scope.scopeType,
            scopeCode: scope.scopeCode,
            limit: 120,
          })
        : Promise.resolve([]),
      permissions.canManageChat
        ? Promise.resolve([])
        : repo.listScopeChatBannedUserIds({
            scopeType: scope.scopeType,
            scopeCode: scope.scopeCode,
          }),
      repo.listScopeRemovedUserIds({
        scopeType: scope.scopeType,
        scopeCode: scope.scopeCode,
      }),
    ]);

  const bannedUserIds = permissions.canManageChat
    ? bans.map((row) => Number(row.user_id))
    : bannedUserIdsRaw;
  const hiddenSet = new Set(
    [...(bannedUserIds || []), ...(removedUserIds || [])]
      .map((value) => Number(value))
      .filter((value) => Number.isFinite(value) && value > 0)
  );
  const visibleRows =
    hiddenSet.size <= 0
      ? rows
      : rows.filter(
          (row) =>
            row.is_system === true || !hiddenSet.has(Number(row.sender_user_id))
        );

  const messageIds = visibleRows
    .map((row) => Number(row.id))
    .filter((value) => Number.isFinite(value) && value > 0);
  const reactionsByMessage = await repo.listScopeChatMessageReactionsForMessages({
    messageIds,
    userId,
  });

  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    canManageChat: permissions.canManageChat,
    chatLocked: settings?.chat_locked === true,
    isBanned,
    messages: visibleRows
      .map((row) => ({
        ...row,
        reaction_counts: reactionsByMessage[Number(row.id)]?.counts || {},
        reaction_total_count: Number(
          reactionsByMessage[Number(row.id)]?.totalCount || 0
        ),
        my_reaction: reactionsByMessage[Number(row.id)]?.myReaction || null,
      }))
      .map((row) => mapScopeChatMessageRow(row, userId))
      .reverse(),
    nextCursor:
      visibleRows.length > 0
        ? Number(visibleRows[visibleRows.length - 1].id)
        : null,
    bans: bans.map(mapScopeBanRow),
  };
}

export async function searchCommunityChatMessages({
  userId,
  userRole,
  scopeType,
  scopeCode,
  query,
}) {
  await repo.touchUserPresence(userId);
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  const permissions = await resolveCommunityPermissions({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  const [rows, bans, bannedUserIdsRaw, removedUserIds] = await Promise.all([
    repo.searchScopeChatMessages({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      search: query.search,
      limit: query.limit,
      beforeId: query.beforeId,
    }),
    permissions.canManageChat
      ? repo.listScopeChatBans({
          scopeType: scope.scopeType,
          scopeCode: scope.scopeCode,
          limit: 120,
        })
      : Promise.resolve([]),
    permissions.canManageChat
      ? Promise.resolve([])
      : repo.listScopeChatBannedUserIds({
          scopeType: scope.scopeType,
          scopeCode: scope.scopeCode,
        }),
    repo.listScopeRemovedUserIds({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
    }),
  ]);

  const bannedUserIds = permissions.canManageChat
    ? bans.map((row) => Number(row.user_id))
    : bannedUserIdsRaw;
  const hiddenSet = new Set(
    [...(bannedUserIds || []), ...(removedUserIds || [])]
      .map((value) => Number(value))
      .filter((value) => Number.isFinite(value) && value > 0)
  );
  const visibleRows =
    hiddenSet.size <= 0
      ? rows
      : rows.filter(
          (row) =>
            row.is_system === true || !hiddenSet.has(Number(row.sender_user_id))
        );

  const messageIds = visibleRows
    .map((row) => Number(row.id))
    .filter((value) => Number.isFinite(value) && value > 0);
  const reactionsByMessage = await repo.listScopeChatMessageReactionsForMessages({
    messageIds,
    userId,
  });

  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    messages: visibleRows
      .map((row) => ({
        ...row,
        reaction_counts: reactionsByMessage[Number(row.id)]?.counts || {},
        reaction_total_count: Number(
          reactionsByMessage[Number(row.id)]?.totalCount || 0
        ),
        my_reaction: reactionsByMessage[Number(row.id)]?.myReaction || null,
      }))
      .map((row) => mapScopeChatMessageRow(row, userId)),
    nextCursor:
      visibleRows.length > 0
        ? Number(visibleRows[visibleRows.length - 1].id)
        : null,
  };
}

export async function emitCommunityChatTyping({
  userId,
  userRole,
  scopeType,
  scopeCode,
  typing,
}) {
  await repo.touchUserPresence(userId);
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  const permissions = await resolveCommunityPermissions({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  const [settings, isBanned, actor] = await Promise.all([
    repo.getScopeChatSettings({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
    }),
    repo.isScopeChatUserBanned({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      userId,
    }),
    repo.findUserPublicProfile(userId),
  ]);

  if (actor?.social_typing_indicators_enabled === false) {
    return { ok: true, suppressed: true };
  }
  if (isBanned) {
    return { ok: true, suppressed: true };
  }
  if (settings?.chat_locked === true && !permissions.canManageChat) {
    return { ok: true, suppressed: true };
  }

  await emitCommunityRealtimeEvent({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    event: "social_community_chat_typing",
    data: {
      actorUserId: Number(userId),
      actorDisplayName: actor?.full_name || "",
      typing: typing === true,
    },
    excludeUserIds: [userId],
  });
  return { ok: true };
}

export async function sendCommunityChatMessage({
  userId,
  userRole,
  scopeType,
  scopeCode,
  dto,
  attachment = null,
  clientMessageId = null,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  const permissions = await resolveCommunityPermissions({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  const [settings, isBanned] = await Promise.all([
    repo.getScopeChatSettings({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
    }),
    repo.isScopeChatUserBanned({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      userId,
    }),
  ]);
  if (isBanned) {
    throw new AppError("COMMUNITY_CHAT_BANNED", { status: 403 });
  }
  if (settings?.chat_locked === true && !permissions.canManageChat) {
    throw new AppError("COMMUNITY_CHAT_LOCKED", { status: 403 });
  }

  assertContentAllowed(dto.body);
  let replyToMessageId = null;
  if (dto.replyToMessageId != null) {
    const reply = await repo.getScopeChatMessageById({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      messageId: dto.replyToMessageId,
    });
    if (!reply) {
      throw new AppError("REPLY_MESSAGE_NOT_FOUND", { status: 404 });
    }
    replyToMessageId = Number(reply.id);
  }
  const normalizedAttachment =
    attachment?.url
      ? {
          url: attachment.url,
          name: String(attachment.name || "").trim() || "attachment",
          mimeType:
            String(attachment.mimeType || "").trim() ||
            "application/octet-stream",
          sizeBytes:
            attachment.sizeBytes == null ? null : Number(attachment.sizeBytes),
          durationMs:
            dto.attachmentDurationMs == null
              ? attachment.durationMs == null
                ? null
                : Number(attachment.durationMs)
              : Number(dto.attachmentDurationMs),
          kind: resolveChatAttachmentKind(attachment),
        }
      : null;
  const normalizedSharedEntity =
    dto.sharedEntity?.type && Number(dto.sharedEntity?.id || 0) > 0
      ? {
          type: String(dto.sharedEntity.type).trim().toLowerCase(),
          id: Number(dto.sharedEntity.id),
          snapshot:
            dto.sharedEntity.snapshot &&
            typeof dto.sharedEntity.snapshot === "object" &&
            !Array.isArray(dto.sharedEntity.snapshot)
              ? dto.sharedEntity.snapshot
              : null,
        }
      : null;
  const inserted = await repo.insertScopeChatMessage({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    senderUserId: userId,
    body: dto.body,
    isSystem: false,
    replyToMessageId,
    attachment: normalizedAttachment,
    sharedEntity: normalizedSharedEntity,
    clientMessageId,
  });
  const wasInserted = inserted?._inserted !== false;
  if (!inserted?.id) {
    throw new AppError("COMMUNITY_CHAT_MESSAGE_CREATE_FAILED", { status: 500 });
  }
  const details = await repo.getScopeChatMessageDetailsById({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    messageId: inserted?.id,
  });
  const message = mapScopeChatMessageRow(details || inserted, userId);
  if (wasInserted) {
    await emitCommunityRealtimeEvent({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      event: "social_community_chat_message",
      data: {
        message,
      },
      excludeUserIds: [userId],
    });
    await notifyCommunityScopeUsers({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      type: "social.community.chat.message",
      title: `رسالة جديدة في ${buildScopeMeta(scope.scopeType, scope.scopeCode).title}`,
      body: `${message.sender?.fullName || "أحد السكان"}: ${compactMessagePreview(dto.body, normalizedAttachment, normalizedSharedEntity)}`,
      excludeUserIds: [userId],
      payload: {
        messageId: message.id,
        senderUserId: message.senderUserId,
      },
    });
  }
  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    message,
  };
}

export async function updateCommunityChatMessage({
  userId,
  userRole,
  scopeType,
  scopeCode,
  messageId,
  dto,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  const target = await repo.getScopeChatMessageById({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    messageId,
  });
  if (!target) {
    throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  }
  if (target.is_system === true) {
    throw new AppError("COMMUNITY_CHAT_SYSTEM_MESSAGE_IMMUTABLE", { status: 409 });
  }
  if (Number(target.sender_user_id) !== Number(userId)) {
    throw new AppError("COMMUNITY_CHAT_EDIT_FORBIDDEN", { status: 403 });
  }
  if (!isMessageWithinEditDeleteWindow(target)) {
    throw new AppError("COMMUNITY_CHAT_EDIT_WINDOW_EXPIRED", { status: 409 });
  }

  assertContentAllowed(dto.body);
  await repo.updateScopeChatMessage({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    messageId,
    body: dto.body,
  });

  const details = await repo.getScopeChatMessageDetailsById({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    messageId,
  });
  if (!details) {
    throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  }
  const reactionsSummary = await repo.listScopeChatMessageReactionsForMessages({
    messageIds: [messageId],
    userId,
  });
  const message = mapScopeChatMessageRow(
    {
      ...details,
      reaction_counts: reactionsSummary[Number(messageId)]?.counts || {},
      reaction_total_count: Number(
        reactionsSummary[Number(messageId)]?.totalCount || 0
      ),
      my_reaction: reactionsSummary[Number(messageId)]?.myReaction || null,
    },
    userId
  );

  await emitCommunityRealtimeEvent({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    event: "social_community_chat_message_updated",
    data: {
      message,
      messageId: Number(messageId),
      updatedByUserId: Number(userId),
    },
    excludeUserIds: [],
  });

  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    message,
  };
}

export async function deleteCommunityChatMessage({
  userId,
  userRole,
  scopeType,
  scopeCode,
  messageId,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  const permissions = await resolveCommunityPermissions({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  const target = await repo.getScopeChatMessageById({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    messageId,
  });
  if (!target) {
    throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  }
  const isMine = Number(target.sender_user_id) === Number(userId);
  if (!isMine && !permissions.canManageChat) {
    throw new AppError("COMMUNITY_CHAT_DELETE_FORBIDDEN", { status: 403 });
  }
  if (
    isMine &&
    !permissions.canManageChat &&
    !isMessageWithinEditDeleteWindow(target)
  ) {
    throw new AppError("COMMUNITY_CHAT_DELETE_WINDOW_EXPIRED", { status: 409 });
  }
  if (target.is_system === true && !permissions.canManageChat) {
    throw new AppError("COMMUNITY_CHAT_DELETE_FORBIDDEN", { status: 403 });
  }

  const deleted = await repo.softDeleteScopeChatMessage({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    messageId,
  });
  if (!deleted) {
    throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  }
  const details = await repo.getScopeChatMessageDetailsById({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    messageId,
    includeDeleted: true,
  });
  if (!details) {
    throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  }
  const message = mapScopeChatMessageRow(
    {
      ...details,
      reaction_counts: {},
      reaction_total_count: 0,
      my_reaction: null,
    },
    userId
  );

  await emitCommunityRealtimeEvent({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    event: "social_community_chat_message_deleted",
    data: {
      messageId: Number(messageId),
      deletedByUserId: Number(userId),
      message,
    },
    excludeUserIds: [],
  });

  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    messageId: Number(messageId),
    message,
    deleted: true,
  };
}

export async function toggleCommunityChatMessageReaction({
  userId,
  userRole,
  scopeType,
  scopeCode,
  messageId,
  dto,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });

  const [isBanned, message] = await Promise.all([
    repo.isScopeChatUserBanned({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      userId,
    }),
    repo.getScopeChatMessageById({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      messageId,
    }),
  ]);
  if (isBanned) {
    throw new AppError("COMMUNITY_CHAT_BANNED", { status: 403 });
  }
  if (!message) {
    throw new AppError("MESSAGE_NOT_FOUND", { status: 404 });
  }

  const toggled = await repo.toggleScopeChatMessageReaction({
    messageId,
    userId,
    reaction: dto.reaction,
  });
  const summary = await repo.listScopeChatMessageReactionsForMessages({
    messageIds: [messageId],
    userId,
  });
  const details = summary[Number(messageId)] || {
    counts: {},
    totalCount: 0,
    myReaction: null,
  };

  await emitCommunityRealtimeEvent({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    event: "social_community_chat_message_reaction",
    data: {
      messageId: Number(messageId),
      reaction: toggled.reaction,
      active: toggled.active === true,
      reactions: details,
      reactedByUserId: Number(userId),
    },
    excludeUserIds: [],
  });

  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    messageId: Number(messageId),
    reaction: toggled.reaction,
    active: toggled.active === true,
    reactions: details,
  };
}

export async function setCommunityChatLock({
  userId,
  userRole,
  scopeType,
  scopeCode,
  locked,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  await ensureScopeManagerAction({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });

  const updated = await repo.upsertScopeChatLock({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    locked,
    lockedByUserId: userId,
  });
  await repo.insertScopeChatMessage({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    senderUserId: userId,
    body:
      locked === true
        ? "تم قفل محادثة المجموعة من قبل الإدارة."
        : "تم فتح محادثة المجموعة من قبل الإدارة.",
    isSystem: true,
  });

  await emitCommunityRealtimeEvent({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    event: "social_community_chat_lock_updated",
    data: {
      chatLocked: updated?.chat_locked === true,
      changedByUserId: Number(userId),
    },
  });
  await notifyCommunityScopeUsers({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    type: "social.community.chat.lock_updated",
    title: `حالة محادثة ${buildScopeMeta(scope.scopeType, scope.scopeCode).title}`,
    body:
      locked === true
        ? "تم إيقاف الرسائل في محادثة المجتمع."
        : "تم فتح محادثة المجتمع من جديد.",
    payload: {
      chatLocked: updated?.chat_locked === true,
    },
  });

  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    chatLocked: updated?.chat_locked === true,
  };
}

export async function banCommunityChatUser({
  userId,
  userRole,
  scopeType,
  scopeCode,
  targetUserId,
  reason,
}) {
  if (Number(userId) === Number(targetUserId)) {
    throw new AppError("COMMUNITY_CHAT_BAN_SELF_NOT_ALLOWED", { status: 400 });
  }
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  await ensureScopeManagerAction({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  const target = await resolveScopeTargetUser({
    targetUserId,
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
  });
  const targetRole = String(target.role || "").trim().toLowerCase();
  if (!scope.isAdmin && isCommunityAdminRole(targetRole)) {
    throw new AppError("COMMUNITY_CHAT_BAN_FORBIDDEN", { status: 403 });
  }

  await repo.upsertScopeChatBan({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId: targetUserId,
    bannedByUserId: userId,
    reason: reason || null,
  });
  await repo.insertScopeChatMessage({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    senderUserId: userId,
    body: `تم كتم ${target.full_name || "مستخدم"} داخل هذا المجتمع.`,
    isSystem: true,
  });
  await Promise.all([
    emitCommunityRealtimeEvent({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      event: "social_community_chat_user_restricted",
      data: {
        userId: Number(targetUserId),
        reason: reason || null,
      },
    }),
    notifySingleCommunityUser({
      userId: Number(targetUserId),
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      type: "social.community.chat.restricted",
      title: `تم تقييدك في ${buildScopeMeta(scope.scopeType, scope.scopeCode).title}`,
      body: reason || "تم إيقاف قدرتك على الإرسال داخل محادثة المجتمع.",
      payload: {
        restrictedUserId: Number(targetUserId),
      },
    }),
  ]);
  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    bannedUserId: Number(targetUserId),
    success: true,
  };
}

export async function unbanCommunityChatUser({
  userId,
  userRole,
  scopeType,
  scopeCode,
  targetUserId,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  await ensureScopeManagerAction({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  const target = await repo.findUserAddressMeta(targetUserId);
  await repo.removeScopeChatBan({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId: targetUserId,
  });
  await repo.insertScopeChatMessage({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    senderUserId: userId,
    body: `تم رفع الحظر عن ${target?.full_name || "مستخدم"}.`,
    isSystem: true,
  });
  await Promise.all([
    emitCommunityRealtimeEvent({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      event: "social_community_chat_user_restored",
      data: {
        userId: Number(targetUserId),
      },
    }),
    notifySingleCommunityUser({
      userId: Number(targetUserId),
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      type: "social.community.chat.restored",
      title: `تم إعادة الإرسال لك في ${buildScopeMeta(scope.scopeType, scope.scopeCode).title}`,
      body: "يمكنك إرسال الرسائل في محادثة المجتمع من جديد.",
      payload: {
        restoredUserId: Number(targetUserId),
      },
    }),
  ]);
  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    unbannedUserId: Number(targetUserId),
    success: true,
  };
}

export async function removeCommunityMember({
  userId,
  userRole,
  scopeType,
  scopeCode,
  targetUserId,
  reason,
}) {
  if (Number(userId) === Number(targetUserId)) {
    throw new AppError("COMMUNITY_MEMBER_REMOVE_SELF_NOT_ALLOWED", {
      status: 400,
    });
  }
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  await ensureScopeManagerAction({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  const target = await resolveScopeTargetUser({
    targetUserId,
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
  });
  const targetRole = String(target.role || "").trim().toLowerCase();
  if (!scope.isAdmin && isCommunityAdminRole(targetRole)) {
    throw new AppError("COMMUNITY_MEMBER_REMOVE_FORBIDDEN", { status: 403 });
  }

  await repo.upsertScopeMemberRemoval({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId: targetUserId,
    removedByUserId: userId,
    reason: reason || null,
  });
  await repo.removeScopeManager({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    managerUserId: targetUserId,
  });
  await repo.insertScopeChatMessage({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    senderUserId: userId,
    body: `تمت إزالة ${target.full_name || "مستخدم"} من هذا المجتمع.`,
    isSystem: true,
  });
  await Promise.all([
    emitCommunityRealtimeEvent({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      event: "social_community_member_removed",
      data: {
        userId: Number(targetUserId),
        reason: reason || null,
      },
    }),
    notifySingleCommunityUser({
      userId: Number(targetUserId),
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      type: "social.community.member.removed",
      title: `تمت إزالتك من ${buildScopeMeta(scope.scopeType, scope.scopeCode).title}`,
      body:
        reason ||
        "لا يمكنك الآن عرض منشورات هذا المجتمع أو المشاركة في محادثته.",
      payload: {
        removedUserId: Number(targetUserId),
      },
    }),
  ]);
  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    removedUserId: Number(targetUserId),
    success: true,
  };
}

export async function restoreCommunityMember({
  userId,
  userRole,
  scopeType,
  scopeCode,
  targetUserId,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  await ensureScopeManagerAction({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  await repo.removeScopeMemberRemoval({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId: targetUserId,
  });
  const target = await repo.findUserAddressMeta(targetUserId);
  await repo.insertScopeChatMessage({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    senderUserId: userId,
    body: `تمت إعادة ${target?.full_name || "مستخدم"} إلى هذا المجتمع.`,
    isSystem: true,
  });
  await Promise.all([
    emitCommunityRealtimeEvent({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      event: "social_community_member_restored",
      data: {
        userId: Number(targetUserId),
      },
    }),
    notifySingleCommunityUser({
      userId: Number(targetUserId),
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      type: "social.community.member.restored",
      title: `تمت إعادتك إلى ${buildScopeMeta(scope.scopeType, scope.scopeCode).title}`,
      body: "يمكنك الآن الوصول إلى هذا المجتمع من جديد.",
      payload: {
        restoredUserId: Number(targetUserId),
      },
    }),
  ]);
  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    restoredUserId: Number(targetUserId),
    success: true,
  };
}

export async function listCommunityBills({
  userId,
  userRole,
  scopeType,
  scopeCode,
  query,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  const permissions = await resolveCommunityPermissions({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  const rows = await repo.listScopeBills({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    category: query.category,
    includeAllApartments: permissions.canManageBills === true,
    apartmentCode:
      permissions.canManageBills === true
        ? null
        : normalizeApartmentCode(scope.viewerHierarchy?.apartment),
    limit: query.limit,
    beforeId: query.beforeId,
  });

  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    canManageBills: permissions.canManageBills,
    bills: rows.map(mapScopeBillRow),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function createCommunityBill({
  userId,
  userRole,
  scopeType,
  scopeCode,
  dto,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  await ensureScopeManagerAction({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  assertContentAllowed(dto.title);
  if (dto.details) assertContentAllowed(dto.details);
  const apartmentCode = normalizeApartmentCode(dto.apartment);
  if (scope.scopeType === "building" && !apartmentCode) {
    throw new AppError("COMMUNITY_BILL_APARTMENT_REQUIRED", {
      status: 400,
      details: { fields: ["apartment"] },
    });
  }
  if (dto.attachmentKind && !["image", "file"].includes(dto.attachmentKind)) {
    throw new AppError("COMMUNITY_BILL_ATTACHMENT_INVALID", {
      status: 400,
      details: { fields: ["attachment"] },
    });
  }

  const inserted = await repo.insertScopeBill({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    category: dto.category,
    title: dto.title,
    amount: dto.amount,
    dueDate: dto.dueDate,
    details: dto.details,
    apartmentCode,
    attachmentUrl: dto.attachmentUrl || null,
    attachmentKind: dto.attachmentKind || null,
    attachmentName: dto.attachmentName || null,
    issuedByUserId: userId,
  });
  const rows = await repo.listScopeBills({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    category: null,
    includeAllApartments: true,
    apartmentCode: null,
    limit: 1,
    beforeId: null,
  });
  const latest = rows[0] || inserted;
  const bill = mapScopeBillRow(latest);
  await Promise.all([
    emitCommunityRealtimeEvent({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      apartmentCode:
        scope.scopeType === "building" ? apartmentCode : null,
      event: "social_community_bill_created",
      data: {
        bill,
      },
    }),
    notifyCommunityScopeUsers({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      type: "social.community.bill.created",
      title: `فاتورة جديدة في ${buildScopeMeta(scope.scopeType, scope.scopeCode).title}`,
      body: dto.title,
      apartmentCode:
        scope.scopeType === "building" ? apartmentCode : null,
      payload: {
        billId: bill.id,
        billCategory: bill.category,
        apartmentCode: bill.apartmentCode,
      },
    }),
  ]);
  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    bill,
  };
}

export async function listCommunityManagers({
  userId,
  userRole,
  scopeType,
  scopeCode,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  const rows = await repo.listScopeManagers({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
  });
  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    canManageManagers: scope.isAdmin,
    managers: rows.map(mapScopeManagerRow),
  };
}

export async function searchCommunityUsersForManagers({
  userId,
  userRole,
  scopeType,
  scopeCode,
  query,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  if (!scope.isAdmin) {
    throw new AppError("COMMUNITY_MANAGER_ASSIGN_FORBIDDEN", { status: 403 });
  }

  const rows = await repo.listUsersForCommunityScopeSearch({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    search: query.search,
    limit: query.limit,
    excludedRoles: ["owner", "delivery", "admin", "deputy_admin", "call_center"],
  });

  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    users: rows.map((row) => ({
      id: Number(row.id),
      fullName: row.full_name || "",
      phone: row.phone || "",
      role: row.role || "user",
      imageUrl: row.image_url || null,
      isManager: row.is_manager === true,
    })),
  };
}

export async function searchCommunityUsersForChatModeration({
  userId,
  userRole,
  scopeType,
  scopeCode,
  query,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  const permissions = await resolveCommunityPermissions({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    userId,
    isAdmin: scope.isAdmin,
  });
  if (!permissions.canManageChat) {
    throw new AppError("COMMUNITY_MANAGER_REQUIRED", { status: 403 });
  }

  const rows = await repo.listUsersForCommunityScopeSearch({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    search: query.search,
    limit: query.limit,
    excludedRoles: scope.isAdmin
      ? ["owner", "delivery", "call_center"]
      : ["owner", "delivery", "call_center", "admin", "deputy_admin"],
    includeChatRestriction: true,
    includeScopeRemoval: true,
    requireApartmentForBuilding:
      scope.scopeType === "building" && scope.isAdmin !== true,
  });

  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    users: rows.map((row) => ({
      id: Number(row.id),
      fullName: row.full_name || "",
      phone: row.phone || "",
      role: row.role || "user",
      imageUrl: row.image_url || null,
      isManager: row.is_manager === true,
      isChatRestricted: row.is_chat_restricted === true,
      isScopeRemoved: row.is_scope_removed === true,
    })),
  };
}

export async function assignCommunityManager({
  userId,
  userRole,
  scopeType,
  scopeCode,
  managerUserId,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  if (!scope.isAdmin) {
    throw new AppError("COMMUNITY_MANAGER_ASSIGN_FORBIDDEN", { status: 403 });
  }

  const target = await resolveScopeTargetUser({
    targetUserId: managerUserId,
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
  });
  const targetRole = String(target.role || "").trim().toLowerCase();
  if (!isCommunityManagerEligibleRole(targetRole)) {
    throw new AppError("COMMUNITY_MANAGER_ROLE_NOT_ALLOWED", { status: 409 });
  }
  await repo.addScopeManager({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    managerUserId,
    assignedByUserId: userId,
  });
  await repo.insertScopeChatMessage({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    senderUserId: userId,
    body: `تم تعيين ${target.full_name || "مستخدم"} مديراً للمجموعة.`,
    isSystem: true,
  });
  await Promise.all([
    emitCommunityRealtimeEvent({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      event: "social_community_manager_updated",
      data: {
        action: "assigned",
        managerUserId: Number(managerUserId),
      },
    }),
    notifySingleCommunityUser({
      userId: Number(managerUserId),
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      type: "social.community.manager.assigned",
      title: `تم تعيينك مديراً في ${buildScopeMeta(scope.scopeType, scope.scopeCode).title}`,
      body: "أصبحت تملك صلاحيات إدارة هذا المجتمع.",
      payload: {
        managerUserId: Number(managerUserId),
      },
    }),
  ]);

  const rows = await repo.listScopeManagers({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
  });
  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    managers: rows.map(mapScopeManagerRow),
  };
}

export async function revokeCommunityManager({
  userId,
  userRole,
  scopeType,
  scopeCode,
  managerUserId,
}) {
  const scope = await resolveScopeAccess({
    userId,
    userRole,
    scopeType,
    scopeCode,
  });
  if (!scope.isAdmin) {
    throw new AppError("COMMUNITY_MANAGER_REVOKE_FORBIDDEN", { status: 403 });
  }

  const target = await repo.findUserAddressMeta(managerUserId);
  await repo.removeScopeManager({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    managerUserId,
  });
  await repo.insertScopeChatMessage({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
    senderUserId: userId,
    body: `تمت إزالة صلاحية المدير عن ${target?.full_name || "مستخدم"}.`,
    isSystem: true,
  });
  await Promise.all([
    emitCommunityRealtimeEvent({
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      event: "social_community_manager_updated",
      data: {
        action: "revoked",
        managerUserId: Number(managerUserId),
      },
    }),
    notifySingleCommunityUser({
      userId: Number(managerUserId),
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
      type: "social.community.manager.revoked",
      title: `تمت إزالة إدارتك من ${buildScopeMeta(scope.scopeType, scope.scopeCode).title}`,
      body: "لم تعد تملك صلاحيات الإدارة في هذا المجتمع.",
      payload: {
        managerUserId: Number(managerUserId),
      },
    }),
  ]);

  const rows = await repo.listScopeManagers({
    scopeType: scope.scopeType,
    scopeCode: scope.scopeCode,
  });
  return {
    scope: buildScopeMeta(scope.scopeType, scope.scopeCode),
    managers: rows.map(mapScopeManagerRow),
  };
}

