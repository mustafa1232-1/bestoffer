# Social V3 — Story Audience Scope

Tracks the authoritative building/block/compound story-scope feature.

## Current safety posture — SAFE

The original privacy defect (UI promised scoped visibility; backend published
globally) is **closed**: `StoryComposerV3` refuses to publish a non-global scope
while `kStoryAudienceScopeSupported = false` — the draft is preserved, no silent
global downgrade, and the user is told
"نشر القصص المخصصة للبناية غير متاح حالياً. تم حفظ المسودة." Global stories
publish normally. Regression test: `story_composer_v3_test.dart`
("SAFETY: building-scoped story is NOT published globally…").

**The capability flag must not be flipped to `true` until every item in
"Remaining" below is implemented and the DB matrix passes.** Enabling scoped
publishing while any read query does not enforce scope would leak "scoped"
stories to everyone — worse than the current blocked state.

## Status language (per the brief)

- **Flutter scoped-Story guard:** PASS
- **Backend fail-closed safety:** PASS
- **Configuration-misuse safety:** PASS
- **Full scoped-Story feature:** DISABLED / NOT IMPLEMENTED
- **Overall scoped-Story privacy:** SAFE WHILE FEATURE DISABLED

## Configuration-misuse safety (the env footgun)

Enabling scoped stories requires **two** conditions, ANDed:

```
effectiveEnabled = STORY_AUDIENCE_SCOPE_IMPLEMENTATION_READY (code const, false)
                   AND env.storyAudienceScopeEnabled
```

`STORY_AUDIENCE_SCOPE_IMPLEMENTATION_READY` is a **hardcoded code constant**, not
an env var, and stays `false` until the full feature ships. Therefore setting
`STORY_AUDIENCE_SCOPE_ENABLED=true` in Railway — accidentally or prematurely —
**cannot** enable scoped publishing or reopen the leak. One shared resolver,
`getStoryAudienceScopeFeatureState()`, is used by the service gate, the
capability endpoint, and startup diagnostics, so the state cannot drift between
surfaces. Startup logs `effectiveEnabled=false reason=IMPLEMENTATION_INCOMPLETE`
and warns if the env flag is set while not ready. Proven by
`feed.story-scope-gate.test.js` (env=true + not-ready → still rejected) and
`feed.capabilities.test.js` (capability returns effective state).

## Done + verified

| Item | Status | Evidence |
|------|--------|----------|
| §1 Flutter safety guard | PASS | `story_composer_v3.dart` + regression test |
| §1 **Backend fail-closed gate** | PASS | `assertStoryAudienceScopeAllowed` in `feed.service.js` rejects ANY non-global request (scope type/code/official, all key aliases + casing) **before any side-effect**, regardless of client or validator. `STORY_AUDIENCE_SCOPE_ENABLED=false`. `AppError STORY_AUDIENCE_SCOPE_NOT_AVAILABLE` (409) with ar/en messages |
| §2 Fail-closed tests (incl. real service + DB) | PASS | `feed.story-scope-gate.test.js`: global allowed; every non-global rejected with code/status; **DB-verified no `social_story` row created** for a rejected scoped request (through the real service); retry creates no story |
| §3 Authoritative capability endpoint | PASS | `GET /api/feed/capabilities` → `social.storyAudienceScope.supported=false, supportedTypes=[global]`; `feed.capabilities.test.js` |
| §4 Migration 135 runner-registered | PASS | matches the runner's numbered-SQL pattern; content asserted; auto-applied by `runSqlMigrations` |
| §9 Git history audit | PASS | commit `581655d` contained only local test config (localhost DB URL + dummy hex `JWT_SECRET`) + scratch scripts; secret-value scan empty → **no real secret**, no history rewrite required; `backend/tmp/` now gitignored |
| §2 Migration `135_social_story_audience_scope.sql` | PASS | applied to local DB, idempotent (ran 2×); adds `audience_scope_type`/`audience_scope_code`/`is_official`, CHECK (global/block/compound/building), consistency CHECK, index `idx_social_story_scope_active`; existing stories default global; legacy media untouched |
| §3 `validateCreateStory` scope validation | PASS | normalizes global/block/compound/building; rejects followers/close_friends/area/custom/forged codes/code-without-type; records `isOfficialRequested` only (`feed.scope-review-validation.test.js`) |

## Flutter capability UX integration — done (feature still disabled)

| Item | Status | Evidence |
|------|--------|----------|
| `SocialCapabilities` model (fail-closed) | PASS | `capabilities/social_capabilities.dart`; `supported=false` ignores advertised types → only `global`; missing/malformed → fail-closed |
| `SocialCapabilitiesApi` (fail-closed on error) | PASS | `capabilities/social_capabilities_api.dart`; any Dio error → `failClosed` |
| `socialCapabilitiesProvider` controller | PASS | short bounded cache (5 min TTL), `ensureFresh`/`refresh`, `markStoryScopeUnsupported` (reset after a 409); `social_capabilities_test.dart` (8 cases: parse, cache TTL, network-error→false, stale-true→reset) |
| Disabled scoped UX | PASS | community "create story" consults the capability via `ensureFresh` before acting; when unsupported → shows "القصص المخصصة للبناية ستتوفر قريباً" and opens a **global** story (never a locked/misleading scope); `live_create_routes_test.dart` (unsupported→global+notice; supported→locked scope) |

**§2 Endpoint access decision:** `GET /api/feed/capabilities` stays behind
`requireAuth` (deliberate). Scoped-story creation is post-login only; guests/
pre-login get the Flutter controller's fail-closed default (`supported=false`),
which is correct. No guest endpoint is needed; the response carries no secrets.

**Feature freeze (§4):** `STORY_AUDIENCE_SCOPE_IMPLEMENTATION_READY=false` and
`STORY_AUDIENCE_SCOPE_ENABLED=false` — unchanged. Capability integration does NOT
enable the feature; it only makes the disabled state a clean UX instead of a
publish-time failure.

## Remaining (must land atomically before flipping the flag)

| § | Item | Notes |
|---|------|-------|
| 4 | `authorizeStoryAudienceScope({userId, scopeType, scopeCode, isOfficial})` | Verify the user's registered Basmaya residence matches the requested block/compound/building (mirror the post-creation residence check). Official stories: verify an **active, non-expired, non-revoked** building role (BUILDING_ADMIN / DEPUTY_ADMIN / ANNOUNCEMENT_EDITOR) for the **same** building via the authoritative building-role tables — never from `app_user.role`, never from the client `isOfficial` flag. Fail creation atomically before insert. |
| 5 | Persist scope transactionally | `api.createStory`/`controller.createStory` already forward `audienceScopeType/Code`; wire the service to authorize → insert scope columns → return normalized scope. |
| 6 | Enforce scope in **every** story read | Apply the proven post pattern (`feed.repo.js:98-114`) to each story query: `social_story` reads at repo lines ~383, ~538, ~614, the two highlight joins (~674/759), archive (~869), and by-id (~944), plus notification target resolution and deep-link resolution. A story is visible iff `global`, or its scope matches the viewer's block/compound/building code. Owner always sees own; unauthorized viewers get 404/unavailable (no metadata leak). |
| 7 | Scope-aware notifications | Resolve only eligible recipients (same scope, exclude creator/blocked/opted-out, dedupe). Never fan out a building story app-wide. Official notifications include building code + role + official marker. |
| 8 | Flutter contract | Add `audienceScopeType/Code/isOfficial/officialPublisherRole/scopeLabel` to `SocialStory`; render from backend-returned values; flip `kStoryAudienceScopeSupported` (or wire to a backend `storyAudienceScopeSupported` capability) **only after** §4–§7 land. |
| 9 | DB matrix | 30 cases (creation authz, visibility, legacy) per the brief, against local Postgres with residence/role fixtures. |

## Enforcement pattern to mirror (from `social_post`)

```sql
AND (
  COALESCE(s.audience_scope_type, 'global') = 'global'
  OR (s.audience_scope_type = 'block'    AND $b::text IS NOT NULL AND s.audience_scope_code = $b)
  OR (s.audience_scope_type = 'compound' AND $c::text IS NOT NULL AND s.audience_scope_code = $c)
  OR (s.audience_scope_type = 'building' AND $g::text IS NOT NULL AND s.audience_scope_code = $g)
)
```
where `$b/$c/$g` are the viewer's normalized block/compound/building codes
(reuse the resolver the post feed already uses).

## Rollback
Migration 135 rollback: drop the two constraints, the index, and the three
columns. No story data loss beyond scope metadata (stories revert to global).
