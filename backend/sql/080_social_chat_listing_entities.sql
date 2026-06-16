ALTER TABLE social_chat_message
  DROP CONSTRAINT IF EXISTS social_chat_message_shared_entity_type_chk;
ALTER TABLE social_chat_message
  ADD CONSTRAINT social_chat_message_shared_entity_type_chk
  CHECK (
    shared_entity_type IS NULL
    OR shared_entity_type IN (
      'post',
      'reel',
      'review',
      'car_listing',
      'real_estate_listing'
    )
  );
