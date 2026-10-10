BEGIN;

CREATE TABLE IF NOT EXISTS maslaki_quiz_question (
  id BIGSERIAL PRIMARY KEY,
  question_key VARCHAR(100) NOT NULL UNIQUE,
  category VARCHAR(40) NOT NULL,
  difficulty VARCHAR(16) NOT NULL CHECK (difficulty IN ('easy','medium','hard')),
  question_ar TEXT NOT NULL,
  options_json JSONB NOT NULL CHECK (jsonb_typeof(options_json) = 'array' AND jsonb_array_length(options_json) = 4),
  answer_index SMALLINT NOT NULL CHECK (answer_index BETWEEN 0 AND 3),
  explanation_ar TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS maslaki_quiz_event (
  id BIGSERIAL PRIMARY KEY,
  event_type VARCHAR(16) NOT NULL CHECK (event_type IN ('duel','tournament')),
  title VARCHAR(160) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'registration'
    CHECK (status IN ('registration','active','completed','cancelled')),
  team_size SMALLINT NOT NULL CHECK (team_size BETWEEN 1 AND 4),
  max_teams SMALLINT NOT NULL CHECK (max_teams BETWEEN 2 AND 64),
  prize_title VARCHAR(120),
  prize_description VARCHAR(500),
  prize_is_mock BOOLEAN NOT NULL DEFAULT TRUE,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  champion_team_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS maslaki_quiz_team (
  id BIGSERIAL PRIMARY KEY,
  event_id BIGINT NOT NULL REFERENCES maslaki_quiz_event(id) ON DELETE CASCADE,
  team_name VARCHAR(48) NOT NULL,
  join_code VARCHAR(8) NOT NULL UNIQUE,
  captain_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  seed_number SMALLINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(event_id, team_name),
  UNIQUE(event_id, seed_number)
);

CREATE TABLE IF NOT EXISTS maslaki_quiz_team_member (
  team_id BIGINT NOT NULL REFERENCES maslaki_quiz_team(id) ON DELETE CASCADE,
  event_id BIGINT NOT NULL REFERENCES maslaki_quiz_event(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(team_id, user_id),
  UNIQUE(user_id, team_id),
  UNIQUE(event_id, user_id)
);

CREATE TABLE IF NOT EXISTS maslaki_quiz_match (
  id BIGSERIAL PRIMARY KEY,
  event_id BIGINT NOT NULL REFERENCES maslaki_quiz_event(id) ON DELETE CASCADE,
  round_number SMALLINT NOT NULL,
  match_number SMALLINT NOT NULL,
  team_a_id BIGINT REFERENCES maslaki_quiz_team(id) ON DELETE SET NULL,
  team_b_id BIGINT REFERENCES maslaki_quiz_team(id) ON DELETE SET NULL,
  winner_team_id BIGINT REFERENCES maslaki_quiz_team(id) ON DELETE SET NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','active','completed','bye')),
  question_number SMALLINT NOT NULL DEFAULT 0,
  score_a INT NOT NULL DEFAULT 0,
  score_b INT NOT NULL DEFAULT 0,
  current_question_id BIGINT REFERENCES maslaki_quiz_question(id) ON DELETE SET NULL,
  question_started_at TIMESTAMPTZ,
  state_version INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(event_id, round_number, match_number)
);

CREATE TABLE IF NOT EXISTS maslaki_quiz_answer (
  id BIGSERIAL PRIMARY KEY,
  match_id BIGINT NOT NULL REFERENCES maslaki_quiz_match(id) ON DELETE CASCADE,
  question_id BIGINT NOT NULL REFERENCES maslaki_quiz_question(id) ON DELETE RESTRICT,
  team_id BIGINT NOT NULL REFERENCES maslaki_quiz_team(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  answer_index SMALLINT NOT NULL CHECK (answer_index BETWEEN 0 AND 3),
  district_id VARCHAR(40) NOT NULL,
  is_timeout BOOLEAN NOT NULL DEFAULT FALSE,
  response_ms INT NOT NULL DEFAULT 30000 CHECK (response_ms BETWEEN 0 AND 30000),
  is_correct BOOLEAN NOT NULL,
  points SMALLINT NOT NULL DEFAULT 0,
  answered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(match_id, question_id, user_id)
);

CREATE TABLE IF NOT EXISTS maslaki_quiz_territory (
  match_id BIGINT NOT NULL REFERENCES maslaki_quiz_match(id) ON DELETE CASCADE,
  district_id VARCHAR(40) NOT NULL,
  team_id BIGINT NOT NULL REFERENCES maslaki_quiz_team(id) ON DELETE CASCADE,
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(match_id, district_id)
);

CREATE INDEX IF NOT EXISTS idx_maslaki_quiz_events_live
  ON maslaki_quiz_event(status, starts_at);
CREATE INDEX IF NOT EXISTS idx_maslaki_quiz_team_event
  ON maslaki_quiz_team(event_id, seed_number);
CREATE INDEX IF NOT EXISTS idx_maslaki_quiz_match_event
  ON maslaki_quiz_match(event_id, round_number, match_number);
CREATE INDEX IF NOT EXISTS idx_maslaki_quiz_questions_pool
  ON maslaki_quiz_question(category, difficulty) WHERE is_active = TRUE;

COMMIT;
