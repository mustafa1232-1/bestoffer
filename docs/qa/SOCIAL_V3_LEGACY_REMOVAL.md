# Social V3 — Legacy Removal (§11)

Old UI is removed once its V3 equivalent is wired and tested. Database content is
never deleted; legacy R2 videos keep playing through the normalized media
adapter (`resolveMediaUrl` + the media contract).

## Deleted (this phase)

| File | Why safe |
|------|----------|
| `lib/features/social/ui/social_reel_viewer_screen.dart` | Imported by nobody after the route cutover — the Reels tab and all reel taps now build `SocialReelsScreenV3`. |
| `lib/features/social/ui/widgets/social_reel_card.dart` | Only imported by the deleted reel viewer. |

`flutter analyze lib/features/social lib/features/social_v3` is clean after
deletion.

## Quarantined (unreachable, kept temporarily)

| Symbol / file | Status | Follow-up |
|---------------|--------|-----------|
| `SocialStoryQuickViewerScreen` (class in `social_story_quick_viewer.dart`) | Unreachable — the `showSocialStoryQuickViewer` **function** in the same file now delegates to `SocialStoryViewerV3`. | Delete the class body; the file stays because the function is the live delegation point. Requires pruning `social_story_canvas`/`social_share_sheet` imports it no longer uses. |
| `SocialStoryViewerScreen` (`social_story_viewer_screen.dart`) | Live loader for the notification-by-storyId path, but it delegates to V3 via `showSocialStoryQuickViewer`. | Fold the group-resolution into a small V3 loader, then delete. |
| Old multipart reel/story upload (`createReel` with `mediaFile`) | Still used by the legacy composer path; V3 uses direct tus + `mediaAssetId`. | Remove once the V3 composers are the only create entry. |
| Generic `FilePicker` social publishing | Superseded by `SocialMediaPickerV3` (native Photo Picker / PHPicker). | Remove the old media-source sheet when the composers are wired into every create button. |

## Repository-wide search results

```
grep -rn "SocialReelViewerScreen|SocialReelCard" lib  → only a doc comment in social_reels_screen.dart
grep -rn "showSocialStoryQuickViewer" lib             → 7 call sites, all now → V3 via the delegating function
```

## Final live-cutover cleanup (create entries)

Every generic create entry now opens V3 via delegation:

| Old symbol | Status | Now |
|------------|--------|-----|
| `showSocialCreatePostSheet` | **ACTIVE_V3** | delegates to `showSocialCreateSelectorV3` (Post/Story/Reel) |
| `showSocialStoryComposerEntrySheet` | **ACTIVE_V3** | delegates to `openStoryComposerV3FromGallery` |
| `SocialCreatePostSheet` / `_CreatePostModePickerSheet` | **DELETED** | old create-post sheet UI removed |
| `social_post_composer_screen.dart` (`showSocialPostComposerScreen`) | **DELETED** | orphaned, no imports |
| `social_story_composer_screen.dart` (screen) | **DEAD_LEGACY** (unreachable) | kept only because its `SocialStoryComposerMode` enum is still referenced by `creator_adapters` + `social_story_draft_controller`; the screen widget is unreachable |
| `pickPostMediaFromDevice` / `pickGalleryMediaFromDevice` | **DOCUMENT_ONLY / non-social** | remaining uses are profile-avatar, report-evidence, residence-proof, and community-scoped/camera creator — not generic Post/Story/Reel publishing; all are gallery pickers, not `FilePicker` |
| `ScopedCommunityStorySheet` | **MUST_REPLACE (scoped)** | community/building-scoped story create; not yet migrated to V3 (needs audience-scope support in `StoryComposerV3`) — documented gap |
| merchant-review create | removed from the create button | not exposed via the V3 selector yet — documented gap |

### Active-route counts

```
Active old Reel viewer routes:   0
Active old Story viewer routes:  0   (all → SocialStoryViewerV3)
Active old Story composer routes: 0  (generic; ScopedCommunityStorySheet is audience-scoped, tracked above)
Active old Reel composer routes:  0
Active social FilePicker media routes: 0   (grep 'FilePicker.platform' lib/features/social → none)
```

## Not deleted (by design)

* Database tables/rows — none touched.
* `social_media_asset` legacy R2 rows — remain readable/playable.
* The `resolveMediaUrl` normalizer — still the transport-safety layer for legacy
  media.
