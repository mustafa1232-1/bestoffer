CREATE TABLE IF NOT EXISTS social_profile_change_request (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  change_kind VARCHAR(24) NOT NULL DEFAULT 'core_identity',
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  current_snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  requested_snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  review_note TEXT NULL,
  reviewed_by_user_id BIGINT NULL REFERENCES app_user(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_profile_change_request_status_chk
    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  CONSTRAINT social_profile_change_request_kind_chk
    CHECK (change_kind IN ('core_identity'))
);

CREATE INDEX IF NOT EXISTS idx_social_profile_change_request_user_recent
  ON social_profile_change_request (user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_social_profile_change_request_status_recent
  ON social_profile_change_request (status, created_at DESC, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_social_profile_change_request_pending_unique
  ON social_profile_change_request (user_id, change_kind)
  WHERE status = 'pending';

DROP TRIGGER IF EXISTS trg_social_profile_change_request_updated ON social_profile_change_request;
CREATE TRIGGER trg_social_profile_change_request_updated
BEFORE UPDATE ON social_profile_change_request
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

