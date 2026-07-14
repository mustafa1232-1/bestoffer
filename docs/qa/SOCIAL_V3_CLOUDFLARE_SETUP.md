# Social V3 — Cloudflare Stream Setup (§5)

Configures direct Flutter → Cloudflare Stream (tus) uploads. **Never commit real
secret values.** Set them as Railway environment variables only.

## Required environment variables (names only)

| Variable | Purpose | Secret? |
|----------|---------|---------|
| `CF_STREAM_ACCOUNT_ID` | Cloudflare account id for Stream | no |
| `CF_STREAM_API_TOKEN` | Stream API token (Stream: Read+Edit) | **yes** |
| `CF_STREAM_CUSTOMER_CODE` | Stream customer/subdomain code | no |
| `CF_STREAM_PLAYBACK_BASE_URL` | optional playback base (derivable) | no |
| `CF_STREAM_THUMBNAIL_BASE_URL` | optional thumbnail base (derivable) | no |
| `CF_STREAM_WEBHOOK_SECRET` | webhook signature secret | **yes** |
| `SOCIAL_STREAM_RECONCILE_INTERVAL_MS` | reconciliation cadence (e.g. 30000) | no |
| `SOCIAL_STREAM_RECONCILE_BATCH_SIZE` | reconciliation batch (e.g. 20) | no |

Legacy R2 vars (`CF_R2_*`) remain for read-only legacy playback and are
unaffected.

The presence of these is validated by
`backend/src/modules/feed/feed.stream-config.js` (`describeStreamConfig` /
`streamConfigHealth`) — it reports booleans only, never values.

## Dashboard steps

1. **Generate the API token** — Cloudflare Dashboard → My Profile → API Tokens →
   Create Token → custom token with **Stream: Read + Edit**. Copy it once into
   `CF_STREAM_API_TOKEN` (Railway).
2. **Account id / customer code** — Dashboard → Stream. The account id is in the
   URL / API section; the customer code is the `customer-<code>` subdomain shown
   on delivery URLs. Set `CF_STREAM_ACCOUNT_ID`, `CF_STREAM_CUSTOMER_CODE`.
3. **Configure the webhook** — Stream → Settings → Webhooks → add the endpoint
   `https://<backend>/api/feed/media/stream/webhook`. Copy the signing secret
   into `CF_STREAM_WEBHOOK_SECRET`.
4. **Set Railway variables** — add all of the above to the backend service
   variables and redeploy.
5. **Verify webhook delivery** — upload a short test video (step 6); confirm a
   `webhook-signature`-signed POST reaches the endpoint and the asset flips to
   `ready` in `social_media_asset`.
6. **Run a test upload** — from the app, create a reel; watch the composer go
   `uploading → processing → published`, or use `curl` against
   `POST /api/feed/media/stream/upload-session` then tus-PATCH to the returned
   `uploadUrl`.

## Behavior when unconfigured

* `streamConfigHealth().stream === "unavailable"`.
* A new reel/story **video** upload session request returns a clear
  service-unavailable error (`STREAM_UPLOAD_SESSION_FAILED` / not-configured).
* The local draft is preserved; the user can retry later.
* **No silent fallback to R2** for new reel/story video.

## Status

Config validator + tests: **PASS** (`feed.stream-config.test.js`, 4 cases).
Live token/webhook verification: **BLOCKED** — requires real Cloudflare
credentials + a deployed backend.
