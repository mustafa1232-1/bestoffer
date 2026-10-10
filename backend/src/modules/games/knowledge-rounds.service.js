import crypto from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { pool, q } from '../../config/db.js';
import { AppError } from '../../shared/utils/errors.js';
import { emitRealtimeToUsers } from '../../shared/realtime/realtime-gateway.js';
import { KNOWLEDGE_DISTRICTS, nextDistricts, knowledgeScoringRules } from './knowledge-game.logic.js';
import { KNOWLEDGE_CATEGORY_LABELS } from './knowledge.question-bank.js';
import { finalizeKnowledgeQuestionTx, knowledgeTieBreakTx, advanceTournamentTx } from './knowledge.service.js';
import { createWorkerLoop } from './games.worker-loop.js';

const adjacency = JSON.stringify(Object.fromEntries(KNOWLEDGE_DISTRICTS.map(d => [d.id, d.neighbors])));
// Must match the grace in maslaki_knowledge_accept_answer (sql/232): a tap made
// before the deadline may still be in flight, so the round closes a bit later.
export const KNOWLEDGE_ANSWER_GRACE_MS = 1500;
const duration = (start) => Math.round((performance.now() - start) * 1000) / 1000;

// These timings use one process clock. They contain no answers, names or tokens.
export async function acceptKnowledgeAnswer(userId, matchId, input, { traceId = crypto.randomUUID(), observe } = {}) {
  traceId = String(traceId || crypto.randomUUID()).slice(0, 100);
  if (!input.roundId || !input.questionId || !input.idempotencyKey) throw new AppError('GAME_UPDATE_REQUIRED', { status: 426 });
  const started = performance.now();
  const client = await pool.connect();
  const poolMs = duration(started);
  try {
    const queryStart = performance.now();
    // Autocommit finishes before pg resolves: an acknowledgement is durable, not optimistic.
    const result = await client.query('SELECT maslaki_knowledge_accept_answer($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10::int) AS receipt',
      [userId, matchId, input.roundId, input.questionId, input.idempotencyKey, input.answerIndex, input.districtId, traceId, adjacency,
        Number.isInteger(input.clientElapsedMs) ? input.clientElapsedMs : null]);
    const receipt = result.rows[0].receipt;
    const metric = { event: 'knowledge_answer_timing', traceId, matchId: Number(matchId), roundId: input.roundId,
      poolMs, queryCommitMs: duration(queryStart), totalMs: duration(started), gateMs: Number(receipt.gateMs || 0),
      code: receipt.error || 'ACCEPTED', queries: 1 };
    observe?.(metric);
    if (process.env.KNOWLEDGE_TIMING_LOGS === '1' || metric.totalMs > 500) console.info(JSON.stringify(metric));
    if (receipt.error) throw new AppError(receipt.error, { status: receipt.error === 'MATCH_NOT_FOUND_OR_FORBIDDEN' ? 404 : 409 });
    delete receipt.gateMs;
    if (!receipt.replayed) wakeKnowledgeWorkers();
    return receipt;
  } finally { client.release(); }
}

export async function knowledgeAttemptStatus(userId, matchId, key) {
  const result = await q(`SELECT s.round_id,s.idempotency_key,s.accepted_at,s.trace_id,r.question_id
    FROM maslaki_quiz_submission s JOIN maslaki_quiz_round r ON r.id=s.round_id
    JOIN maslaki_quiz_match m ON m.id=r.match_id
    JOIN maslaki_quiz_team_member tm ON tm.user_id=$1 AND tm.team_id IN(m.team_a_id,m.team_b_id)
    WHERE s.user_id=$1 AND r.match_id=$2 AND s.idempotency_key=$3`, [userId, matchId, key]);
  const row = result.rows[0];
  return row ? { submitted: true, roundId: Number(row.round_id), questionId: Number(row.question_id),
    idempotencyKey: row.idempotency_key, acceptedAt: row.accepted_at, traceId: row.trace_id } : { submitted: false };
}

async function journal(client, match, round, event, payload = {}) {
  await client.query(`INSERT INTO maslaki_quiz_event_outbox(match_id,round_id,state_version,event_name,payload)
    VALUES($1,$2,$3,$4,$5::jsonb)`, [match.id, round?.id || null, match.state_version, event, JSON.stringify(payload)]);
}

async function startRound(client, match) {
  const selected = await client.query(`WITH asked AS (
      SELECT COALESCE(q.fact_key,q.question_key) AS fact,q.category FROM maslaki_quiz_round r
      JOIN maslaki_quiz_question q ON q.id=r.question_id WHERE r.match_id=$1
    ), categories AS (SELECT category,COUNT(*) AS n FROM asked GROUP BY category)
    SELECT q.id,q.time_limit_seconds FROM maslaki_quiz_question q
    LEFT JOIN categories c ON c.category=q.category WHERE q.is_active
      AND NOT EXISTS(SELECT 1 FROM asked WHERE fact=COALESCE(q.fact_key,q.question_key))
    ORDER BY COALESCE(c.n,0),md5(q.id::text || ':' || $1::text || ':' || $2::text) LIMIT 1`, [match.id, match.question_number]);
  if (!selected.rowCount) throw new AppError('QUESTION_BANK_EMPTY', { status: 503 });
  const question = selected.rows[0];
  const updated = await client.query(`UPDATE maslaki_quiz_match SET status='active',current_question_id=$2,
    question_started_at=clock_timestamp()+INTERVAL '3 seconds',state_version=state_version+1,updated_at=NOW()
    WHERE id=$1 RETURNING *`, [match.id, question.id]);
  match = { ...match, ...updated.rows[0] };
  const round = (await client.query(`INSERT INTO maslaki_quiz_round(match_id,round_number,question_id,phase,starts_at,deadline_at,expected_answers,state_version)
    VALUES($1,$2,$3,'countdown',$4::timestamptz,$4::timestamptz+$5*INTERVAL '1 second',
      (SELECT COUNT(*) FROM maslaki_quiz_team_member WHERE team_id IN($6,$7)),$8) RETURNING *`,
  [match.id, match.question_number, question.id, match.question_started_at, question.time_limit_seconds, match.team_a_id, match.team_b_id, match.state_version])).rows[0];
  await journal(client, match, round, 'knowledge_round_started');
}

// Match NO KEY UPDATE deliberately permits FK KEY SHARE in concurrent accepts.
// The round's exclusive gate waits for every admitted submission to commit.
export async function advanceKnowledgeMatch(matchId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const selected = await client.query(`SELECT m.*,e.event_type,e.best_of FROM maslaki_quiz_match m
      JOIN maslaki_quiz_event e ON e.id=m.event_id WHERE m.id=$1 AND m.protocol_version=2
      AND m.status IN('pending','active') AND e.status='active' FOR NO KEY UPDATE OF m SKIP LOCKED`, [matchId]);
    const match = selected.rows[0];
    if (!match) { await client.query('COMMIT'); return false; }
    const round = (await client.query(`SELECT * FROM maslaki_quiz_round WHERE match_id=$1
      ORDER BY round_number DESC LIMIT 1 FOR UPDATE`, [match.id])).rows[0];
    if (!round) {
      await startRound(client, match);
    } else if (round.finalized_at) {
      const due = (await client.query('SELECT $1::timestamptz<=clock_timestamp() AS due', [round.next_at])).rows[0].due;
      if (due) {
        await client.query('UPDATE maslaki_quiz_round SET next_at=NULL WHERE id=$1', [round.id]);
        match.question_number = Number(match.question_number) + 1;
        if (round.result_json?.gameCompleted) {
          // Archive is committed with the last answer. Reset only after its
          // result interval, preserving the completed board for both clients.
          await client.query('DELETE FROM maslaki_quiz_territory WHERE match_id=$1', [match.id]);
          match.series_game = Number(match.series_game) + 1;
          match.game_start_question = match.question_number;
          await client.query(`UPDATE maslaki_quiz_match SET score_a=0,score_b=0,series_game=$2,
            game_start_question=$3 WHERE id=$1`, [match.id,match.series_game,match.game_start_question]);
        }
        await client.query('UPDATE maslaki_quiz_match SET question_number=$2 WHERE id=$1', [match.id, match.question_number]);
        await startRound(client, match);
      }
    } else {
      const state = (await client.query(`SELECT clock_timestamp()>=$2::timestamptz+${KNOWLEDGE_ANSWER_GRACE_MS}*INTERVAL '1 millisecond' AS expired,
        clock_timestamp()>=$3::timestamptz AS opened,COUNT(*)::int AS submitted
        FROM maslaki_quiz_submission WHERE round_id=$1`, [round.id, round.deadline_at, round.starts_at])).rows[0];
      if (state.expired || state.submitted >= round.expected_answers) {
        // Bulk materialization keeps the established voting/scoring/tiebreak rules.
        // Only the worker, after the exclusive gate, may write scoring inputs.
        await client.query(`INSERT INTO maslaki_quiz_answer(match_id,question_id,team_id,user_id,answer_index,
          district_id,is_timeout,response_ms,is_correct,points,answered_at)
          SELECT $1,$2,tm.team_id,tm.user_id,COALESCE(s.answer_index,0),COALESCE(s.district_id,'none'),
            s.user_id IS NULL,COALESCE(s.response_ms,q.time_limit_seconds*1000),FALSE,0,
            -- Speed and tie order use the lag-compensated credited time.
            COALESCE($7::timestamptz+s.response_ms*INTERVAL '1 millisecond',$5)
          FROM maslaki_quiz_team_member tm JOIN maslaki_quiz_question q ON q.id=$2
          LEFT JOIN maslaki_quiz_submission s ON s.user_id=tm.user_id AND s.round_id=$3
          WHERE tm.team_id IN($4,$6) ON CONFLICT(match_id,question_id,user_id) DO NOTHING`,
        [match.id, round.question_id, round.id, match.team_a_id, round.deadline_at, match.team_b_id, round.starts_at]);
        const outcome = await finalizeKnowledgeQuestionTx(client, match);
        if (!outcome) throw new Error('KNOWLEDGE_ROUND_INCOMPLETE');
        const scores = (await client.query('SELECT score_a,score_b FROM maslaki_quiz_match WHERE id=$1', [match.id])).rows[0];
        let gameWinner = null;
        if (Number(match.question_number) - Number(match.game_start_question) + 1 >= 5) {
          gameWinner = Number(scores.score_a) > Number(scores.score_b) ? match.team_a_id
            : Number(scores.score_b) > Number(scores.score_a) ? match.team_b_id : await knowledgeTieBreakTx(client, match);
        }
        let winner = null;
        if (gameWinner != null) {
          await client.query(`INSERT INTO maslaki_quiz_series_game(match_id,game_number,winner_team_id,
            score_a,score_b,territories,first_question,last_question)
            VALUES($1,$2,$3,$4,$5,COALESCE((SELECT jsonb_agg(jsonb_build_object('districtId',district_id,'teamId',team_id))
              FROM maslaki_quiz_territory WHERE match_id=$1),'[]'::jsonb),$6,$7)`,
          [match.id,match.series_game,gameWinner,scores.score_a,scores.score_b,match.game_start_question,match.question_number]);
          match.wins_a = Number(match.wins_a) + (Number(gameWinner) === Number(match.team_a_id) ? 1 : 0);
          match.wins_b = Number(match.wins_b) + (Number(gameWinner) === Number(match.team_b_id) ? 1 : 0);
          await client.query('UPDATE maslaki_quiz_match SET wins_a=$2,wins_b=$3 WHERE id=$1', [match.id,match.wins_a,match.wins_b]);
          const target = Math.floor(Number(match.best_of)/2)+1;
          if (match.wins_a >= target || match.wins_b >= target) winner = gameWinner;
        }
        const version = Number(match.state_version) + 1;
        const answer = (await client.query('SELECT answer_index FROM maslaki_quiz_question WHERE id=$1', [round.question_id])).rows[0];
        const result = { ...outcome, correctAnswerIndex: Number(answer.answer_index), winnerTeamId: winner == null ? null : Number(winner),
          gameCompleted: gameWinner != null, gameWinnerTeamId: gameWinner == null ? null : Number(gameWinner),
          gameNumber: Number(match.series_game), winsA: Number(match.wins_a), winsB: Number(match.wins_b),
          scoreA: Number(scores.score_a), scoreB: Number(scores.score_b) };
        await client.query(`UPDATE maslaki_quiz_round SET finalized_at=clock_timestamp(),phase='round_result',
          result_json=$2::jsonb,state_version=$3,next_at=CASE WHEN $4 THEN NULL
            ELSE clock_timestamp()+$5*INTERVAL '1 second' END WHERE id=$1`,
        [round.id, JSON.stringify(result), version, winner != null, gameWinner != null ? 6 : 3]);
        await client.query(`UPDATE maslaki_quiz_match SET state_version=$2,status=CASE WHEN $3::bigint IS NULL THEN 'active' ELSE 'completed' END,
          winner_team_id=$3,updated_at=NOW() WHERE id=$1`, [match.id, version, winner]);
        await journal(client, { ...match, state_version: version }, round, winner ? 'knowledge_match_finished' : 'knowledge_round_result', result);
        if (winner && match.event_type === 'tournament') await advanceTournamentTx(client, Number(match.event_id), Number(match.round_number));
        if (winner && match.event_type === 'duel') await client.query(`UPDATE maslaki_quiz_event SET status='completed',champion_team_id=$2 WHERE id=$1`, [match.event_id, winner]);
      } else if (round.phase === 'countdown' && state.opened) {
        await client.query(`UPDATE maslaki_quiz_round SET phase='question_open' WHERE id=$1`, [round.id]);
        await journal(client, match, round, 'knowledge_question_open');
      }
    }
    await client.query('COMMIT');
    return true;
  } catch (error) { await client.query('ROLLBACK'); throw error; }
  finally { client.release(); }
}

export async function publishKnowledgeEvents(publish = emitRealtimeToUsers) {
  // A short DB lease, not a transaction held across network publication.
  const batch = await q(`UPDATE maslaki_quiz_event_outbox SET retry_at=NOW()+INTERVAL '30 seconds',attempts=attempts+1
    WHERE id IN(SELECT id FROM maslaki_quiz_event_outbox WHERE published_at IS NULL AND retry_at<=NOW()
      ORDER BY id LIMIT 64 FOR UPDATE SKIP LOCKED) RETURNING *`);
  const delivered = await Promise.allSettled(batch.rows.map(async event => {
    try {
      const members = await q(`SELECT tm.user_id FROM maslaki_quiz_team_member tm JOIN maslaki_quiz_match m
        ON tm.team_id IN(m.team_a_id,m.team_b_id) WHERE m.id=$1`, [event.match_id]);
      const ids = members.rows.map(row => Number(row.user_id));
      const payload = { eventId: Number(event.id), matchId: Number(event.match_id), roundId: Number(event.round_id),
        stateVersion: Number(event.state_version) };
      if (event.event_name === 'knowledge_answer_accepted') {
        const recipient = Number(event.payload.recipientUserId);
        if (ids.includes(recipient)) await publish([recipient], event.event_name, { ...payload, traceId: event.payload.traceId }, { requireDurable: true });
        await publish(ids, 'knowledge_match_updated', payload, { requireDurable: true });
      } else { await publish(ids, event.event_name, payload, { requireDurable: true }); }
      await q('UPDATE maslaki_quiz_event_outbox SET published_at=clock_timestamp() WHERE id=$1', [event.id]);
    } catch (error) {
      await q(`UPDATE maslaki_quiz_event_outbox SET retry_at=NOW()+LEAST(30,POWER(2,LEAST(attempts,5)))*INTERVAL '1 second' WHERE id=$1`, [event.id]);
      throw error;
    }
  }));
  return { events: batch.rowCount, failed: delivered.filter(item => item.status === 'rejected').length };
}

export async function runKnowledgeCycle({ publish = emitRealtimeToUsers } = {}) {
  const work = await q(`SELECT m.id FROM maslaki_quiz_match m LEFT JOIN LATERAL
    (SELECT * FROM maslaki_quiz_round WHERE match_id=m.id ORDER BY round_number DESC LIMIT 1) r ON TRUE
    WHERE m.protocol_version=2 AND m.status IN('pending','active') AND
      (r.id IS NULL OR (r.phase='countdown' AND r.starts_at<=NOW()) OR
       (r.finalized_at IS NULL AND (r.deadline_at+${KNOWLEDGE_ANSWER_GRACE_MS}*INTERVAL '1 millisecond'<=NOW() OR
         (SELECT COUNT(*) FROM maslaki_quiz_submission s WHERE s.round_id=r.id)>=r.expected_answers)) OR r.next_at<=NOW())
    ORDER BY m.updated_at,m.id LIMIT 64`);
  const failures = [];
  let advanced = 0;
  for (let offset = 0; offset < work.rows.length; offset += 4) {
    const results = await Promise.allSettled(work.rows.slice(offset, offset + 4).map(row => advanceKnowledgeMatch(row.id)));
    failures.push(...results.filter(item => item.status === 'rejected'));
    advanced += results.filter(item => item.status === 'fulfilled' && item.value === true).length;
  }
  const outbox = publish ? await publishKnowledgeEvents(publish) : { events: 0, failed: 0 };
  if (failures.length || outbox.failed) console.warn(JSON.stringify({ event: 'knowledge_worker_retry', failures: failures.length, unpublished: outbox.failed }));
  return { processed: work.rowCount, advanced, failures: failures.length, ...outbox };
}

// Milliseconds until the earliest timer of any live match: a countdown that
// opens, a deadline (+grace) that closes, or a result screen that advances.
async function nextKnowledgeDueMs() {
  const due = await q(`SELECT GREATEST(0,EXTRACT(EPOCH FROM MIN(t)-clock_timestamp())*1000)::int AS ms FROM (
      SELECT CASE WHEN r.finalized_at IS NULL AND r.phase='countdown' THEN r.starts_at
        WHEN r.finalized_at IS NULL THEN r.deadline_at+${KNOWLEDGE_ANSWER_GRACE_MS}*INTERVAL '1 millisecond'
        ELSE r.next_at END AS t
      FROM maslaki_quiz_match m JOIN LATERAL
        (SELECT * FROM maslaki_quiz_round WHERE match_id=m.id ORDER BY round_number DESC LIMIT 1) r ON TRUE
      WHERE m.protocol_version=2 AND m.status IN('pending','active')) due WHERE t IS NOT NULL`);
  const ms = due.rows[0]?.ms;
  return ms == null ? null : Number(ms);
}

const knowledgeLoop = createWorkerLoop('knowledge_worker', async () => {
  const result = await runKnowledgeCycle({ publish: null });
  if (result.advanced > 0) {
    knowledgePublisher.wake();
    return { busy: true, failed: result.failures };
  }
  return { nextDueMs: await nextKnowledgeDueMs(), failed: result.failures };
});
// A slow broadcast provider must not stop deadlines or authoritative scoring.
const knowledgePublisher = createWorkerLoop('knowledge_publish', async () => {
  const result = await publishKnowledgeEvents();
  return { busy: result.events > 0, failed: result.failed };
}, { maxDelayMs: 750 });

// Called after a committed answer: an all-answered round resolves immediately
// and the acknowledgement fan-out does not wait for the next poll.
export function wakeKnowledgeWorkers() {
  knowledgeLoop.wake();
  knowledgePublisher.wake();
}
export function startKnowledgeWorker() {
  knowledgeLoop.start();
  knowledgePublisher.start();
}
export async function stopKnowledgeWorker() { await Promise.allSettled([knowledgeLoop.stop(), knowledgePublisher.stop()]); }

export async function readKnowledgeSnapshot(userId, matchId) {
  // One MVCC snapshot, no writes and no row locks in the read path.
  const result = await q(`SELECT m.*,e.title,e.event_type,e.team_size,e.best_of,tm.team_id AS my_team_id,
    ta.team_name AS team_a_name,tb.team_name AS team_b_name,statement_timestamp() AS server_time,
    to_jsonb(rd)-'result_json' AS round_data,CASE WHEN rd.finalized_at IS NOT NULL THEN rd.result_json END AS result,
    jsonb_build_object('id',qu.id,'category',qu.category,'difficulty',qu.difficulty,'text',qu.question_ar,
      'options',qu.options_json,'timeLimitSeconds',qu.time_limit_seconds) AS question,
    (SELECT jsonb_agg(jsonb_build_object('userId',x.user_id,'teamId',x.team_id,'name',u.full_name) ORDER BY x.joined_at,x.user_id)
      FROM maslaki_quiz_team_member x JOIN app_user u ON u.id=x.user_id WHERE x.team_id IN(m.team_a_id,m.team_b_id)) AS members,
    (SELECT jsonb_agg(jsonb_build_object('districtId',t.district_id,'teamId',t.team_id)) FROM maslaki_quiz_territory t WHERE t.match_id=m.id) AS territories,
    (SELECT jsonb_agg(jsonb_build_object('number',g.game_number,'winnerTeamId',g.winner_team_id,
      'scoreA',g.score_a,'scoreB',g.score_b) ORDER BY g.game_number)
      FROM maslaki_quiz_series_game g WHERE g.match_id=m.id) AS games,
    (SELECT jsonb_build_object('roundId',s.round_id,'questionId',rd.question_id,'idempotencyKey',s.idempotency_key,
      'answerIndex',s.answer_index,'districtId',s.district_id,'acceptedAt',s.accepted_at,'submitted',TRUE)
      FROM maslaki_quiz_submission s WHERE s.round_id=rd.id AND s.user_id=$1) AS own_answer,
    (SELECT COUNT(*)::int FROM maslaki_quiz_submission s WHERE s.round_id=rd.id AND s.team_id=tm.team_id) AS submitted,
    (SELECT jsonb_agg(to_jsonb(c)) FROM (SELECT c.id,c.channel,c.user_id AS "userId",c.body,u.full_name AS name,c.created_at AS "createdAt"
      FROM maslaki_quiz_chat_message c JOIN app_user u ON u.id=c.user_id WHERE c.match_id=m.id
      AND(c.channel='public' OR c.team_id=tm.team_id) ORDER BY c.id DESC LIMIT 40) c) AS messages,
    (SELECT jsonb_agg(to_jsonb(c)) FROM maslaki_quiz_chat_consent c WHERE c.match_id=m.id) AS consents,
    (SELECT jsonb_agg(to_jsonb(r)) FROM (SELECT r.id,r.kind,r.user_id AS "userId",u.full_name AS name
      FROM maslaki_quiz_reaction r JOIN app_user u ON u.id=r.user_id WHERE r.match_id=m.id AND r.created_at>NOW()-INTERVAL '12 seconds'
      ORDER BY r.id DESC LIMIT 24) r) AS reactions
    FROM maslaki_quiz_match m JOIN maslaki_quiz_event e ON e.id=m.event_id
    JOIN maslaki_quiz_team_member tm ON tm.user_id=$1 AND tm.team_id IN(m.team_a_id,m.team_b_id)
    LEFT JOIN maslaki_quiz_team ta ON ta.id=m.team_a_id LEFT JOIN maslaki_quiz_team tb ON tb.id=m.team_b_id
    LEFT JOIN LATERAL(SELECT * FROM maslaki_quiz_round WHERE match_id=m.id ORDER BY round_number DESC LIMIT 1) rd ON TRUE
    LEFT JOIN maslaki_quiz_question qu ON qu.id=rd.question_id WHERE m.id=$2`, [userId, matchId]);
  const m = result.rows[0];
  if (!m) throw new AppError('MATCH_NOT_FOUND_OR_FORBIDDEN', { status: 404 });
  // Historical results are read-only and remain viewable after the cutover.
  // An active legacy match cannot safely infer the new explicit round contract.
  if (Number(m.protocol_version) !== 2 && m.status !== 'completed') throw new AppError('GAME_UPDATE_REQUIRED', { status: 426 });
  const members = m.members || [];
  const territories = m.territories || [];
  const side = Number(m.my_team_id) === Number(m.team_a_id) ? 'a' : 'b';
  const team = (s) => ({ id: Number(m[`team_${s}_id`]), name: m[`team_${s}_name`], score: Number(m[`score_${s}`]),
    members: members.filter(x => Number(x.teamId) === Number(m[`team_${s}_id`])).map(x => ({ id: Number(x.userId), name: x.name })) });
  const owned = (s) => territories.filter(x => Number(x.teamId) === Number(m[`team_${s}_id`])).map(x => x.districtId);
  const consent = (teamId) => {
    const people = members.filter(x => Number(x.teamId) === Number(teamId));
    const optedIn = people.filter(x => (m.consents || []).some(c => Number(c.user_id) === Number(x.userId) && c.enabled)).length;
    return { optedIn, total: people.length, required: people.length, open: people.length > 0 && optedIn === people.length };
  };
  const publicEnabled = consent(m.team_a_id).open && consent(m.team_b_id).open;
  const rd = m.round_data;
  const phase = m.status === 'completed' ? 'finished' : !rd ? 'waiting' : rd.finalized_at ? 'round_result'
    : new Date(m.server_time) < new Date(rd.starts_at) ? 'countdown'
      : new Date(m.server_time) >= new Date(rd.deadline_at) ? 'resolving' : 'question_open';
  return { protocolVersion: 2, myUserId: Number(userId), stateVersion: Number(m.state_version), serverTime: m.server_time, phase,
    round: rd ? { id: Number(rd.id), number: Number(rd.round_number), startsAt: rd.starts_at, deadlineAt: rd.deadline_at, nextAt: rd.next_at } : null,
    match: { id: Number(m.id), eventId: Number(m.event_id), eventTitle: m.title, eventType: m.event_type,
      round: Number(m.round_number), matchNumber: Number(m.match_number), questionNumber: Number(m.question_number)-Number(m.game_start_question),
      totalQuestionNumber: Number(m.question_number), questionsPerGame: 5,
      series: { bestOf: Number(m.best_of), winsRequired: Math.floor(Number(m.best_of)/2)+1,
        game: Number(m.series_game), winsA: Number(m.wins_a), winsB: Number(m.wins_b), games: m.games || [] },
      status: m.status, teamSize: Number(m.team_size), mySide: side, winnerTeamId: m.winner_team_id == null ? null : Number(m.winner_team_id),
      teams: { a: team('a'), b: team('b') }, territories: { a: owned('a'), b: owned('b') }, districts: KNOWLEDGE_DISTRICTS,
      availableDistricts: nextDistricts(KNOWLEDGE_DISTRICTS, owned(side)).filter(d => !territories.some(t => t.districtId === d.id)) },
    // The question body stays on the server until the shared start instant; the
    // board shows "get ready" during the countdown anyway.
    question: m.question?.id ? { ...m.question, ...(phase === 'countdown' ? { text: null, options: [] } : {}), id: Number(m.question.id), scoring: knowledgeScoringRules(m.question.difficulty), categoryLabel: KNOWLEDGE_CATEGORY_LABELS[m.question.category] || 'المعرفة' } : null,
    answered: m.own_answer != null, ownAnswer: m.own_answer, lastAnswer: { submitted: m.submitted, total: team(side).members.length }, result: m.result,
    chat: { messages: (m.messages || []).reverse().filter(x => x.channel === 'team' || publicEnabled), publicEnabled,
      consent: { enabled: (m.consents || []).some(c => Number(c.user_id) === Number(userId) && c.enabled),
        ownTeam: consent(m.my_team_id), opponentTeam: consent(side === 'a' ? m.team_b_id : m.team_a_id) }, reactions: (m.reactions || []).reverse() } };
}
