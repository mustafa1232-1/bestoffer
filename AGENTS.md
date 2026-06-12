# BestOffer Execution Notes

## Run
- Backend dev: `cd backend && npm install && npm run dev`
- Backend app server: `cd backend && npm run start:app`
- Backend ops server: `cd backend && npm run start:ops`
- Flutter app: `flutter pub get && flutter run`

## Tests
- Flutter: `flutter test`
- Backend unit/contracts: `cd backend && npm test`
- Backend checks: `cd backend && npm run permissions:check && npm run flow:check`
- Backend release verify (local fast): `cd backend && npm run verify:release:local`
- Backend release verify (Railway runtime): `cd backend && railway run --service bestoffer npm run verify:release:runtime`
- Backend runtime security audit: `cd backend && railway run --service bestoffer npm run security:runtime:check`
- Backend E2E:
  - Orders: `cd backend && npm run e2e:order:check`
  - Taxi: `cd backend && npm run e2e:taxi:check`
  - Community: `cd backend && npm run e2e:community:check`
  - Jobs: `cd backend && npm run e2e:jobs:check`
  - Pharmacy: `cd backend && npm run e2e:pharmacy:check`

## Railway
- Current linked service: `railway status`
- Run backend command on linked service: `cd backend && railway run <command>`
- Health smoke:
  - `https://bestoffer-production.up.railway.app/health`
  - `https://bestoffer-production.up.railway.app/ready`

## Load Tests
- Seed temporary Railway fixtures:
  - `cd backend && railway run node src/scripts/seedLoadFixtures.js --customer-pool 50`
- Cleanup temporary Railway fixtures:
  - `cd backend && railway run node src/scripts/cleanupLoadFixtures.js --run-tag <tag>`
- Mixed HTTP load with k6:
  - `k6 run tests/load/k6/mixed-workload.js -e BASE_URL=https://bestoffer-production.up.railway.app -e AUTH_TOKENS_FILE=<path-to-json> -e MERCHANT_ID=<id> -e PRODUCT_ID=<id> -e PHARMACY_MERCHANT_ID=<id> -e PHARMACY_PRODUCT_ID=<id> -e RUN_TAG=<tag>`
- SSE/realtime load:
  - `cd backend && $env:STRESS_AUTH_TOKENS_FILE='<path-to-json>'; node src/scripts/sseStreamStress.js --base-url https://bestoffer-production.up.railway.app --users 250 --run-tag <tag>`
- Stage runner:
  - `powershell -File scripts/load/run-railway-load.ps1 -BaseUrl https://bestoffer-production.up.railway.app -Stages 25,50,100,250,500,1000,2500,5000`

## Done Criteria
- `flutter test` green
- `cd backend && npm test` green
- critical backend checks green
- Railway seed/load/cleanup commands complete without orphaned temp data
- final smoke on `/health` and `/ready` returns `200`
