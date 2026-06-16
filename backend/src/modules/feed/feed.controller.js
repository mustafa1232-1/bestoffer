import { buildUploadedFileUrl } from "../../shared/utils/upload.js";
import * as service from "./feed.service.js";
import {
  validateCreateStory,
  validateCreateComment,
  validateUpdateComment,
  validateCreatePost,
  validateResubmitModeratedPost,
  validateResubmitModeratedStory,
  validateCreateThread,
  validateGroupThreadMembersBody,
  validateGroupThreadMemberRoleBody,
  validateCommentId,
  validateReportBody,
  validateHighlightId,
  validateHighlightStory,
  validateListStories,
  validateListStoryArchive,
  validateListMessages,
  validateThreadMessageSearchQuery,
  validateListPosts,
  validateMessageId,
  validateMessageReaction,
  validateAdminChatMonitorListQuery,
  validateQualityReviewConsentBody,
  validateResidenceChangeBody,
  validateResidenceChangeId,
  validateRelationListQuery,
  validateMerchantSearch,
  validateUserSearch,
  validatePostId,
  validateStoryId,
  validateThreadCallEnd,
  validateThreadCallSignal,
  validateThreadCallStateQuery,
  validateCommunityAnnouncementBody,
  validateCommunityAnnouncementListQuery,
  validateCommunityBillBody,
  validateCommunityBillListQuery,
  validateCommunityChatBanBody,
  validateCommunityChatListQuery,
  validateCommunityChatLockBody,
  validateCommunityChatMessageBody,
  validateCommunityChatMessageUpdateBody,
  validateCommunityFeedQuery,
  validateCommunityManagerBody,
  validateCommunityScopeParams,
  validateCommunityUserSearchQuery,
  validateSuperAdminUserActionBody,
  validateUpdateSocialProfile,
  validateUserId,
  validateUserNotificationPreferenceBody,
  validateSendMessage,
  validateScheduledThreadMessageBody,
  validateScheduledThreadMessageId,
  validateScheduledThreadMessageListQuery,
  validateThreadMessageUpdateBody,
  validateThreadId,
  validateUpdateGroupThread,
  validateSocialSearchQuery,
  validateSavedCollectionBody,
  validateSavedCollectionId,
  validateSavedToggleBody,
  validateSavedListQuery,
  validateHashtagParam,
  validateUsernameQuery,
  validateSimpleLimitQuery,
  validateReelViewBody,
  validateThreadTypingBody,
  validateThreadMuteBody,
  validateThreadPinBody,
  validateThreadThemeBody,
  validateTranslateThreadMessageBody,
} from "./feed.validators.js";

const HOT_RESPONSE_TTL_MS = 10_000;
const hotResponseCache = new Map();

function buildHotResponseCacheKey(prefix, userId, query = {}) {
  const parts = Object.entries(query || {})
    .filter(([, value]) => value !== undefined)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${JSON.stringify(value)}`);
  return `${prefix}:${Number(userId)}:${parts.join("&")}`;
}

function readHotResponse(prefix, userId, query = {}) {
  const key = buildHotResponseCacheKey(prefix, userId, query);
  const cached = hotResponseCache.get(key);
  if (!cached) return null;
  if (cached.expiresAt <= Date.now()) {
    hotResponseCache.delete(key);
    return null;
  }
  return cached.serialized;
}

function writeHotResponse(prefix, userId, query = {}, payload) {
  const key = buildHotResponseCacheKey(prefix, userId, query);
  hotResponseCache.set(key, {
    serialized: JSON.stringify(payload),
    expiresAt: Date.now() + HOT_RESPONSE_TTL_MS,
  });
}

function badRequest(res, fields) {
  return res.status(400).json({
    message: "VALIDATION_ERROR",
    fields,
  });
}

export async function listPosts(req, res, next) {
  try {
    const v = validateListPosts(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.listPosts(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listExplore(req, res, next) {
  try {
    const v = validateListPosts(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const hot = readHotResponse("explore", req.userId, v.value);
    if (hot) {
      res.type("application/json");
      return res.send(hot);
    }
    const out = await service.listExplore(req.userId, v.value);
    writeHotResponse("explore", req.userId, v.value, out);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listTrending(req, res, next) {
  try {
    const v = validateListPosts(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.listTrending(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listExploreReels(req, res, next) {
  try {
    const v = validateListPosts({ ...(req.query || {}), kind: 'reel' });
    if (!v.ok) return badRequest(res, v.errors);
    const hot = readHotResponse("explore_reels", req.userId, v.value);
    if (hot) {
      res.type("application/json");
      return res.send(hot);
    }
    const out = await service.listExploreReels(req.userId, v.value);
    writeHotResponse("explore_reels", req.userId, v.value, out);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listSuggestedPeople(req, res, next) {
  try {
    const v = validateSimpleLimitQuery(req.query || {}, { defaultLimit: 12, maxLimit: 30 });
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.listSuggestedPeople(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function searchSocialCatalog(req, res, next) {
  try {
    const v = validateSocialSearchQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.searchSocialCatalog(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listHashtagPosts(req, res, next) {
  try {
    const tag = validateHashtagParam(req.params.tag);
    if (!tag.ok) return badRequest(res, tag.errors);
    const query = validateListPosts(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listHashtagPosts(req.userId, tag.value, query.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listTrendingTags(req, res, next) {
  try {
    const v = validateSimpleLimitQuery(req.query || {}, { defaultLimit: 12, maxLimit: 30 });
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.listTrendingTags(v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listMentionUsers(req, res, next) {
  try {
    const v = validateUserSearch(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.listMentionUsers(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listHashtagSuggestions(req, res, next) {
  try {
    const v = validateUserSearch(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.listHashtagSuggestions(v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listSavedCollections(req, res, next) {
  try {
    const out = await service.listSavedCollectionsForUser(req.userId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createSavedCollection(req, res, next) {
  try {
    const v = validateSavedCollectionBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.createSavedCollectionForUser(req.userId, v.value);
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateSavedCollection(req, res, next) {
  try {
    const id = validateSavedCollectionId(req.params.collectionId);
    if (!id.ok) return badRequest(res, id.errors);
    const v = validateSavedCollectionBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.updateSavedCollectionForUser({
      userId: req.userId,
      collectionId: id.value,
      dto: v.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function deleteSavedCollection(req, res, next) {
  try {
    const id = validateSavedCollectionId(req.params.collectionId);
    if (!id.ok) return badRequest(res, id.errors);
    const out = await service.deleteSavedCollectionForUser({
      userId: req.userId,
      collectionId: id.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function toggleSavedContent(req, res, next) {
  try {
    const v = validateSavedToggleBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.toggleSavedContentForUser({
      userId: req.userId,
      dto: v.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listSavedContent(req, res, next) {
  try {
    const v = validateSavedListQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.listSavedContentForUser(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listStories(req, res, next) {
  try {
    const v = validateListStories(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.listStories(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listMyStoryArchive(req, res, next) {
  try {
    const v = validateListStoryArchive(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.listMyStoryArchive(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listMyArchivedPosts(req, res, next) {
  try {
    const v = validateListPosts(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.listMyArchivedPosts(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getPostById(req, res, next) {
  try {
    const v = validatePostId(req.params.postId);
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.getPostById(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function archivePost(req, res, next) {
  try {
    const v = validatePostId(req.params.postId);
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.setPostArchivedState({
      userId: req.userId,
      postId: v.value,
      archived: true,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function restorePost(req, res, next) {
  try {
    const v = validatePostId(req.params.postId);
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.setPostArchivedState({
      userId: req.userId,
      postId: v.value,
      archived: false,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function deletePost(req, res, next) {
  try {
    const v = validatePostId(req.params.postId);
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.deletePost({
      userId: req.userId,
      postId: v.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getUserProfile(req, res, next) {
  try {
    const v = validateUserId(req.params.userId);
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.getUserProfile(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function setUserNotificationPreference(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const body = validateUserNotificationPreferenceBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.setUserNotificationPreference({
      userId: req.userId,
      otherUserId: user.value,
      enabled: body.value.enabled,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function runSuperAdminUserAction(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const body = validateSuperAdminUserActionBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.runSuperAdminUserAction({
      userId: req.userId,
      targetUserId: user.value,
      action: body.value.action,
      note: body.value.note,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listUserPosts(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const query = validateListPosts(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listUserPosts(req.userId, user.value, query.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listMyReportedPosts(req, res, next) {
  try {
    const query = validateListPosts(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listMyReportedPosts({
      userId: req.userId,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listMyReportedStories(req, res, next) {
  try {
    const query = validateListPosts(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listMyReportedStories({
      userId: req.userId,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listUserHighlights(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const out = await service.listUserHighlights(req.userId, user.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listUserFollowers(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const query = validateRelationListQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listUserFollowers({
      viewerUserId: req.userId,
      targetUserId: user.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listUserFollowing(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const query = validateRelationListQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listUserFollowing({
      viewerUserId: req.userId,
      targetUserId: user.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listUserFriends(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const query = validateRelationListQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listUserFriends({
      viewerUserId: req.userId,
      targetUserId: user.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createPost(req, res, next) {
  try {
    const body = {
      ...req.body,
      postKind: req.body?.postKind || req.body?.post_kind,
    };
    const v = validateCreatePost(body);
    if (!v.ok) return badRequest(res, v.errors);

    const media = req.file
      ? {
          url: buildUploadedFileUrl(req, req.file),
          mimetype: req.file.mimetype,
        }
      : null;
    const post = await service.createPost(
      req.userId,
      { ...body, ...v.value },
      media
    );
    return res.status(201).json({ post });
  } catch (error) {
    return next(error);
  }
}

export async function resubmitModeratedPost(req, res, next) {
  try {
    const post = validatePostId(req.params.postId);
    if (!post.ok) return badRequest(res, post.errors);
    const body = validateResubmitModeratedPost(req.body || {}, {
      hasMediaUpload: !!req.file,
    });
    if (!body.ok) return badRequest(res, body.errors);
    const media = req.file
      ? {
          url: buildUploadedFileUrl(req, req.file),
          mimetype: req.file.mimetype,
        }
      : null;
    const out = await service.resubmitModeratedPost({
      postId: post.value,
      userId: req.userId,
      caption: body.value.caption,
      clearMedia: body.value.clearMedia,
      media,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function resubmitModeratedStory(req, res, next) {
  try {
    const story = validateStoryId(req.params.storyId);
    if (!story.ok) return badRequest(res, story.errors);
    const body = validateResubmitModeratedStory(req.body || {}, {
      hasMediaUpload: !!req.file,
    });
    if (!body.ok) return badRequest(res, body.errors);
    const media = req.file
      ? {
          url: buildUploadedFileUrl(req, req.file),
          mimetype: req.file.mimetype,
        }
      : null;
    const out = await service.resubmitModeratedStory({
      storyId: story.value,
      userId: req.userId,
      caption: body.value.caption,
      clearMedia: body.value.clearMedia,
      media,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createStory(req, res, next) {
  try {
    const v = validateCreateStory(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const media = req.file
      ? {
          url: buildUploadedFileUrl(req, req.file),
          mimetype: req.file.mimetype,
        }
      : null;

    const story = await service.createStory(
      req.userId,
      { ...(req.body || {}), ...v.value },
      media
    );
    return res.status(201).json({ story });
  } catch (error) {
    return next(error);
  }
}

export async function updateMyProfile(req, res, next) {
  try {
    const body = {
      ...(req.body || {}),
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
    };
    const v = validateUpdateSocialProfile(body, {
      hasImageUpload: !!req.file,
    });
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.updateMyProfile(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function checkMyUsernameAvailability(req, res, next) {
  try {
    const v = validateUsernameQuery(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.checkMyUsernameAvailability({
      userId: req.userId,
      username: v.value.username,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateMyUsername(req, res, next) {
  try {
    const v = validateUsernameQuery(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.updateMyUsername({
      userId: req.userId,
      username: v.value.username,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getMyResidenceChangeRequest(req, res, next) {
  try {
    const out = await service.getMyResidenceChangeRequest(req.userId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listMyActiveSocialCapabilityRestrictions(req, res, next) {
  try {
    const out = await service.listMyActiveSocialCapabilityRestrictions(
      req.userId
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createMyResidenceChangeRequest(req, res, next) {
  try {
    const body = {
      ...(req.body || {}),
      documentImageUrl: buildUploadedFileUrl(req, req.file) || req.body?.documentImageUrl,
    };
    const v = validateResidenceChangeBody(body);
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.submitResidenceChangeRequest(req.userId, v.value);
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function cancelMyResidenceChangeRequest(req, res, next) {
  try {
    const id = validateResidenceChangeId(req.params.requestId);
    if (!id.ok) return badRequest(res, id.errors);
    const out = await service.cancelMyResidenceChangeRequest({
      userId: req.userId,
      requestId: id.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function highlightStory(req, res, next) {
  try {
    const story = validateStoryId(req.params.storyId);
    if (!story.ok) return badRequest(res, story.errors);
    const payload = validateHighlightStory(req.body || {});
    if (!payload.ok) return badRequest(res, payload.errors);
    const out = await service.highlightStory({
      userId: req.userId,
      storyId: story.value,
      title: payload.value.title,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function removeHighlight(req, res, next) {
  try {
    const id = validateHighlightId(req.params.highlightId);
    if (!id.ok) return badRequest(res, id.errors);
    await service.removeHighlight({
      userId: req.userId,
      highlightId: id.value,
    });
    return res.status(204).send();
  } catch (error) {
    return next(error);
  }
}

export async function markStoryViewed(req, res, next) {
  try {
    const v = validateStoryId(req.params.storyId);
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.markStoryViewed({
      storyId: v.value,
      userId: req.userId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function toggleLike(req, res, next) {
  try {
    const v = validatePostId(req.params.postId);
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.toggleLike({
      postId: v.value,
      userId: req.userId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listPostLikers(req, res, next) {
  try {
    const post = validatePostId(req.params.postId);
    if (!post.ok) return badRequest(res, post.errors);
    const query = validateRelationListQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listPostLikers({
      viewerUserId: req.userId,
      postId: post.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listUserLikedPosts(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const query = validateListPosts(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listUserLikedPosts({
      viewerUserId: req.userId,
      targetUserId: user.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listUserCommentedPosts(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const query = validateListPosts(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listUserCommentedPosts({
      viewerUserId: req.userId,
      targetUserId: user.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listPostComments(req, res, next) {
  try {
    const post = validatePostId(req.params.postId);
    if (!post.ok) return badRequest(res, post.errors);
    const query = validateListMessages(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listComments({
      postId: post.value,
      userId: req.userId,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function addComment(req, res, next) {
  try {
    const post = validatePostId(req.params.postId);
    if (!post.ok) return badRequest(res, post.errors);
    const body = validateCreateComment(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.addComment({
      postId: post.value,
      userId: req.userId,
      body: body.value.body,
      parentCommentId: body.value.parentCommentId,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateComment(req, res, next) {
  try {
    const post = validatePostId(req.params.postId);
    if (!post.ok) return badRequest(res, post.errors);
    const comment = validateCommentId(req.params.commentId);
    if (!comment.ok) return badRequest(res, comment.errors);
    const body = validateUpdateComment(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.updateComment({
      postId: post.value,
      commentId: comment.value,
      userId: req.userId,
      body: body.value.body,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function deleteComment(req, res, next) {
  try {
    const post = validatePostId(req.params.postId);
    if (!post.ok) return badRequest(res, post.errors);
    const comment = validateCommentId(req.params.commentId);
    if (!comment.ok) return badRequest(res, comment.errors);
    const out = await service.deleteComment({
      postId: post.value,
      commentId: comment.value,
      userId: req.userId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function toggleCommentLike(req, res, next) {
  try {
    const post = validatePostId(req.params.postId);
    if (!post.ok) return badRequest(res, post.errors);
    const comment = validateCommentId(req.params.commentId);
    if (!comment.ok) return badRequest(res, comment.errors);
    const out = await service.toggleCommentLike({
      postId: post.value,
      commentId: comment.value,
      userId: req.userId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function reportPost(req, res, next) {
  try {
    const post = validatePostId(req.params.postId);
    if (!post.ok) return badRequest(res, post.errors);
    const body = validateReportBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.reportPost({
      postId: post.value,
      reporterUserId: req.userId,
      reason: body.value.reason,
      details: body.value.details,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function reportUser(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const body = validateReportBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.reportUser({
      reportedUserId: user.value,
      reporterUserId: req.userId,
      reason: body.value.reason,
      details: body.value.details,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listStoryComments(req, res, next) {
  try {
    const story = validateStoryId(req.params.storyId);
    if (!story.ok) return badRequest(res, story.errors);
    const query = validateListMessages(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listStoryComments({
      storyId: story.value,
      userId: req.userId,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function addStoryComment(req, res, next) {
  try {
    const story = validateStoryId(req.params.storyId);
    if (!story.ok) return badRequest(res, story.errors);
    const body = validateCreateComment(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.addStoryComment({
      storyId: story.value,
      userId: req.userId,
      body: body.value.body,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function toggleStoryLike(req, res, next) {
  try {
    const story = validateStoryId(req.params.storyId);
    if (!story.ok) return badRequest(res, story.errors);
    const out = await service.toggleStoryLike({
      storyId: story.value,
      userId: req.userId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function reportStory(req, res, next) {
  try {
    const story = validateStoryId(req.params.storyId);
    if (!story.ok) return badRequest(res, story.errors);
    const body = validateReportBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.reportStory({
      storyId: story.value,
      reporterUserId: req.userId,
      reason: body.value.reason,
      details: body.value.details,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function archiveStory(req, res, next) {
  try {
    const story = validateStoryId(req.params.storyId);
    if (!story.ok) return badRequest(res, story.errors);
    const out = await service.setStoryArchivedState({
      userId: req.userId,
      storyId: story.value,
      archived: true,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function restoreStory(req, res, next) {
  try {
    const story = validateStoryId(req.params.storyId);
    if (!story.ok) return badRequest(res, story.errors);
    const out = await service.setStoryArchivedState({
      userId: req.userId,
      storyId: story.value,
      archived: false,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listMerchants(req, res, next) {
  try {
    const v = validateMerchantSearch(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.listMerchantOptions(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function searchUsers(req, res, next) {
  try {
    const v = validateUserSearch(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.searchUsers(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listShareRecipients(req, res, next) {
  try {
    const v = validateUserSearch(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.listShareRecipients({
      userId: req.userId,
      query: v.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listThreads(req, res, next) {
  try {
    const hot = readHotResponse("chat_threads", req.userId);
    if (hot) {
      res.type("application/json");
      return res.send(hot);
    }
    const out = await service.listThreads(req.userId);
    writeHotResponse("chat_threads", req.userId, {}, out);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listChatRequests(req, res, next) {
  try {
    const hot = readHotResponse("chat_requests", req.userId);
    if (hot) {
      res.type("application/json");
      return res.send(hot);
    }
    const out = await service.listChatRequests(req.userId);
    writeHotResponse("chat_requests", req.userId, {}, out);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createThread(req, res, next) {
  try {
    const v = validateCreateThread(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const thread = await service.createThread({
      userId: req.userId,
      otherUserId: v.value.userId,
      kind: v.value.kind,
      title: v.value.title,
      imageUrl: v.value.imageUrl,
      memberIds: v.value.memberIds,
      context: v.value.context,
    });
    return res.status(201).json({ thread });
  } catch (error) {
    return next(error);
  }
}

export async function getGroupThreadDetails(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const out = await service.getGroupThreadDetails({
      userId: req.userId,
      threadId: thread.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateGroupThread(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const body = validateUpdateGroupThread(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.updateGroupThread({
      userId: req.userId,
      threadId: thread.value,
      title: body.value.title,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function addGroupThreadMembers(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const body = validateGroupThreadMembersBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.addGroupThreadMembers({
      userId: req.userId,
      threadId: thread.value,
      memberIds: body.value.memberIds,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function removeGroupThreadMember(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const member = validateUserId(req.params.userId);
    if (!member.ok) return badRequest(res, member.errors);
    const out = await service.removeGroupThreadMember({
      userId: req.userId,
      threadId: thread.value,
      memberUserId: member.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function leaveGroupThread(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const out = await service.leaveGroupThread({
      userId: req.userId,
      threadId: thread.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateGroupThreadMemberRole(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const member = validateUserId(req.params.userId);
    if (!member.ok) return badRequest(res, member.errors);
    const body = validateGroupThreadMemberRoleBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.updateGroupThreadMemberRole({
      userId: req.userId,
      threadId: thread.value,
      memberUserId: member.value,
      memberRole: body.value.memberRole,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listThreadMessages(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const query = validateListMessages(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listMessages({
      userId: req.userId,
      threadId: thread.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function searchThreadMessages(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const query = validateThreadMessageSearchQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.searchThreadMessages({
      userId: req.userId,
      threadId: thread.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function sendThreadMessage(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const body = validateSendMessage({
      ...(req.body || {}),
      hasAttachment: !!req.file,
    });
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.sendMessage({
      userId: req.userId,
      threadId: thread.value,
      body: body.value.body,
      replyToMessageId: body.value.replyToMessageId,
      attachmentDurationMs: body.value.attachmentDurationMs,
      sharedEntity: body.value.sharedEntity,
      attachment: req.file
        ? {
            url: buildUploadedFileUrl(req, req.file),
            name: req.file.originalname || req.file.filename || "attachment",
            mimeType: req.file.mimetype || "application/octet-stream",
            sizeBytes: Number(req.file.size || 0),
            durationMs: body.value.attachmentDurationMs,
          }
        : null,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listScheduledThreadMessages(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const query = validateScheduledThreadMessageListQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listScheduledMessages({
      userId: req.userId,
      threadId: thread.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function scheduleThreadMessage(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const body = validateScheduledThreadMessageBody({
      ...(req.body || {}),
      hasAttachment: !!req.file,
    });
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.scheduleMessage({
      userId: req.userId,
      threadId: thread.value,
      body: body.value.body,
      scheduledFor: body.value.scheduledFor,
      replyToMessageId: body.value.replyToMessageId,
      attachmentDurationMs: body.value.attachmentDurationMs,
      sharedEntity: body.value.sharedEntity,
      attachment: req.file
        ? {
            url: buildUploadedFileUrl(req, req.file),
            name: req.file.originalname || req.file.filename || "attachment",
            mimeType: req.file.mimetype || "application/octet-stream",
            sizeBytes: Number(req.file.size || 0),
            durationMs: body.value.attachmentDurationMs,
          }
        : null,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function cancelScheduledThreadMessage(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const scheduled = validateScheduledThreadMessageId(
      req.params.scheduledMessageId
    );
    if (!scheduled.ok) return badRequest(res, scheduled.errors);
    const out = await service.cancelScheduledMessage({
      userId: req.userId,
      threadId: thread.value,
      scheduledMessageId: scheduled.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function acceptChatRequest(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const out = await service.acceptChatRequest({
      userId: req.userId,
      threadId: thread.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function rejectChatRequest(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const out = await service.rejectChatRequest({
      userId: req.userId,
      threadId: thread.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function blockChatRequest(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const out = await service.blockChatRequest({
      userId: req.userId,
      threadId: thread.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateThreadMessage(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const message = validateMessageId(req.params.messageId);
    if (!message.ok) return badRequest(res, message.errors);
    const body = validateThreadMessageUpdateBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.updateMessage({
      userId: req.userId,
      threadId: thread.value,
      messageId: message.value,
      body: body.value.body,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function translateThreadMessage(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const message = validateMessageId(req.params.messageId);
    if (!message.ok) return badRequest(res, message.errors);
    const body = validateTranslateThreadMessageBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.translateThreadMessage({
      userId: req.userId,
      threadId: thread.value,
      messageId: message.value,
      targetLanguage: body.value.targetLanguage,
      refresh: body.value.refresh,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function deleteThreadMessage(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const message = validateMessageId(req.params.messageId);
    if (!message.ok) return badRequest(res, message.errors);

    const out = await service.deleteMessage({
      userId: req.userId,
      threadId: thread.value,
      messageId: message.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getMyChatQualityReviewConsent(req, res, next) {
  try {
    const out = await service.getMyChatQualityReviewConsent({
      userId: req.userId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function setMyChatQualityReviewConsent(req, res, next) {
  try {
    const body = validateQualityReviewConsentBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.setMyChatQualityReviewConsent({
      userId: req.userId,
      enabled: body.value.enabled,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listAdminMonitoredThreads(req, res, next) {
  try {
    const query = validateAdminChatMonitorListQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listAdminMonitoredThreads({
      userId: req.userId,
      isSuperAdmin: req.userIsSuperAdmin === true,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listAdminMonitoredThreadMessages(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const query = validateListMessages(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listAdminMonitoredThreadMessages({
      userId: req.userId,
      isSuperAdmin: req.userIsSuperAdmin === true,
      threadId: thread.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listAdminMonitoredCommunityMessages(req, res, next) {
  try {
    const scope = validateCommunityScopeParams({
      scopeType: req.params.scopeType,
      scopeCode: req.params.scopeCode,
    });
    if (!scope.ok) return badRequest(res, scope.errors);
    const query = validateListMessages(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listAdminMonitoredCommunityMessages({
      userId: req.userId,
      isSuperAdmin: req.userIsSuperAdmin === true,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function toggleThreadMessageReaction(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const message = validateMessageId(req.params.messageId);
    if (!message.ok) return badRequest(res, message.errors);
    const body = validateMessageReaction(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.toggleMessageReaction({
      userId: req.userId,
      threadId: thread.value,
      messageId: message.value,
      reaction: body.value.reaction,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getUserRelationState(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const out = await service.getUserRelationState({
      userId: req.userId,
      otherUserId: user.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function sendUserRelationRequest(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const out = await service.sendUserRelationRequest({
      userId: req.userId,
      otherUserId: user.value,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function acceptUserRelationRequest(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const out = await service.acceptUserRelationRequest({
      userId: req.userId,
      otherUserId: user.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function rejectUserRelationRequest(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const out = await service.rejectUserRelationRequest({
      userId: req.userId,
      otherUserId: user.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function cancelUserRelationRequest(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const out = await service.cancelUserRelationRequest({
      userId: req.userId,
      otherUserId: user.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function removeUserRelation(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const out = await service.removeUserRelation({
      userId: req.userId,
      otherUserId: user.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function blockUserRelation(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const out = await service.blockUserRelation({
      userId: req.userId,
      otherUserId: user.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function unblockUserRelation(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const out = await service.unblockUserRelation({
      userId: req.userId,
      otherUserId: user.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listIncomingRelationRequests(req, res, next) {
  try {
    const qv = validateRelationListQuery(req.query || {});
    if (!qv.ok) return badRequest(res, qv.errors);
    const out = await service.listIncomingRelationRequests({
      userId: req.userId,
      query: qv.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listOutgoingRelationRequests(req, res, next) {
  try {
    const qv = validateRelationListQuery(req.query || {});
    if (!qv.ok) return badRequest(res, qv.errors);
    const out = await service.listOutgoingRelationRequests({
      userId: req.userId,
      query: qv.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getThreadCallState(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const qv = validateThreadCallStateQuery(req.query || {});
    if (!qv.ok) return badRequest(res, qv.errors);
    const out = await service.getThreadCallState({
      userId: req.userId,
      threadId: thread.value,
      signalLimit: qv.value.signalLimit,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function startThreadCall(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const out = await service.startThreadCall({
      userId: req.userId,
      threadId: thread.value,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function sendThreadCallSignal(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const body = validateThreadCallSignal(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.sendThreadCallSignal({
      userId: req.userId,
      threadId: thread.value,
      dto: body.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function endThreadCall(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const body = validateThreadCallEnd(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.endThreadCall({
      userId: req.userId,
      threadId: thread.value,
      dto: body.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

function parseScopeParams(req) {
  return validateCommunityScopeParams({
    scopeType: req.params.scopeType,
    scopeCode: req.params.scopeCode,
  });
}

export async function getMyCommunityScopes(req, res, next) {
  try {
    const out = await service.getMyCommunityScopes({
      userId: req.userId,
      userRole: req.userRole,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listCommunityFeed(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const query = validateCommunityFeedQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listCommunityFeed({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listCommunityAnnouncements(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const query = validateCommunityAnnouncementListQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listCommunityAnnouncements({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createCommunityAnnouncement(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const body = validateCommunityAnnouncementBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.createCommunityAnnouncement({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      dto: body.value,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listCommunityChat(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const query = validateCommunityChatListQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listCommunityChat({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function searchCommunityChatMessages(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const query = validateThreadMessageSearchQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.searchCommunityChatMessages({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function sendCommunityChatMessage(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const body = validateCommunityChatMessageBody({
      ...(req.body || {}),
      hasAttachment: !!req.file,
    });
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.sendCommunityChatMessage({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      dto: body.value,
      attachment: req.file
        ? {
            url: buildUploadedFileUrl(req, req.file),
            name: req.file.originalname || req.file.filename || "attachment",
            mimeType: req.file.mimetype || "application/octet-stream",
            sizeBytes: Number(req.file.size || 0),
            durationMs: body.value.attachmentDurationMs,
          }
        : null,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function emitCommunityChatTyping(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const body = validateThreadTypingBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.emitCommunityChatTyping({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      typing: body.value.typing,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateCommunityChatMessage(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const message = validateMessageId(req.params.messageId);
    if (!message.ok) return badRequest(res, message.errors);
    const body = validateCommunityChatMessageUpdateBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.updateCommunityChatMessage({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      messageId: message.value,
      dto: body.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function deleteCommunityChatMessage(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const message = validateMessageId(req.params.messageId);
    if (!message.ok) return badRequest(res, message.errors);
    const out = await service.deleteCommunityChatMessage({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      messageId: message.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function toggleCommunityChatMessageReaction(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const message = validateMessageId(req.params.messageId);
    if (!message.ok) return badRequest(res, message.errors);
    const body = validateMessageReaction(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.toggleCommunityChatMessageReaction({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      messageId: message.value,
      dto: body.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function setCommunityChatLock(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const body = validateCommunityChatLockBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.setCommunityChatLock({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      locked: body.value.locked,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function banCommunityChatUser(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const body = validateCommunityChatBanBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.banCommunityChatUser({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      targetUserId: body.value.userId,
      reason: body.value.reason,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function unbanCommunityChatUser(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const target = validateUserId(req.params.userId);
    if (!target.ok) return badRequest(res, target.errors);
    const out = await service.unbanCommunityChatUser({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      targetUserId: target.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function removeCommunityMember(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const body = validateCommunityChatBanBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.removeCommunityMember({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      targetUserId: body.value.userId,
      reason: body.value.reason,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function restoreCommunityMember(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const target = validateUserId(req.params.userId);
    if (!target.ok) return badRequest(res, target.errors);
    const out = await service.restoreCommunityMember({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      targetUserId: target.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listCommunityBills(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const query = validateCommunityBillListQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listCommunityBills({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createCommunityBill(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const body = validateCommunityBillBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const attachmentUrl = req.file ? buildUploadedFileUrl(req, req.file) : null;
    const mime = String(req.file?.mimetype || "").toLowerCase();
    const attachmentKind = !attachmentUrl
      ? null
      : mime.startsWith("image/")
      ? "image"
      : "file";
    const attachmentName =
      req.file && typeof req.file.originalname === "string"
        ? req.file.originalname.trim().slice(0, 180)
        : null;
    const out = await service.createCommunityBill({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      dto: {
        ...body.value,
        attachmentUrl,
        attachmentKind,
        attachmentName,
      },
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listCommunityManagers(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const out = await service.listCommunityManagers({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function searchCommunityUsersForManagers(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const query = validateCommunityUserSearchQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.searchCommunityUsersForManagers({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function searchCommunityUsersForChatModeration(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const query = validateCommunityUserSearchQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.searchCommunityUsersForChatModeration({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function assignCommunityManager(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const body = validateCommunityManagerBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.assignCommunityManager({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      managerUserId: body.value.managerUserId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function revokeCommunityManager(req, res, next) {
  try {
    const scope = parseScopeParams(req);
    if (!scope.ok) return badRequest(res, scope.errors);
    const managerUser = validateUserId(req.params.userId);
    if (!managerUser.ok) return badRequest(res, managerUser.errors);
    const out = await service.revokeCommunityManager({
      userId: req.userId,
      userRole: req.userRole,
      scopeType: scope.value.scopeType,
      scopeCode: scope.value.scopeCode,
      managerUserId: managerUser.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getProfileInsights(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const out = await service.getSocialProfileInsights({
      viewerUserId: req.userId,
      targetUserId: user.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listProfileReels(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const query = validateListPosts({ ...(req.query || {}), kind: 'reel' });
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listProfileReels(req.userId, user.value, query.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listProfileTaggedPosts(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const query = validateListPosts(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listProfileTaggedPosts(req.userId, user.value, query.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createReel(req, res, next) {
  try {
    const body = {
      ...req.body,
      postKind: 'reel',
    };
    const v = validateCreatePost(body);
    if (!v.ok) return badRequest(res, v.errors);
    const media = req.file
      ? {
          url: buildUploadedFileUrl(req, req.file),
          mimetype: req.file.mimetype,
          sizeBytes: req.file.size,
        }
      : null;
    const reel = await service.createReel(
      req.userId,
      { ...body, ...v.value },
      media
    );
    return res.status(201).json({ reel });
  } catch (error) {
    return next(error);
  }
}

export async function recordReelView(req, res, next) {
  try {
    const reel = validatePostId(req.params.reelId);
    if (!reel.ok) return badRequest(res, reel.errors);
    const v = validateReelViewBody(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.recordReelView({
      viewerUserId: req.userId,
      reelId: reel.value,
      dto: v.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getReelById(req, res, next) {
  try {
    const reel = validatePostId(req.params.reelId);
    if (!reel.ok) return badRequest(res, reel.errors);
    const out = await service.getReelById(req.userId, reel.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listThreadMedia(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const query = validateListMessages(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);
    const out = await service.listThreadMedia({
      userId: req.userId,
      threadId: thread.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function setThreadMute(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const body = validateThreadMuteBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.setThreadMute({
      userId: req.userId,
      threadId: thread.value,
      enabled: body.value.enabled,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function setThreadPinned(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const body = validateThreadPinBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.setThreadPinned({
      userId: req.userId,
      threadId: thread.value,
      enabled: body.value.enabled,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function setThreadTheme(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const body = validateThreadThemeBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.setThreadTheme({
      userId: req.userId,
      threadId: thread.value,
      themeKey: body.value.themeKey,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function markThreadRead(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const out = await service.markThreadRead({
      userId: req.userId,
      threadId: thread.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function pinThreadMessage(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const message = validateMessageId(req.params.messageId);
    if (!message.ok) return badRequest(res, message.errors);
    const out = await service.pinThreadMessage({
      userId: req.userId,
      threadId: thread.value,
      messageId: message.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function unpinThreadMessage(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const message = validateMessageId(req.params.messageId);
    if (!message.ok) return badRequest(res, message.errors);
    const out = await service.unpinThreadMessage({
      userId: req.userId,
      threadId: thread.value,
      messageId: message.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function emitThreadTyping(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const body = validateThreadTypingBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);
    const out = await service.emitThreadTyping({
      userId: req.userId,
      threadId: thread.value,
      typing: body.value.typing,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}
