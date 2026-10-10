# Knowledge Map: Tournament Series

Date: 2026-10-08. Local implementation and verification only; no production deployment, AAB, version bump, or production fixture writes.

## Delivered Checklist

- [x] New room and admin tournament creation expose best-of 3, 5, or 9.
- [x] First to 2, 3, or 5 game wins ends the match immediately; unused games are not played.
- [x] Each game retains five base questions and the existing tied-score rules. Score and territories reset between games, not series wins.
- [x] Completed games are archived with winner, scores, territories and question boundaries in the scoring transaction.
- [x] Server-authoritative series scores and game-result banners; no client-side invented wins.
- [x] Tournament progression waits for the series winner. Bracket propagation is serialized and idempotent.
- [x] Complete mirrored bracket, central illustrated trophy, connectors, byes, known advancers, champion, prize and round tabs.
- [x] Pan, zoom and fit controls; separate readable match list on phones; RTL and enlarged text tested.
- [x] Only a member's real match can be opened. Public bracket data excludes invite codes, answers and private chat.
- [x] Bracket refresh pauses while a match is open and while the app is inactive. Return reuses the original page and resumes one poller.
- [x] 200 additional question entries; balanced category selection and no repeated canonical fact within a series.
- [x] Existing room formats remain unchanged (`best_of=1`). An omitted field from an old client retains that default.

## Rules And Compatibility

A question, a game, and a tournament round are different units. Five base questions determine one game. A match is a series of games. Winning that series advances the team to the next tournament round, once all matches in the current tournament round have completed.

After a tied game score, existing logic compares correct-question count, response time, then territories. An unresolved tie may add up to three questions; the existing final random tie-break is unchanged. Existing team-A priority for a same-target territory is also unchanged. These are not newly introduced fairness guarantees.

Answer admission still uses one database function call and returns only after commit. The series archive and win increment happen under the existing round gate. Global question numbering stays monotonic across games, while the UI displays the question number within the current game. Reopening the app reads the stored state; it does not restart a series.

Bracket refresh is a five-second HTTP fallback, not a claim of instant tournament-wide push. Match realtime and voice contracts are unchanged. No new entry fee, payout automation or prize redemption was added; prizes continue to use the existing admin-defined metadata.

## Question Bank

The bank now contains **1200 entries**, not 1200 independent facts. The original 1000 entries include alternate wordings of 116 base prompts. The addition is 40 authored prompts plus 160 parameterized numerical puzzles (eight templates with twenty inputs). There are now 316 distinct category/canonical-prompt keys. Parameter changes are not claimed to be wholly different concepts.

New categories: space, mathematics and logic. Existing categories are retained. `fact_key` links known legacy wording variants, and the selector prefers categories asked less often during this match. Administrator-authored questions remain supported. Seeding fills fact metadata without overwriting edited question text or reactivating disabled entries.

The 160 numeric answer keys are independently recomputed by tests. Space prompts were checked against NASA's [planets](https://science.nasa.gov/solar-system/planets/), [Venus](https://science.nasa.gov/venus/) and [Pluto](https://science.nasa.gov/dwarf-planets/pluto/) pages. This is not a claim that the entire legacy bank underwent a new factual audit.

## Verification Evidence

| Check | Result / artifact |
| --- | --- |
| Knowledge backend + realtime gateway | 46 passed, zero failed, one intentionally skipped; `knowledge-series-backend-all.log` |
| Real PostgreSQL series tests | Best-of 3 early/full, 5 and 9; reset/persistence, concurrent resolver retries, scoped tie-break, no repeated facts; included above |
| Tournament propagation | 12 teams, four byes, 15 slots (8/4/2/1), outsider denied match access, repeated advancement through champion; included above |
| Numerical question keys | All 160 independently recomputed, four distinct choices each; included above |
| Flutter full suite | 871 passed, zero failed, one skipped; `knowledge-series-flutter-full.log`. Includes the final navigation regression; only a braces-only lint correction followed this run. |
| Flutter focused game tests | 52 passed, one skipped before the final navigation regression; `knowledge-series-flutter-games.log` |
| Navigation regression | Seven screen tests passed including paused polling and reuse of the bracket after match exit; `knowledge-series-navigation.log` |
| Static analysis | No issues found; `knowledge-series-analyze.log` |
| HTTP permission matrix | 45 passed, zero failed; cleanup verified by restored local user count; `knowledge-series-permissions.log` |
| Flow check | Exit 0; `knowledge-series-flow.log` |
| Real Flutter browser + PostgreSQL | Actual 12-team bracket, 15 slots, zoom/fit, final tab, phone and desktop; `knowledge-tournament-browser.json` |
| Actual match browser | One HTTP 200 durable answer receipt, visible confirmation, settings and chat; `knowledge-series-match-browser.log`, `knowledge-web-report.json` |
| Public health smoke | `/health` and `/ready` both returned HTTP 200 on 2026-10-08; read-only check of the deployed old backend, not verification of this release |

Screenshots: [phone](knowledge-tournament-phone.png), [desktop](knowledge-tournament-desktop.png), [final](knowledge-tournament-final.png). Golden: `test/features/games/goldens/knowledge-tournament.png`. The trophy reuses the bundled atlas documented in [the theme report](KNOWLEDGE_THEME_UPDATE.md); no extra image download per match.

### Full Backend Is Not Green

The broad run recorded 714 passes, 16 failures and one skipped test (`knowledge-series-backend-full.log`). Ten failures reproduce the prior baseline outside this game: nine delivery payment/evidence cases and one delivery outbox assertion (`PUSH_FAILED` versus `PUSH_ACCEPTED`). No unrelated commerce/payment logic was changed to suppress these failures.

The other six were Windows Node/libuv process shutdown assertions (`UV_HANDLE_CLOSING`) while using `--test-force-exit`. Re-running those six files serially without that flag passed all eight assertions (`knowledge-series-backend-infra-retry.log`). This does not make the remaining ten baseline failures green.

## Deployment And Rollback

1. Before release, back up the database and drain active legacy matches as required by migration 229's protocol cutover; see [the rebuild report](KNOWLEDGE_MAP_REBUILD.md).
2. Apply the repository SQL migrations through `230_knowledge_match_series.sql` using the normal `npm run migrate:sql` process. Migration 230 is additive and preserves existing event formats. It has only been applied to isolated local QA databases here.
3. Deploy the matching backend, including the game worker, question expansion and bracket route. Seeding runs through the existing bank initializer; inspect the actual enabled question counts if administrators have edited the bank.
4. Release the Flutter client with the series selector and bracket screen. Verify real room creation, 2-0 and 2-1 results, leaving/resuming, and tournament advancement in staging first.
5. Do not roll back to a worker that lacks series support while a best-of series is active: that worker would interpret a game boundary as a match boundary. Drain affected series before rollback; retain additive columns and archives.

## Local Preview And Limits

Preview: `http://127.0.0.1:4879/?bracket=1`; ordinary match: `http://127.0.0.1:4879`. Hidden local dev servers use ports 4879 (Flutter) and 4878 (QA API). The non-shipping entrypoint is `test_driver/knowledge_preview.dart`; the opt-in API fixture is `backend/src/qa/knowledge-preview.test.js`. Both use a dedicated loopback PostgreSQL clone, never production accounts.

No physical Android/iPhone test, multi-device LiveKit audio test, production latency test, prize fulfillment test or release build was performed for this change. No app-wide 100% readiness claim is made. Load/seed/cleanup against Railway was deliberately not run: only local fixtures were created, and the permission fixture cleanup was verified.
