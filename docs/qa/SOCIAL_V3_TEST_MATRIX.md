# Social V3 — Test Matrix

Statuses: **PASS · PARTIAL · FAIL · BLOCKED · NOT_TESTED**

Source SHA at time of writing: `a35e8b6` (+ this closure commit). Local Postgres
(`127.0.0.1`) reachable; no Railway/Cloudflare/device/keystore/macOS.

## §1 Source baseline — PASS
HEAD `e9a1a66` (docs), code `a35e8b6` is an ancestor, working tree clean except
excluded local/generated (`.env.test`, `third_party/**/.cxx`, `backend/tmp/`).

## §2 Migration review — PASS (introspected, non-destructive)
Social V3 migrations (execution order): `017_social_stories`, `018_social_story_style`,
`116c_social_post_audience_scope`, `121_social_post_media_gallery`,
`134_social_media_stream_asset`. All use `IF NOT EXISTS` / guarded
`ADD CONSTRAINT` → idempotent. Introspection of the local DB confirms:
`social_media_asset` has `provider, stream_uid, processing_status, playback_url,
thumbnail_url, poster_url` (all present), 3 indexes; `social_post.audience_scope_type`
present; legacy `provider='r2'` rows preserved (none in this DB). No destructive
statements touch legacy R2 rows.

## §3 Story scope authorization — see `SOCIAL_V3_STORY_SCOPE.md`
- **Safety guard:** PASS — scoped story publish is blocked (no misleading UI /
  no silent global downgrade); draft preserved. Regression test in
  `story_composer_v3_test.dart`.
- **Migration `135_social_story_audience_scope.sql`:** PASS — applied to local
  DB, idempotent; columns + CHECK constraints + index; existing stories default
  global.
- **`validateCreateStory` scope validation:** PASS — normalizes
  global/block/compound/building; rejects relationship/forged/code-without-type
  (`feed.scope-review-validation.test.js`).
- **Service authorization + read-query enforcement + notifications + capability
  flip:** NOT_STARTED (must land atomically before scoped publishing is enabled —
  a partial backend would leak). Full spec + 30-case matrix in
  `SOCIAL_V3_STORY_SCOPE.md`. The capability flag stays `false` (publish blocked)
  until then.
- **Post scope validation** (unchanged): PASS — forged/relationship/malformed
  scopes rejected, `block A`/`building A101` accepted.

## §4 Merchant review
- **Validation layer:** PASS — `validateCreatePost` requires `merchantId` +
  `reviewRating` (1–5) for `merchant_review`; out-of-range rating rejected
  (`feed.scope-review-validation.test.js`).
- **DB business policy** (verified purchase from a completed owned order,
  one-review-per-merchant, edit/delete, moderation): NOT_TESTED — needs order +
  review fixtures and the authoritative service/DB rules; not exercised here.

## §5 Railway env config — PARTIAL (validator PASS, config BLOCKED)
Config validator run against local env: `Social Stream configuration: UNAVAILABLE
(missing: CF_STREAM_ACCOUNT_ID, CF_STREAM_API_TOKEN, CF_STREAM_CUSTOMER_CODE,
CF_STREAM_PLAYBACK_BASE_URL, CF_STREAM_THUMBNAIL_BASE_URL, CF_STREAM_WEBHOOK_SECRET)`
— correct (production secrets absent locally; no secrets printed). Setting the
Railway values is BLOCKED (no access).

## §6 Cloudflare webhook — PARTIAL
Route registration PASS (`feed.media-routes.test.js`); signature/idempotency logic
PASS (`feed.stream-media.test.js`). Public reachability + real Cloudflare event
delivery BLOCKED.

## §7 Reconciliation — PASS (logic) / BLOCKED (runtime)
`startSocialStreamReconciliationWorker` + status mapping tested; live recovery
against Cloudflare BLOCKED.

## §8 Real direct tus upload smoke — BLOCKED
Needs Cloudflare creds + deployed backend. Client logic PASS
(`tus_upload_client_test.dart`, 11 cases incl. resume-from-server-offset).

## §9 Large-upload matrix (5–500 MB) — BLOCKED
Needs creds + device/network.

## §10 Publish-to-visible ≤5s — BLOCKED (runtime) / PASS (gate logic)
`resolveSocialMediaAssetForPublishing` READY-gate + composer controller tested;
production timing BLOCKED.

## §11 Install authoritative QA APK — NOT_TESTED
APK built + hashed; `adb`/device absent. Verify SHA-256 then install per
`SOCIAL_V3_DEVICE_EVIDENCE.md`.

## §12 Android device visual acceptance — BLOCKED (no device)
## §13 Deep links — BLOCKED (no device); canonical-link no-leak PASS (`share_sheet_v3_test.dart`)
## §14 Notifications — BLOCKED (no device)
## §15 iOS — BLOCKED (no macOS/iPhone)
## §16 Signed release APK/AAB — BLOCKED (keystore vars absent)

## Automated test totals (this environment)
Flutter `social_v3`: 75 · Backend: 20 (media 6, config 6, routes 1, scope/review 7).
`flutter analyze lib`: clean.
