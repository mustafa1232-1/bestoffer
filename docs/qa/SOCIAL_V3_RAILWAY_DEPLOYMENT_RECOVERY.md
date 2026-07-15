# Social V3 Railway Deployment Recovery

Recovery started: 2026-07-15 (Asia/Baghdad)

## Incident statement

Railway deployment `2c426c89-3cb1-4242-8b83-533eb97116b8` was uploaded from an
uncommitted Social worktree. Railway reports the deployment as healthy, but its
metadata has no branch or commit SHA. It is therefore not an accepted,
reproducible release.

The deployed worktree was recovered at:

- branch: `feat/social-v3-interactions-reviews-closure`
- base SHA: `7a73125e4eb0253995dbe63535440f42af7a8823`
- worktree: `D:\new apps\storeapp\bestoffer-social-interactions-closure`

The initially supplied workspace path was a different worktree on
`closure/full-application-closure` at the same SHA. Its only tracked dirt was a
local `.env.test` edit plus generated `.cxx` artifacts. No source was changed
until both worktrees had been identified and the Social tree had been backed up.

## Frozen dirty-tree snapshot

The recoverable patch is outside every Git worktree:

- path: `D:\new apps\storeapp\social-v3-precommit-deployed-tree.patch`
- SHA-256: `DCC5718D2216FA7BEBE7935995C51DF9C34DFF0BDA9A40878B80C7949EC6CC75`
- contents: 14 tracked diffs plus the four untracked Social source/docs files

The 18 Social files represented by that patch were:

1. `backend/src/modules/feed/feed.repo.js`
2. `backend/src/modules/feed/feed.service.js`
3. `backend/src/modules/feed/feed.validators.js`
4. `backend/src/tests/feed.phase3b.test.js`
5. `lib/features/social/ui/social_chat_thread_screen.dart`
6. `lib/features/social/ui/social_content_navigation.dart`
7. `lib/features/social/ui/social_share_sheet.dart`
8. `lib/features/social/ui/social_story_quick_viewer.dart`
9. `lib/features/social/ui/widgets/social_community_content_widgets.dart`
10. `lib/features/social_v3/capabilities/social_capabilities_controller.dart`
11. `packages/social_core/lib/src/models/social_models.dart`
12. `test/features/social_v3/share_sheet_v3_test.dart`
13. `test/features/social_v3/social_capabilities_test.dart`
14. `test/social/social_story_document_test.dart`
15. `backend/sql/136_social_story_interaction_settings.sql`
16. `backend/src/tests/feed.story-interactions.test.js`
17. `docs/qa/SOCIAL_V3_MERCHANT_REVIEW_POLICY.md`
18. `docs/qa/SOCIAL_V3_POST_7A73125_VERIFICATION.md`

`git status --short` also showed `.tmp/` local PostgreSQL data and generated
Linux/macOS/Windows Flutter plugin registrants. They are local test/generated
artifacts, were not included in the Social patch, and must not be committed.

The initially supplied worktree's unrelated dirt was separately preserved at
`D:\new apps\storeapp\social-v3-primary-cwd-snapshot.patch` with SHA-256
`19E535B3B476118FACBBFDCFC07351A31D9E6D1A85D706932D18A43CA85D1002`.

## Railway identity and non-reproducible deployment

- project: `amiable-unity`
- project ID: `c7fc8214-3833-44db-b110-9600931dba72`
- environment: `production`
- environment ID: `fafa1412-4902-43f0-8faf-d89995602178`
- service: `bestoffer`
- service ID: `a6e3d13c-0e6d-4437-acc4-c315a15b1cc8`
- deployment ID: `2c426c89-3cb1-4242-8b83-533eb97116b8`
- deployment created: `2026-07-15T10:33:07.314Z`
- canonical domain: `https://bestoffer-production.up.railway.app`
- Railway metadata image digest:
  `sha256:241f959766c00951e73206056708e7a97946f2e1c5d8c2fba498ece957c2c625`
- uploaded build snapshot digest:
  `sha256:f6a0134e1dd540fe31b2467d7c70059e0454a6e0ad83a775d336a462565864b5`
- branch metadata: absent
- commit SHA metadata: absent

The incident record identifies the upload as a direct dirty-tree deployment.
Railway metadata confirms `reason=deploy`, `/backend` as the root directory,
`backend/Dockerfile` as the build definition, and no Git SHA. The exact flags
used with the original manual upload command were not preserved and are not
invented here.

Build/runtime commands visible in Railway and repository evidence were:

- manual dirty-tree upload: `railway up` (exact original flags unavailable)
- image dependency step: `npm ci --omit=dev --no-audit --no-fund`
- container entry point: `npm start`
- resolved backend entry point: `node src/start.js`

No further `railway up` was run during the evidence and migration-recovery
phase.

## Health evidence

At `2026-07-15T11:02Z`:

- `GET /health` returned `200`
- `GET /ready` returned `200`

These results prove only process/dependency readiness. They do not establish a
reproducible Git source or the Social interaction contract.

## Production migration evidence

Inspection used a PostgreSQL `READ ONLY` transaction. The migration ledger is
exactly `public.schema_migration`, with:

- `id BIGINT PRIMARY KEY`
- `name TEXT NOT NULL UNIQUE`
- `applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

The ledger contains:

```text
136_social_story_interaction_settings.sql | 2026-07-15T10:34:10.376Z
```

It does not contain `136_delivery_grouped_job.sql`. Railway startup logs
independently report that the Social 136 migration was applied. Migration
history was not edited or deleted.

The production `public.social_story` table contains these exact fields, all
`BOOLEAN NOT NULL DEFAULT TRUE`:

- `allow_likes`
- `allow_private_replies`
- `allow_comments`
- `allow_sharing`
- `allow_reshare`

Production does not contain any of the delivery-branch tables:

- `delivery_job`
- `delivery_pickup_stop`
- `notification_outbox`

This resolves the initial migration uncertainty: old Social 136 did run;
delivery 136 did not run.

## Collision resolution

The uncommitted source file `136_social_story_interaction_settings.sql` was
replaced with `140_social_story_interaction_settings.sql`. Migration 140:

- performs the complete change on a pre-feature schema;
- backfills only rows with a null interaction field;
- preserves explicit `FALSE` values;
- reconciles defaults and nullability when old Social 136 already ran;
- is safe to execute twice;
- does not remove or rewrite the production ledger row for old Social 136.

Local PostgreSQL integration tests cover pre-feature, old-136-applied, and
twice-executed schemas. The first recovery run passed 3/3 with zero failures or
skips.

## Local verification

The current recovery branch now passes the local release gates against the QA
database and local app server:

- `npm test` — 328/328 passing
- `npm run verify:release:local` — green
- `npm run permissions:check` — green after restoring a valid local QA matrix
  and session-bound login headers
- `backend/src/tests/feed.story-interaction-migration.pg.test.js` — 3/3 passing

The permissions checker needed a minimal local matrix file plus the live device
headers because the auth sessions are bound to client identity in this branch.
That is a local verification concern only; it does not change the product
contract.

## Production smoke

The authenticated production smoke reached the story and native-DM assertions
and then failed on reel creation with `STREAM_NOT_CONFIGURED` from the live
service. The failure is real: the deployed environment is missing the Cloudflare
Stream configuration required to exercise the reel upload path. The smoke
harness remains in the repo so the missing runtime config is visible rather than
being silently skipped.
