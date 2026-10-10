import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import { pool, q } from '../config/db.js';
import * as game from '../modules/games/knowledge.service.js';
import { advanceKnowledgeMatch, publishKnowledgeEvents, runKnowledgeCycle } from '../modules/games/knowledge-rounds.service.js';
import { KNOWLEDGE_DISTRICTS } from '../modules/games/knowledge-game.logic.js';
import { knowledgeAnswerBody } from '../modules/games/games.validators.js';
import { __realtimeGatewayTestApi } from '../shared/realtime/realtime-gateway.js';

let serial = 0;
test.after(() => pool.end());
async function fixture(size = 1) {
  await game.seedKnowledgeQuestionBank();
  const users = [];
  const tag = randomUUID().slice(0, 8);
  for (let i = 0; i < size * 2; i++) {
    const row = await q(`INSERT INTO app_user(full_name,phone,pin_hash,block,building_number,apartment,username,role)
      VALUES($1,$2,'x','A','1','1',$1,'user') RETURNING id`, [`qa_round_${tag}_${i}`, `0789${++serial}`]);
    users.push(Number(row.rows[0].id));
  }
  const room = await game.createDuel(users[0], { teamSize: size });
  for (const [i, user] of users.entries()) await game.joinKnowledgeRoomSeat(user, room.eventId, i < size ? 'a' : 'b');
  const matchId = Number((await q('SELECT id FROM maslaki_quiz_match WHERE event_id=$1', [room.eventId])).rows[0].id);
  await advanceKnowledgeMatch(matchId);
  return { users, matchId, room, snapshot: await game.knowledgeMatchSnapshot(users[0], matchId) };
}
async function openRound(f) {
  await q(`UPDATE maslaki_quiz_round SET starts_at=clock_timestamp()-INTERVAL '1 second',deadline_at=clock_timestamp()+INTERVAL '20 seconds',phase='question_open' WHERE id=$1`, [f.snapshot.round.id]);
  await q('UPDATE maslaki_quiz_match SET question_started_at=(SELECT starts_at FROM maslaki_quiz_round WHERE id=$2) WHERE id=$1', [f.matchId, f.snapshot.round.id]);
  f.snapshot = await game.knowledgeMatchSnapshot(f.users[0], f.matchId);
}
const input = (f, extra = {}) => ({ roundId: f.snapshot.round.id, questionId: f.snapshot.question.id,
  idempotencyKey: randomUUID(), answerIndex: 0, districtId: 'souk', ...extra });

test('explicit round validation never infers a question from an old client', () => {
  assert.equal(knowledgeAnswerBody({ answerIndex: 0, districtId: 'souk' }), null);
  assert.equal(knowledgeAnswerBody({ roundId: 1, questionId: 2, answerIndex: null, districtId: 'souk', idempotencyKey: randomUUID() }), null);
  assert.ok(knowledgeAnswerBody({ roundId: 1, questionId: 2, answerIndex: 0, districtId: 'souk', idempotencyKey: randomUUID() }));
});

test('countdown, membership, invalid choices, old questions and early answer privacy', async () => {
  const f = await fixture();
  assert.equal(f.snapshot.phase, 'countdown');
  assert.equal(f.snapshot.result, null);
  assert.equal(f.snapshot.question.answerIndex, undefined);
  assert.equal(f.snapshot.question.explanation, undefined);
  assert.equal(f.snapshot.question.scoring.territoryBonusPoints, 0);
  assert.equal(f.snapshot.question.scoring.maxSpeedBonus, 50);
  await assert.rejects(game.answerKnowledgeQuestion(f.users[0], f.matchId, input(f)), /QUESTION_NOT_OPEN/);
  await openRound(f);
  await assert.rejects(game.answerKnowledgeQuestion(f.users[0], f.matchId, input(f, { questionId: 999999 })), /STALE_QUESTION/);
  await assert.rejects(game.answerKnowledgeQuestion(f.users[0], f.matchId, input(f, { districtId: 'secret' })), /DISTRICT_INVALID/);
  await assert.rejects(game.answerKnowledgeQuestion(f.users[0], f.matchId, input(f, { answerIndex: 4 })), /ANSWER_INVALID/);
  await assert.rejects(game.answerKnowledgeQuestion(99999999, f.matchId, input(f)), /MATCH_NOT_FOUND_OR_FORBIDDEN/);
  const receipt = await game.answerKnowledgeQuestion(f.users[0], f.matchId, input(f));
  assert.equal(receipt.submitted, true);
  assert.equal(receipt.correct, undefined);
  const other = await game.knowledgeMatchSnapshot(f.users[1], f.matchId);
  assert.equal(other.ownAnswer, null);
  assert.equal(other.result, null);
  assert.equal(other.lastAnswer.submitted, 0);
});

test('simultaneous retries persist once, conflict clearly, and recover a lost reply', async () => {
  const f = await fixture(); await openRound(f);
  const body = input(f);
  const receipts = await Promise.all(Array.from({ length: 8 }, () => game.answerKnowledgeQuestion(f.users[0], f.matchId, body)));
  assert.ok(receipts.every(r => r.submitted));
  assert.equal((await q('SELECT COUNT(*)::int AS n FROM maslaki_quiz_submission WHERE round_id=$1', [body.roundId])).rows[0].n, 1);
  await assert.rejects(game.answerKnowledgeQuestion(f.users[0], f.matchId, { ...body, answerIndex: 1 }), /IDEMPOTENCY_CONFLICT/);
  await assert.rejects(game.answerKnowledgeQuestion(f.users[0], f.matchId, { ...body, idempotencyKey: randomUUID() }), /ANSWER_ALREADY_RECORDED/);
  assert.equal((await game.knowledgeAttemptStatus(f.users[0], f.matchId, body.idempotencyKey)).submitted, true);
  assert.equal((await game.knowledgeAttemptStatus(f.users[1], f.matchId, body.idempotencyKey)).submitted, false);
  assert.equal((await game.knowledgeMatchSnapshot(f.users[0], f.matchId)).ownAnswer.idempotencyKey, body.idempotencyKey);
});

test('all eight votes are required; two resolvers cannot score twice; results survive worker restart', async () => {
  const f = await fixture(4); await openRound(f);
  const correct = Number((await q('SELECT answer_index FROM maslaki_quiz_question WHERE id=$1', [f.snapshot.question.id])).rows[0].answer_index);
  await Promise.all(f.users.slice(0, 7).map(user => game.answerKnowledgeQuestion(user, f.matchId, input(f, { answerIndex: correct }))));
  await advanceKnowledgeMatch(f.matchId);
  assert.equal((await game.knowledgeMatchSnapshot(f.users[0], f.matchId)).phase, 'question_open');
  await game.answerKnowledgeQuestion(f.users[7], f.matchId, input(f, { answerIndex: correct }));
  await Promise.all([advanceKnowledgeMatch(f.matchId), advanceKnowledgeMatch(f.matchId)]);
  const result = await game.knowledgeMatchSnapshot(f.users[0], f.matchId);
  assert.equal(result.phase, 'round_result');
  assert.equal(result.result.correctAnswerIndex, correct);
  assert.ok(result.match.teams.a.score > 0);
  // Retain the existing A-first contested district rule until product approves a change.
  assert.deepEqual(result.match.territories.a, ['souk']);
  assert.deepEqual(result.match.territories.b, ['river']);
  await advanceKnowledgeMatch(f.matchId);
  assert.deepEqual((await game.knowledgeMatchSnapshot(f.users[0], f.matchId)).result, result.result);
  assert.equal((await q('SELECT COUNT(*)::int AS n FROM maslaki_quiz_answer WHERE match_id=$1', [f.matchId])).rows[0].n, 8);
  await q(`UPDATE maslaki_quiz_round SET next_at=NOW()-INTERVAL '1 second' WHERE id=$1`, [f.snapshot.round.id]);
  await runKnowledgeCycle({ publish: async () => {} });
  const resumed = await game.knowledgeMatchSnapshot(f.users[0], f.matchId);
  assert.equal(resumed.phase, 'countdown');
  assert.notEqual(resumed.question.id, f.snapshot.question.id);
  assert.ok(resumed.stateVersion > result.stateVersion);
  await assert.rejects(game.answerKnowledgeQuestion(f.users[0], f.matchId, input(f)), /ROUND_CLOSED/);
});

test('exclusive deadline gate includes an admitted but uncommitted answer', async () => {
  const f = await fixture(); await openRound(f);
  const client = await pool.connect();
  const body = input(f);
  try {
    await client.query('BEGIN');
    const saved = await client.query('SELECT maslaki_knowledge_accept_answer($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb) AS receipt',
      [f.users[0], f.matchId, body.roundId, body.questionId, body.idempotencyKey, 0, 'souk', 'gate-test',
        JSON.stringify(Object.fromEntries(KNOWLEDGE_DISTRICTS.map(d => [d.id, d.neighbors])))]);
    assert.equal(saved.rows[0].receipt.submitted, true);
    await game.answerKnowledgeQuestion(f.users[1], f.matchId, input(f));
    let finished = false;
    const closing = advanceKnowledgeMatch(f.matchId).then(() => { finished = true; });
    await new Promise(r => setTimeout(r, 50));
    assert.equal(finished, false);
    await client.query('COMMIT');
    await closing;
    const count = await q('SELECT COUNT(*)::int AS n FROM maslaki_quiz_answer WHERE match_id=$1 AND NOT is_timeout', [f.matchId]);
    assert.equal(count.rows[0].n, 2);
    assert.equal((await game.answerKnowledgeQuestion(f.users[0], f.matchId, body)).replayed, true);
  } finally { await client.query('ROLLBACK'); client.release(); }
});

test('a request waiting behind closure cannot be admitted using an earlier arrival timestamp', async () => {
  const f=await fixture(); await openRound(f);
  const locker=await pool.connect();
  try {
    await locker.query('BEGIN');
    await locker.query(`UPDATE maslaki_quiz_round SET finalized_at=clock_timestamp(),phase='round_result' WHERE id=$1`,[f.snapshot.round.id]);
    const waiting=game.answerKnowledgeQuestion(f.users[0],f.matchId,input(f)).catch(error=>error);
    await new Promise(resolve=>setTimeout(resolve,30));
    await locker.query('COMMIT');
    assert.match((await waiting).message,/ROUND_CLOSED/);
    assert.equal((await q('SELECT * FROM maslaki_quiz_submission WHERE round_id=$1',[f.snapshot.round.id])).rowCount,0);
  } finally {await locker.query('ROLLBACK');locker.release();}
});

test('failure after scoring rolls back the whole resolution; restart recovers once', async () => {
  const f=await fixture();await openRound(f);
  const correct=Number((await q('SELECT answer_index FROM maslaki_quiz_question WHERE id=$1',[f.snapshot.question.id])).rows[0].answer_index);
  await Promise.all(f.users.map(user=>game.answerKnowledgeQuestion(user,f.matchId,input(f,{answerIndex:correct}))));
  await q(`CREATE FUNCTION qa_fail_knowledge_result() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN
    IF NEW.event_name='knowledge_round_result' THEN RAISE EXCEPTION 'QA_CRASH_AFTER_SCORE'; END IF;RETURN NEW; END $$;
    CREATE TRIGGER qa_fail_knowledge_result BEFORE INSERT ON maslaki_quiz_event_outbox FOR EACH ROW EXECUTE FUNCTION qa_fail_knowledge_result()`);
  try {
    await assert.rejects(advanceKnowledgeMatch(f.matchId),/QA_CRASH_AFTER_SCORE/);
    const before=await game.knowledgeMatchSnapshot(f.users[0],f.matchId);
    assert.equal(before.match.teams.a.score,0);assert.equal(before.result,null);
    assert.equal(before.answered,true);
  } finally {await q('DROP TRIGGER qa_fail_knowledge_result ON maslaki_quiz_event_outbox; DROP FUNCTION qa_fail_knowledge_result()');}
  await advanceKnowledgeMatch(f.matchId);
  const after=await game.knowledgeMatchSnapshot(f.users[0],f.matchId);
  assert.ok(after.match.teams.a.score>0);
  await advanceKnowledgeMatch(f.matchId);
  assert.equal((await game.knowledgeMatchSnapshot(f.users[0],f.matchId)).match.teams.a.score,after.match.teams.a.score);
});

test('expired rounds progress without a read or a connected player, and events retry after failure', async () => {
  const f = await fixture(); await openRound(f);
  await q(`UPDATE maslaki_quiz_round SET starts_at=NOW()-INTERVAL '21 seconds',deadline_at=NOW()-INTERVAL '1 second' WHERE id=$1`, [f.snapshot.round.id]);
  await assert.rejects(game.answerKnowledgeQuestion(f.users[0], f.matchId, input(f)), /QUESTION_EXPIRED/);
  await runKnowledgeCycle({ publish: async () => { throw new Error('offline'); } });
  assert.equal((await game.knowledgeMatchSnapshot(f.users[0], f.matchId)).phase, 'round_result');
  const pending = await q('SELECT id FROM maslaki_quiz_event_outbox WHERE match_id=$1 AND published_at IS NULL', [f.matchId]);
  assert.ok(pending.rowCount > 0);
  await q('UPDATE maslaki_quiz_event_outbox SET retry_at=NOW() WHERE published_at IS NULL');
  const events = [];
  await Promise.all([publishKnowledgeEvents(async (ids, name, payload) => events.push({ ids, name, payload })),
    publishKnowledgeEvents(async (ids, name, payload) => events.push({ ids, name, payload }))]);
  assert.ok(events.length > 0);
  assert.ok(events.every(e => !('answerIndex' in e.payload) && !('correctAnswerIndex' in e.payload)));
  assert.equal((await q('SELECT id FROM maslaki_quiz_event_outbox WHERE match_id=$1 AND published_at IS NULL', [f.matchId])).rowCount, 0);
});

for (const size of [1, 4]) test(`full ${size}v${size} lifecycle finishes exactly once`, async () => {
  const f = await fixture(size);
  for (let round = 0; round < 8; round++) {
    await openRound(f);
    const correct = Number((await q('SELECT answer_index FROM maslaki_quiz_question WHERE id=$1', [f.snapshot.question.id])).rows[0].answer_index);
    const snapshots = await Promise.all(f.users.map(user => game.knowledgeMatchSnapshot(user, f.matchId)));
    await Promise.all(f.users.map((user, i) => game.answerKnowledgeQuestion(user, f.matchId,
      input(f, { answerIndex: i < size ? correct : (correct + 1) % 4, districtId: snapshots[i].match.availableDistricts[0]?.id || 'none' }))));
    await advanceKnowledgeMatch(f.matchId);
    const closed = await game.knowledgeMatchSnapshot(f.users[0], f.matchId);
    if (round < 4) assert.equal(closed.phase, 'round_result');
    else { assert.equal(closed.phase, 'finished'); assert.equal(closed.match.winnerTeamId, closed.match.teams.a.id); break; }
    await q('UPDATE maslaki_quiz_round SET next_at=NOW() WHERE id=$1', [f.snapshot.round.id]);
    await advanceKnowledgeMatch(f.matchId);
    f.snapshot = await game.knowledgeMatchSnapshot(f.users[0], f.matchId);
  }
  const again=await game.createDuel(f.users[0],{teamSize:size});
  assert.notEqual(again.eventId,f.room.eventId);
  const fresh=await game.getKnowledgeRoom(f.users[0],again.eventId);
  assert.equal(fresh.status,'registration');assert.equal(fresh.occupiedSeats,0);
  assert.equal((await q('SELECT * FROM maslaki_quiz_match WHERE event_id=$1',[again.eventId])).rowCount,0);
  const old=await game.knowledgeMatchSnapshot(f.users[0],f.matchId);
  assert.equal(old.phase,'finished');
});

test('a waiting player can free a seat without erasing the room or starting early',async()=>{
  const f=await fixture();
  const room=await game.createDuel(f.users[0],{teamSize:1});
  await game.joinKnowledgeRoomSeat(f.users[0],room.eventId,'a');
  await game.leaveKnowledgeRoomSeat(f.users[0],room.eventId);
  await game.leaveKnowledgeRoomSeat(f.users[0],room.eventId);
  const state=await game.getKnowledgeRoom(f.users[0],room.eventId);
  assert.equal(state.occupiedSeats,0);assert.equal(state.status,'registration');
  await assert.rejects(game.leaveKnowledgeRoomSeat(f.users[0],f.room.eventId),/ROOM_ALREADY_STARTED/);
});

test('team chat is private and public messages require every seated player consent', async () => {
  __realtimeGatewayTestApi.setModeResolver(() => 'sse_only');
  try {
    const f = await fixture(4);
    await game.sendKnowledgeChatMessage(f.users[0], f.matchId, { channel: 'team', body: 'QA private message' });
    assert.equal((await game.knowledgeMatchSnapshot(f.users[1], f.matchId)).chat.messages.length, 1);
    assert.equal((await game.knowledgeMatchSnapshot(f.users[4], f.matchId)).chat.messages.length, 0);
    await assert.rejects(game.knowledgeMatchSnapshot(99999999, f.matchId), /MATCH_NOT_FOUND_OR_FORBIDDEN/);
    for (const user of f.users.slice(0, 7)) await game.setKnowledgePublicChatConsent(user, f.matchId, true);
    await assert.rejects(game.sendKnowledgeChatMessage(f.users[0], f.matchId, { channel: 'public', body: 'QA public message' }), /PUBLIC_CHAT_NEEDS_BOTH_TEAMS/);
    await game.setKnowledgePublicChatConsent(f.users[7], f.matchId, true);
    await game.sendKnowledgeChatMessage(f.users[0], f.matchId, { channel: 'public', body: 'QA public message' });
    const publicState = await game.knowledgeMatchSnapshot(f.users[4], f.matchId);
    assert.equal(publicState.chat.publicEnabled, true);
    assert.deepEqual(publicState.chat.messages.map(m => m.channel), ['public']);
    await game.setKnowledgePublicChatConsent(f.users[7], f.matchId, false);
    assert.equal((await game.knowledgeMatchSnapshot(f.users[4], f.matchId)).chat.messages.length, 0);
    await assert.rejects(game.sendKnowledgeChatMessage(f.users[0], f.matchId, { channel: 'public', body: 'QA denied' }), /PUBLIC_CHAT_NEEDS_BOTH_TEAMS/);
  } finally { __realtimeGatewayTestApi.reset(); }
});

test('no-territory sentinel is accepted only after the server frontier is empty', async () => {
  const f = await fixture(); await openRound(f);
  await assert.rejects(game.answerKnowledgeQuestion(f.users[0], f.matchId, input(f, { districtId: 'none' })), /DISTRICT_INVALID/);
  await q(`INSERT INTO maslaki_quiz_territory(match_id,team_id,district_id)
    SELECT $1,$2,UNNEST($3::text[])`, [f.matchId, f.snapshot.match.teams.a.id, KNOWLEDGE_DISTRICTS.map(d => d.id)]);
  assert.equal((await game.knowledgeMatchSnapshot(f.users[0], f.matchId)).match.availableDistricts.length, 0);
  assert.equal((await game.answerKnowledgeQuestion(f.users[0], f.matchId, input(f, { districtId: 'none' }))).submitted, true);
});

test('historical protocol-one results remain readable without inventing a round', async () => {
  const f = await fixture();
  await q('DELETE FROM maslaki_quiz_round WHERE match_id=$1', [f.matchId]);
  await q(`UPDATE maslaki_quiz_match SET protocol_version=1,status='completed',
    score_a=100,score_b=50,winner_team_id=team_a_id WHERE id=$1`, [f.matchId]);
  const history = await game.knowledgeMatchSnapshot(f.users[0], f.matchId);
  assert.equal(history.phase, 'finished');
  assert.equal(history.match.teams.a.score, 100);
  assert.equal(history.match.winnerTeamId, history.match.teams.a.id);
  assert.equal(history.round, null);
  assert.equal(history.question, null);
  await q("UPDATE maslaki_quiz_match SET status='active' WHERE id=$1", [f.matchId]);
  await assert.rejects(game.knowledgeMatchSnapshot(f.users[0], f.matchId), /GAME_UPDATE_REQUIRED/);
});
