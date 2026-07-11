# Phase 2D Company/Admin Finance Report

## Baseline

- Working branch: `closure/full-application-closure`
- Starting HEAD: `a9fda00499f1ce9bba59effba26573d807b28be2`
- Origin branch HEAD: `4034661545ea66366a6bc741b3327d13b4767b0d`
- Phase 2C code checkpoint: `be457249f7aa637e422cfa40ff748e0eb7d0ec3b`
- Phase 2C deployed commit: `a9fda00499f1ce9bba59effba26573d807b28be2`
- Railway deployment ID: `00af763c-db5f-4ad4-83e5-9da4bacff354`
- Railway deployment status: `SUCCESS`
- Health: `200`
- Ready: `200`
- Deployment timestamp: `2026-07-12 00:51:25 +03:00`
- Environment: `production`
- Service: `bestoffer`

## Test Baseline

- `flutter analyze`: passed
- `flutter test`: passed
- `cd backend && npm test`: passed
- `cd backend && npm run verify:release:local`: passed after resetting the local QA DB to the single seeded `super_admin`
- `railway run --service bestoffer npm run verify:release:runtime`: passed after the backend script update
- `backend/src/scripts/securityRuntimeCheck.js`: passed on Railway for backoffice, accountant, and surface-isolation checks
- `backend/src/scripts/authSessionPushE2ECheck.js`: passed on Railway for company/admin login, bootstrap, and push/realtime session flow
- `backend/src/scripts/financialSettlementsE2ECheck.js`: passed on Railway for financial settlement proof and cleanup
- `railway run --service bestoffer npm run e2e:financial:check`: passed on the final script revision with `run_tag=financial-e2e-mrgyhidm`
- Pharmacy runtime proof: passed and remains closed in `Phase 2C`

## Exact Scope

- Company app authentication and shell
- Admin and super-admin permissions
- User management
- Store and merchant management
- Store creation and ownership assignment
- Merchant approval and suspension
- Delivery agent management
- Taxi captain management
- Pharmacy approval and management
- Services / Jobs / Real Estate / Cars moderation surfaces already present
- Coupons and promotions administration
- Financial reports
- Merchant dues and receivables
- Settlement requests
- Collections and payments
- Commission configuration
- Service fee and delivery fee configuration
- Dashboard KPIs
- Export, PDF, Excel, print, and thermal output
- Audit logs
- Admin notification routing
- Role-based access and data isolation
- Runtime E2E coverage

## Exclusions

- Kysely
- Prisma
- Social overhaul
- Stories
- Reels
- AI / assistant
- broad performance / load testing
- new unrelated business modules
- production data cleanup
- database redesign

## Notes

- Phase 2D starts from a deployed, healthy Phase 2C baseline.
- Any new database work must stay forward-only and non-destructive.
- Company/Admin runtime proof now covers authentication/bootstrap isolation, backoffice permissions, accountant summary access, and financial settlement flows on Railway.
- Company portal branch/user/config surfaces remain covered by automated UI/API tests in the audit matrix and are not device-gated.
- The local QA database was reset safely with `node --env-file=.env.test src/scripts/resetDbKeepSuperAdmin.js` before rerunning `verify:release:local`.
