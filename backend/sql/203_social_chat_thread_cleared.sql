-- Per-user "delete conversation": hide a thread from the user's chat list.
-- cleared_at marks when the user deleted the conversation for themselves; the
-- thread is hidden from their list until a newer message arrives.
ALTER TABLE social_chat_thread_participant_state
  ADD COLUMN IF NOT EXISTS cleared_at TIMESTAMPTZ;
