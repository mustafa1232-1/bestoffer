# Social V3 — Route Map (BEFORE cutover)

Live navigation as it exists on `closure/full-application-closure` @ `c688e43`
before the V3 route cutover. The **Reels tab row is the route that produced the
supplied failure screenshot** (community "الرئيسية" shell → Reels tab →
`SocialReelsScreen` → `SocialReelViewerScreen` → old `SocialReelCard`).

## Reels

| Entry point | Source file | Widget/fn | Current target | Intended V3 target | Auth | initialId passed | Nav state preserved |
|---|---|---|---|---|---|---|---|
| Bottom-nav Reels tab | `social/ui/social_shell_screen.dart:150` | `_pageFor` | `SocialReelsScreen` → `SocialReelViewerScreen` | `SocialReelsScreenV3` (via connector) | guest ok | `initialReelId` | tab-persisted |
| Feed reel tap | `social/ui/social_content_navigation.dart:28-40` | `openSocialContent` | `SocialReelViewerScreen(initialReelId)` | V3 connector | guest ok | yes | pushed route |
| Shared reel (chat/entity) | `social/ui/social_content_navigation.dart:70-77` | `openSocialSharedEntity` | `SocialReelViewerScreen(initialReelId: entity.id)` | V3 connector | guest ok | yes | pushed route |
| Explore reel tap | `social/ui/social_explore_screen.dart:217` | grid onTap | `SocialReelViewerScreen(initialReelId)` | V3 connector | guest ok | yes | pushed route |
| Profile reels grid | `social/ui/social_profile_posts_screen.dart:235` | grid onTap | `SocialReelViewerScreen(initialReelId)` | V3 connector | guest ok | yes | pushed route |
| Search reel tap | `social/ui/social_search_screen.dart:308` | result onTap | `SocialReelViewerScreen(initialReelId)` | V3 connector | guest ok | yes | pushed route |
| Reel from notification | `core/notifications/notification_navigation.dart` | reel target | shell → Reels tab (`initialReelId`) | V3 (via shell) | auth | yes | replaces to shell |
| Reel data load by id | `social/ui/social_reel_viewer_screen.dart:198` | `_bootstrapInitialReel` | `api.getReelById(id)` + explore feed | reused by connector | — | — | — |

## Stories

| Entry point | Source file | Widget/fn | Current target | Intended V3 target | Auth | initialId passed | Nav state |
|---|---|---|---|---|---|---|---|
| Story ring (feed) | `social/ui/social_feed_screen.dart:121` | `showSocialStoryQuickViewer` | `SocialStoryQuickViewerScreen` (fullscreenDialog) | `SocialStoryViewerV3` | guest ok | `initialStoryId` | pushed |
| Story from profile | `social/ui/social_profile_screen.dart:836,920` | `showSocialStoryQuickViewer` | same | `SocialStoryViewerV3` | guest ok | yes | pushed |
| Story from archive | `social/ui/social_profile_archive_screen.dart:182`, `social_story_archive_screen.dart:94` | `showSocialStoryQuickViewer` | same | `SocialStoryViewerV3` | auth | yes | pushed |
| Story from chat | `social/ui/social_chat_thread(s)_screen.dart` | `showSocialStoryQuickViewer` | same | `SocialStoryViewerV3` | auth | yes | pushed |
| Story from notification | `core/notifications/notification_navigation.dart:803,829` | route builder | `SocialStoryViewerScreen(storyId)` | `SocialStoryViewerV3` | auth | yes | pushed |

**Single cutover point for stories:** `showSocialStoryQuickViewer()` is called by
every story entry above except the notification path, so rewriting its body to
push `SocialStoryViewerV3.route(...)` cuts all of them over at once. The
notification path is switched separately.

## Create / composer

| Entry point | Source file | Current target | Intended V3 target |
|---|---|---|---|
| Create Reel | `social/ui/social_reel_viewer_screen.dart:414` `_openCreateReel` | `SocialCreatePostSheet` / composer | `ReelComposerV3` (later phase) |
| Create Story | `social/ui/social_story_composer_entry_sheet.dart` | `SocialStoryComposerScreen` | `StoryComposerV3` (later phase) |
| Add Reel to Story | `social/ui/social_reel_viewer_screen.dart:361` `_shareToStory` | old attachment-card composer | `StoryComposerV3(StorySource.sharedReel)` (later phase) |

## Old widgets to quarantine after cutover

`SocialReelViewerScreen`, `SocialReelsScreen` (old body), `SocialReelCard`,
`SocialStoryQuickViewerScreen`, `SocialStoryViewerScreen`, and the
`SocialPostCardV2` reel-preview path.
