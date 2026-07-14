# Social V3 — Direct Upload Pipeline (§3–§8)

Video never passes through the backend/Railway. Flutter uploads straight to
Cloudflare Stream via a one-time tus URL the backend provisions.

## Flow

```
Flutter (ReelComposerController)
  │  1. POST /api/feed/media/stream/upload-session {sourceType:reel, sizeBytes, mimeType}
  ▼
Backend (feed.media.service.createSocialMediaStreamUploadSession)
  │  → createCloudflareStreamUploadSession()  [Stream API secret stays here]
  │  → inserts social_media_asset(provider='stream', processing_status='pending')
  │  ← { uploadSession: { assetId, streamUid, uploadUrl } }
  ▼
Flutter (TusUploadClient + DioTusTransport)
  │  2. tus HEAD/PATCH chunks DIRECTLY to Cloudflare uploadUrl  [body never hits backend]
  ▼
Cloudflare Stream
  │  3. POST /api/feed/media/stream/webhook  (signed)
  ▼
Backend (handleCloudflareStreamWebhook)
  │  → verify signature → find asset by stream_uid → map status
  │  → update playback_url/thumbnail/duration/dimensions, set 'ready'|'failed'
  ▼
Reconciliation worker (startSocialStreamReconciliationWorker)
  │  → recovers missed webhooks: fetchCloudflareStreamVideoDetails(uid) → update
  ▼
Flutter polls GET /api/feed/media/assets/:id until 'ready'
  │  4. POST /api/feed/reels {mediaAssetId, caption, audience, ...}  (no file body)
  ▼
Backend (createReel → resolveSocialMediaAssetForPublishing)
     → enforces READY + ownership + source match, then publishes.
```

## Endpoints

| Method | Path | Purpose | Status |
|--------|------|---------|--------|
| POST | `/api/feed/media/stream/upload-session` | provision tus URL | existing (proven) |
| POST | `/api/feed/media/stream/upload-session/:assetId/cancel` | cancel in-flight session | **added this phase** |
| GET | `/api/feed/media/assets/:assetId` | processing status | existing |
| POST | `/api/feed/media/stream/webhook` | Stream webhook (signed, idempotent) | existing (proven) |
| POST | `/api/feed/reels` (with `mediaAssetId`) | publish from ready asset | existing |

## Lifecycle states

`pending → uploading (client) → processing → ready → published`, plus `failed`,
`cancelled`. The backend owns the terminal state (webhook/reconciliation);
Flutter never decides final publication (`ReelComposerController` only advances
to `published` after the backend `publishReel` returns).

## Guarantees

* **No R2 fallback for new reel/story video** — Stream-eligible video always uses
  the Stream provider; failure returns a clear error and keeps the draft.
* **Legacy R2 stays playable** — old rows keep `provider='r2'` and normalized
  URLs; the media contract still guards posters.
* **Secrets stay server-side** — the client only ever holds a one-time upload URL.
* **Idempotency** — publish carries an `Idempotency-Key`; retry does not create a
  second reel (the controller reuses one key per composer session).

## Flutter components

| Component | File |
|-----------|------|
| Resumable client | `lib/features/social_v3/upload/tus_upload_client.dart` |
| Production transport | `lib/features/social_v3/upload/dio_tus_transport.dart` |
| Backend API client | `lib/features/social_v3/upload/reel_upload_api_impl.dart` |
| Publish orchestration | `lib/features/social_v3/composer/reel_composer_state.dart` |
| Native pickers | `lib/features/social_v3/pickers/social_media_picker_v3.dart` |

## Verification status

* **Client/orchestration logic:** PASS — `tus_upload_client_test.dart` (11 cases:
  normal, 10%/80% interruption, offset mismatch, expired URL, cancel, retry,
  retry-exhaustion, restart recovery, duplicate completion, progress),
  `reel_composer_controller_test.dart` (4 cases incl. failed-not-published,
  idempotency).
* **Backend status mapping:** PASS — `feed.stream-media.test.js` (6 cases).
* **Live Cloudflare upload / webhook delivery / publish-to-visible timing:**
  BLOCKED — requires Cloudflare credentials + deployed backend + device. Code and
  mocked tests are complete.
