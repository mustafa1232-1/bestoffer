-- Keep old clients on WebRTC. 'auto' upgrades only when the callee opts in.
ALTER TABLE social_call_session ADD COLUMN IF NOT EXISTS voice_transport TEXT NOT NULL DEFAULT 'webrtc'
  CHECK (voice_transport IN ('webrtc', 'auto', 'livekit'));

CREATE TABLE IF NOT EXISTS social_call_voice_cleanup (
  session_id BIGINT PRIMARY KEY REFERENCES social_call_session(id) ON DELETE CASCADE,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION queue_social_call_voice_cleanup() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.voice_transport = 'livekit' AND NEW.status IN ('ended', 'declined', 'missed') THEN
    INSERT INTO social_call_voice_cleanup(session_id) VALUES (NEW.id)
      ON CONFLICT (session_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS social_call_voice_cleanup_trigger ON social_call_session;
CREATE TRIGGER social_call_voice_cleanup_trigger AFTER UPDATE OF status ON social_call_session
  FOR EACH ROW EXECUTE FUNCTION queue_social_call_voice_cleanup();
