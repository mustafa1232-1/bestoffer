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
- [x] Phase 1C checkpoint commit created in `3c56dfd`
- Real-device push/background/killed-app validation remains pending and must not be claimed as passed

## Phase 1D Continuation

- Taxi negotiation and lifecycle runtime proof captured with `node --env-file=.env.test src/scripts/taxiE2ECheck.js`
- `railway run --service bestoffer npm run verify:release:runtime` passed after the taxi negotiation and lifecycle updates
- Direct captain acceptance, multi-offer negotiation, counter-offer, chat gating, live tracking gating, and terminal lifecycle transitions are now proven in runtime
- `docs/qa/PHASE_1D_TAXI_NEGOTIATION_REPORT.md` created
- Real-device taxi push/background/killed-app validation remains pending and must not be claimed as passed

## Phase 1E Continuation

- Current Railway deployment was confirmed on `bestoffer` production with deployment id `499746db-3ec6-426c-921d-4f7024c87956`
- Signed QA APKs were rebuilt from HEAD `4034661545ea66366a6bc741b3327d13b4767b0d` for user, store, delivery, and captain
- `docs/qa/PHASE_1E_REAL_DEVICE_RELEASE_REPORT.md` created
- Real-device QA remains blocked because no physical Android devices were available in this workspace
- Signed AAB generation remains deferred until real-device gates are available

## Phase 2A Continuation

- [x] Services runtime proof captured with `backend/src/scripts/servicesE2ECheck.js`
- [x] Jobs runtime proof captured with `backend/src/scripts/jobsE2ECheck.js`
- [x] `npm test`, `verify:release:local`, and `verify:release:runtime` passed after the services/jobs fixes
- [x] `docs/qa/PHASE_2A_SERVICES_JOBS_REPORT.md` created
- [x] Phase 2A checkpoint commit recorded in `0d5e548`
- [x] Services/jobs remain non-device-gated and must not be claimed as device-verified

## Phase 2B Continuation

- [x] Real-estate runtime proof captured with `backend/src/scripts/realEstateE2ECheck.js`
- [x] Cars runtime proof captured with `backend/src/scripts/carsE2ECheck.js`
- [x] `npm test`, `verify:release:local`, and `verify:release:runtime` passed after the Phase 2B marketplace fixes
- [x] `docs/qa/PHASE_2B_REAL_ESTATE_CARS_REPORT.md` created
- [x] Phase 2B checkpoint commit created
- [x] Real-estate and cars remain non-device-gated and must not be claimed as device-verified

## Phase 2C Continuation

- [x] Pharmacy runtime proof captured with `backend/src/scripts/pharmacyE2ECheck.js`
- [x] Pharmacy conversation, proposed-cart, accept/reject/request-revision, attachment, and order conversion flows are now proven on Railway
- [x] Notification targets remain stable for `pharmacy_conversation`, `order_details`, and `owner_order_details`
- [x] `docs/qa/PHASE_2C_PHARMACY_REPORT.md` created
- [x] Pharmacy remains non-device-gated in this program and must not be claimed as real-device verified

## Notes

- Phase 1 must not start until the P0 blockers are the only active closure scope.
- Any destructive production action, ambiguous business rule, missing access, or irreversible migration must stop the program before Phase 1.
