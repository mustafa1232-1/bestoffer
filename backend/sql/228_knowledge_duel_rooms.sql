BEGIN;

ALTER TABLE maslaki_quiz_event
  DROP CONSTRAINT IF EXISTS maslaki_quiz_event_status_check;

ALTER TABLE maslaki_quiz_event
  ADD CONSTRAINT maslaki_quiz_event_status_check
  CHECK (status IN ('registration','active','completed','cancelled','closed'));

ALTER TABLE maslaki_quiz_event
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_maslaki_quiz_duel_rooms_visibility
  ON maslaki_quiz_event(status,is_private,created_at DESC)
  WHERE event_type='duel';

COMMIT;
