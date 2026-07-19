ALTER TABLE service_offerings
  DROP CONSTRAINT IF EXISTS service_offerings_moderation_chk;

ALTER TABLE service_offerings
  ADD CONSTRAINT service_offerings_moderation_chk
  CHECK (moderation_status IN ('pending', 'approved', 'rejected', 'changes_requested', 'hidden'));
