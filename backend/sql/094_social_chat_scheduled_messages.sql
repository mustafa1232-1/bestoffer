BEGIN;

CREATE TABLE IF NOT EXISTS social_chat_scheduled_message (
  id BIGSERIAL PRIMARY KEY,
  thread_id BIGINT NOT NULL REFERENCES social_chat_thread(id) ON DELETE CASCADE,
  sender_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  body TEXT NOT NULL DEFAULT '',
  reply_to_message_id BIGINT NULL REFERENCES social_chat_message(id) ON DELETE SET NULL,
  attachment_url TEXT NULL,
  attachment_kind VARCHAR(16) NULL,
  attachment_name TEXT NULL,
  attachment_mime_type VARCHAR(160) NULL,
  attachment_size_bytes INTEGER NULL,
  attachment_duration_ms INTEGER NULL,
  shared_entity_type VARCHAR(32) NULL,
  shared_entity_id BIGINT NULL,
  shared_snapshot_json JSONB NULL,
  scheduled_for TIMESTAMPTZ NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'scheduled',
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error_code VARCHAR(80) NULL,
  processing_started_at TIMESTAMPTZ NULL,
  sent_message_id BIGINT NULL REFERENCES social_chat_message(id) ON DELETE SET NULL,
  sent_at TIMESTAMPTZ NULL,
  cancelled_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_chat_scheduled_message_status_check
    CHECK (status IN ('scheduled', 'processing', 'sent', 'cancelled', 'failed')),
  CONSTRAINT social_chat_scheduled_message_attachment_kind_check
    CHECK (
      attachment_kind IS NULL
      OR attachment_kind IN ('image', 'video', 'audio', 'file')
    )
);

CREATE INDEX IF NOT EXISTS idx_social_chat_scheduled_message_sender_thread
  ON social_chat_scheduled_message (sender_user_id, thread_id, scheduled_for DESC)
  WHERE status IN ('scheduled', 'processing', 'failed');

CREATE INDEX IF NOT EXISTS idx_social_chat_scheduled_message_due
  ON social_chat_scheduled_message (status, scheduled_for ASC, id ASC)
  WHERE status IN ('scheduled', 'processing');

COMMIT;
