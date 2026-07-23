import { Router } from "express";

import { optionalAuth, requireAuth } from "../../shared/middleware/auth.middleware.js";
import {
  chatAttachmentUpload,
  imageUpload,
  mediaUpload,
} from "../../shared/utils/upload.js";
import * as c from "./feed.controller.js";

export const feedRouter = Router();

feedRouter.post("/media/stream/webhook", c.streamWebhook);
// Numeric constraint: this public route is declared before the authenticated
// block, so an unconstrained ":reelId" also swallowed GET /reels/explore
// (reelId="explore" -> validatePostId fails -> 400) and the Reels page could
// never load its feed.
feedRouter.get("/reels/:reelId(\\d+)", optionalAuth, c.getPublicReelById);

feedRouter.use(requireAuth);

feedRouter.get("/capabilities", c.getSocialCapabilities);
feedRouter.post("/media/stream/upload-session", c.createStreamUploadSession);
feedRouter.post(
  "/media/stream/upload-session/:assetId/cancel",
  c.cancelStreamUploadSession
);
feedRouter.get("/media/assets/:assetId", c.getSocialMediaAssetById);
feedRouter.get(
  "/media/assets/:assetId/diagnostics",
  c.getSocialMediaAssetDiagnosticsById
);

feedRouter.get("/explore", c.listExplore);
feedRouter.get("/trending", c.listTrending);
feedRouter.get("/reels/explore", c.listExploreReels);
feedRouter.get("/users/suggested", c.listSuggestedPeople);
feedRouter.get("/search", c.searchSocialCatalog);
feedRouter.get("/hashtags/trending", c.listTrendingTags);
feedRouter.get("/hashtags/suggest", c.listHashtagSuggestions);
feedRouter.get("/hashtags/:tag", c.listHashtagPosts);
feedRouter.get("/mentions/users", c.listMentionUsers);
feedRouter.get("/posts", c.listPosts);
feedRouter.get("/posts/:postId", c.getPostById);
feedRouter.get("/users/search", c.searchUsers);
feedRouter.get("/communities/scopes/me", c.getMyCommunityScopes);
feedRouter.get("/communities/:scopeType/:scopeCode/feed", c.listCommunityFeed);
feedRouter.get(
  "/communities/:scopeType/:scopeCode/announcements",
  c.listCommunityAnnouncements
);
feedRouter.post(
  "/communities/:scopeType/:scopeCode/announcements",
  c.createCommunityAnnouncement
);
feedRouter.get(
  "/communities/:scopeType/:scopeCode/chat/messages",
  c.listCommunityChat
);
feedRouter.get(
  "/communities/:scopeType/:scopeCode/chat/messages/search",
  c.searchCommunityChatMessages
);
feedRouter.post(
  "/communities/:scopeType/:scopeCode/chat/messages",
  chatAttachmentUpload.single("attachmentFile"),
  c.sendCommunityChatMessage
);
feedRouter.post(
  "/communities/:scopeType/:scopeCode/chat/typing",
  c.emitCommunityChatTyping
);
feedRouter.patch(
  "/communities/:scopeType/:scopeCode/chat/messages/:messageId",
  c.updateCommunityChatMessage
);
feedRouter.delete(
  "/communities/:scopeType/:scopeCode/chat/messages/:messageId",
  c.deleteCommunityChatMessage
);
feedRouter.post(
  "/communities/:scopeType/:scopeCode/chat/messages/:messageId/reaction",
  c.toggleCommunityChatMessageReaction
);
feedRouter.patch(
  "/communities/:scopeType/:scopeCode/chat/lock",
  c.setCommunityChatLock
);
feedRouter.post(
  "/communities/:scopeType/:scopeCode/chat/ban",
  c.banCommunityChatUser
);
feedRouter.get(
  "/communities/:scopeType/:scopeCode/chat/users",
  c.searchCommunityUsersForChatModeration
);
feedRouter.delete(
  "/communities/:scopeType/:scopeCode/chat/ban/:userId",
  c.unbanCommunityChatUser
);
feedRouter.post(
  "/communities/:scopeType/:scopeCode/members/remove",
  c.removeCommunityMember
);
feedRouter.delete(
  "/communities/:scopeType/:scopeCode/members/remove/:userId",
  c.restoreCommunityMember
);
feedRouter.get("/communities/:scopeType/:scopeCode/bills", c.listCommunityBills);
feedRouter.post(
  "/communities/:scopeType/:scopeCode/bills",
  chatAttachmentUpload.single("attachmentFile"),
  c.createCommunityBill
);
feedRouter.get(
  "/communities/:scopeType/:scopeCode/managers",
  c.listCommunityManagers
);
feedRouter.get(
  "/communities/:scopeType/:scopeCode/users/search",
  c.searchCommunityUsersForManagers
);
feedRouter.post(
  "/communities/:scopeType/:scopeCode/managers",
  c.assignCommunityManager
);
feedRouter.delete(
  "/communities/:scopeType/:scopeCode/managers/:userId",
  c.revokeCommunityManager
);
feedRouter.get("/users/:userId/profile", c.getUserProfile);
feedRouter.post("/users/:userId/report", c.reportUser);
feedRouter.patch(
  "/users/:userId/notification-preference",
  c.setUserNotificationPreference
);
feedRouter.post("/users/:userId/super-admin/action", c.runSuperAdminUserAction);
feedRouter.get("/users/:userId/followers", c.listUserFollowers);
feedRouter.get("/users/:userId/following", c.listUserFollowing);
feedRouter.get("/users/:userId/friends", c.listUserFriends);
feedRouter.get("/users/:userId/posts", c.listUserPosts);
feedRouter.get("/users/:userId/liked-posts", c.listUserLikedPosts);
feedRouter.get("/users/:userId/commented-posts", c.listUserCommentedPosts);
feedRouter.get("/users/:userId/highlights", c.listUserHighlights);
feedRouter.get("/users/:userId/relation", c.getUserRelationState);
feedRouter.post("/users/:userId/relation/request", c.sendUserRelationRequest);
feedRouter.post("/users/:userId/relation/accept", c.acceptUserRelationRequest);
feedRouter.post("/users/:userId/relation/reject", c.rejectUserRelationRequest);
feedRouter.post("/users/:userId/relation/cancel", c.cancelUserRelationRequest);
feedRouter.post("/users/:userId/relation/remove", c.removeUserRelation);
feedRouter.post("/users/:userId/relation/block", c.blockUserRelation);
feedRouter.post("/users/:userId/relation/unblock", c.unblockUserRelation);
feedRouter.get("/relations/incoming", c.listIncomingRelationRequests);
feedRouter.get("/relations/outgoing", c.listOutgoingRelationRequests);
feedRouter.patch("/profile/me", imageUpload.single("imageFile"), c.updateMyProfile);
feedRouter.get("/profile/me/username/check", c.checkMyUsernameAvailability);
feedRouter.patch("/profile/me/username", c.updateMyUsername);
feedRouter.get("/profile/me/residence-change", c.getMyResidenceChangeRequest);
feedRouter.post(
  "/profile/me/residence-change",
  imageUpload.single("documentImageFile"),
  c.createMyResidenceChangeRequest
);
feedRouter.post(
  "/profile/me/residence-change/:requestId/cancel",
  c.cancelMyResidenceChangeRequest
);
feedRouter.get(
  "/profile/me/social-restrictions",
  c.listMyActiveSocialCapabilityRestrictions
);
feedRouter.get("/profile/me/reported-posts", c.listMyReportedPosts);
feedRouter.get("/profile/me/reported-stories", c.listMyReportedStories);
feedRouter.get("/archive/posts", c.listMyArchivedPosts);
feedRouter.get("/saved", c.listSavedContent);
feedRouter.get("/saved/collections", c.listSavedCollections);
feedRouter.post("/saved/collections", c.createSavedCollection);
feedRouter.patch("/saved/collections/:collectionId", c.updateSavedCollection);
feedRouter.delete("/saved/collections/:collectionId", c.deleteSavedCollection);
feedRouter.post("/saved/toggle", c.toggleSavedContent);
feedRouter.post(
  "/posts",
  mediaUpload.fields([
    { name: "mediaFile", maxCount: 1 },
    { name: "mediaFiles", maxCount: 10 },
  ]),
  c.createPost
);
feedRouter.patch(
  "/posts/:postId/resubmit",
  mediaUpload.single("mediaFile"),
  c.resubmitModeratedPost
);
feedRouter.post("/posts/:postId/archive", c.archivePost);
feedRouter.post("/posts/:postId/restore", c.restorePost);
feedRouter.delete("/posts/:postId", c.deletePost);
feedRouter.post("/posts/:postId/like", c.toggleLike);
feedRouter.get("/posts/:postId/likes", c.listPostLikers);
feedRouter.get("/posts/:postId/comments", c.listPostComments);
feedRouter.post("/posts/:postId/comments", c.addComment);
feedRouter.patch("/posts/:postId/comments/:commentId", c.updateComment);
feedRouter.delete("/posts/:postId/comments/:commentId", c.deleteComment);
feedRouter.post("/posts/:postId/comments/:commentId/like", c.toggleCommentLike);
feedRouter.post("/posts/:postId/report", c.reportPost);
feedRouter.get("/stories", c.listStories);
feedRouter.get("/stories/archive/me", c.listMyStoryArchive);
feedRouter.post("/stories", mediaUpload.single("mediaFile"), c.createStory);
feedRouter.get("/stories/:storyId", c.getStoryById);
feedRouter.post("/stories/:storyId/archive", c.archiveStory);
feedRouter.post("/stories/:storyId/restore", c.restoreStory);
feedRouter.post("/stories/:storyId/view", c.markStoryViewed);
feedRouter.post("/stories/:storyId/like", c.toggleStoryLike);
feedRouter.get("/stories/:storyId/comments", c.listStoryComments);
feedRouter.post("/stories/:storyId/comments", c.addStoryComment);
feedRouter.post("/stories/:storyId/report", c.reportStory);
feedRouter.post("/stories/:storyId/highlight", c.highlightStory);
feedRouter.delete("/highlights/:highlightId", c.removeHighlight);
feedRouter.get("/merchants", c.listMerchants);
feedRouter.get("/share/recipients", c.listShareRecipients);
feedRouter.get("/profiles/:userId/insights", c.getProfileInsights);
feedRouter.get("/profiles/:userId/reels", c.listProfileReels);
feedRouter.get("/profiles/:userId/tagged", c.listProfileTaggedPosts);
feedRouter.post("/reels", mediaUpload.single("mediaFile"), c.createReel);
feedRouter.post("/reels/:reelId/view", c.recordReelView);

feedRouter.get("/chats/threads", c.listThreads);
feedRouter.post("/chats/threads", c.createThread);
feedRouter.get("/chats/threads/:threadId/group", c.getGroupThreadDetails);
feedRouter.patch("/chats/threads/:threadId/group", c.updateGroupThread);
feedRouter.post(
  "/chats/threads/:threadId/group/members",
  c.addGroupThreadMembers
);
feedRouter.delete(
  "/chats/threads/:threadId/group/members/:userId",
  c.removeGroupThreadMember
);
feedRouter.patch(
  "/chats/threads/:threadId/group/members/:userId/role",
  c.updateGroupThreadMemberRole
);
feedRouter.post("/chats/threads/:threadId/group/leave", c.leaveGroupThread);
feedRouter.get("/chats/requests", c.listChatRequests);
feedRouter.get(
  "/chats/privacy/quality-review-consent",
  c.getMyChatQualityReviewConsent
);
feedRouter.patch(
  "/chats/privacy/quality-review-consent",
  c.setMyChatQualityReviewConsent
);
feedRouter.get("/admin/chats/threads", c.listAdminMonitoredThreads);
feedRouter.get(
  "/admin/chats/threads/:threadId/messages",
  c.listAdminMonitoredThreadMessages
);
feedRouter.get(
  "/admin/chats/community/:scopeType/:scopeCode/messages",
  c.listAdminMonitoredCommunityMessages
);
feedRouter.get(
  "/chats/threads/:threadId/messages/search",
  c.searchThreadMessages
);
feedRouter.get(
  "/chats/threads/:threadId/messages/scheduled",
  c.listScheduledThreadMessages
);
feedRouter.post(
  "/chats/threads/:threadId/messages/scheduled",
  chatAttachmentUpload.single("attachmentFile"),
  c.scheduleThreadMessage
);
feedRouter.delete(
  "/chats/threads/:threadId/messages/scheduled/:scheduledMessageId",
  c.cancelScheduledThreadMessage
);
feedRouter.get("/chats/threads/:threadId/messages", c.listThreadMessages);
feedRouter.post(
  "/chats/threads/:threadId/messages",
  chatAttachmentUpload.single("attachmentFile"),
  c.sendThreadMessage
);
feedRouter.patch(
  "/chats/threads/:threadId/messages/:messageId",
  c.updateThreadMessage
);
feedRouter.post(
  "/chats/threads/:threadId/messages/:messageId/translate",
  c.translateThreadMessage
);
feedRouter.delete(
  "/chats/threads/:threadId/messages/:messageId",
  c.deleteThreadMessage
);
feedRouter.post(
  "/chats/threads/:threadId/messages/:messageId/reaction",
  c.toggleThreadMessageReaction
);
feedRouter.post("/chats/requests/:threadId/accept", c.acceptChatRequest);
feedRouter.post("/chats/requests/:threadId/reject", c.rejectChatRequest);
feedRouter.post("/chats/requests/:threadId/block", c.blockChatRequest);
feedRouter.get("/chats/threads/:threadId/call", c.getThreadCallState);
feedRouter.post("/chats/threads/:threadId/call/start", c.startThreadCall);
feedRouter.post("/chats/threads/:threadId/call/signal", c.sendThreadCallSignal);
feedRouter.post("/chats/threads/:threadId/call/end", c.endThreadCall);
feedRouter.get("/chats/threads/:threadId/media", c.listThreadMedia);
feedRouter.patch("/chats/threads/:threadId/read", c.markThreadRead);
feedRouter.post("/chats/threads/:threadId/typing", c.emitThreadTyping);
feedRouter.patch("/chats/threads/:threadId/mute", c.setThreadMute);
feedRouter.patch("/chats/threads/:threadId/pin", c.setThreadPinned);
feedRouter.patch("/chats/threads/:threadId/theme", c.setThreadTheme);
feedRouter.post(
  "/chats/threads/:threadId/messages/:messageId/pin",
  c.pinThreadMessage
);
feedRouter.delete(
  "/chats/threads/:threadId/messages/:messageId/pin",
  c.unpinThreadMessage
);
