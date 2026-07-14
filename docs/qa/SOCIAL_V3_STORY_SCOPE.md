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

## Done + verified

| Item | Status | Evidence |
|------|--------|----------|
| §1 Safety guard (no misleading scoped publish) | PASS | `story_composer_v3.dart` + regression test |
| §2 Migration `135_social_story_audience_scope.sql` | PASS | applied to local DB, idempotent (ran 2×); adds `audience_scope_type`/`audience_scope_code`/`is_official`, CHECK (global/block/compound/building), consistency CHECK, index `idx_social_story_scope_active`; existing stories default global; legacy media untouched |
| §3 `validateCreateStory` scope validation | PASS | normalizes global/block/compound/building; rejects followers/close_friends/area/custom/forged codes/code-without-type; records `isOfficialRequested` only (`feed.scope-review-validation.test.js`) |

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
