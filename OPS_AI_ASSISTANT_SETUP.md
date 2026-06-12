# OPS AI Assistant Setup

## What was added
- Backend module: `backend/src/ops/*`
- New DB migration: `backend/sql/113_ops_ai_dev_support.sql`
- New admin UI area: `AI DEV SUPPORT`

## Required env
- Configure `backend/.env.example` keys in real `.env`.
- Minimum: `DATABASE_URL`, `JWT_SECRET`, `OPS_API_KEY`.

## Startup
1. `cd backend && npm ci`
2. set `RUN_SQL_MIGRATIONS=true`
3. `npm start`
4. `flutter pub get && flutter run`

## Webhooks test
- `POST /ops/webhooks/sentry`
- `POST /ops/webhooks/datadog`
- `POST /ops/webhooks/github-actions`
- Header: `x-ops-api-key: <OPS_API_KEY>`
