import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { pool,q } from '../config/db.js';
import * as game from '../modules/games/knowledge.service.js';
import { advanceKnowledgeMatch } from '../modules/games/knowledge-rounds.service.js';
import { knowledgeDuelBody,knowledgeTournamentBody } from '../modules/games/games.validators.js';

test.after(()=>pool.end());
async function user() {
  const tag=randomUUID().replaceAll('-','').slice(0,12);
  return Number((await q(`INSERT INTO app_user(full_name,username,phone,pin_hash,block,building_number,apartment,role)
    VALUES($1,$1,$2,'x','A','1','1','user') RETURNING id`,['series_'+tag,'qa_'+tag])).rows[0].id);
}
async function duel(bestOf) {
  await game.seedKnowledgeQuestionBank();
  const users=[await user(),await user()];
  const room=await game.createDuel(users[0],{teamSize:1,bestOf});
  await game.joinKnowledgeRoomSeat(users[0],room.eventId,'a');
  await game.joinKnowledgeRoomSeat(users[1],room.eventId,'b');
  const matchId=Number((await q('SELECT id FROM maslaki_quiz_match WHERE event_id=$1',[room.eventId])).rows[0].id);
  await advanceKnowledgeMatch(matchId);
  return {users,matchId,eventId:room.eventId};
}
async function next(f) {
  await q(`UPDATE maslaki_quiz_round SET next_at=NOW()-INTERVAL '1 second' WHERE match_id=$1 AND next_at IS NOT NULL`,[f.matchId]);
  await advanceKnowledgeMatch(f.matchId);
  return game.knowledgeMatchSnapshot(f.users[0],f.matchId);
}
async function answer(f,winner) {
  let s=await game.knowledgeMatchSnapshot(f.users[0],f.matchId);
  await q(`UPDATE maslaki_quiz_round SET starts_at=NOW()-INTERVAL '1 second',deadline_at=NOW()+INTERVAL '25 seconds',phase='question_open' WHERE id=$1`,[s.round.id]);
  await q('UPDATE maslaki_quiz_match SET question_started_at=(SELECT starts_at FROM maslaki_quiz_round WHERE id=$2) WHERE id=$1',[f.matchId,s.round.id]);
  const correct=Number((await q('SELECT answer_index FROM maslaki_quiz_question WHERE id=$1',[s.question.id])).rows[0].answer_index);
  for(let i=0;i<2;i++) {
    s=await game.knowledgeMatchSnapshot(f.users[i],f.matchId);
    await game.answerKnowledgeQuestion(f.users[i],f.matchId,{roundId:s.round.id,questionId:s.question.id,
      answerIndex:(i===(winner==='a'?0:1))?correct:(correct+1)%4,
      districtId:s.match.availableDistricts[0]?.id || 'none',idempotencyKey:randomUUID()});
  }
  await Promise.all([advanceKnowledgeMatch(f.matchId),advanceKnowledgeMatch(f.matchId)]);
  return game.knowledgeMatchSnapshot(f.users[0],f.matchId);
}

test('series validators retain legacy omission and reject even or excessive counts',()=>{
  assert.equal(knowledgeDuelBody({}).bestOf,1);
  for(const bestOf of [3,5,9]) {
    assert.equal(knowledgeDuelBody({bestOf}).bestOf,bestOf);
    assert.equal(knowledgeTournamentBody({title:'بطولة',teamSize:4,maxTeams:12,bestOf}).bestOf,bestOf);
  }
  for(const bestOf of [0,2,4,7,10,'oops']) assert.equal(knowledgeDuelBody({bestOf}),null);
});

for(const [bestOf,winners] of [[3,['a','a']],[3,['a','b','b']],[5,['a','b','a','b','a']],[9,['a','b','a','b','a','b','a','b','b']]]) {
  test(`best of ${bestOf}: ${winners.join('')} persists, resets boards and ends only on majority`,async()=>{
    const f=await duel(bestOf);
    let s;
    const questions=new Set();
    for(let g=0;g<winners.length;g++) {
      for(let question=0;question<5;question++) {
        s=await answer(f,winners[g]);
        assert.equal(s.match.series.game,g+1);
        assert.equal(s.match.questionNumber,question);
        assert.equal(questions.has(s.question.id),false); questions.add(s.question.id);
        if(question<4) { assert.equal(s.result.gameCompleted,false); await next(f); }
      }
      assert.equal(s.result.gameCompleted,true);
      assert.equal(s.match.series.games.length,g+1);
      assert.equal(s.match.status,g===winners.length-1?'completed':'active');
      if(g<winners.length-1) {
        s=await next(f);
        assert.equal(s.match.teams.a.score,0); assert.equal(s.match.teams.b.score,0);
        assert.deepEqual(s.match.territories,{a:[],b:[]}); assert.equal(s.match.questionNumber,0);
      }
    }
    const winner=s.match.teams[winners.at(-1)].id;
    assert.equal(s.match.winnerTeamId,winner);
    assert.equal(Number((await q('SELECT champion_team_id FROM maslaki_quiz_event WHERE id=$1',[f.eventId])).rows[0].champion_team_id),winner);
    await advanceKnowledgeMatch(f.matchId);
    assert.equal((await game.knowledgeMatchSnapshot(f.users[0],f.matchId)).match.series.games.length,winners.length);
    const facts=(await q(`SELECT COALESCE(q.fact_key,q.question_key) AS fact FROM maslaki_quiz_round r
      JOIN maslaki_quiz_question q ON q.id=r.question_id WHERE r.match_id=$1`,[f.matchId])).rows;
    assert.equal(new Set(facts.map(r=>r.fact)).size,facts.length);
  });
}

test('tie break excludes previous games even when the previous winner has more correct answers',async()=>{
  const f=await duel(3);
  for(let i=0;i<5;i++){await answer(f,'a');await next(f);}
  const s=await answer(f,'b');
  const m=(await q('SELECT * FROM maslaki_quiz_match WHERE id=$1',[f.matchId])).rows[0];
  assert.equal(Number(await game.knowledgeTieBreakTx({query:q},m)),s.match.teams.b.id);
});

test('12-team bracket exposes all 15 slots, fair byes and no private match access; champion advances once',async()=>{
  const users=[];for(let i=0;i<13;i++)users.push(await user());
  const actor={userId:users[0],canManageGames:true};
  const event=await game.createKnowledgeTournament(actor,{title:'بطولة الاختبار',teamSize:1,maxTeams:12,bestOf:3});
  for(let i=0;i<12;i++) await game.registerTeam(users[i],event.id,`فريق ${i+1}`);
  assert.equal((await game.readKnowledgeBracket(users[12],event.id)).rounds.length,0);
  await game.startKnowledgeTournament(actor,event.id);
  let bracket=await game.readKnowledgeBracket(users[12],event.id);
  assert.deepEqual(bracket.rounds.map(r=>r.matches.length),[8,4,2,1]);
  assert.equal(bracket.rounds[0].matches.filter(m=>m.status==='bye').length,4);
  assert.equal(bracket.rounds.flatMap(r=>r.matches).some(m=>m.canPlay),false);
  assert.equal(JSON.stringify(bracket).includes('joinCode'),false);
  const actual=bracket.rounds[0].matches.find(m=>m.status==='pending');
  await assert.rejects(game.knowledgeMatchSnapshot(users[12],actual.id),/MATCH_NOT_FOUND_OR_FORBIDDEN/);
  assert.equal(bracket.rounds[1].matches[0].sourceB.matchNumber,2);
  // Test bracket propagation independently of question resolution (covered above).
  for(let round=1;round<=4;round++) {
    await q(`UPDATE maslaki_quiz_match SET status='completed',winner_team_id=team_a_id,wins_a=2 WHERE event_id=$1 AND round_number=$2 AND status<>'bye'`,[event.id,round]);
    for(let retry=0;retry<2;retry++) {
      const client=await pool.connect();
      try {await client.query('BEGIN');await game.advanceTournamentTx(client,event.id,round);await client.query('COMMIT');}
      finally{client.release();}
    }
  }
  bracket=await game.readKnowledgeBracket(users[12],event.id);
  assert.equal(bracket.event.status,'completed');assert.ok(bracket.event.champion.id);
  assert.equal(bracket.rounds.flatMap(r=>r.matches).length,15);
  assert.equal((await q('SELECT COUNT(*)::int AS n FROM maslaki_quiz_match WHERE event_id=$1',[event.id])).rows[0].n,15);
});
