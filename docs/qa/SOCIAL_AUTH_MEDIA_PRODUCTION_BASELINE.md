# Social/Auth/Media Production Baseline

Generated: 2026-07-19

## Scope

- In scope: social, auth, media, session, chat, story, reel, and crash/observability closures.
- Out of scope: Services V2, Taxi, Delivery, Coupons, and unrelated dirty work in the root tree.

## Isolation State

- Branch: `feat/social-auth-media-production-closure`
- Base SHA: `31ca8b6cb8e77c76f354261368162ed0b9a60c29`
- Source worktree: `D:\new apps\storeapp\bestoffer-social-auth-media-closure`
- Source worktree status at baseline: clean
- Preserved original dirty worktree: `D:\new apps\storeapp\bestoffer` (untouched)

## Baseline Statement

No Social/Auth/Media Production Closure implementation has started beyond baseline documentation and defect capture.

## Current Flutter Surfaces

### Story

- `lib/features/social_v3/stories/social_story_viewer_v3.dart`
- `lib/features/social/ui/social_story_quick_viewer.dart`
- `lib/features/social/ui/social_story_viewer_screen.dart`
- `lib/features/social/ui/widgets/social_story_canvas.dart`
- `lib/features/social_v3/composer/story_composer_v3.dart`
- `lib/features/social_v3/domain/story_view_data.dart`

### Reels

- `lib/features/social_v3/composer/reel_composer_state.dart`
- `lib/features/social_v3/reels/social_reels_screen_v3.dart`
- `lib/features/social_v3/state/social_reels_v3_connector.dart`
- `lib/features/social/ui/social_profile_screen.dart`
- `lib/features/social/ui/social_post_details_screen.dart`

### Chat / Messaging

- `lib/features/social/ui/social_chat_thread_screen.dart`
- `lib/features/social/ui/widgets/social_community_content_widgets.dart`
- `lib/features/social/ui/widgets/social_voice_message_widgets.dart`
- `lib/features/social/ui/widgets/social_group_thread_sheet.dart`

### Auth / Session

- `lib/core/network/session_invalidation.dart`
- `lib/features/auth/state/auth_controller.dart`
- `lib/core/network/dio_client.dart`
- `lib/core/network/api_error_mapper.dart`
- `lib/app_user_bootstrap.dart`

## Current Backend Surfaces

### Feed / Social

- `backend/src/modules/feed/feed.routes.js`
- `backend/src/modules/feed/feed.controller.js`
- `backend/src/modules/feed/feed.service.js`
- `backend/src/modules/feed/feed.repo.js`
- `backend/src/modules/feed/feed.media.service.js`
- `backend/src/modules/feed/feed.validators.js`
- `backend/src/modules/feed/feed.cache.js`
- `backend/src/modules/feed/feed.product.mappers.js`
- `backend/src/modules/feed/feed.reels.service.js`
- `backend/src/modules/feed/feed.discovery.repo.js`
- `backend/src/modules/feed/feed.discovery.service.js`
- `backend/src/modules/feed/feed.recommendations.service.js`

### Auth / Runtime

- `backend/src/modules/auth/auth.routes.js`
- `backend/src/modules/auth/auth.service.js`
- `backend/src/modules/auth/auth.repo.js`
- `backend/src/shared/middleware/error.middleware.js`
- `backend/src/shared/middleware/access-auth.js`
- `backend/src/shared/realtime/realtime-outbox.js`
- `backend/src/server.js`

## Current Routes Relevant To This Closure

### Media / Story / Reel

- `POST /api/feed/media/stream/upload-session`
- `GET /api/feed/media/assets/:assetId`
- `POST /api/feed/media/stream/webhook`
- `GET /api/feed/stories`
- `GET /api/feed/stories/:storyId`
- `POST /api/feed/stories/:storyId/view`
- `POST /api/feed/stories/:storyId/like`
- `GET /api/feed/stories/:storyId/comments`
- `POST /api/feed/stories/:storyId/comments`
- `POST /api/feed/reels`
- `GET /api/feed/reels/:reelId`
- `POST /api/feed/reels/:reelId/view`
- `GET /api/feed/reels/explore`
- `GET /api/feed/profiles/:userId/reels`

### Chat / Messaging

- `GET /api/feed/chats/threads`
- `POST /api/feed/chats/threads`
- `GET /api/feed/chats/threads/:threadId/messages`
- `POST /api/feed/chats/threads/:threadId/messages`
- `GET /api/feed/chats/threads/:threadId/messages/scheduled`
- `GET /api/feed/chats/requests`
- `GET /api/feed/communities/:scopeType/:scopeCode/chat/messages`
- `POST /api/feed/communities/:scopeType/:scopeCode/chat/messages`

### Auth / Session

- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `POST /api/auth/logout-all`
- `GET /api/auth/sessions`

## Current Tables / Entities

### Media / Social

- `social_media_asset`
- `social_post`
- `social_post_media`
- `social_post_like`
- `social_post_comment`
- `social_post_report`
- `social_post_save`
- `social_story`
- `social_story_view`
- `social_story_like`
- `social_story_comment`
- `social_story_report`
- `social_story_highlight`
- `social_story_report_review_log`
- `social_reel_view_event`

### Chat / Notifications

- `social_chat_thread`
- `social_chat_thread_member`
- `social_chat_participant_state`
- `social_chat_message`
- `social_chat_scheduled_message`
- `social_chat_message_reaction`
- `social_chat_message_translation`
- `realtime_outbox`
- `app_notification`
- `user_push_token`

### Auth / Sessions

- `app_user`
- `user_session`
- `user_device_binding`
- `user_activity_event`

## Current Enums / State Shapes

### Media asset processing

- `pending`
- `processing`
- `ready`
- `failed`
- `rejected`
- `deleted`
- `cancelled`
- `expired`
- `moderated`
- `published`

### Reel composer stage

- `draft`
- `creatingSession`
- `uploading`
- `paused`
- `processing`
- `published`
- `failed`
- `cancelled`

### Chat attachment kind

- `audio`
- `image`
- `video`
- `file`

### Story interaction settings

- `allowLikes`
- `allowPrivateReplies`
- `allowComments`
- `allowSharing`
- `allowReshare`

## Current Flow Notes

- Story lists are grouped in `feed.service.listStories()` from raw rows, with a high row cap before grouping.
- Story viewing exists in both the legacy quick viewer and the V3 full-screen viewer; the V3 viewer is the intended primary surface.
- Reel composition uses Cloudflare Stream upload sessions, then publishes from the client after upload completes.
- Chat messages persist attachment metadata in `social_chat_message`, but the Flutter bubble rendering still has legacy/generic branches for non-audio content.
- Session invalidation is coordinated in Flutter, but only a narrow set of 401 codes currently terminate the session.
- The backend already has durable realtime outbox plumbing for social/chat notifications.

## Known Gaps At Baseline

- No bounded story preload window or performance metrics are present in the current viewer path.
- Voice note rendering can still fall back to a generic attachment row before the server/realtime shape stabilizes.
- Chat image/video rendering is still partially generic instead of fully inline media-first.
- Reel publish currently advances from upload completion to publish without a separate readiness gate in the client flow.
- There is no dedicated media-asset diagnostics endpoint yet.
- The client session invalidation path can still over-treat stale 401s as terminal.
- Same-client concurrent query hotspots remain in the social/chat backend paths and need a regression guard.
- Crash reporting exists, but the redacted envelope and proof-of-delivery coverage are not yet complete for this closure.

## Verification Status

- `flutter analyze`: not run during baseline capture
- `flutter test`: not run during baseline capture
- `cd backend && npm test`: not run during baseline capture
- `cd backend && npm run verify:release:local`: not run during baseline capture
