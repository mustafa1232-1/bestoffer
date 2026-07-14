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
| `ScopedCommunityStorySheet` | **DELETED** | community/building story now opens `StoryComposerV3` with a locked, backend-validated scope (`openStoryComposerV3Scoped`); the old sheet dropped scope entirely and is deleted |
| `SocialStoryComposerMode` | **DOMAIN_MODEL** | already lives in `social_core/social_story_document.dart`; the old UI screen `social_story_composer_screen.dart` is **DELETED** |
| merchant-review create | **ACTIVE_V3** | `PostComposerV3(mode: merchantReview)` via `openPostComposerV3Review`; old review sheet deleted |

### Active-route counts (final)

```
Active old Reel viewer routes:          0
Active old Reel composer routes:        0
Active old Story viewer routes:         0   (all → SocialStoryViewerV3)
Active old generic Story composer routes: 0 (social_story_composer_screen.dart deleted)
Active old scoped Story composer routes:  0 (ScopedCommunityStorySheet deleted)
Active old Post composer routes:        0   (social_post_composer_screen.dart deleted)
Active old merchant-review composer routes: 0
Active social FilePicker media routes:  0   (grep 'FilePicker.platform' lib/features/social → none)
Old small Reel-to-Story card routes:    0
```

### Compatibility entry functions (not legacy UI)

`showSocialCreatePostSheet` and `showSocialStoryComposerEntrySheet` contain **no
old UI** — they only forward to V3. They are kept as thin compatibility wrappers
so existing call sites don't need edits.

### Scoped story now sends authoritative scope

The V3 scoped path fixes a pre-existing bug: `ScopedCommunityStorySheet` called
`createStory(caption, mediaFile)` with **no scope**, so community stories were
published globally. `api.createStory` / `controller.createStory` now carry
`audienceScopeType`/`audienceScopeCode`, re-validated by the backend
(`feed.validators.js`).

## Not deleted (by design)

* Database tables/rows — none touched.
* `social_media_asset` legacy R2 rows — remain readable/playable.
* The `resolveMediaUrl` normalizer — still the transport-safety layer for legacy
  media.
