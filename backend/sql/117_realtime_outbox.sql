CREATE TABLE IF NOT EXISTS realtime_outbox (
  id BIGSERIAL PRIMARY KEY,
  topic TEXT NOT NULL,
  event TEXT NOT NULL,
  payload JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT realtime_outbox_status_chk
    CHECK (status IN ('pending', 'processing', 'published', 'failed'))
);

CREATE INDEX IF NOT EXISTS idx_realtime_outbox_pending
  ON realtime_outbox (status, next_attempt_at, id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_realtime_outbox_topic_created
  ON realtime_outbox (topic, created_at DESC, id DESC);

-- Idempotency / de-duplication key. Two logically-identical events collapse to a
-- single in-flight row; once published the same key can be re-queued again.
ALTER TABLE realtime_outbox
  ADD COLUMN IF NOT EXISTS dedupe_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_realtime_outbox_dedupe_active
  ON realtime_outbox (dedupe_key)
  WHERE status IN ('pending', 'processing') AND dedupe_key IS NOT NULL;
