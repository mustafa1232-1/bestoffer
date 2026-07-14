BEGIN;

ALTER TABLE social_media_asset
  ADD COLUMN IF NOT EXISTS provider VARCHAR(16) NOT NULL DEFAULT 'r2',
  ADD COLUMN IF NOT EXISTS stream_uid TEXT,
  ADD COLUMN IF NOT EXISTS playback_url TEXT,
  ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;

ALTER TABLE social_media_asset
  DROP CONSTRAINT IF EXISTS social_media_asset_provider_check;

ALTER TABLE social_media_asset
  ADD CONSTRAINT social_media_asset_provider_check
  CHECK (provider IN ('r2', 'stream'));

UPDATE social_media_asset
SET
  provider = COALESCE(NULLIF(provider, ''), 'r2'),
  playback_url = COALESCE(NULLIF(playback_url, ''), normalized_url, original_url),
  thumbnail_url = COALESCE(NULLIF(thumbnail_url, ''), poster_url)
WHERE TRUE;

CREATE INDEX IF NOT EXISTS idx_social_media_asset_provider_recent
  ON social_media_asset (provider, created_at DESC, id DESC);

COMMIT;
