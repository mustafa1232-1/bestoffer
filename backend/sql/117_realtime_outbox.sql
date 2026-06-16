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
