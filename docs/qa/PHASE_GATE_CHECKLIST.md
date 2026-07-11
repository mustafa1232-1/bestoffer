# Phase Gate Checklist

## Phase 0 Exit Criteria

- [x] Baseline git facts verified
- [x] Safety backup branch created
- [x] Phase 0 documentation scaffold committed in `03dbbdd`
- [x] Required Phase 0 docs exist and are substantive
- [x] Inventory counts captured from tracked repository files
- [x] Audit matrix row counts captured
- [x] P0 blocker reproduction states recorded
- [x] ERD labeled as conceptual until physical FK validation
- [x] Kysely status confirmed as documentation-only / not started
- [x] Phase 0 completion checkpoint commit created
- [x] Final Phase 0 handoff delivered with exact counts and entry scope

## Phase 1 Entry Criteria

- Phase 0 report committed
- Phase 0 inventory counts recorded
- P0 blockers ranked and reproducible
- No unresolved baseline modified or untracked files
- Working branch remains `closure/full-application-closure`
- Scope locked to P0 launch blockers only

## Phase 1A Continuation

- Live backend runtime evidence captured for store / catalog / coupon scope
- Department-aware browse cache keys fixed for men / women fashion sections
- `npm test`, `verify:release:local`, and `verify:release:runtime` passed after the fix
- Phase 1A checkpoint commit `558b989` has been created
- Store-app device smoke remains pending and must not be claimed as passed

## Phase 1B Continuation

- Local order / store / delivery runtime proof captured with `node --env-file=.env.test src/scripts/orderE2ECheck.js`
- `npm run verify:release:local` passed after the order flow proof
- `railway run --service bestoffer npm run verify:release:runtime` passed after the order flow proof
- `docs/qa/PHASE_1B_ORDER_STORE_DELIVERY_REPORT.md` created
- Store / delivery device smoke remains pending and must not be claimed as passed

## Phase 1C Continuation

- Auth / session / push runtime proof captured with `railway run --service bestoffer npm run verify:release:runtime`
- `backend/src/scripts/authSessionPushE2ECheck.js` passed on Railway with guest, super-admin, owner, customer, delivery, and captain coverage
- Guest NO_TOKEN, refresh/logout-all, push-token, and realtime-token lifecycle is now proven in runtime
- `docs/qa/PHASE_1C_AUTH_SESSION_PUSH_REPORT.md` created
- Real-device push/background/killed-app validation remains pending and must not be claimed as passed

## Notes

- Phase 1 must not start until the P0 blockers are the only active closure scope.
- Any destructive production action, ambiguous business rule, missing access, or irreversible migration must stop the program before Phase 1.
