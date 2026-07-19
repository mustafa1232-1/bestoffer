# Social/Auth/Media Defect Ledger

Generated: 2026-07-19

## 1. STORY_SLOW_FIRST_FRAME

- User-visible symptom: opening a story is slow to show the first visible frame, and advancing between items is not prewarmed.
- Flutter screen/widget/controller:
  - `lib/features/social_v3/stories/social_story_viewer_v3.dart`
  - `lib/features/social/ui/social_story_quick_viewer.dart`
  - `lib/features/social/ui/widgets/social_story_canvas.dart`
- API endpoint:
  - `GET /api/feed/stories`
  - `GET /api/feed/stories/:storyId`
- Backend controller/service/repo:
  - `backend/src/modules/feed/feed.controller.js`
  - `backend/src/modules/feed/feed.service.js`
  - `backend/src/modules/feed/feed.repo.js`
- DB tables:
  - `social_story`
  - `social_media_asset`
  - `social_story_view`
- Realtime/media provider:
  - Cloudflare R2 and Cloudflare Stream
- Reproduction steps:
  1. Open a user with multiple stories.
  2. Tap into the story viewer on a cold cache.
  3. Observe the delay before the first frame and the lack of a true bounded preload window.
- Current root cause:
  - The primary story path initializes media only after route build/post-frame and does not maintain a bounded current/next preload window or viewer metrics. The story feed also fetches a large grouped payload before grouping in Flutter, which increases time-to-first-frame.
- Acceptance test:
  - Poster appears immediately, first frame follows quickly, next item preloads, no duplicate advance, and no controller leak on reopen.

## 2. VOICE_TEMPORARILY_RENDERED_AS_FILE

- User-visible symptom: a voice note briefly appears as a generic file/attachment before stabilizing as audio.
- Flutter screen/widget/controller:
  - `lib/features/social/ui/social_chat_thread_screen.dart`
  - `lib/features/social/ui/widgets/social_community_content_widgets.dart`
  - `lib/features/social/ui/widgets/social_voice_message_widgets.dart`
- API endpoint:
  - `POST /api/feed/chats/threads/:threadId/messages`
  - `GET /api/feed/chats/threads/:threadId/messages`
  - `GET /api/feed/chats/threads/:threadId/messages/scheduled`
- Backend controller/service/repo:
  - `backend/src/modules/feed/feed.controller.js`
  - `backend/src/modules/feed/feed.service.js`
  - `backend/src/modules/feed/feed.repo.js`
- DB tables:
  - `social_chat_message`
  - `social_chat_scheduled_message`
- Realtime/media provider:
  - realtime chat message stream
- Reproduction steps:
  1. Record and send a voice message.
  2. Observe the outgoing message bubble immediately after send.
  3. Wait for the periodic chat refresh to reconcile the payload.
- Current root cause:
  - The chat path still depends on a fallback polling loop and the UI has legacy attachment rendering branches. The canonical audio attachment shape is not enforced end-to-end on the first send/realtime frame, so the local optimistic message can momentarily render as a generic attachment before the audio-specific bubble wins.
- Acceptance test:
  - From send until READY, the voice message never renders as a generic file card.

## 3. CHAT_IMAGE_RENDERED_AS_LINK_OR_FILE

- User-visible symptom: an image shared in chat renders as a link/file-style attachment instead of an inline image bubble.
- Flutter screen/widget/controller:
  - `lib/features/social/ui/social_chat_thread_screen.dart`
  - `lib/features/social/ui/widgets/social_community_content_widgets.dart`
- API endpoint:
  - `POST /api/feed/chats/threads/:threadId/messages`
  - `GET /api/feed/chats/threads/:threadId/messages`
- Backend controller/service/repo:
  - `backend/src/modules/feed/feed.controller.js`
  - `backend/src/modules/feed/feed.service.js`
  - `backend/src/modules/feed/feed.repo.js`
- DB tables:
  - `social_chat_message`
  - `social_chat_scheduled_message`
- Realtime/media provider:
  - chat realtime event payload
- Reproduction steps:
  1. Send an image to a chat thread.
  2. Open the thread on a receiving client.
  3. Observe the message bubble rendering.
- Current root cause:
  - The thread bubble UI treats every non-audio attachment as a generic attachment row and opens the media by tap, instead of rendering an inline image/video bubble with a dedicated contract.
- Acceptance test:
  - Local preview, server image, fullscreen zoom, and no generic file/link rendering for image messages.

## 4. REEL_PUBLISH_FAILED

- User-visible symptom: a reel upload completes, but publishing fails or the reel never becomes visible.
- Flutter screen/widget/controller:
  - `lib/features/social_v3/composer/reel_composer_state.dart`
  - `lib/features/social_v3/composer/reel_composer_v3.dart`
  - `lib/features/social_v3/upload/reel_upload_api_impl.dart`
- API endpoint:
  - `POST /api/feed/media/stream/upload-session`
  - `GET /api/feed/media/assets/:assetId`
  - `POST /api/feed/reels`
- Backend controller/service/repo:
  - `backend/src/modules/feed/feed.controller.js`
  - `backend/src/modules/feed/feed.service.js`
  - `backend/src/modules/feed/feed.media.service.js`
  - `backend/src/modules/feed/feed.repo.js`
- DB tables:
  - `social_media_asset`
  - `social_post`
- Realtime/media provider:
  - Cloudflare Stream
- Reproduction steps:
  1. Start a reel upload from the composer.
  2. Let the upload finish.
  3. Observe the publish step or feed visibility.
- Current root cause:
  - The client transitions from upload completion straight into publish, while the backend publish path is still gated by asset readiness/reconciliation. If the asset has not reached READY, publish can fail or remain invisible.
- Acceptance test:
  - Upload session, TUS progress, processing, webhook, reconciliation, READY, publish, then feed visibility.

## 5. FALSE_SESSION_EXPIRED

- User-visible symptom: the app logs the user out or shows an expired-session state even though the failure was a stale access token or a recoverable transient auth error.
- Flutter screen/widget/controller:
  - `lib/core/network/session_invalidation.dart`
  - `lib/features/auth/state/auth_controller.dart`
  - `lib/core/network/dio_client.dart`
  - `lib/core/network/api_error_mapper.dart`
- API endpoint:
  - `POST /api/auth/refresh`
  - any authenticated endpoint returning a stale 401
- Backend controller/service/repo:
  - `backend/src/modules/auth/auth.service.js`
  - `backend/src/modules/auth/auth.repo.js`
  - `backend/src/shared/middleware/access-auth.js`
- DB tables:
  - `user_session`
  - `user_push_token`
- Realtime/media provider:
  - realtime token refresh path
- Reproduction steps:
  1. Let an access token expire.
  2. Trigger concurrent authenticated requests and a refresh.
  3. Observe whether the client tears down the session.
- Current root cause:
  - The client-side invalidation path treats a narrow set of 401 auth codes as terminal without enough distinction between stale access-token expiry, refresh-in-flight races, and actual terminal session revocation.
- Acceptance test:
  - Only proven terminal errors end the session; stale 401s do not.

## 6. INTERMITTENT_CRASH

- User-visible symptom: the app intermittently crashes in social flows with a dynamic map cast / concurrent-query warning signature.
- Flutter screen/widget/controller:
  - `lib/features/social/ui/social_chat_thread_screen.dart`
  - `lib/features/social/ui/social_story_canvas.dart`
  - `lib/features/social_v3/composer/story_composer_v3.dart`
  - `lib/features/social_v3/upload/reel_upload_api_impl.dart`
- API endpoint:
  - various social/chat/story endpoints that return dynamic JSON payloads
- Backend controller/service/repo:
  - `backend/src/modules/feed/feed.service.js`
  - `backend/src/modules/feed/feed.repo.js`
  - `backend/src/server.js`
  - `backend/src/app.js`
- DB tables:
  - `social_chat_message`
  - `social_story`
  - `social_media_asset`
  - `realtime_outbox`
- Realtime/media provider:
  - social realtime stream and outbox
- Reproduction steps:
  1. Open a social screen that parses mixed legacy and current JSON.
  2. Trigger a refresh or live event while the backend is busy.
  3. Observe the dynamic cast failure or concurrent-query warning path.
- Current root cause:
  - Several social parsing paths still assume `Map<String, dynamic>` even when the payload is coming from a dynamic source, and the backend still has same-client query hot spots that can overlap on the same transaction/client during busy social flows.
- Acceptance test:
  - Redacted crash events reach observability, and the concurrent-query warning path is eliminated.

## 7. PG_CLIENT_CONCURRENT_QUERY

- User-visible symptom: backend emits a PostgreSQL warning/error pattern indicating concurrent use of the same client connection.
- Flutter screen/widget/controller:
  - not Flutter-specific; triggered by social/backend runtime activity
- API endpoint:
  - any busy social/auth/media path that touches the overlapping backend code
- Backend controller/service/repo:
  - `backend/src/server.js`
  - `backend/src/app.js`
  - `backend/src/modules/feed/feed.repo.js`
  - `backend/src/modules/feed/feed.service.js`
  - `backend/src/modules/orders/orders.repo.js`
  - `backend/src/modules/delivery/delivery-job.service.js`
  - `backend/src/modules/company/company.service.js`
- DB tables:
  - whichever table the hot path touches; the issue is connection usage, not a single table
- Realtime/media provider:
  - not provider-specific
- Reproduction steps:
  1. Run the backend under load or trace mode.
  2. Exercise overlapping social reads/writes that share a transaction client.
  3. Observe the concurrent `client.query()` warning.
- Current root cause:
  - The hot path still contains same-client overlapping query usage and/or `Promise.all` patterns around a transaction-scoped client, which can trigger the concurrent query warning on PostgreSQL.
- Acceptance test:
  - Sequential query usage or separate connections eliminate the warning path under regression load.
