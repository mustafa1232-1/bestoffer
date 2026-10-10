BEGIN;

-- Preserve existing rooms as single-game matches. New clients explicitly
-- choose a best-of series; never change the rules of an active match.
ALTER TABLE maslaki_quiz_event ADD COLUMN IF NOT EXISTS best_of SMALLINT NOT NULL DEFAULT 1
  CHECK (best_of IN (1,3,5,9));
ALTER TABLE maslaki_quiz_match ADD COLUMN IF NOT EXISTS series_game SMALLINT NOT NULL DEFAULT 1 CHECK(series_game>0);
ALTER TABLE maslaki_quiz_match ADD COLUMN IF NOT EXISTS game_start_question INT NOT NULL DEFAULT 0 CHECK(game_start_question>=0);
ALTER TABLE maslaki_quiz_match ADD COLUMN IF NOT EXISTS wins_a SMALLINT NOT NULL DEFAULT 0 CHECK(wins_a>=0);
ALTER TABLE maslaki_quiz_match ADD COLUMN IF NOT EXISTS wins_b SMALLINT NOT NULL DEFAULT 0 CHECK(wins_b>=0);

CREATE TABLE IF NOT EXISTS maslaki_quiz_series_game (
  match_id BIGINT NOT NULL REFERENCES maslaki_quiz_match(id) ON DELETE CASCADE,
  game_number SMALLINT NOT NULL,
  winner_team_id BIGINT NOT NULL REFERENCES maslaki_quiz_team(id),
  score_a INT NOT NULL,
  score_b INT NOT NULL,
  territories JSONB NOT NULL,
  first_question INT NOT NULL,
  last_question INT NOT NULL,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(match_id,game_number)
);

-- Wording variants share one fact; a series must not ask it twice.
ALTER TABLE maslaki_quiz_question ADD COLUMN IF NOT EXISTS fact_key TEXT;
CREATE INDEX IF NOT EXISTS idx_knowledge_question_fact ON maslaki_quiz_question(fact_key);
COMMIT;
