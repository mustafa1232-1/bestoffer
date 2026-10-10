BEGIN;

CREATE TABLE IF NOT EXISTS game_campaign (
  id BIGSERIAL PRIMARY KEY,
  campaign_key VARCHAR(80) NOT NULL UNIQUE,
  title VARCHAR(180) NOT NULL,
  is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  reward_type VARCHAR(30) NOT NULL DEFAULT 'mock_coupon',
  reward_value NUMERIC(12,2) NOT NULL DEFAULT 0,
  reward_valid_days INT NOT NULL DEFAULT 7,
  claim_limit INT,
  claimed_count INT NOT NULL DEFAULT 0,
  is_mock BOOLEAN NOT NULL DEFAULT TRUE,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (reward_valid_days BETWEEN 1 AND 365),
  CHECK (claim_limit IS NULL OR claim_limit >= 0),
  CHECK (claimed_count >= 0)
);

CREATE TABLE IF NOT EXISTS game_puzzle_definition (
  id BIGSERIAL PRIMARY KEY,
  slug VARCHAR(100) NOT NULL UNIQUE,
  title_ar VARCHAR(180) NOT NULL,
  title_en VARCHAR(180) NOT NULL,
  difficulty VARCHAR(20) NOT NULL CHECK (difficulty IN ('easy','medium','hard')),
  theme VARCHAR(30) NOT NULL DEFAULT 'logic',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS game_puzzle_version (
  id BIGSERIAL PRIMARY KEY,
  puzzle_id BIGINT NOT NULL REFERENCES game_puzzle_definition(id) ON DELETE CASCADE,
  version INT NOT NULL,
  code_length SMALLINT NOT NULL CHECK (code_length IN (3,4)),
  solution_code VARCHAR(4) NOT NULL,
  constraints_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  clues_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  hints_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  explanation_ar TEXT NOT NULL,
  explanation_en TEXT NOT NULL,
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  verified_solution_count INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (puzzle_id, version),
  CHECK (solution_code ~ '^[0-9]{3,4}$')
);

CREATE TABLE IF NOT EXISTS game_room (
  id BIGSERIAL PRIMARY KEY,
  invite_code VARCHAR(6) UNIQUE,
  mode VARCHAR(20) NOT NULL CHECK (mode IN ('solo','cooperative')),
  status VARCHAR(20) NOT NULL DEFAULT 'lobby'
    CHECK (status IN ('lobby','active','paused','completed','failed','abandoned')),
  host_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE RESTRICT,
  max_players SMALLINT NOT NULL DEFAULT 4 CHECK (max_players BETWEEN 1 AND 4),
  state_version INT NOT NULL DEFAULT 1,
  campaign_id BIGINT REFERENCES game_campaign(id) ON DELETE SET NULL,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  paused_at TIMESTAMPTZ,
  abandoned_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS game_membership (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES game_room(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  seat_number SMALLINT NOT NULL CHECK (seat_number BETWEEN 1 AND 4),
  is_ready BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  reward_eligible BOOLEAN NOT NULL DEFAULT FALSE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  disconnected_at TIMESTAMPTZ,
  left_at TIMESTAMPTZ,
  UNIQUE (room_id, user_id),
  UNIQUE (room_id, seat_number)
);

CREATE TABLE IF NOT EXISTS game_session (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL UNIQUE REFERENCES game_room(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','paused','completed','failed','abandoned')),
  current_round_index SMALLINT NOT NULL DEFAULT 1 CHECK (current_round_index BETWEEN 1 AND 3),
  score INT NOT NULL DEFAULT 0,
  elapsed_seconds INT NOT NULL DEFAULT 0,
  state_version INT NOT NULL DEFAULT 1,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS game_round (
  id BIGSERIAL PRIMARY KEY,
  session_id BIGINT NOT NULL REFERENCES game_session(id) ON DELETE CASCADE,
  puzzle_version_id BIGINT NOT NULL REFERENCES game_puzzle_version(id) ON DELETE RESTRICT,
  round_index SMALLINT NOT NULL CHECK (round_index BETWEEN 1 AND 3),
  status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','active','solved','failed')),
  attempts_remaining SMALLINT NOT NULL DEFAULT 5 CHECK (attempts_remaining BETWEEN 0 AND 5),
  wrong_attempts SMALLINT NOT NULL DEFAULT 0 CHECK (wrong_attempts BETWEEN 0 AND 5),
  hints_used SMALLINT NOT NULL DEFAULT 0 CHECK (hints_used BETWEEN 0 AND 3),
  score INT NOT NULL DEFAULT 0,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  UNIQUE (session_id, round_index)
);

CREATE TABLE IF NOT EXISTS game_clue_assignment (
  id BIGSERIAL PRIMARY KEY,
  round_id BIGINT NOT NULL REFERENCES game_round(id) ON DELETE CASCADE,
  membership_id BIGINT REFERENCES game_membership(id) ON DELETE CASCADE,
  clue_index SMALLINT NOT NULL,
  is_shared BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (round_id, clue_index)
);

CREATE TABLE IF NOT EXISTS game_proposal (
  id BIGSERIAL PRIMARY KEY,
  round_id BIGINT NOT NULL REFERENCES game_round(id) ON DELETE CASCADE,
  proposer_membership_id BIGINT NOT NULL REFERENCES game_membership(id) ON DELETE CASCADE,
  kind VARCHAR(20) NOT NULL CHECK (kind IN ('code','hint')),
  proposed_code VARCHAR(4),
  status VARCHAR(20) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','approved','rejected','expired','cancelled')),
  command_id VARCHAR(80) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (round_id, command_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_game_round_active_proposal
  ON game_proposal (round_id)
  WHERE status = 'active';

CREATE TABLE IF NOT EXISTS game_vote (
  id BIGSERIAL PRIMARY KEY,
  proposal_id BIGINT NOT NULL REFERENCES game_proposal(id) ON DELETE CASCADE,
  membership_id BIGINT NOT NULL REFERENCES game_membership(id) ON DELETE CASCADE,
  vote VARCHAR(10) NOT NULL CHECK (vote IN ('approve','reject')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (proposal_id, membership_id)
);

CREATE TABLE IF NOT EXISTS game_attempt (
  id BIGSERIAL PRIMARY KEY,
  round_id BIGINT NOT NULL REFERENCES game_round(id) ON DELETE CASCADE,
  membership_id BIGINT NOT NULL REFERENCES game_membership(id) ON DELETE RESTRICT,
  proposed_code VARCHAR(4) NOT NULL,
  is_correct BOOLEAN NOT NULL,
  command_id VARCHAR(80) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (round_id, command_id)
);

CREATE TABLE IF NOT EXISTS game_message (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES game_room(id) ON DELETE CASCADE,
  membership_id BIGINT NOT NULL REFERENCES game_membership(id) ON DELETE CASCADE,
  body VARCHAR(300) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS game_reward_claim (
  id BIGSERIAL PRIMARY KEY,
  campaign_id BIGINT NOT NULL REFERENCES game_campaign(id) ON DELETE RESTRICT,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  session_id BIGINT NOT NULL REFERENCES game_session(id) ON DELETE RESTRICT,
  reward_type VARCHAR(30) NOT NULL,
  reward_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (campaign_id, user_id),
  UNIQUE (session_id, user_id)
);

CREATE TABLE IF NOT EXISTS game_command (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES game_room(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  command_id VARCHAR(80) NOT NULL,
  command_type VARCHAR(40) NOT NULL,
  response_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (room_id, user_id, command_id)
);

CREATE INDEX IF NOT EXISTS idx_game_membership_user ON game_membership (user_id, joined_at DESC);
CREATE INDEX IF NOT EXISTS idx_game_room_status ON game_room (status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_game_message_room ON game_message (room_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_game_round_session ON game_round (session_id, round_index);

INSERT INTO game_campaign (
  campaign_key, title, is_enabled, starts_at, ends_at, reward_type,
  reward_value, reward_valid_days, claim_limit, is_mock
)
VALUES (
  'team_code_test', 'Team Code test campaign', TRUE,
  NOW() - INTERVAL '1 day', NOW() + INTERVAL '180 days',
  'mock_coupon', 10, 7, 100000, TRUE
)
ON CONFLICT (campaign_key) DO NOTHING;

COMMIT;
