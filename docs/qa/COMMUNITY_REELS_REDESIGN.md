# Community and Reels redesign

## Scope and implementation sequence

Source: user specification in `pasted-text-1.txt` attached on 2026-09-22,
including both visual references. This is an implementation ledger, not a
completion report. All unverified items remain open.

1. Audit existing routes, models, controllers, endpoints and tests.
2. Redesign the existing feed, stories and post card in place; retain callbacks.
3. Redesign immersive reels and verify current/next-only playback, lifecycle,
   navigation, comments and rapid paging.
4. Separate reel editing, preview and publication. Reuse story layers and real
   media processing; implement cover, trim, drafts and supported settings.
5. Verify upload progress, retry, cancellation and publication against existing
   contracts. Expose no pretend server capabilities.
6. Verify RTL/LTR at 320, 360, 390, 412, 430 and 768+ widths, analysis, existing
   tests, regressions and visual/browser checks. Produce final delivery report.

## Audit evidence

- Entry: `social_shell_screen.dart` -> `social_feed_screen.dart`; existing
  Riverpod `SocialController` owns feed pagination and interactions.
- Feed card: `social_post_card_v2.dart` is the existing shared implementation,
  also used outside the feed. Gallery, cached image and inline video support
  already exist; evolve it without a second competing card.
- Reels: connected V3 viewer and `ReelPlaybackCoordinator`. Initially retains
  previous/current/next, unlike requested current/next. Route and shell
  visibility require verification, especially comments and retained tabs.
- Creation: `reel_gallery_entry_v3.dart` -> `reel_composer_v3.dart` uses story
  document/layers and `ReelComposerController`. Existing editor combines editing
  and publishing and lacks dedicated cover/trim/draft flow.
- Upload: existing Stream session + tus + asset polling + post publication.
  Progress is real; cancellation/disposal races and resumed progress need tests.
- Processing: existing native FFmpeg export with H.264/yuv420p, CRF 22 and
  original geometry; creator filter registry already exists. Web export needs
  explicit capability handling, not a native call or simulated effect.
- Models and API are in `packages/social_core`, re-exported by app wrappers.
- Feed listing currently accepts kind, limit and beforeId only. Following/latest
  tabs need a verified server query; client-only filtering one page is inadequate.
- Existing caption, audience, comment/sharing settings, story layers and
  thumbnail contracts must be traced through validators and persistence before
  exposing publishing options. No new backend changes yet for this redesign.

## Verification outstanding

All specification sections A-U remain subject to final audit. In particular:
post ownership menus and follow, full comments functionality, guest actions,
deep links, actual overlay playback/export, cover persistence, local draft media
durability, processing capability matrix, 20+ reel navigation, upload failure
and cancellation, platform builds and responsive visual evidence.

## Latest implementation notes

- Feed post actions now visually distinguish disabled actions, and post cards
  show a clear note when comments or sharing are turned off by post settings.
- Responsive post/navigation widget coverage was extended for disabled comments
  and sharing, while preserving existing like, save, comments and caption flows.
