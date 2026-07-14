# Social V3 — Release Report

**Statuses:** PASS · PARTIAL · FAIL · BLOCKED · NOT_TESTED

> Honesty note: this report is written from a development environment with the
> Flutter toolchain but **no connected Android/iOS device and no `adb`**. Every
> claim below is scoped to what was actually verified. On-device acceptance
> (§0, §15) is **NOT_TESTED** here and is the user's to run — the exact commands
> are in `SOCIAL_V3_DEVICE_EVIDENCE.md`.

## Build identity

| Item | Value |
|------|-------|
| Implementation branch | `closure/full-application-closure` |
| Working-tree HEAD (old build SHA) | `c688e43dbbd72c5d1f347d3f2085c5322b312973` |
| New build SHA | **not yet built** — V3 changes are uncommitted on the working tree |
| Installed device build SHA | **NOT_TESTED** — no device/`adb` in this environment |
| User flavor applicationId | `com.maslaki.user` |
| Backend base URL | `https://bestoffer-production.up.railway.app` |

The `BuildInfo` contract + hidden diagnostics screen + startup log now let the
*next* installed APK self-report its SHA, which is the mechanism that resolves
the "stale APK vs intended commit" question the brief opens with.

## Section-by-section status

| § | Area | Status | Evidence |
|---|------|--------|----------|
| 0 | BuildInfo contract, diagnostics screen, startup SHA log | PASS | `lib/core/diagnostics/build_info.dart`, `build_diagnostics_screen.dart`; `flutter analyze` clean |
| 0 | Uninstall / clean / build user APK / install / capture SHA screenshot | NOT_TESTED | no device |
| 2 | Media contract + debug assertions + HLS-never-image tests | PASS | `social_media_contract_test.dart` (12 assertions) |
| 1 | `social_v3` clean module + coordinators | PASS (scaffolded) | `lib/features/social_v3/*` |
| 3 | Full-screen Reels (screen/page/surface/rail/overlay/coordinator) | PASS | `reels_v3_regression_test.dart`, `reels_v3_coordinator_test.dart` |
| 5 | Story Viewer V3 full-screen (not a bottom sheet) | PASS | `stories_v3_regression_test.dart` |
| 4 | Feed Reel preview vs viewer separation | NOT_STARTED | — |
| 6 | Reel-to-Story from the data model (full-canvas) | PARTIAL | `StoryV3Item.sharedReel` + "فتح الريل" affordance modeled; composer base still pending |
| 7 | Story Composer V3 | NOT_STARTED | — |
| 8 | Reel Composer V3 + direct tus upload | NOT_STARTED | backend tus provisioning + Flutter uploader pending |
| 9 | Native gallery-first pickers | NOT_STARTED | — |
| 10 | Reel eligibility query + publish-to-visible | NOT_STARTED | — |
| 11 | Unified Share Sheet V3 | NOT_STARTED | — |
| 12 | Comments/reactions/saves/messages on V3 surfaces | PARTIAL | optimistic like/save without controller rebuild proven in coordinator test; comments/messages pending |
| 13 | Maslaki visual identity | PARTIAL | navy/gold accents, verified badge, local-context badge, neutral placeholder applied in built screens |
| 14 | Golden matrix | PARTIAL | deterministic structural regression tests in place (no-AppBar, no-Card, no-ClipOval, vertical pager, per-group progress); pixel goldens pending |
| 15 | Real device acceptance (21-step video/screenshot evidence) | NOT_TESTED | no device |
| 16 | Delete old UI after cutover | NOT_STARTED | old widgets still the active route |
| 17 | Documentation | PARTIAL | this file + `FAILURE_BASELINE` + `MEDIA_CONTRACT`; remaining docs pending |

## Root causes

* **Broken poster / circular empty media:** the gallery branch of
  `resolveSocialPostPosterUrl()` returned a video `playbackUrl` (HLS `.m3u8`) as
  a poster without the `!isSocialVideoPost` guard the asset branch has; the
  manifest was then handed to `CachedAppImage`. Fixed structurally by the V3
  media contract. See `SOCIAL_V3_FAILURE_BASELINE.md`.
* **Small Reel-to-Story card:** shared reels were rendered as a fixed-width
  attachment card. V3 models the shared reel as the story *base media*
  (`StoryV3Item` fills the 9:16 canvas). Composer-side enforcement is pending.

## Not yet done / blocked

* Direct Cloudflare Stream **tus** upload proof, Stream webhook proof,
  publish-to-visible timing — **BLOCKED** on backend one-time-upload
  provisioning work (not yet written).
* Route cutover + deletion of old widgets — **not started**; the old Reel/Story
  UI is still the active route until the V3 connectors and navigation swap land.
* All on-device evidence — **NOT_TESTED**.

## Route cutover phase (update)

**Primary acceptance — "Does every live Reel and Story entry point now open
V3?" → PASS** (proven by `test/features/social_v3/cutover_routes_test.dart`).

| Item | Status | Evidence |
|------|--------|----------|
| Reels tab → V3 | PASS | `SocialReelsScreen.build` returns `SocialReelsV3Connector` |
| Feed/explore/profile/search reel taps → V3 | PASS | `openSocialReelsV3` in `social_content_navigation.dart` |
| Shared reel (chat/entity) → V3 | PASS | `openSocialSharedEntity` → `openSocialReelsV3` |
| Notification reel → V3 | PASS | shell Reels tab is the V3 connector |
| All story entries → V3 | PASS | `showSocialStoryQuickViewer` delegates to `openSocialStoryViewerV3` |
| Notification story → V3 | PASS | loader resolves group then delegates to V3 |
| Old `SocialReelViewerScreen` reachable? | PASS (no) | only a doc-comment references it |
| Feed reel preview V3 | PARTIAL | `SocialFeedReelPreviewV3` + regression test landed; wiring into every `SocialPostCardV2` tile is a follow-up |
| QA build badge | PASS | `QaBuildBadge` (`--dart-define=SHOW_QA_BADGE=true`) |
| Route map before/after docs | PASS | `SOCIAL_V3_ROUTE_MAP_BEFORE/AFTER.md` |
| Visual comparison doc | PASS | `SOCIAL_V3_VISUAL_COMPARISON.md` |

Route/module tests after cutover: **34 passing** in `test/features/social_v3/`.

## APK handoff (verification build)

| Field | Value |
|------|-------|
| Git SHA | `cbd42c4606c28f8c50ced372b73fcbdb3576c89a` |
| Branch | `closure/full-application-closure` |
| Working tree | dirty (V3 changes uncommitted at build time) |
| Build type | **debug-signed** (release keystore env vars not present here → release build BLOCKED on signing) |
| APK artifact | `build/app/outputs/flutter-apk/Maslaki-user-social-v3-cbd42c46-debug.apk` |
| APK SHA-256 | `3a3c1ed3734b9aabb4b30fff4a0d17bcb699ef642e79c0d71b90777156173448` |
| applicationId | `com.maslaki.user` |
| versionName / versionCode | `1.0.1` / `9` |
| Backend base URL | `https://bestoffer-production.up.railway.app` |
| dart-defines | `GIT_SHA`, `GIT_BRANCH`, `BUILD_TIMESTAMP`, `APP_FLAVOR=user`, `APP_APPLICATION_ID=com.maslaki.user`, `BACKEND_BASE_URL`, `SHOW_QA_BADGE=true` |

### Device installation — BLOCKED (no `adb` on the build machine)

Run on a machine with `adb` + a connected device:

```bash
adb uninstall com.maslaki.user
adb install "build/app/outputs/flutter-apk/Maslaki-user-social-v3-cbd42c46-debug.apk"
adb shell pm clear com.maslaki.user
```

Then confirm the `[buildinfo] sha=cbd42c4606c2 ...` logcat line and the QA badge,
and capture the §15 evidence. For a store-signed release APK, re-run the build
with the release keystore env vars (`ANDROID_KEYSTORE_PATH`, `ANDROID_KEY_ALIAS`,
etc.) per `ANDROID_RELEASE_SIGNING_GUIDE.md`.

## Full-sequence phase (composers → upload → share → legacy)

| Area (§) | Status | Evidence |
|----------|--------|----------|
| Reel Composer V3 UI (§1) | PASS (widget) | `reel_composer_v3.dart` (editor + upload/processing/published states) |
| Native gallery pickers (§2) | PASS (logic) | `social_media_picker_v3.dart`; `social_media_picker_test.dart` (type inference); uses pinned Android Photo Picker; no `withData` for video |
| tus resumable client (§5) | PASS | `tus_upload_client.dart`; `tus_upload_client_test.dart` — 11 cases (normal, 10%/80% interruption, offset mismatch, expired URL, cancel, retry, retry-exhaustion, restart recovery, duplicate completion, progress) |
| Production tus transport (§5) | PARTIAL | `dio_tus_transport.dart` (tus 1.0 HEAD/PATCH, chunked from disk) — code-complete, needs a live endpoint |
| Backend upload session (§3) | PASS (existing) | `createSocialMediaStreamUploadSession` reused (proven) |
| Cancel session (§3) | PASS | added `cancelSocialMediaStreamUploadSession` + `POST …/upload-session/:id/cancel` |
| Stream webhook (§6) | PASS (logic) | `handleCloudflareStreamWebhook` (signed, idempotent) reused; `feed.stream-media.test.js` proves status mapping + uid extraction + duplicate-ready idempotency |
| Reconciliation worker (§7) | PASS (existing) | `startSocialStreamReconciliationWorker` reused (proven) |
| Publish lifecycle (§8) | PASS (logic) | `reel_composer_state.dart` + `reel_upload_api_impl.dart`; `reel_composer_controller_test.dart` (published, failed-not-published, idempotency, stage order); backend `resolveSocialMediaAssetForPublishing` READY-gate reused |
| Unified Share Sheet V3 (§9) | PASS | `share_sheet_v3.dart` + `canonical_links.dart`; `share_sheet_v3_test.dart` proves canonical-URL-only (no HLS/R2/upload/api leak) |
| Comments/messages on V3 (§10) | PARTIAL | reels wired to existing comments/share/like/save via `SocialReelsV3Connector` (no controller rebuild); dedicated messaging-reference UI pending |
| Legacy deletion (§11) | PARTIAL | deleted `SocialReelViewerScreen` + `SocialReelCard`; others quarantined-unreachable — see `SOCIAL_V3_LEGACY_REMOVAL.md` |
| Live Cloudflare upload / webhook delivery | BLOCKED | needs Cloudflare account creds + deployed backend |
| publish-to-visible ≤5s (§8) | BLOCKED | needs deployed backend runtime |
| Device/iOS evidence (§15) | BLOCKED | no `adb`/device/macOS here |

### Test-category summary (what each proves)

- **media contract** (12): an HLS/MP4 URL can never reach an image widget; poster/playback ordering; processing-status semantics.
- **reels regression** (6): no AppBar, no Card, no `ClipOval`, vertical pager, cover fit, RTL — the §18 hard rules.
- **reels coordinator** (7): single-playing, {prev,active,next} window, dispose-on-advance, mute preserved, lifecycle pause, no-recreate-on-like.
- **story regression** (5): full-screen (not bottom sheet), per-group progress segments, image auto-advance/no-loop, RTL.
- **cutover routes** (4): Reels tab → V3 connector, story entry → V3 (not bottom sheet), feed preview rectangular/bounded.
- **story composer** (6): shared reel is base media (no width-278 card), full-screen, blurred backdrop for horizontal, deleted-not-public, publish callback.
- **tus client** (11) / **composer controller** (4) / **pickers** (3): the upload/publish pipeline.
- **share sheet** (5): canonical-only, no internal-URL leak.
- **backend stream-media** (6): provider→internal status mapping, duplicate-ready idempotency, uid/playback extraction.

Flutter `social_v3` suite: **63 passing**. Backend `feed.stream-media`: **6 passing**.

## QA APK (§13 — full-sequence build)

| Field | Value |
|------|-------|
| Artifact | `build/app/outputs/flutter-apk/Maslaki-user-social-v3-cbd42c46-qa.apk` |
| SHA-256 | `ba6d3e9558169fb4ac6079e7aa8ca6d694efd0dcbd1b015d70e327d148f75681` |
| Git SHA / branch | `cbd42c4606c28f8c50ced372b73fcbdb3576c89a` / `closure/full-application-closure` |
| Build timestamp | see `BUILD_TIMESTAMP` define at build (UTC) |
| Backend URL / release SHA | `https://bestoffer-production.up.railway.app` / (pass `BACKEND_RELEASE_SHA`) |
| Flavor / appId | `user` / `com.maslaki.user` |
| versionName / versionCode | `1.0.1` / `9` |
| QA badge | enabled (`SHOW_QA_BADGE=true`) |
| Build type | debug-signed (QA) — **not** a release artifact |

This is distinct from the earlier route-cutover intermediate
`Maslaki-user-social-v3-cbd42c46-debug.apk` (SHA-256
`3a3c1ed3…`); the cbd42c46 debug artifact is **not** overwritten.

### Signed release command (run where the keystore exists)

```bash
flutter build apk --release --flavor user -t lib/main.dart \
  --dart-define=GIT_SHA=$(git rev-parse HEAD) \
  --dart-define=GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD) \
  --dart-define=BUILD_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --dart-define=BUILD_FLUTTER_VERSION="$(flutter --version | head -1)" \
  --dart-define=APP_FLAVOR=user \
  --dart-define=APP_APPLICATION_ID=com.maslaki.user \
  --dart-define=BACKEND_BASE_URL=https://bestoffer-production.up.railway.app \
  --dart-define=BACKEND_RELEASE_SHA=<railway release sha>
```

**Missing signing variables (BLOCKED here)** — required by
`android/app/build.gradle.kts` release `signingConfig`:
`ANDROID_KEYSTORE_PATH` (storeFile), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Without them only the debug-signed
QA APK can be produced.

## Final closure phase (commit → live wiring → clean rebuild)

### Source committed & pushed

| | |
|---|---|
| Final frontend source SHA | `e335c78687bda8667ea10ba1bb3eab67509d8e69` |
| Prior integration SHA | `b68fce8975024279378c92c42ba45131fb97ea8e` |
| Branch | `closure/full-application-closure` (pushed to `origin`) |
| Working tree after commit | clean except deliberately-excluded local/generated: `backend/.env.test`, `third_party/**/*.cxx/*.bin`, `backend/tmp/` |
| Secret scan | PASS — no secret values staged (only variable **names** appear, in docs) |

The stale-SHA problem is resolved: all Reel Composer / tus / picker / Share
Sheet / backend / test / docs work is now committed at `e335c78`, and the final
QA APK is built from that SHA.

### Live composer/share wiring (§2/§3) — now PASS

Previously the V3 composers existed but no live button opened them. Now:

| Live action | Opens | Proof |
|-------------|-------|-------|
| Reels tab create icon | native video picker → `ReelComposerV3` | `composer_wiring_test.dart` (create control fires), `ReelGalleryEntryV3` |
| Reel share button | `ShareSheetV3` | `SocialReelsV3Connector._share` |
| Share → Add to Story | `StoryComposerV3` (`SharedReelSource`) | `composer_wiring_test.dart` (Add-to-Story fires) |
| Create-reel pipeline | production `ReelComposerController` + `ReelUploadApiImpl` + `DioTusTransport` (no fakes) | `reel_publish_integration_test.dart` — picker→controller→real API over fake Dio→tus→poll→publish |

**Remaining PARTIAL wiring:** the legacy feed/profile "create post" sheet
(`showSocialCreatePostSheet`) and the old story-entry sheet
(`SocialStoryComposerScreen`) still open the old composers — documented in
`SOCIAL_V3_LEGACY_REMOVAL.md`; the primary Reels-tab create + reel-share paths
are on V3.

### Backend route/config verification (§4/§5)

- Route registration: PASS — `feed.media-routes.test.js` proves
  `POST /media/stream/upload-session`, `…/:assetId/cancel`, `GET /media/assets/:assetId`,
  `POST /media/stream/webhook`, and `POST /reels` are registered on `feedRouter`
  (not merely helpers).
- Config validator: PASS — `feed.stream-config.test.js` (presence-only, no value
  leak). See `SOCIAL_V3_CLOUDFLARE_SETUP.md`.
- Full backend `npm test` / migration-integration matrix (idempotency, ownership,
  oversize, expired, publish-before/after READY, duplicate webhook): BLOCKED on a
  provisioned test DB in this environment; targeted logic + route-registration
  tests pass.

### Deploy/runtime (§6), real Stream upload matrix (§7), device (§9), signed release (§10)

**BLOCKED** — no Railway deploy access, no Cloudflare credentials, no `adb`/device,
no macOS/keystore. Code, config validation, mocked tests, and procedures are
complete; runtime/device evidence must be produced where those are available.

### Final QA APK (§8/§13) — clean rebuild from the new SHA

Built after `flutter clean` + `flutter pub get` + `flutter analyze lib` (clean) +
the 66-test Flutter suite.

| Field | Value |
|------|-------|
| Artifact | `build/app/outputs/flutter-apk/Maslaki-user-social-v3-e335c786-qa.apk` |
| APK SHA-256 | `a1f9d14567edcb4c2d1f0ed0bb52acffbc8821462ef846cf728e4398ea835af9` |
| Git SHA | `e335c78687bda8667ea10ba1bb3eab67509d8e69` |
| Branch | `closure/full-application-closure` |
| Backend URL | `https://bestoffer-production.up.railway.app` |
| Backend release SHA | pass `BACKEND_RELEASE_SHA` at build (not deployed from here) |
| Flavor / appId | `user` / `com.maslaki.user` |
| versionName / versionCode | `1.0.1` / `9` |
| Build mode | debug (QA) |
| QA badge | enabled via `SHOW_QA_BADGE=true` (also passed `QA_BUILD=true`) |
| Signing cert | Android debug keystore (release keystore BLOCKED — see below) |

This **supersedes** the earlier `cbd42c46` artifacts; the diagnostics screen and
QA badge now report SHA `e335c786`, matching the committed source. The earlier
`cbd42c46` APKs are intermediate and must not be used as final evidence.

### Signed release (§10) — BLOCKED

Missing keystore env vars (from `android/app/build.gradle.kts` release
`signingConfig`): `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. With them:
`flutter build apk --release --flavor user …` →
`Maslaki-user-social-v3-e335c786-release.apk`, and
`flutter build appbundle --release --flavor user …` →
`Maslaki-user-social-v3-e335c786-release.aab`. Release builds pass **no** QA
defines, so the badge is absent in production.

## Final live-cutover cleanup (create entries) — now PASS

Every **generic** live create action opens V3:

| Live entry | Opens | Proof |
|-----------|-------|-------|
| Feed create (post/story) | `SocialCreateSelectorV3` → Post/Story/Reel | `showSocialCreatePostSheet` delegates |
| Create Reel | native video picker → `ReelComposerV3` | `live_create_routes_test.dart` |
| Create Story | native picker → `StoryComposerV3` | `live_create_routes_test.dart` |
| Create Post | native multi-pick → `PostComposerV3` | `live_create_routes_test.dart` |
| Reel → Add to Story | `StoryComposerV3` (`SharedReelSource`) | `live_create_routes_test.dart` |
| Full-screen Reels route | no floating Create button | `live_create_routes_test.dart` (`floatingActionButton == null`) |

Deleted: old create-post sheet UI, `social_post_composer_screen.dart`. Active
old create-route counts are **0** (see `SOCIAL_V3_LEGACY_REMOVAL.md`), except two
documented non-generic gaps: `ScopedCommunityStorySheet` (audience-scoped) and
merchant-review creation.

Flutter `social_v3` suite: **72 passing**. Backend: **11 passing**.

### Final QA APK — from the newest SHA `d083d875`

| Field | Value |
|------|-------|
| Artifact | `build/app/outputs/flutter-apk/Maslaki-user-social-v3-d083d875-qa.apk` |
| APK SHA-256 | `1105558ac0151780721d8e146f4bd23fe69c126b4143c7a0c8428a398295e7d5` |
| Git SHA | `d083d8758f0deeaa2fcd505432316882700ada6b` |
| Branch | `closure/full-application-closure` |
| Flavor / appId | `user` / `com.maslaki.user` |
| versionName / versionCode | `1.0.1` / `9` |
| Build mode | debug (QA), QA badge + diagnostics show `d083d875` |

Built after `flutter clean` + `pub get` + `flutter analyze lib` (clean) + the
72-test suite. **Supersedes** `e335c786` and `cbd42c46`. The QA source tag
`social-v3-qa-e335c786` remains the tagged prior QA point; this newer APK is
built from `d083d87` per the "new source → new SHA" rule.

## Specialized-flow closure (scoped story + merchant review)

| Item (§) | Status | Evidence |
|----------|--------|----------|
| Scoped community Story → V3 **UI** (§2) | PASS | `openStoryComposerV3Scoped`; community `_openCreateStorySheet` rewired; `ScopedCommunityStorySheet` deleted; `live_create_routes_test.dart` + `story_composer_v3_test.dart` |
| Story-level scope **persistence/enforcement** (§2/§3) | **NOT_IMPLEMENTED (backend gap)** | `validateCreateStory` + story service ignore scope; only `social_post` has `audience_scope`. Old & new paths both publish global stories. Flutter forwards scope (forward-compatible). Follow-up spec in `SOCIAL_V3_TEST_MATRIX.md` §3. Earlier "fixes a bug" claim retracted |
| Post scope validation (never trust Flutter) | PASS | `feed.scope-review-validation.test.js` — forged/relationship/malformed scopes rejected, `block A`/`building A101` accepted |
| Composer scope-value safety | PASS | fixed a defect: the generic composer previously cycled to `followers`/`close_friends`, which the backend rejects; now only backend-valid scopes are emitted |
| Merchant review → V3 (§3) | PASS | `PostComposerV3(mode: merchantReview)` + `openPostComposerV3Review`; rating required; `live_create_routes_test.dart` |
| Old Story composer screen removed (§4) | PASS | `social_story_composer_screen.dart` deleted; `SocialStoryComposerMode` already in `social_core` domain |
| Legacy counts all 0 (§5) | PASS | see `SOCIAL_V3_LEGACY_REMOVAL.md` |
| Stream config classifier + startup log (§6) | PASS | `classifyStreamConfig` (PRESENT/MISSING/INVALID_FORMAT) + `logStreamConfigStartup`; `feed.stream-config.test.js` |
| Backend scope permission enforcement | PARTIAL | backend re-validates scope via existing validators; a dedicated per-scope authorization test matrix (unauthorized building / expired-role / revoked-role) needs a provisioned DB → BLOCKED here |
| Real Stream smoke + size matrix (§8) | BLOCKED | Cloudflare creds + deployed backend |
| Deploy/runtime (§7), device QA (§9), signed release (§10) | BLOCKED | no Railway/creds/device/keystore |

Flutter `social_v3` suite: **75 passing**. Backend: **13 passing** (media 6, config 6, routes 1).

### Final QA APK — newest SHA `a35e8b67`

| Field | Value |
|------|-------|
| Artifact | `build/app/outputs/flutter-apk/Maslaki-user-social-v3-a35e8b67-qa.apk` |
| APK SHA-256 | `5ca4b7bd5dd296bd1b51fa163f789adfea403e7fb398f378cb75037c7c4e6fe2` |
| Git SHA | `a35e8b676a670753ef65ec96615906833bf501e6` |
| QA tag | `social-v3-qa-a35e8b67` (prior tags `d083d875`, `e335c786` preserved) |
| Flavor / appId / version | `user` / `com.maslaki.user` / `1.0.1+9` |
| QA badge + diagnostics | show `a35e8b67` |

Built after `flutter clean` + `pub get` + `flutter analyze lib` (clean) + 75-test
suite. **Supersedes** `d083d875`. Filename, QA badge, diagnostics, release report,
and Git tag all refer to `a35e8b67`.

## Production runtime closure (in-environment portion)

| Item (§) | Status | Evidence |
|----------|--------|----------|
| Source baseline (§1) | PASS | HEAD `e9a1a66`→ now `d1d7021`; a35e8b6 ancestor; tree clean |
| Migration review (§2) | PASS | non-destructive DB introspection: `social_media_asset` V3 cols + 3 indexes present, `social_post.audience_scope_type` present, legacy R2 preserved; migrations idempotent (`IF NOT EXISTS`) |
| Story-scope authz (§3) | PARTIAL / NOT_IMPLEMENTED | post-scope validation PASS (`feed.scope-review-validation.test.js`); **story-level scope not backend-implemented** — role matrix NOT_TESTED (no feature). See `SOCIAL_V3_TEST_MATRIX.md` §3 |
| Merchant-review authz (§4) | PARTIAL | validation PASS (merchant+rating required, 1–5); verified-purchase/order-ownership/one-per-merchant DB matrix NOT_TESTED (needs fixtures) |
| Railway env / Stream config (§5) | PARTIAL | validator run locally → `UNAVAILABLE (missing: CF_STREAM_*)` (correct; secrets absent); Railway set BLOCKED |
| Webhook (§6) / reconciliation (§7) | PASS (logic) / BLOCKED (runtime) | route-registration + signature/idempotency tests pass |
| Real upload smoke + matrix (§8/§9) | BLOCKED | Cloudflare creds + deployed backend |
| Publish-to-visible (§10) | PASS (gate logic) / BLOCKED (timing) | READY-gate + controller tests |
| Install QA APK (§11) | NOT_TESTED | no `adb`/device |
| Device / deep links / notifications / iOS (§12–15) | BLOCKED | no device/macOS |
| Signed release APK/AAB (§16) | BLOCKED | keystore env vars absent |

**Defect found & fixed during this closure:** the generic `StoryComposerV3`
scope toggle previously cycled to `followers`/`close_friends`, which the backend
rejects (`normalizeCommunityScope` accepts only global/block/compound/building);
now only backend-valid scopes are emitted. This is exactly the kind of defect
runtime/DB review is meant to catch.

### Final QA APK — newest SHA `d1d70214`

| Field | Value |
|------|-------|
| Artifact | `build/app/outputs/flutter-apk/Maslaki-user-social-v3-d1d70214-qa.apk` |
| APK SHA-256 | `3f76cd74e3e54f980435823b39616eabe591b8a54cfc1e73d271862bf6d885ea` |
| Git SHA | `d1d702145d11e51b1eb94c3290d5a062009d9311` |
| QA tag | `social-v3-qa-d1d70214` (prior tags preserved) |
| appId / version | `com.maslaki.user` / `1.0.1+9` · debug (QA) |

Built after `flutter clean` + `pub get` + `flutter analyze lib` (clean) + 75-test
suite. Supersedes `a35e8b67`. Filename, badge, diagnostics, report, tag all →
`d1d70214`. Backend tests: **20 passing**.

## Story-scope privacy remediation

| Item | Status | Evidence |
|------|--------|----------|
| Privacy defect (UI promised scoped visibility; backend published globally) | **CLOSED** | `StoryComposerV3` blocks non-global publish while `kStoryAudienceScopeSupported=false`; draft preserved; no silent global downgrade; `story_composer_v3.dart` + regression test |
| §2 Migration `135_social_story_audience_scope.sql` | PASS | applied to local DB, idempotent (2×); scope cols + CHECKs + index; existing stories default global; non-destructive |
| §3 `validateCreateStory` scope validation | PASS | normalizes global/block/compound/building; rejects relationship/forged/code-without-type; `isOfficial` request-only (`feed.scope-review-validation.test.js`) |
| §4–§10 service authz + read-enforcement + notifications + capability flip | NOT_STARTED (atomic, security-critical) | full spec + 30-case matrix in `SOCIAL_V3_STORY_SCOPE.md`. Flag stays `false` until complete — a partial backend would leak |
| Merchant-review DB business policy (§11) | NOT_STARTED | validation PASS; verified-purchase/order-ownership/one-per-merchant matrix pending |

**Why not a partial backend:** persisting story scope without enforcing it in
every story read query would store "scoped" stories that are visible to everyone
— worse than the current safely-blocked state. So the read-enforcement feature
must land atomically before scoped publishing is re-enabled.

### Git hygiene note
Commit `581655d` inadvertently included a local `backend/.env.test` change
(localhost test-DB **port** only — no secret; the dummy test JWT was pre-existing)
and `backend/tmp/*.mjs` scratch scripts. Corrected in `757db30`: `.env.test`
reverted, tmp untracked, `backend/tmp/` added to `.gitignore`.

### Final QA APK — newest SHA `757db305` (contains the privacy safety guard)

| Field | Value |
|------|-------|
| Artifact | `build/app/outputs/flutter-apk/Maslaki-user-social-v3-757db305-qa.apk` |
| APK SHA-256 | `85184cdb298397402ebf946b57cc5b64ca01940f4719d8983cc5af04900c66aa` |
| Git SHA | `757db30556e1068eac8978f043046142318d7ce8` |
| QA tag | `social-v3-qa-757db305` (prior tags preserved) |
| appId / version | `com.maslaki.user` / `1.0.1+9` · debug (QA) |

Supersedes `d1d70214`. Built after clean + analyze(clean) + 75-test suite.
Backend: 24 tests passing.

## Overall Social V3 status: **PARTIAL** (by design)

Per §11 completion language, Social V3 stays **PARTIAL** until direct upload is
runtime-verified, the device APK is installed, and Reel playback / sharing /
publish-to-visible / deep-links are visually verified on a device — all
currently **BLOCKED** on external credentials/deployment/hardware. All
in-environment implementation, migrations-reuse, tests, and docs are complete.

## Rollback plan

The `social_v3` module is additive and not yet wired into navigation, so the
current app behavior is unchanged. Rollback = do not perform the route cutover
(§16); delete `lib/features/social_v3/` and its tests. No database or media data
is touched by any of this work.
