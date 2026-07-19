ALTER TABLE social_media_asset
  ADD COLUMN IF NOT EXISTS trace_id TEXT;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_provider TEXT;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_preview_url TEXT;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_thumbnail_url TEXT;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_width INTEGER;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_height INTEGER;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_upload_state TEXT;

ALTER TABLE social_chat_message
  ADD COLUMN IF NOT EXISTS attachment_trace_id TEXT;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_provider TEXT;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_preview_url TEXT;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_thumbnail_url TEXT;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_width INTEGER;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_height INTEGER;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_upload_state TEXT;

ALTER TABLE social_scope_chat_message
  ADD COLUMN IF NOT EXISTS attachment_trace_id TEXT;

ALTER TABLE social_chat_scheduled_message
  ADD COLUMN IF NOT EXISTS attachment_provider TEXT;

ALTER TABLE social_chat_scheduled_message
  ADD COLUMN IF NOT EXISTS attachment_preview_url TEXT;

ALTER TABLE social_chat_scheduled_message
  ADD COLUMN IF NOT EXISTS attachment_thumbnail_url TEXT;

ALTER TABLE social_chat_scheduled_message
  ADD COLUMN IF NOT EXISTS attachment_width INTEGER;

ALTER TABLE social_chat_scheduled_message
  ADD COLUMN IF NOT EXISTS attachment_height INTEGER;

ALTER TABLE social_chat_scheduled_message
  ADD COLUMN IF NOT EXISTS attachment_upload_state TEXT;

ALTER TABLE social_chat_scheduled_message
  ADD COLUMN IF NOT EXISTS attachment_trace_id TEXT;
