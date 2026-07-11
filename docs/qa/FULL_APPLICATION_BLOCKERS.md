# Full Application Blockers

This list starts as the authoritative working blocker set for the closure program.

## P0 Launch Blockers

| Priority | Blocker | P0 reproduction status | Repro / evidence | Notes |
|---|---|---|---|---|
| P0 | Second store creation returns only `فشل` | PASS_RUNTIME | Owner register path can return `OWNER_ALREADY_HAS_MERCHANT`; the shared Flutter mapper translates it instead of falling back to a generic failure, and live duplicate-owner smoke now proves the backend surface | Store-app device smoke still pending |
| P0 | Men/women fashion leakage | PASS_RUNTIME | Department-aware browse cache keys now separate men / women / unisex results and live create/list/search smoke passed | Device proof still pending |
| P0 | Missing category visibility | PASS_RUNTIME | Category create/list/runtime smoke now shows immediate visibility on owner and public merchant surfaces | Device proof still pending |
| P0 | Missing product visibility | PASS_RUNTIME | Product create/list/runtime smoke now shows immediate visibility on owner and public merchant surfaces | Device proof still pending |
| P0 | Merchant/admin coupon failure | PASS_RUNTIME | Merchant/admin coupon runtime smoke now passes create/validate/preview/checkout with the correct scopes | Device proof still pending |
| P0 | Order -> store -> delivery workflow gaps | PASS_RUNTIME | Local QA runtime proof via `backend/src/scripts/orderE2ECheck.js` covered customer create, store approval, courier assignment, pickup, delivery, and confirmation | Notifications and deep links were observed in the runtime flow; device proof still missing |
| P0 | Taxi notification / negotiation regressions | PARTIALLY_REPRODUCED | `backend/src/scripts/taxiE2ECheck.js` now proves the taxi lifecycle locally, and `railway run --service bestoffer npm run verify:release:runtime` passed with direct captain acceptance, multi-offer negotiation, counter-offer, chat gating, and live tracking gating | Real-device push/background/killed-app proof still missing; device QA is still required |
| P0 | Stale-token / push-token / session regressions | PASS_RUNTIME | `backend/src/scripts/authSessionPushE2ECheck.js`, `backend/src/scripts/securityRuntimeCheck.js`, and `backend/src/scripts/realtimeRuntimeCheck.js` all passed on Railway; guest NO_TOKEN handling, refresh/logout/logout-all, push-token, and realtime-token lifecycle are now proven | Real-device push/background/killed-app proof still missing |

## P1+

| Priority | Blocker | Current status | Notes |
|---|---|---|---|
| P1 | Services coverage | PASS_RUNTIME | `backend/src/scripts/servicesE2ECheck.js` and `railway run --service bestoffer npm run verify:release:runtime` now prove provider onboarding, offering approval, request/quote, and completion | Device proof not required for this scope |
| P1 | Jobs coverage | PASS_RUNTIME | `backend/src/scripts/jobsE2ECheck.js` and `railway run --service bestoffer npm run verify:release:runtime` now prove duplicate-apply blocking, hire, accept-offer, withdraw, and expired-job rejection | Device proof not required for this scope |
| P1 | Real estate coverage | PASS_RUNTIME | `backend/src/scripts/realEstateE2ECheck.js` passed on Railway with listing approval, workspace visibility, and business chat routing | Runtime proof only; device proof not required |
| P1 | Cars coverage | PASS_RUNTIME | `backend/src/scripts/carsE2ECheck.js` passed on Railway with listing approval, workspace visibility, and business chat routing | Runtime proof only; device proof not required |
| P1 | Pharmacy coverage | PASS_RUNTIME | `backend/src/scripts/pharmacyE2ECheck.js` passed on Railway with conversation, cart proposal, accept/reject/request-revision, order conversion, and exact notification target coverage; no device gate is required for this phase |
| P1 | Company/admin shell and permissions | PASS_RUNTIME | Railway runtime proof captured with company/admin session isolation, backoffice gating, and accountant access checks (`authSessionPushE2ECheck.js`, `securityRuntimeCheck.js`) |
| P1 | Company/admin merchant and user management | PASS_AUTOMATED | UI/API automated coverage exists for company portal screens and client behavior (`test/core/admin_companies_screen_test.dart`, `test/features/company/company_dio_client_test.dart`) |
| P1 | Company/admin financial reports and settlements | PASS_RUNTIME | Railway runtime proof captured for summary, pending settlements, approvals, and payment-request cleanup (`financialSettlementsE2ECheck.js`, `securityRuntimeCheck.js`) |
| P2 | Stories autoplay/progress | NOT_STARTED | Audit later |
| P2 | Reel sharing | NOT_STARTED | Audit later |
| P2 | Social/discovery/profile/messaging | NOT_STARTED | Audit later |
