BEGIN;

CREATE TABLE IF NOT EXISTS social_user_notification_pref (
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  actor_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  muted BOOLEAN NOT NULL DEFAULT FALSE,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, actor_user_id)
);

CREATE INDEX IF NOT EXISTS idx_social_user_notification_pref_actor
  ON social_user_notification_pref (actor_user_id, muted, updated_at DESC);

DROP TRIGGER IF EXISTS trg_social_user_notification_pref_updated ON social_user_notification_pref;
CREATE TRIGGER trg_social_user_notification_pref_updated
BEFORE UPDATE ON social_user_notification_pref
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
