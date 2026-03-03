BEGIN;

CREATE TABLE IF NOT EXISTS social_user_relation (
  user_a_id          BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  user_b_id          BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  initiator_user_id  BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  status             VARCHAR(16) NOT NULL DEFAULT 'pending',
  requested_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  responded_at       TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_a_id, user_b_id),
  CONSTRAINT social_user_relation_order_check
    CHECK (user_a_id < user_b_id),
  CONSTRAINT social_user_relation_initiator_check
    CHECK (initiator_user_id = user_a_id OR initiator_user_id = user_b_id),
  CONSTRAINT social_user_relation_status_check
    CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled', 'blocked'))
);

CREATE INDEX IF NOT EXISTS idx_social_user_relation_status
  ON social_user_relation (status, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_social_user_relation_a_pending
  ON social_user_relation (user_a_id, requested_at DESC)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_social_user_relation_b_pending
  ON social_user_relation (user_b_id, requested_at DESC)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_social_user_relation_initiator_pending
  ON social_user_relation (initiator_user_id, requested_at DESC)
  WHERE status = 'pending';

DROP TRIGGER IF EXISTS trg_social_user_relation_updated ON social_user_relation;
CREATE TRIGGER trg_social_user_relation_updated
BEFORE UPDATE ON social_user_relation
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_call_session (
  id               BIGSERIAL PRIMARY KEY,
  thread_id        BIGINT NOT NULL REFERENCES social_chat_thread(id) ON DELETE CASCADE,
  caller_user_id   BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  callee_user_id   BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  status           VARCHAR(16) NOT NULL DEFAULT 'ringing',
  started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  answered_at      TIMESTAMPTZ,
  ended_at         TIMESTAMPTZ,
  end_reason       VARCHAR(80),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_call_session_distinct_users_check
    CHECK (caller_user_id <> callee_user_id),
  CONSTRAINT social_call_session_status_check
    CHECK (status IN ('ringing', 'active', 'ended', 'declined', 'missed'))
);

CREATE INDEX IF NOT EXISTS idx_social_call_session_thread_recent
  ON social_call_session (thread_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_call_session_caller_recent
  ON social_call_session (caller_user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_call_session_callee_recent
  ON social_call_session (callee_user_id, created_at DESC, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_social_call_session_thread_active
  ON social_call_session (thread_id)
  WHERE status IN ('ringing', 'active');

DROP TRIGGER IF EXISTS trg_social_call_session_updated ON social_call_session;
CREATE TRIGGER trg_social_call_session_updated
BEFORE UPDATE ON social_call_session
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS social_call_signal (
  id              BIGSERIAL PRIMARY KEY,
  session_id      BIGINT NOT NULL REFERENCES social_call_session(id) ON DELETE CASCADE,
  thread_id       BIGINT NOT NULL REFERENCES social_chat_thread(id) ON DELETE CASCADE,
  sender_user_id  BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  signal_type     VARCHAR(20) NOT NULL,
  signal_payload  JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_call_signal_type_check
    CHECK (signal_type IN ('ringing', 'accept', 'offer', 'answer', 'ice', 'hangup', 'decline'))
);

CREATE INDEX IF NOT EXISTS idx_social_call_signal_session_recent
  ON social_call_signal (session_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_call_signal_thread_recent
  ON social_call_signal (thread_id, id DESC);

COMMIT;
