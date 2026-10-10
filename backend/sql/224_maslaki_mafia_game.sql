BEGIN;

CREATE TABLE IF NOT EXISTS mafia_room (
  id BIGSERIAL PRIMARY KEY,
  invite_code VARCHAR(6) NOT NULL UNIQUE,
  host_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE RESTRICT,
  ruleset VARCHAR(20) NOT NULL DEFAULT 'standard'
    CHECK (ruleset IN ('standard','advanced')),
  status VARCHAR(24) NOT NULL DEFAULT 'lobby'
    CHECK (status IN (
      'lobby','role_reveal','night','day_discussion','day_nomination',
      'day_defense','day_vote','day_revote','completed','cancelled'
    )),
  min_players SMALLINT NOT NULL DEFAULT 7 CHECK (min_players BETWEEN 7 AND 14),
  max_players SMALLINT NOT NULL DEFAULT 14 CHECK (max_players BETWEEN 7 AND 14),
  day_number SMALLINT NOT NULL DEFAULT 0 CHECK (day_number BETWEEN 0 AND 50),
  phase_version INT NOT NULL DEFAULT 1,
  phase_started_at TIMESTAMPTZ,
  phase_ends_at TIMESTAMPTZ,
  voice_room_name VARCHAR(120) NOT NULL UNIQUE,
  winner VARCHAR(12) CHECK (winner IS NULL OR winner IN ('town','mafia')),
  settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (min_players <= max_players)
);

CREATE TABLE IF NOT EXISTS mafia_player (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES mafia_room(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  seat_number SMALLINT NOT NULL CHECK (seat_number BETWEEN 1 AND 14),
  role VARCHAR(24) CHECK (role IS NULL OR role IN (
    'citizen','mafia','don','detective','doctor','bodyguard','framer'
  )),
  team VARCHAR(12) CHECK (team IS NULL OR team IN ('town','mafia')),
  life_status VARCHAR(12) NOT NULL DEFAULT 'alive'
    CHECK (life_status IN ('alive','dead','left')),
  is_ready BOOLEAN NOT NULL DEFAULT FALSE,
  role_acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  disconnected_at TIMESTAMPTZ,
  eliminated_at TIMESTAMPTZ,
  eliminated_reason VARCHAR(24),
  UNIQUE (room_id,user_id),
  UNIQUE (room_id,seat_number)
);

CREATE TABLE IF NOT EXISTS mafia_action (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES mafia_room(id) ON DELETE CASCADE,
  day_number SMALLINT NOT NULL,
  phase_version INT NOT NULL,
  actor_player_id BIGINT NOT NULL REFERENCES mafia_player(id) ON DELETE CASCADE,
  action_type VARCHAR(24) NOT NULL CHECK (action_type IN (
    'mafia_kill','doctor_protect','bodyguard_protect','detective_inspect',
    'don_inspect','framer_frame'
  )),
  target_player_id BIGINT NOT NULL REFERENCES mafia_player(id) ON DELETE CASCADE,
  command_id VARCHAR(80) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (room_id,actor_player_id,day_number,action_type),
  UNIQUE (room_id,actor_player_id,command_id),
  CHECK (actor_player_id <> target_player_id OR action_type = 'doctor_protect')
);

CREATE TABLE IF NOT EXISTS mafia_ballot (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES mafia_room(id) ON DELETE CASCADE,
  day_number SMALLINT NOT NULL,
  phase_version INT NOT NULL,
  ballot_type VARCHAR(16) NOT NULL CHECK (ballot_type IN ('nomination','vote','revote')),
  voter_player_id BIGINT NOT NULL REFERENCES mafia_player(id) ON DELETE CASCADE,
  target_player_id BIGINT REFERENCES mafia_player(id) ON DELETE CASCADE,
  command_id VARCHAR(80) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (room_id,voter_player_id,day_number,ballot_type),
  UNIQUE (room_id,voter_player_id,command_id),
  CHECK (target_player_id IS NULL OR voter_player_id <> target_player_id)
);

CREATE TABLE IF NOT EXISTS mafia_event (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES mafia_room(id) ON DELETE CASCADE,
  day_number SMALLINT NOT NULL DEFAULT 0,
  event_type VARCHAR(40) NOT NULL,
  visibility VARCHAR(16) NOT NULL DEFAULT 'public'
    CHECK (visibility IN ('public','mafia','dead','private')),
  recipient_player_id BIGINT REFERENCES mafia_player(id) ON DELETE CASCADE,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (visibility <> 'private' OR recipient_player_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS mafia_message (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES mafia_room(id) ON DELETE CASCADE,
  sender_player_id BIGINT NOT NULL REFERENCES mafia_player(id) ON DELETE CASCADE,
  channel VARCHAR(16) NOT NULL CHECK (channel IN ('public','mafia','dead')),
  body VARCHAR(300) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mafia_room_status_phase
  ON mafia_room (status,phase_ends_at);
CREATE INDEX IF NOT EXISTS idx_mafia_player_user
  ON mafia_player (user_id,joined_at DESC);
CREATE INDEX IF NOT EXISTS idx_mafia_event_room
  ON mafia_event (room_id,id DESC);
CREATE INDEX IF NOT EXISTS idx_mafia_message_room
  ON mafia_message (room_id,id DESC);
CREATE INDEX IF NOT EXISTS idx_mafia_ballot_tally
  ON mafia_ballot (room_id,day_number,ballot_type,target_player_id);

COMMIT;
