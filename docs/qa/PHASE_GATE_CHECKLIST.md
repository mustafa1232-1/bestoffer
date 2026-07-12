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
- [x] Phase 2C checkpoint commit created in `be45724`
- [x] Pharmacy remains non-device-gated in this program and must not be claimed as real-device verified

## Phase 2D Prep

- [x] Phase 2C code is confirmed deployed on Railway at commit `a9fda00499f1ce9bba59effba26573d807b28be2`
- [x] Railway deployment ID `00af763c-db5f-4ad4-83e5-9da4bacff354` returned `SUCCESS`
- [x] `/health` returned `200`
- [x] `/ready` returned `200`
- [x] `docs/qa/PHASE_2D_COMPANY_ADMIN_FINANCE_REPORT.md` created
- [x] Company/Admin and finance scope is being expanded in the audit matrix before any code fix

## Phase 2D Continuation

- [x] Local QA DB was reset safely to the single seeded `super_admin` using `node --env-file=.env.test src/scripts/resetDbKeepSuperAdmin.js`
- [x] `flutter analyze` passed
- [x] `flutter test` passed
- [x] `npm run verify:release:local` passed after the local QA DB reset
- [x] `backend/src/scripts/securityRuntimeCheck.js` passed on Railway for backoffice, accountant, and role/surface isolation
- [x] `backend/src/scripts/authSessionPushE2ECheck.js` passed on Railway for company/admin session bootstrap and push/realtime
- [x] `backend/src/scripts/financialSettlementsE2ECheck.js` passed on Railway and cleaned up its temporary merchant/user artifacts
- [x] `railway run --service bestoffer npm run verify:release:runtime` passed after the backend script update
- [x] Phase 2D proof now distinguishes runtime coverage from automated-only company portal screens

## Phase 3A Continuation

- [x] Social discovery / profile / messaging runtime proof captured with `backend/src/scripts/socialE2ECheck.js`
- [x] Stories runtime proof captured with `backend/src/scripts/storiesE2ECheck.js`
- [x] Reels runtime proof captured with `backend/src/scripts/reelsE2ECheck.js`
- [x] `backend/src/tests/feed.phase3a.test.js` passed with phase 3A social validators
- [x] `npm test`, `npm run verify:release:local`, and `railway run --service bestoffer npm run verify:release:runtime` passed after the wrapper exit fix
- [x] `docs/qa/PHASE_3A_SOCIAL_PROFILES_DISCOVERY_STORIES_REELS_REPORT.md` created
- [x] Phase 3A checkpoint commit created in `4872c39`
- [x] Phase 3A remains backend-only and does not require a device gate in this program

## Phase 3B Continuation

- [x] Messaging runtime proof captured with `backend/src/scripts/socialE2ECheck.js`
- [x] `backend/src/tests/feed.phase3b.test.js` passed with clientMessageId validation for thread and community chat
- [x] `flutter analyze`, `flutter test`, `npm test`, `npm run verify:release:local`, and `railway run --service bestoffer npm run verify:release:runtime` passed after the Phase 3B messaging changes
- [x] `docs/qa/PHASE_3B_MESSAGING_GROUPS_VOICE_NOTES_ATTACHMENTS_REPORT.md` created
- [x] Phase 3B checkpoint commit created on `closure/full-application-closure`
- [x] Voice-note attachment dedupe and unread-state stability are now proven in runtime
- [x] Real-device push/background/killed-app and notification-tap validation remains pending and must not be claimed as passed

## Phase 3C Continuation

- [x] Migration `132_social_chat_client_message_id.sql` integrity audited against repo, local QA DB, and Railway
- [x] Security re-audit passed for auth/surface isolation, headers, and runtime guard behavior
- [x] Bounded local performance smoke completed without failures
- [x] Signed APK/AAB release-candidate artifacts were built for user, store, delivery, captain, pharmacy, and company
- [x] `docs/qa/PHASE_3C_RELEASE_CANDIDATE_REPORT.md` created
- [x] `docs/qa/ANDROID_ARTIFACT_MANIFEST.md` created
- [x] Phase 3C checkpoint commit created in `633d700`
- [ ] Real-device push/background/killed-app and notification-tap validation remains pending and must not be claimed as passed
- [ ] Full `permissions:check` role matrix remains blocked until user / owner / delivery QA credentials are available

## Notes

- Phase 1 must not start until the P0 blockers are the only active closure scope.
- Any destructive production action, ambiguous business rule, missing access, or irreversible migration must stop the program before Phase 1.
