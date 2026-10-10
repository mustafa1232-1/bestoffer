BEGIN;

-- Knowledge answers: bounded lag compensation.
--
-- A player's speed is measured on their own device, from the moment the
-- question became visible to the tap (p_client_ms). The server never trusts it
-- blindly: the credited time is clamped to
--   [server_elapsed - 1500ms, server_elapsed]
-- so a slow network can win back at most 1.5s and a forged value can never
-- beat the time the server actually observed minus that same bound.
-- A tap made before the deadline that arrives up to 1.5s late is still accepted;
-- the resolver waits for that grace window before closing the round.
DROP FUNCTION IF EXISTS maslaki_knowledge_accept_answer(BIGINT,BIGINT,BIGINT,BIGINT,TEXT,INT,TEXT,TEXT,JSONB);

CREATE OR REPLACE FUNCTION maslaki_knowledge_accept_answer(
  p_user BIGINT, p_match BIGINT, p_round BIGINT, p_question BIGINT,
  p_key TEXT, p_answer INT, p_district TEXT, p_trace TEXT, p_adjacency JSONB,
  p_client_ms INT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
  r RECORD;
  previous maslaki_quiz_submission%ROWTYPE;
  receipt_time TIMESTAMPTZ := statement_timestamp();
  admission_time TIMESTAMPTZ;
  inserted_count INT;
  event_id BIGINT;
  lock_start TIMESTAMPTZ := clock_timestamp();
  lock_ms NUMERIC;
  grace INTERVAL := INTERVAL '1500 milliseconds';
  max_compensation_ms INT := 1500;
  server_ms INT;
  limit_ms INT;
  credited_ms INT;
BEGIN
  SELECT s.* INTO previous FROM maslaki_quiz_submission s
    WHERE s.user_id=p_user AND s.idempotency_key=p_key;
  IF FOUND THEN
    IF previous.round_id<>p_round OR previous.answer_index<>p_answer OR previous.district_id<>p_district
       OR NOT EXISTS(SELECT 1 FROM maslaki_quiz_round WHERE id=p_round AND match_id=p_match AND question_id=p_question) THEN
      RETURN jsonb_build_object('error','IDEMPOTENCY_CONFLICT');
    END IF;
    RETURN jsonb_build_object('submitted',TRUE,'roundId',p_round,'questionId',p_question,
      'idempotencyKey',p_key,'acceptedAt',previous.accepted_at,'replayed',TRUE,'traceId',previous.trace_id);
  END IF;
  SELECT rd.*, tm.team_id, m.team_a_id, m.team_b_id, m.status AS match_status, e.status AS event_status
    INTO r FROM maslaki_quiz_round rd
    JOIN maslaki_quiz_match m ON m.id=rd.match_id
    JOIN maslaki_quiz_event e ON e.id=m.event_id
    JOIN maslaki_quiz_team_member tm ON tm.user_id=p_user AND tm.team_id IN(m.team_a_id,m.team_b_id)
    WHERE rd.id=p_round AND rd.match_id=p_match FOR SHARE OF rd;
  lock_ms := EXTRACT(EPOCH FROM clock_timestamp()-lock_start)*1000;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','MATCH_NOT_FOUND_OR_FORBIDDEN'); END IF;
  IF r.question_id<>p_question THEN RETURN jsonb_build_object('error','STALE_QUESTION'); END IF;
  admission_time := clock_timestamp();
  IF r.finalized_at IS NOT NULL OR r.match_status<>'active' OR r.event_status<>'active' THEN
    RETURN jsonb_build_object('error','ROUND_CLOSED');
  END IF;
  IF receipt_time<r.starts_at THEN RETURN jsonb_build_object('error','QUESTION_NOT_OPEN'); END IF;
  IF p_answer IS NULL OR p_answer<0 OR p_answer>3 THEN RETURN jsonb_build_object('error','ANSWER_INVALID'); END IF;

  server_ms := GREATEST(0, EXTRACT(EPOCH FROM receipt_time-r.starts_at)*1000)::INT;
  limit_ms := (EXTRACT(EPOCH FROM r.deadline_at-r.starts_at)*1000)::INT;
  credited_ms := CASE WHEN p_client_ms IS NULL OR p_client_ms<0 THEN server_ms
    ELSE GREATEST(server_ms-max_compensation_ms, LEAST(server_ms, p_client_ms)) END;
  credited_ms := LEAST(30000, GREATEST(0, credited_ms));
  -- Inside the window: always accepted. Inside the grace tail: only when the
  -- credited tap time itself was before the deadline.
  IF admission_time>=r.deadline_at+grace
     OR (admission_time>=r.deadline_at AND credited_ms>=limit_ms) THEN
    RETURN jsonb_build_object('error','QUESTION_EXPIRED');
  END IF;

  IF p_district='none' THEN
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_adjacency) AS d(id)
      WHERE NOT EXISTS(SELECT 1 FROM maslaki_quiz_territory WHERE match_id=p_match AND district_id=d.id)
      AND (NOT EXISTS(SELECT 1 FROM maslaki_quiz_territory WHERE match_id=p_match AND team_id=r.team_id)
        OR EXISTS(SELECT 1 FROM maslaki_quiz_territory t WHERE t.match_id=p_match AND t.team_id=r.team_id
          AND (p_adjacency->t.district_id) ? d.id))) THEN
      RETURN jsonb_build_object('error','DISTRICT_INVALID');
    END IF;
  ELSIF NOT (p_adjacency ? p_district) OR EXISTS(
      SELECT 1 FROM maslaki_quiz_territory WHERE match_id=p_match AND district_id=p_district)
    OR (EXISTS(SELECT 1 FROM maslaki_quiz_territory WHERE match_id=p_match AND team_id=r.team_id)
      AND NOT EXISTS(SELECT 1 FROM maslaki_quiz_territory t
        WHERE t.match_id=p_match AND t.team_id=r.team_id AND (p_adjacency->t.district_id) ? p_district)) THEN
    RETURN jsonb_build_object('error','DISTRICT_INVALID');
  END IF;
  INSERT INTO maslaki_quiz_submission(round_id,user_id,team_id,idempotency_key,answer_index,district_id,
    received_at,accepted_at,response_ms,trace_id)
    VALUES(p_round,p_user,r.team_id,p_key,p_answer,p_district,receipt_time,admission_time,credited_ms,p_trace)
    ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS inserted_count=ROW_COUNT;
  IF inserted_count=0 THEN
    SELECT * INTO previous FROM maslaki_quiz_submission WHERE user_id=p_user AND idempotency_key=p_key;
    IF FOUND THEN
      IF previous.round_id=p_round AND previous.answer_index=p_answer AND previous.district_id=p_district THEN
        RETURN jsonb_build_object('submitted',TRUE,'roundId',p_round,'questionId',p_question,
          'idempotencyKey',p_key,'acceptedAt',previous.accepted_at,'replayed',TRUE,'traceId',previous.trace_id);
      END IF;
      RETURN jsonb_build_object('error','IDEMPOTENCY_CONFLICT');
    END IF;
    RETURN jsonb_build_object('error','ANSWER_ALREADY_RECORDED');
  END IF;
  INSERT INTO maslaki_quiz_event_outbox(match_id,round_id,state_version,event_name,payload)
    VALUES(p_match,p_round,r.state_version,'knowledge_answer_accepted',jsonb_build_object('traceId',p_trace,'recipientUserId',p_user)) RETURNING id INTO event_id;
  RETURN jsonb_build_object('submitted',TRUE,'roundId',p_round,'questionId',p_question,'idempotencyKey',p_key,
    'acceptedAt',admission_time,'traceId',p_trace,'eventId',event_id,'stateVersion',r.state_version,'gateMs',lock_ms,
    'creditedMs',credited_ms);
END $$;

-- Mafia: the interaction cooldown and mission progress look up a sender's
-- interactions on every request/snapshot.
CREATE INDEX IF NOT EXISTS idx_mafia_event_interaction_sender
  ON mafia_event (room_id,(payload->>'senderPlayerId'),created_at DESC)
  WHERE event_type='player_interaction';
CREATE INDEX IF NOT EXISTS idx_mafia_event_reports
  ON mafia_event (id DESC) WHERE event_type='player_reported';

COMMIT;
