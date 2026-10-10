BEGIN;

ALTER TABLE maslaki_quiz_question
  ADD COLUMN IF NOT EXISTS time_limit_seconds SMALLINT NOT NULL DEFAULT 20;

DO $$ BEGIN
  ALTER TABLE maslaki_quiz_question
    ADD CONSTRAINT maslaki_quiz_question_time_limit_check
    CHECK (time_limit_seconds BETWEEN 5 AND 60);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

UPDATE maslaki_quiz_question
SET time_limit_seconds = CASE difficulty WHEN 'easy' THEN 30 WHEN 'hard' THEN 15 ELSE 20 END;

CREATE TABLE IF NOT EXISTS maslaki_quiz_chat_message (
  id BIGSERIAL PRIMARY KEY,
  match_id BIGINT NOT NULL REFERENCES maslaki_quiz_match(id) ON DELETE CASCADE,
  team_id BIGINT REFERENCES maslaki_quiz_team(id) ON DELETE CASCADE,
  channel VARCHAR(12) NOT NULL CHECK (channel IN ('team','public')),
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  body VARCHAR(500) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK ((channel='team' AND team_id IS NOT NULL) OR (channel='public' AND team_id IS NULL))
);

CREATE TABLE IF NOT EXISTS maslaki_quiz_chat_consent (
  match_id BIGINT NOT NULL REFERENCES maslaki_quiz_match(id) ON DELETE CASCADE,
  team_id BIGINT NOT NULL REFERENCES maslaki_quiz_team(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(match_id,user_id)
);

CREATE TABLE IF NOT EXISTS maslaki_quiz_reaction (
  id BIGSERIAL PRIMARY KEY,
  match_id BIGINT NOT NULL REFERENCES maslaki_quiz_match(id) ON DELETE CASCADE,
  team_id BIGINT NOT NULL REFERENCES maslaki_quiz_team(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  kind VARCHAR(24) NOT NULL CHECK (kind IN ('happy','angry','laugh','surprised','applause','request_public_chat')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_maslaki_quiz_chat_history
  ON maslaki_quiz_chat_message(match_id,channel,team_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_maslaki_quiz_reaction_live
  ON maslaki_quiz_reaction(match_id,created_at DESC);

COMMIT;
