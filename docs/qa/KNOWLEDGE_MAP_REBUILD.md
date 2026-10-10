# Knowledge Map: Performance and Correctness Audit

## Scope and Release Status

Repository: `D:\new apps\storeapp\bestoffer`. Branch: `feature/team-code-game`.
Starting HEAD: `27815ddb468641d97c10cb66d03ffc3ce69ffacd`.
There were hundreds of pre-existing changes, including untracked game modules. They were preserved.
This work changes Knowledge Map, its tests, worker startup, and an opt-in durable-publisher check in the existing realtime gateway. No commerce, delivery, taxi, account or billing logic was edited.

**Not deployed. No production migration, app version bump, APK or AAB.**
This is a coordinated backend/client protocol migration, not a backend-only hotfix for existing mobile binaries.

### File Map

| Area | Implementation |
| --- | --- |
| Durable admission and schema | [migration 229](../../backend/sql/229_knowledge_round_protocol.sql) |
| Read, admission, resolver and journal workers | [round service](../../backend/src/modules/games/knowledge-rounds.service.js) |
| Voting and existing game rules | [pure logic](../../backend/src/modules/games/knowledge-game.logic.js), [game service](../../backend/src/modules/games/knowledge.service.js) |
| Flutter recovery and lifecycle | [match controller](../../lib/features/games/state/knowledge_match_controller.dart) |
| Actual arena and waiting screen | [arena](../../lib/features/games/ui/knowledge_match_board.dart), [screens](../../lib/features/games/ui/knowledge_game_screen.dart) |
| Concurrency, privacy and crash tests | [DB tests](../../backend/src/tests/games.knowledge-rounds.db.test.js) |

## Proven Findings

- The old answer request locked the match for its entire transaction and executed 11 to 29 database calls. The last answer also calculated the result before responding.
- The old snapshot reader took the same match lock, and advanced expired questions on reads. It contended with answers, and a disconnected room could stop advancing.
- Old answers carried only option/district. A late retry could therefore answer whichever question was current when processed.
- Flutter fetched a full snapshot every two seconds, fetched again after submitting, and could display raw Dio errors.
- These were confirmed from the local code and benchmark. **The specific historical Dio exception was not recovered from production logs**, so this report does not invent its status code or blame its network.

## New Protocol

`POST /api/games/knowledge/matches/:matchId/answers` accepts `roundId`, `questionId`, `idempotencyKey`, `answerIndex`, `districtId`. Player identity comes from authenticated `req.userId`.

Migration `229_knowledge_round_protocol.sql` adds rounds, submissions and a transactional event journal. Acceptance is one database round trip using `maslaki_knowledge_accept_answer`. Its PostgreSQL statement commits before the receipt is returned. Replays return the original receipt; changed payloads conflict; different keys cannot create another vote for that player/round. `GET .../attempts/:key` and the own-answer snapshot recover lost responses.

Acceptance uses a **shared round-row gate**, with no match-counter update. Resolution takes an exclusive round gate, then reads all committed submissions. The match lock is `FOR NO KEY UPDATE` to remain compatible with foreign-key checks performed by admissions. This avoids a shared-to-exclusive upgrade deadlock. The worker materializes all scoring inputs and commits scoring, territories, result, match progression and outbox together. A crash rolls that transaction back; another worker retries. Multiple workers use PostgreSQL locks and `SKIP LOCKED`, not process memory, to coordinate.

The worker has separate resolution and publication loops. Slow external publication does not stall deadlines. Durable publication uses the existing user-topic gateway and shared retry outbox. The knowledge journal is only marked published when the gateway either published or durably queued the event. Failed journal entries remain retryable; duplicates are allowed and deduplicated by the client. Published journal retention is intentionally not automated in this change, preserving audit history; operational retention can be scheduled separately.

Reads are one consistent MVCC query without row locks. They include a state version, server time, round timestamps, own receipt and scoped chat. Correct answer and explanation are returned only after finalization. Broadcast events contain identifiers/versions, never answer options, keys, team messages or the solution.
Completed protocol-1 matches remain readable as historical results without inventing rounds; active protocol-1 matches still require the coordinated cutover.

## Timing and Rules

- Shared three-second countdown, then 30/20/15-second questions according to the existing difficulty configuration. Three seconds show the result before the next countdown.
- Server PostgreSQL time is authoritative. A request must acquire admission before the deadline; an earlier HTTP/client timestamp is not a grace entitlement.
- Scoring uses the database statement receipt timestamp, excluding subsequent row-gate wait for admitted requests. Network, HTTP scheduling and connection-pool wait before that statement are **not** removed from response time. Device timestamps are not trusted. There is no hidden latency grace.
- All seated members must submit, or the deadline must expire. Missing members do not cast a vote. Majority wins; tied option votes use the earliest submitted vote. Team speed is the latest non-timeout submission, matching prior behavior.
- **Existing contested-territory rule retained:** team A is processed first; team B can get the next eligible territory. A product question was raised about switching to fastest-team priority, but no answer authorized that rule change. This is a known fairness/product issue, not silently declared solved.
- Five normal questions. Existing tie-breaks compare correct rounds, average response, territory count, then overtime; the existing last-resort random tie-break remains.
- A new match does not repeat a question. No eligible territory is represented explicitly as `none`, accepted only when the server proves the frontier is empty.
- Rematch creates a fresh room with empty seats and fresh match state. It does not erase the previous result. Waiting players can explicitly free a seat; active players cannot invalidate the locked roster this way.

## Flutter Changes

- Real match screen, not a separate mockup: `knowledge_game_screen.dart` and `knowledge_match_board.dart`.
- Compact team/score/time header; question and answers first; actual server adjacency graph; clipped hit targets; team shield/flag in addition to color; stable target bounds; constrained wide layout; existing Maslaki logo.
- Isolated local clock, confirmed score/ownership transitions, answer selection animation and short result celebration. Reduced motion, effects and haptics are independently controlled. No automatically opened microphone.
- Folded team/public chat retains unanimous-consent enforcement and existing LiveKit controller.
- `KnowledgeMatchController` owns one realtime subscription, one in-flight snapshot, coalesced invalidation and bounded fallback. It rejects older snapshots/events, retains durable confirmation across a stale same-version read, and restores the round after resume.
- Immutable attempt with player-scoped local persistence; selected/submitting/confirmed/reconciling/closed/failed states; bounded retries; no different answer while outcome is uncertain. Arabic error categories replace raw Dio output. Existing shared session-refresh logic remains in place.

## Matched Measurements

Node v25.2.1, local PostgreSQL 18, same machine and connection-pool settings. Direct service calls include pool wait, SQL and commit, **not mobile RTT or rendering**. Each 1v1 and 4v4 case repeats ten times; burst is 25 rooms x8 players (200 answers). These are short controlled samples, not a sustained production-capacity claim.

| Case | Before p95 / p99 ms | After p95 / p99 ms | Errors |
| --- | ---: | ---: | --- |
| 1v1, 20 answers, local | 13.69 / 20.51 | 4.71 / 10.18 | 0 / 0 |
| 4v4, 80 answers, local | 121.42 / 203.68 | 78.88 / 170.86 | 0 / 0 |
| 25 x4v4, 200 answers, local | 286.65 / 300.62 | 99.44 / 143.66 | 0 / 0 |
| 1v1, +8ms per DB call | 447.49 / 561.62 | 23.97 / 25.21 | 0 / 0 |
| 4v4, +8ms per DB call | 1289.30 / 1420.10 | 81.45 / 101.33 | 0 / 0 |
| 25 x4v4, +8ms per DB call | 5866.35 / 6324.05 | 224.81 / 225.12 | 0 / 0 |

Acceptance calls: **11..29 -> 1**. The 200-player delayed-DB case missed the 150ms p95 target; pool wait p95 was 209.5ms. No pool-size or paid infrastructure change was made to conceal that limit.

The synthetic 8ms delay wraps each answer database call in both versions; it is not an actual cross-region network measurement. Baseline files: `knowledge-baseline-local.json`, `knowledge-baseline-delay8.json`. Matched after files: `knowledge-after-local.json`, `knowledge-after-delay8.json`. Later resolution measurements, if generated, are separate and must not replace these matched numbers without rerunning their baseline.

### Additional Measurements

`knowledge-measured-final.json` separately measures real round resolution, including SQL and commit: p95 **20.21ms (1v1)**, **28.39ms (4v4)** and **15.71ms per room (25 concurrent rooms, four resolver slots)**. These are first-round scoring samples, not tournament-final resolution or device-render latency. Acceptance used one call; resolution used at most 15 calls. The final run also records query plans and indexes: latest-round lookup uses the unique match/round index, replay lookup uses the unique user/idempotency index, and pending events use the partial pending index. Cardinalities are QA-sized, not a production query-plan guarantee.

Actual HTTP router, signed local QA accounts, PostgreSQL, 4v4, 40 answers per condition, receipt at most 232 bytes (`knowledge-http-latency.json`):

| Added round-trip delay | p50 | p95 | p99 | Errors |
| --- | ---: | ---: | ---: | ---: |
| 0ms | 19.91ms | 85.28ms | 89.66ms | 0/40 |
| 100ms | 120.51ms | 125.98ms | 135.48ms | 0/40 |
| 250ms | 279.31ms | 280.45ms | 280.47ms | 0/40 |

Half the synthetic delay is applied before sending, half after receipt. Jitter/loss are zero; this is not packet-level shaping or a cellular measurement. Connection warm-up is mixed into these small runs rather than a separately characterized cold-start benchmark.

## Verification and Limits

- Final whole Flutter suite: **861 passed, 1 skipped**, `knowledge-flutter-suite-final.log`. Game-only: **43 passed, 1 skipped**. Final `flutter analyze`: **No issues found**.
- Permissions matrix against local full application: 45 passed, 0 failures. `flow:check`: OK.
- Full backend run at concurrency 2: 699 passed, 10 failed, 1 skipped. Nine failures are delivery payment/evidence expectations (`MERCHANT_PAYMENT_REQUIRED` / `customer_order_merchant_payment_evidence_check`), and one is delivery outbox expected `PUSH_ACCEPTED` versus `PUSH_FAILED`. These are outside the changed game files and remain unresolved. **The complete backend suite is not green.**
- Initial unrestricted parallel backend run also had local timeout failures. Retrying with bounded concurrency removed those, but did not remove the ten genuine failing checks above. No tests were weakened to hide them.
- Final backend games + shared gateway run: **47 passed, 0 failed, 1 opt-in benchmark skipped**, `knowledge-backend-games-final.log`. Coverage includes concurrent eight-player votes, duplicate keys/payload conflict, lost reply restoration, shared/exclusive admission, two resolvers, crash rollback/recovery, private team chat and unanimous public consent, no-territory validation, early/late submission, complete 1v1/4v4, fresh rematch, historical protocol-1 results and waiting-seat release.
- Actual Flutter arena widget screenshots and size/text tests: 320x640 at 1.6 text scale, 360x800, 390x844 and 900x700, RTL, simulated keyboard insets, reduced motion. Golden: `test/features/games/goldens/knowledge-question.png`.
- Browser QA uses the actual Flutter match screen, real games HTTP router and isolated local PostgreSQL; a QA opponent and loopback-only signed test accounts. Screenshots `knowledge-web-phone.png` and `knowledge-web-confirmed.png` show the real flow. Voice-provider traffic is not part of this test. See `test_driver/knowledge_browser_check.cjs` for reproducibility.
- Browser check passed: exactly one HTTP 200 durable answer receipt, visible confirmation, expandable chat and working reduced-motion switch, with zero browser page errors. Evidence: [phone](knowledge-web-phone.png), [confirmation](knowledge-web-confirmed.png), [wide layout](knowledge-web-desktop.png), [settings](knowledge-web-settings.png), `knowledge-web-report.json`.
- No physical Android/iPhone profile test, radio Wi-Fi/cellular handover, real LiveKit microphone pair test, production realtime multi-instance transport test, or cold production deployment test was run. No 60fps or 100% voice claim is made.
- Existing voice access checks membership and unanimous consent before granting public-room access. This task did not add server-side revocation of already-issued LiveKit tokens; ordinary clients disconnect on consent withdrawal. Provider-level revocation against a modified client needs a separate privacy check before claiming immediate public-voice revocation.
- End-to-end result-commit-to-device-display target is not established by the direct-service benchmark. Browser fallback verification is not a substitute for production realtime latency measurement.

## Deployment and Rollback

1. Resolve the unrelated failing backend checks before declaring an app-wide release healthy. Review game rules, especially contested territories.
2. Prepare a coordinated client release with the explicit round contract. Set the existing application minimum-version/maintenance gate for the game and drain protocol-1 active matches before cutover. Do not hot-deploy this backend expecting published old binaries to keep playing.
3. Back up data, review/apply migration 229 through the existing migration runner, then deploy the backend and compatible Flutter/web together in authorized staging. The new schema default applies protocol 2 to new matches; pending matches are upgraded; historical active/completed matches are not silently rewritten.
4. Older answer requests missing identifiers get a clear HTTP 426 `GAME_UPDATE_REQUIRED`; they are never mapped to the latest question. Verify the application update gate and user-facing upgrade path before reopening rooms.
5. Validate worker startup in every app process, database headroom, accepted-answer timings, unpublished journal age, all 1v1/4v4 rounds, and real two-device voice. Then authorize production rollout separately.
6. Rollback: close new room creation, stop the new worker/application, preserve submissions/results/journal, and restore the previous compatible app pair. Do not drop the new tables or run a destructive down migration. Restore the match `protocol_version` default deliberately if resuming the old server; do not let old code progress an active protocol-2 match. Resume the protocol-2 worker to finish those matches or cancel through a reviewed administrative path.

## Reproduce Safely

Use `backend/.env.test` and the existing isolated per-file DB bootstrap. Never point these commands at production.

```powershell
cd backend
npm run pretest
node --env-file=.env.test --import ./src/tests/setup/per-file-db.mjs --test --test-force-exit --test-concurrency=2 "src/tests/games*.test.js" src/tests/realtime.gateway.test.js
$env:KNOWLEDGE_BENCHMARK='1'
$env:KNOWLEDGE_BENCHMARK_OUTPUT='../docs/qa/knowledge-measured-final.json'
node --env-file=.env.test --import ./src/tests/setup/per-file-db.mjs --test src/tests/games.knowledge-performance.db.test.js
```

For local web QA, enable `KNOWLEDGE_PREVIEW=1` and `AUTH_ALLOW_LEGACY_TOKENS=true` **only in the loopback test process**; run `src/qa/knowledge-preview.test.js` through the same per-file bootstrap. Then `flutter run -d web-server --web-hostname 127.0.0.1 --web-port 4879 -t test_driver/knowledge_preview.dart`. The production app never mounts `/fixture`. Do not publish this test entrypoint. The manual server is outside the automated test glob: running both previously attempted to recreate an in-use QA database (55006), not a gameplay failure.

Reference for the locking contract: [PostgreSQL row locks](https://www.postgresql.org/docs/current/explicit-locking.html). Hardware-performance caveat: [Flutter profile guidance](https://docs.flutter.dev/perf/ui-performance), [Flutter rendering practices](https://docs.flutter.dev/perf/best-practices).

## طريقة اللعب بعد التطوير

التحديث البصري اللاحق ونتائج فحصه موثقة في [KNOWLEDGE_THEME_UPDATE.md](KNOWLEDGE_THEME_UPDATE.md). لا يغير قواعد النقاط أو الاحتلال الموضحة هنا.

1. أنشئ غرفة عامة أو خاصة، وحدد حجم الفريق من 1 ضد 1 إلى 4 ضد 4، أو ادخل غرفة متاحة برمزها.
2. احجز مقعدًا في فريقك. إنشاء الغرفة وحده لا يحجز مقعدًا. تبدأ المباراة بعد اكتمال الفريقين، ويمكن تحرير المقعد قبل البداية.
3. بعد العد التنازلي المشترك، اختر إجابة ومنطقة متاحة على الخريطة ثم اضغط «اعتماد الإجابة». التحديد فوري، أما تأكيد التسجيل فلا يظهر إلا بعد الحفظ في الخادم.
4. قرار الفريق يُحسب من أصوات أعضائه. تنتهي الجولة باكتمال الإجابات أو انتهاء الوقت، ثم تظهر الإجابة الصحيحة والنقاط وتغيّر السيطرة.
5. الدردشة قابلة للطي. التواصل العام يحتاج موافقة كل اللاعبين، والميكروفون لا يعمل تلقائيًا.
6. بعد الأسئلة الخمسة يُحسم الفائز وفق النقاط وقواعد التعادل الحالية. «إعادة اللعب» تفتح غرفة جديدة دون محو نتيجة المباراة السابقة.

ملاحظة القاعدة الحالية: إذا اختار الفريقان المنطقة نفسها، بقيت أولوية الفريق «أ» كما كانت. تغييرها إلى أولوية الأسرع يحتاج قرارًا صريحًا، ولم يُغيّر خفية ضمن إصلاح الأداء.
