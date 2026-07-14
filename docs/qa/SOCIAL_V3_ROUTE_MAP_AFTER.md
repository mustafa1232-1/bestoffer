# Social V3 — Route Map (AFTER cutover)

One authoritative target per social action. Verified by
`test/features/social_v3/cutover_routes_test.dart`.

## Reels — every entry now opens `SocialReelsScreenV3`

| Entry point | Source file | Now routes to | Mechanism |
|---|---|---|---|
| Bottom-nav Reels tab | `social/ui/social_reels_screen.dart` | `SocialReelsScreenV3` | `SocialReelsScreen.build` → `SocialReelsV3Connector` |
| Feed reel tap | `social/ui/social_content_navigation.dart` | `SocialReelsScreenV3` | `openSocialContent` → `openSocialReelsV3` |
| Shared reel (chat/entity) | `social/ui/social_content_navigation.dart` | `SocialReelsScreenV3` | `openSocialSharedEntity` → `openSocialReelsV3` |
| Explore reel tap | `social/ui/social_explore_screen.dart` | `SocialReelsScreenV3` | `_openReels` → `openSocialReelsV3` |
| Profile reels grid | `social/ui/social_profile_posts_screen.dart` | `SocialReelsScreenV3` | `_openReel` → `openSocialReelsV3` |
| Search reel tap | `social/ui/social_search_screen.dart` | `SocialReelsScreenV3` | `onOpenDetails` → `openSocialReelsV3` |
| Reel from notification | shell Reels tab (`initialReelId`) | `SocialReelsScreenV3` | shell tab is now the V3 connector |
| Shared reel inside a story | `social_v3/state/social_story_v3_connector.dart` | `SocialReelsScreenV3` | story `onOpenSharedReel` → `openSocialReelsV3` |

`SocialReelsV3Connector` reuses `socialReelsControllerProvider` + `getReelById`
for data and wires like/save/comments/share/view to the existing API.

## Stories — every entry now opens `SocialStoryViewerV3`

| Entry point | Source file | Now routes to | Mechanism |
|---|---|---|---|
| Story ring (feed) | `social/ui/social_feed_screen.dart` | `SocialStoryViewerV3` | `showSocialStoryQuickViewer` → `openSocialStoryViewerV3` |
| Story from profile | `social/ui/social_profile_screen.dart` | `SocialStoryViewerV3` | same |
| Story from archive | `social/ui/social_profile_archive_screen.dart`, `social_story_archive_screen.dart` | `SocialStoryViewerV3` | same |
| Story from chat | `social/ui/social_chat_thread(s)_screen.dart` | `SocialStoryViewerV3` | same |
| Story from notification | `social/ui/social_story_viewer_screen.dart` (loader) | `SocialStoryViewerV3` | loader resolves group then calls `showSocialStoryQuickViewer` → V3 |

`showSocialStoryQuickViewer()` is the single delegation point: its body now
pushes `SocialStoryViewerV3.route(...)`. The old `SocialStoryQuickViewerScreen`
(fullscreenDialog) is unreachable.

## Create entries — every generic create action opens V3

| Action | Route | Mechanism |
|--------|-------|-----------|
| Feed / community create | `SocialCreateSelectorV3` (Post/Story/Reel) | `showSocialCreatePostSheet` → `showSocialCreateSelectorV3` |
| Create Story (ring add) | `StoryComposerV3` | `showSocialStoryComposerEntrySheet` → `openStoryComposerV3FromGallery` |
| Reels tab create icon | native video picker → `ReelComposerV3` | `SocialReelsScreenV3.onCreate` → `openReelComposerV3` |
| Reel → Add to Story | `StoryComposerV3(SharedReelSource)` | `ShareSheetV3.onAddToStory` |
| Create Post | native multi-pick → `PostComposerV3` | `openPostComposerV3` |

## Feed reel preview

The in-feed reel preview target is `SocialFeedReelPreviewV3` (rectangular,
poster-only, bounded 9:16–4:5), which opens `SocialReelsScreenV3` on tap.
(Widget + regression test landed; wiring it into every `SocialPostCardV2` reel
tile is a follow-up so the shared card is not disturbed mid-cutover.)

## Quarantined (no live route reaches these)

| Old widget | State |
|---|---|
| `SocialReelViewerScreen` | unreachable — only a doc-comment mentions it |
| `SocialReelsScreen` (old body) | replaced by V3 connector |
| `SocialReelCard` | only used by the now-dead `SocialReelViewerScreen` |
| `SocialStoryQuickViewerScreen` | unreachable — entry function delegates to V3 |
| `SocialStoryViewerScreen` | still the notification loader shell, but it now delegates to V3 |

Full deletion of the dead widgets is scheduled in the LEGACY DELETION phase
(after composers/upload land) to keep this cutover diff reviewable.

## Acceptance

Primary question — *"Does every live Reel and Story entry point now open V3?"*
→ **PASS.** Every reel entry resolves to `SocialReelsScreenV3` and every story
entry to `SocialStoryViewerV3`, proven by `cutover_routes_test.dart`.
