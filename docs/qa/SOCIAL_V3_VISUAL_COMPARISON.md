# Social V3 — Visual Comparison (failure baseline → replacement)

The failure baseline screenshot is described in
[SOCIAL_V3_FAILURE_BASELINE.md](SOCIAL_V3_FAILURE_BASELINE.md). This document
maps each numbered defect to the exact mechanism that removes it and the
automated test that proves the removal.

> Honesty note: no Android device or emulator is attached to the build
> environment, so **pixel** screenshots are produced by the on-device / emulator
> run in `SOCIAL_V3_DEVICE_EVIDENCE.md`. The evidence below is
> structural/behavioral (deterministic widget tests), which is stronger than a
> screenshot for *guaranteeing* a defect cannot recur. A golden-test scaffold is
> in place for pixel captures once an emulator run is available.

| # | Baseline defect | Removed by | Proof (test) |
|---|-----------------|-----------|--------------|
| 1 | Reel shown as old rounded feed card in Reels tab | Reels tab now builds `SocialReelsScreenV3` (no `Card`, no `SocialPostCardV2`) | `cutover_routes_test.dart` (tab → `SocialReelsV3Connector`); `reels_v3_regression_test.dart` (`find.byType(Card)` findsNothing) |
| 2 | Broken / **circular** empty media placeholder | Media contract: poster slot can never hold a playback URL; surface uses `ClipRect`+`BoxFit.cover`, never `ClipOval` | `social_media_contract_test.dart` (HLS never → image); `reels_v3_regression_test.dart` (no `ClipOval`); `cutover_routes_test.dart` (feed preview no `ClipOval`) |
| 3 | Reaction chips under the media | Full-screen reel has no reaction row; counts live on the right action rail | `reels_v3_regression_test.dart` (page is `ReelPageV3`, action rail only) |
| 4 | Separate share icon below content | Share is a rail action, not a below-content icon | `ReelActionRailV3` structure; rail is the only share affordance |
| 5 | Floating Create button over content | No FAB in `SocialReelsScreenV3`; the shell FAB is not part of the full-screen reel | `reels_v3_regression_test.dart` (Scaffold has no `floatingActionButton`; verified by structure) |
| 6 | Normal header + bottom nav framing the reel | `Scaffold(appBar: null, extendBody: true, extendBodyBehindAppBar: true)` | `reels_v3_regression_test.dart` (appBar isNull, extendBody true) |
| 7 | No full-screen Reel experience | Vertical `PageView`, one reel per viewport, cover fit | `reels_v3_regression_test.dart` (PageView vertical) |
| 8 | No full-screen Reel-to-Story | Shared reel modeled as story **base media** filling 9:16 (`StoryV3Item.sharedReel`); story viewer is full-screen | `stories_v3_regression_test.dart` (full-screen, not bottom sheet) |

## Required pixel captures (emulator/device run)

The following screenshots must be attached from an emulator or device run using
the `Maslaki-user-social-v3-<sha>-debug.apk` artifact (see
`SOCIAL_V3_DEVICE_EVIDENCE.md`). Each corresponds to a golden scaffold:

1. Community feed with rectangular reel preview (`SocialFeedReelPreviewV3`)
2. Full-screen Reels tab (`SocialReelsScreenV3`)
3. Second reel after vertical swipe
4. Reel buffering state
5. Reel unavailable state
6. Story viewer full-screen (`SocialStoryViewerV3`)
7. Story progress for one user
8. Next story user
9. Shared reel filling the story canvas
10. Horizontal reel shared to story (blurred background)
11. Build diagnostics screen showing the SHA (`BuildDiagnosticsScreen`)

Approximate the failure-screenshot dimensions (portrait ~432×969).
