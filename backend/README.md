# BestOffer Backend

Production-ready Express/Postgres backend for the BestOffer marketplace app.

## Quick start

```bash
cd backend
npm install
cp .env.example .env
npm run dev
```

## Architecture notes

- `src/app.js`: Express app composition, middleware chain, route mounting.
- `src/server.js`: boot sequence (env validation, migrations, schema checks, startup).
- `src/config/env.js`: centralized env parsing and runtime validation.
- `src/shared/middleware/error.middleware.js`: unified JSON error contract.
- `src/shared/middleware/security.middleware.js`: default security headers.
- `src/shared/middleware/rate-limit.middleware.js`: in-memory request throttling.

## Health endpoints

- `GET /health` -> app + DB health check.
- `GET /ready` -> readiness probe.

## Cars API (new)

Routes are mounted under `/api/cars`:

- `GET /brands?search=...`
- `GET /models?brand=Toyota&search=...`
- `GET /browse?brand=...&model=...&condition=any|new|used&bodyType=...&yearFrom=...&yearTo=...&limit=...&offset=...`
- `POST /smart-search`

Example smart search body:

```json
{
  "budgetMinM": 20,
  "budgetMaxM": 50,
  "bodyType": "any",
  "usage": "personal",
  "condition": "any",
  "fuelPreference": "any",
  "transmission": "any",
  "priority": "balanced",
  "minSeats": 4,
  "freeText": "",
  "limit": 6
}
```

## New environment keys

- `JSON_BODY_LIMIT` (default: `10mb`)
- `REQUEST_TIMEOUT_MS` (default: `30000`)
- `LOG_HTTP_REQUESTS` (default: `true`)
- `RATE_LIMIT_WINDOW_MS` (default: `60000`)
- `RATE_LIMIT_MAX_REQUESTS` (default: `240`)
- `RATE_LIMIT_AUTH_MAX_REQUESTS` (default: `40`)
- `SUPABASE_REALTIME_ENABLED` (default: `false`)
- `SUPABASE_REALTIME_MODE` (`dual | supabase_only | sse_only`, default: `dual`)
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_JWT_SECRET`
- `SUPABASE_REALTIME_OUTBOX_MAX_ATTEMPTS` (default: `8`)
- `SUPABASE_REALTIME_OUTBOX_BASE_DELAY_MS` (default: `1000`)

## Realtime delivery modes

- `sse_only`: keeps `/api/notifications/stream` and `/api/taxi/stream` as the only live transport.
- `dual`: publishes to legacy SSE and Supabase private channels together.
- `supabase_only`: publishes only to Supabase private channels.

Client bootstrap:

1. Authenticate with Railway.
2. Call `POST /api/realtime/token`.
3. Initialize Supabase with the returned `supabaseUrl` and `supabaseAnonKey`.
4. Call `supabase.realtime.setAuth(realtimeToken)`.
5. Subscribe to private channels only.

Reference:
- [../docs/realtime-supabase-contract.md](../docs/realtime-supabase-contract.md)

## Error response format

All errors return:

```json
{
  "message": "ERROR_CODE",
  "requestId": "uuid"
}
```

For validation failures, controllers still return:

```json
{
  "message": "VALIDATION_ERROR",
  "fields": ["fieldA", "fieldB"]
}
```

## Maintenance reading order

- [../SYSTEM_OVERVIEW.md](../SYSTEM_OVERVIEW.md)
- [../SUPPORT_GUIDE.md](../SUPPORT_GUIDE.md)
- [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
- [../ROUTES_AND_PERMISSIONS_MAP.md](../ROUTES_AND_PERMISSIONS_MAP.md)
- [../DATA_FLOW_GUIDE.md](../DATA_FLOW_GUIDE.md)
- [../ENV_GUIDE.md](../ENV_GUIDE.md)
