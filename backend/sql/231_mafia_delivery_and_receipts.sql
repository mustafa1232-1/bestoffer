BEGIN;

-- One coalesced durable invalidation per room. Separate leases prevent a slow
-- voice provider from holding up game deadlines or realtime text updates.
CREATE TABLE IF NOT EXISTS mafia_room_delivery (
  room_id BIGINT PRIMARY KEY REFERENCES mafia_room(id) ON DELETE CASCADE,
  revision BIGINT NOT NULL DEFAULT 1,
  voice_revision BIGINT NOT NULL DEFAULT 1,
  notify_pending BOOLEAN NOT NULL DEFAULT TRUE,
  voice_pending BOOLEAN NOT NULL DEFAULT TRUE,
  notify_lease_until TIMESTAMPTZ NOT NULL DEFAULT '-infinity',
  voice_lease_until TIMESTAMPTZ NOT NULL DEFAULT '-infinity'
);
ALTER TABLE mafia_room_delivery ADD COLUMN IF NOT EXISTS voice_revision BIGINT NOT NULL DEFAULT 1;
CREATE INDEX IF NOT EXISTS idx_mafia_delivery_notify ON mafia_room_delivery(notify_lease_until) WHERE notify_pending;
CREATE INDEX IF NOT EXISTS idx_mafia_delivery_voice ON mafia_room_delivery(voice_lease_until) WHERE voice_pending;

CREATE OR REPLACE FUNCTION mafia_queue_delivery() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE rid BIGINT; voice_changed BOOLEAN := FALSE;
BEGIN
  IF TG_TABLE_NAME = 'mafia_room' THEN
    rid := NEW.id;
    voice_changed := TRUE;
  ELSE
    rid := COALESCE(NEW.room_id, OLD.room_id);
    IF TG_TABLE_NAME = 'mafia_player' THEN
      voice_changed := TG_OP <> 'UPDATE' OR NEW.life_status IS DISTINCT FROM OLD.life_status
        OR NEW.role IS DISTINCT FROM OLD.role OR NEW.team IS DISTINCT FROM OLD.team;
    END IF;
  END IF;
  INSERT INTO mafia_room_delivery(room_id,voice_pending)
    SELECT rid,voice_changed WHERE EXISTS(SELECT 1 FROM mafia_room WHERE id=rid)
    ON CONFLICT(room_id) DO UPDATE SET revision=mafia_room_delivery.revision+1,
      voice_revision=mafia_room_delivery.voice_revision+CASE WHEN EXCLUDED.voice_pending THEN 1 ELSE 0 END,
      notify_pending=TRUE,voice_pending=mafia_room_delivery.voice_pending OR EXCLUDED.voice_pending;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS mafia_room_dirty ON mafia_room;
CREATE TRIGGER mafia_room_dirty AFTER INSERT OR UPDATE OF status,phase_version,settings,host_user_id ON mafia_room
  FOR EACH ROW EXECUTE FUNCTION mafia_queue_delivery();
DROP TRIGGER IF EXISTS mafia_player_dirty ON mafia_player;
CREATE TRIGGER mafia_player_dirty AFTER INSERT OR DELETE OR UPDATE OF life_status,is_ready,role_acknowledged,role,team ON mafia_player
  FOR EACH ROW EXECUTE FUNCTION mafia_queue_delivery();
DROP TRIGGER IF EXISTS mafia_event_dirty ON mafia_event;
CREATE TRIGGER mafia_event_dirty AFTER INSERT ON mafia_event FOR EACH ROW EXECUTE FUNCTION mafia_queue_delivery();
DROP TRIGGER IF EXISTS mafia_message_dirty ON mafia_message;
CREATE TRIGGER mafia_message_dirty AFTER INSERT ON mafia_message FOR EACH ROW EXECUTE FUNCTION mafia_queue_delivery();
DROP TRIGGER IF EXISTS mafia_action_dirty ON mafia_action;
CREATE TRIGGER mafia_action_dirty AFTER INSERT OR UPDATE ON mafia_action FOR EACH ROW EXECUTE FUNCTION mafia_queue_delivery();
DROP TRIGGER IF EXISTS mafia_ballot_dirty ON mafia_ballot;
CREATE TRIGGER mafia_ballot_dirty AFTER INSERT OR UPDATE ON mafia_ballot FOR EACH ROW EXECUTE FUNCTION mafia_queue_delivery();
INSERT INTO mafia_room_delivery(room_id) SELECT id FROM mafia_room ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS mafia_command_receipt (
  room_id BIGINT NOT NULL REFERENCES mafia_room(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  command_id VARCHAR(80) NOT NULL,
  request JSONB NOT NULL,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(room_id,user_id,command_id)
);
ALTER TABLE mafia_message ADD COLUMN IF NOT EXISTS client_message_id VARCHAR(80);
CREATE UNIQUE INDEX IF NOT EXISTS idx_mafia_message_retry
  ON mafia_message(room_id,sender_player_id,client_message_id) WHERE client_message_id IS NOT NULL;
COMMIT;
