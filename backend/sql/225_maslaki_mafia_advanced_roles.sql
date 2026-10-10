BEGIN;

-- This migration is intentionally separate from the initial Mafia schema.
-- Production databases that already applied 224 must receive the completed
-- advanced-role actions without rebuilding any game data.
ALTER TABLE mafia_action
  DROP CONSTRAINT IF EXISTS mafia_action_action_type_check;

ALTER TABLE mafia_action
  ADD CONSTRAINT mafia_action_action_type_check CHECK (action_type IN (
    'mafia_kill','doctor_protect','bodyguard_protect','detective_inspect',
    'don_inspect','framer_frame'
  ));

COMMIT;
