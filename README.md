# Maslaki / BestOffer

Multi-surface Flutter + Node.js platform for Maslaki. The backend is a single Node.js API on Railway backed by:

- one PostgreSQL database
- one Redis instance
- Cloudflare R2 for all public media objects

## Production backend architecture

Application traffic uses:
- `DATABASE_URL` as the only write/read database target
- `REDIS_URL` for rate limiting, cache, OTP/session-like ephemeral data, and lightweight coordination
- Cloudflare R2 for product images, profile images, videos, reels, and public files

Redis namespaces are centralized in `backend/src/config/redis-keys.js`:
- `rl:` rate limiting
- `fw:` firewall / temporary blocks
- `cache:` short-lived endpoint caching
- reserved: `otp:`, `queue:`, `lock:`, `session:`

The application does **not** use standby promotion logic anymore. If the database fails, restore or replace the single primary and redeploy using:
- [Postgres Recovery Runbook](docs/postgres-failover-runbook.md)
- [Railway Cleanup Checklist](docs/railway-cleanup-checklist.md)

## Hybrid Realtime

Railway PostgreSQL remains the only source of truth for auth, roles, orders, taxi logic, payments, moderation, and every sensitive write.

Supabase Realtime is now supported as an optional delivery layer for live events only:
- notifications
- social chat/thread/typing/call updates
- taxi ride/bid/location updates
- order channel updates

Rollout modes:
- `SUPABASE_REALTIME_MODE=sse_only`: legacy SSE only
- `SUPABASE_REALTIME_MODE=dual`: SSE + Supabase broadcast
- `SUPABASE_REALTIME_MODE=supabase_only`: Supabase broadcast only

Flutter integration contract:
- authenticate with Railway first
- call `POST /api/realtime/token`
- initialize Supabase with `SUPABASE_URL` + `SUPABASE_ANON_KEY`
- call `supabase.realtime.setAuth(realtimeToken)`
- subscribe only to authorized private channels
- keep all writes on Railway APIs

Detailed contract:
- [docs/realtime-supabase-contract.md](docs/realtime-supabase-contract.md)

## Backend quick start

```powershell
cd backend
npm install
copy .env.example .env
npm start
```

Required core variables:
- `DATABASE_URL`
- `JWT_SECRET`
- `CF_R2_ACCESS_KEY_ID`
- `CF_R2_SECRET_ACCESS_KEY`
- `CF_R2_BUCKET`
- `CF_R2_ENDPOINT`
- `CF_R2_PUBLIC_BASE_URL`

Optional but recommended:
- `REDIS_URL`
- Firebase / Twilio / TURN variables if those features are enabled in your environment

## Health endpoints

- `GET /health`
  - detailed app, primary DB, Redis, storage, and runtime posture
- `GET /ready`
  - readiness gate for production checks

## Media policy

Public media must live in Cloudflare R2 only.

Inside PostgreSQL keep only metadata such as:
- object key
- public URL
- MIME type
- file size
- duration / thumbnail references if needed

Do not store:
- image/video blobs in PostgreSQL
- media blobs in Redis

## Deployment

Use the Railway deployment script from the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\railway_deploy_backend.ps1
```

Supporting docs:
- [Backend Deploy Guide](backend/DEPLOY.md)
- [Realtime Supabase Contract](docs/realtime-supabase-contract.md)
- [Postgres Recovery Runbook](docs/postgres-failover-runbook.md)
- [Railway Cleanup Checklist](docs/railway-cleanup-checklist.md)
- [System Overview](SYSTEM_OVERVIEW.md)
- [Support Guide](SUPPORT_GUIDE.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Routes and Permissions Map](ROUTES_AND_PERMISSIONS_MAP.md)
- [Data Flow Guide](DATA_FLOW_GUIDE.md)
- [Environment Guide](ENV_GUIDE.md)

## Multi-App structure

The repository now has standalone Flutter apps under `apps/`:

- `apps/app_user` -> user app (includes rider taxi flow only)
- `apps/app_store` -> store owner app
- `apps/app_delivery` -> delivery app
- `apps/app_taxi_captain` -> taxi captain app
- `apps/app_company` -> company/ops app

Current state:
- `apps/*` entrypoints are isolated behind shell packages under `packages/app_*_shell`.
- Direct imports from `apps/*/lib` to `package:bestoffer/*` are blocked by guard scripts.
- Full hard split (removing shell bridge to root runtime) is still tracked as remaining scope.

Quick run examples:

```powershell
cd apps/app_user
flutter pub get
flutter run
```

```powershell
cd apps/app_taxi_captain
flutter pub get
flutter run
```

## Split size verification

Generate APK size report (root + split apps):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_split_size_report.ps1 -Rebuild true
```

Latest generated report:
- [docs/APP_SIZE_DIFF_REPORT.md](docs/APP_SIZE_DIFF_REPORT.md)

Build production Android artifacts (APK + AAB) for all split apps:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_android_production_artifacts.ps1
```

Latest artifact report:
- [docs/ANDROID_PRODUCTION_ARTIFACTS.md](docs/ANDROID_PRODUCTION_ARTIFACTS.md)

## Boundary and localization guards

Run app-boundary checks:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check_import_boundaries.ps1
```

Run Arabic term consistency check:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check_localization_terms.ps1
```

CI workflow:
- [mobile-hard-split-gates.yml](.github/workflows/mobile-hard-split-gates.yml)
