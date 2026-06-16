BEGIN;

CREATE INDEX IF NOT EXISTS idx_social_post_author_kind_recent
  ON social_post (user_id, post_kind, id DESC)
  WHERE is_deleted = FALSE AND moderation_status = 'approved';

CREATE INDEX IF NOT EXISTS idx_social_story_owner_recent
  ON social_story (user_id, id DESC)
  WHERE is_deleted = FALSE AND moderation_status = 'approved';

CREATE INDEX IF NOT EXISTS idx_social_post_caption_lower
  ON social_post ((lower(COALESCE(caption, ''))));

CREATE INDEX IF NOT EXISTS idx_social_story_caption_lower
  ON social_story ((lower(COALESCE(caption, ''))));

CREATE INDEX IF NOT EXISTS idx_social_chat_message_sender_thread_recent
  ON social_chat_message (sender_user_id, thread_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_saved_item_entity_lookup
  ON social_saved_item (entity_type, entity_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_social_mention_entity_lookup
  ON social_mention (entity_type, entity_id, created_at DESC);

COMMIT;
