# Maslaki Night Responsiveness

Date: 2026-10-08. Scope: Mafia game only. No version bump, Android artifact,
production migration, Railway deployment, or production game data changes.

## Root Causes And Changes

- Snapshot GET performed phase transitions, row locks, presence writes and
  multiple serial reads. `mafia.snapshot.js` now reads one consistent MVCC
  snapshot without mutation. Private roles, events and chat remain filtered.
- Commands previously waited for realtime publication and sequential LiveKit
  calls. Migration 231 atomically records coalesced notification/voice work.
  `mafia.worker.js` runs independent deadline, notification and voice loops.
  Failed delivery remains pending; revision-aware leases retain newer work.
- Voice has its own revision: chat bursts do not repeatedly update audio grants.
  Recipients are notified concurrently; one slow recipient cannot delay all
  other seats. Voice updates are bounded to four participants concurrently,
  revoke before granting, and stop when superseded by a newer voice revision.
- Signing voice access no longer makes external create-room calls. LiveKit
  creates the room on join. Refresh schedules reconciliation for already joined
  clients; the Flutter controller reconciles again after connection.
- Flutter preserves microphone intent through silent phases, serializes capture
  changes, coalesces refresh requests and rejects connections after disposal.
  Main/afterlife publishing is exclusive. Muted participants stay muted when
  their audio track arrives later. A denied microphone does not kill listening.
- Command receipts make retries idempotent. A reused command with different
  content is rejected; optional phaseVersion prevents stale-phase actions.
  Clients already installed can omit the new optional fields.
- Chat has optional clientMessageId deduplication and returns its saved message.
  The open sheet receives live snapshots, keeps failed drafts, separates private
  channel drafts, and uses readable RTL messages with newest messages at bottom.
- A command's returned snapshot is used directly. Realtime hints received while
  a read is in flight queue one follow-up. Older revisions cannot overwrite a
  confirmed choice. Background heartbeat/read requests are suppressed and
  heartbeat calls do not overlap. Polling remains a 15-second fallback.
- The countdown uses elapsed time and a genuine progress ring; accepted choices
  have a server-backed receipt. Existing arena, role reveal, gifts, reactions,
  narrator and phase-transition animations remain in place.

## Rules

- New rooms created from the UI default to quick pace. Classic remains available;
  existing rooms and legacy quick timings are unchanged.
- New quick timings: reveal 15s, introductory night 8s, later night 30s,
  discussion 90s, nomination 20s, defense 30s, vote 20s, revote 15s.
- Reveal may finish after all living players acknowledge, with a minimum 4s.
- Random role assignment and the existing 7-14 player balanced decks remain.
- A unique highest vote eliminates the candidate, even without an absolute
  majority. Ties get one revote; another tie eliminates nobody.
- Voting stays open for its full deadline so players can change their decision.
  Votes/role actions from departed players do not count.
- Eliminated players can listen and speak in afterlife, not to living players.
  The existing rule allowing them to hear the main room at night is preserved.
  After completion everyone uses the main room; secondary publishing stops.
- Private text cannot bypass backend rules through LiveKit data messages.

## Measured Evidence

Same opt-in local benchmark, 10 samples, an artificial 8ms delay for each database
round trip. Windows timer resolution affects the absolute values. These are
not production latencies and do not measure voice/audio quality.

| Operation | Before queries | After queries | Before p95 | After p95 |
| --- | ---: | ---: | ---: | ---: |
| Snapshot | 12 | 1 | 187.83ms | 16.21ms |
| Send message | 4 | 1 | 63.75ms | 16.05ms |

Raw data: `mafia-latency-before.json`, `mafia-latency-after.json`.
Harness: `backend/src/qa/mafia-latency.test.js`.

## Verification

- Full Flutter suite: 876 passed, one opt-in LiveKit integration test skipped.
  After the final UI/concurrency edits, all 18 Mafia widget/controller tests pass.
- Full backend suite: 724 passed, 10 failed, one opt-in benchmark skipped.
  The 10 failures reproduce the pre-existing delivery fixture/outbox failures:
  nine `MERCHANT_PAYMENT_REQUIRED` paths and one `PUSH_FAILED` assertion. No
  delivery code was changed as part of this game task.
- Final targeted backend: all 26 Mafia rules, flow and responsiveness tests pass.
  Includes autonomous deadlines, read-only snapshots, deduplicated chat, private
  channels, stale actions, publish failures, concurrent newer revisions, slow
  voice isolation, bounded permission writes and post-connect reconciliation.
- Permission HTTP matrix: 45 passed, fixture account count restored afterward.
  `npm run flow:check` passed. Full `flutter analyze`: no issues.
- Browser harness uses the real Flutter room, authenticated HTTP routes and SSE
  delivery on loopback. Unique message bodies and HTTP 201 receipts prevent old
  history from falsely satisfying the test. See `mafia-browser.json` and
  `mafia-phone.png`, `mafia-chat.png`, `mafia-desktop.png`.
  Final unique incoming-message sample: 271ms from HTTP post to visible SSE
  update, on the local debug preview. This is one sample, not a production SLA.
- Existing production `/health` and `/ready` both returned HTTP 200. This only
  checks the currently deployed server; it does not deploy these improvements.

## Not Verified / Release Gate

- No live microphone media was transported in this environment: local LiveKit
  credentials are absent. Token/grant tests use a fake local signing secret and
  an invalid provider hostname; provider permission tests use a controlled fake.
- Physical Android/iPhone background recovery, Bluetooth/speaker routing, echo,
  audio under packet loss and microphone permissions still require device tests.
  No claim of 100% reliability, production latency or zero packet loss is made.
- Apply `231_mafia_delivery_and_receipts.sql` through the normal migration runner
  before deploying the new backend, and ensure `server.js` starts the Mafia worker.
  It has only been applied to the local `qa_template` used for isolated tests.
- Build/release the Flutter changes separately when authorized. No AAB/APK was
  produced and existing public users are not running these changes yet.

## Local Reproduction

Use the migrated local QA template and the existing per-file DB isolation hook.
Do not run the database-preparation pretest while a QA preview is open.

```powershell
cd backend
node --env-file=.env.test --import ./src/tests/setup/per-file-db.mjs --test src/tests/mafia.rules.test.js src/tests/mafia.flow.db.test.js src/tests/mafia.responsiveness.db.test.js
$env:MAFIA_BENCH='1'
$env:MAFIA_BENCH_LABEL='after'
node --env-file=.env.test --import ./src/tests/setup/per-file-db.mjs --test src/qa/mafia-latency.test.js
```

Preview: opt-in `MAFIA_PREVIEW=1` with `src/qa/mafia-preview.test.js`, backend
127.0.0.1:4880; Flutter entrypoint `test_driver/mafia_preview.dart`, port 4881.
It is an isolated test room, not a production login or real multiplayer server.

SDK references checked: LiveKit [participant permissions](https://docs.livekit.io/intro/basics/rooms-participants-tracks/participants/),
[tokens and grants](https://docs.livekit.io/frontends/reference/tokens-grants/),
and [publishing media](https://docs.livekit.io/transport/media/publish/).
