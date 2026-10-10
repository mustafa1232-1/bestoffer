BEGIN;

-- Existing matches remain protocol 1. New clients/matches opt into the explicit
-- round contract; a questionless legacy answer must never target a newer round.
ALTER TABLE maslaki_quiz_match ADD COLUMN IF NOT EXISTS protocol_version SMALLINT NOT NULL DEFAULT 1;
ALTER TABLE maslaki_quiz_match ALTER COLUMN protocol_version SET DEFAULT 2;
UPDATE maslaki_quiz_match SET protocol_version=2 WHERE status='pending';
CREATE TABLE IF NOT EXISTS maslaki_quiz_round (
  id BIGSERIAL PRIMARY KEY,
  match_id BIGINT NOT NULL REFERENCES maslaki_quiz_match(id) ON DELETE CASCADE,
  round_number INT NOT NULL,
  question_id BIGINT NOT NULL REFERENCES maslaki_quiz_question(id),
  phase TEXT NOT NULL CHECK (phase IN ('countdown','question_open','round_result')),
  starts_at TIMESTAMPTZ NOT NULL,
  deadline_at TIMESTAMPTZ NOT NULL,
  next_at TIMESTAMPTZ,
  expected_answers SMALLINT NOT NULL,
  state_version INT NOT NULL,
  finalized_at TIMESTAMPTZ,
  result_json JSONB,
  UNIQUE(match_id, round_number),
  UNIQUE(match_id, question_id),
  CHECK (deadline_at > starts_at)
);
CREATE INDEX IF NOT EXISTS idx_knowledge_round_work ON maslaki_quiz_round(phase, deadline_at, next_at)
  WHERE finalized_at IS NULL OR next_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS maslaki_quiz_submission (
  round_id BIGINT NOT NULL REFERENCES maslaki_quiz_round(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  team_id BIGINT NOT NULL REFERENCES maslaki_quiz_team(id) ON DELETE CASCADE,
  idempotency_key VARCHAR(80) NOT NULL,
  answer_index SMALLINT NOT NULL CHECK (answer_index BETWEEN 0 AND 3),
  district_id VARCHAR(40) NOT NULL,
  received_at TIMESTAMPTZ NOT NULL,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  response_ms INT NOT NULL CHECK(response_ms BETWEEN 0 AND 30000),
  trace_id VARCHAR(100),
  PRIMARY KEY(round_id,user_id),
  UNIQUE(user_id,idempotency_key)
);

-- This journal is written in the state transaction and drained after commit.
-- Unpublished events survive a crash; clients deduplicate by its increasing id.
CREATE TABLE IF NOT EXISTS maslaki_quiz_event_outbox (
  id BIGSERIAL PRIMARY KEY,
  match_id BIGINT NOT NULL REFERENCES maslaki_quiz_match(id) ON DELETE CASCADE,
  round_id BIGINT REFERENCES maslaki_quiz_round(id) ON DELETE CASCADE,
  state_version INT NOT NULL,
  event_name TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  published_at TIMESTAMPTZ,
  retry_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  attempts INT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_knowledge_event_pending ON maslaki_quiz_event_outbox(retry_at,id) WHERE published_at IS NULL;

-- One client round trip, concurrent shared admission gates. The resolver takes
-- FOR UPDATE on the round, so it waits for every accepted insert to commit and
-- no answer can slip in after closure. Do not update match/round counters here:
-- upgrading all these shared locks would serialize answers or deadlock.
CREATE OR REPLACE FUNCTION maslaki_knowledge_accept_answer(
  p_user BIGINT, p_match BIGINT, p_round BIGINT, p_question BIGINT,
  p_key TEXT, p_answer INT, p_district TEXT, p_trace TEXT, p_adjacency JSONB
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
  -- Recheck after acquiring the gate: a resolver may have closed it while this
  -- statement waited. Scoring uses DB statement receipt, never a client clock.
  admission_time := clock_timestamp();
  IF r.finalized_at IS NOT NULL OR r.match_status<>'active' OR r.event_status<>'active' THEN
    RETURN jsonb_build_object('error','ROUND_CLOSED');
  END IF;
  IF receipt_time<r.starts_at THEN RETURN jsonb_build_object('error','QUESTION_NOT_OPEN'); END IF;
  IF admission_time>=r.deadline_at THEN RETURN jsonb_build_object('error','QUESTION_EXPIRED'); END IF;
  IF p_answer IS NULL OR p_answer<0 OR p_answer>3 THEN RETURN jsonb_build_object('error','ANSWER_INVALID'); END IF;
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
    VALUES(p_round,p_user,r.team_id,p_key,p_answer,p_district,receipt_time,admission_time,
      LEAST(30000,GREATEST(0,EXTRACT(EPOCH FROM receipt_time-r.starts_at)*1000))::INT,p_trace)
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
    'acceptedAt',admission_time,'traceId',p_trace,'eventId',event_id,'stateVersion',r.state_version,'gateMs',lock_ms);
END $$;
COMMIT;
