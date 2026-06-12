# Supabase Realtime Contract

Railway stays the official backend for:
- auth
- roles and permissions
- orders
- taxi ride logic
- payments and settlements
- moderation and audit

Supabase Realtime is delivery-only in this integration.

## Client bootstrap

1. Authenticate with Railway normally.
2. Call `POST /api/realtime/token` with the Railway access token.
3. Receive:

```json
{
  "supabaseUrl": "https://YOUR_PROJECT.supabase.co",
  "supabaseAnonKey": "public-anon-key",
  "realtimeToken": "short-lived-jwt",
  "userId": 123,
  "expiresIn": 900
}
```

4. Initialize Supabase on Flutter with the returned URL and anon key.
5. Before subscribing, call `supabase.realtime.setAuth(realtimeToken)`.
6. Subscribe to private channels only.

## Allowed channel patterns

- `notifications:user:{me}`
- `social:user:{me}`
- `taxi:user:{me}`
- `chat:thread:{threadId}`
- `taxi:ride:{rideId}`
- `order:{orderId}`

## Important rules

- Treat Supabase events as UI refresh hints only.
- All sensitive writes stay on Railway APIs.
- If reconnect happens or a `resync_required`-style state is detected, refetch official state from Railway REST APIs.
- Never write order, taxi, payment, or permission changes directly to Supabase.

## Legacy fallback

Legacy SSE remains available during migration:
- `GET /api/notifications/stream`
- `GET /api/taxi/stream`

Runtime mode:
- `sse_only`
- `dual`
- `supabase_only`
