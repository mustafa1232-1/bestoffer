# BestOffer Backend Deployment Guide

This backend is designed for a simple and explicit production topology:

- one PostgreSQL database
- one Redis instance
- Cloudflare R2 for all public media

No AI services, AI databases, or AI environment variables are required.

## Railway deploy from this repo

Do not run `railway up` from inside `backend/`.
The Railway service uses `rootDirectory=/backend`, so the upload archive must contain a top-level `backend/` folder.

Use:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\railway_deploy_backend.ps1
```

Optional:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\railway_deploy_backend.ps1 `
  -Service bestoffer `
  -Environment production `
  -HealthUrl https://bestoffer-production.up.railway.app/health
```

## Required variables

### Core
- `NODE_ENV=production`
- `HOST=0.0.0.0`
- `PORT=3000`
- `JWT_SECRET`
- `DATABASE_URL`
- `CF_R2_ACCESS_KEY_ID`
- `CF_R2_SECRET_ACCESS_KEY`
- `CF_R2_BUCKET`
- `CF_R2_ENDPOINT`
- `CF_R2_PUBLIC_BASE_URL`

### Recommended
- `REDIS_URL`
- `RUN_SQL_MIGRATIONS=true`
- `CORS_ORIGINS=https://YOUR_APP_DOMAIN`
- `LOG_HTTP_REQUESTS=false`

### Optional Supabase realtime delivery
- `SUPABASE_REALTIME_ENABLED=true`
- `SUPABASE_REALTIME_MODE=dual`
- `SUPABASE_URL=https://YOUR_PROJECT.supabase.co`
- `SUPABASE_ANON_KEY=...`
- `SUPABASE_SERVICE_ROLE_KEY=...`
- `SUPABASE_JWT_SECRET=...`
- `SUPABASE_REALTIME_OUTBOX_MAX_ATTEMPTS=8`
- `SUPABASE_REALTIME_OUTBOX_BASE_DELAY_MS=1000`

Required manual SQL when enabling Supabase realtime:
- run Railway migration `backend/sql/117_realtime_outbox.sql`
- run Supabase SQL `backend/sql_supabase/001_realtime_authorization.sql`

Recommended rollout:
1. start with `SUPABASE_REALTIME_ENABLED=true` and `SUPABASE_REALTIME_MODE=dual`
2. verify `/api/notifications/stream` still works
3. verify `POST /api/realtime/token` returns URL + anon key + short-lived token
4. verify chat/taxi/notification events arrive on Supabase private channels
5. switch to `supabase_only` only after mobile clients have migrated

### Optional integrations
- Firebase push variables
- Twilio variables
- TURN variables
- OCR variables

## Health verification

After deploy:

```bash
curl https://bestoffer-production.up.railway.app/health
curl https://bestoffer-production.up.railway.app/ready
```

Expected:
- `/health` returns detailed component state
- `/ready` returns `200` only when the primary DB and required storage are ready

## Postgres recovery policy

The app uses a single primary database only.

If the database fails:
- recover or recreate the PostgreSQL service
- update `DATABASE_URL` if it changed
- redeploy or restart the backend

Detailed steps:
- [docs/postgres-failover-runbook.md](../docs/postgres-failover-runbook.md)

## Media storage policy

Cloudflare R2 is the only supported production media backend.
The backend should store only media metadata in PostgreSQL:
- object key
- public URL
- mime type
- size
- duration / thumbnail refs

Do not store media binaries in PostgreSQL or Redis.

## Self-hosted Docker example

```bash
cd backend/deploy
cp .env.prod.example .env.prod
# fill in secrets + R2 values

docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

This compose example includes:
- one primary Postgres
- one Redis
- the API
- TURN relay

## Railway cleanup

Use the checklist here after deploying the cleaned backend:
- [docs/railway-cleanup-checklist.md](../docs/railway-cleanup-checklist.md)
