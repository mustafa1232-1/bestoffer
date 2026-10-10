import test from 'node:test';
import assert from 'node:assert/strict';
import {resolveKnowledgeVotes} from '../modules/games/knowledge-game.logic.js';

const start=new Date('2026-10-07T10:00:00Z');
const answer=(id,team,choice,ms,timeout=false)=>({id,team_id:team,answer_index:choice,answered_at:new Date(+start+ms),is_timeout:timeout,district_id:'souk'});
const resolve=answers=>resolveKnowledgeVotes({teamIds:[1,2],answers,territories:[],startedAt:start,
  question:{answer_index:2,difficulty:'medium',time_limit_seconds:20}});
test('majority beats fastest minority, equal votes use earliest receipt',()=>{
  const r=resolve([answer(1,1,0,100),answer(2,1,2,1000),answer(3,1,2,2000),answer(4,2,2,3000),answer(5,2,0,4000)]);
  assert.equal(r.outcomes[0].correct,true);assert.equal(r.outcomes[1].correct,true);
  assert.equal(r.outcomes[0].points,195);assert.equal(r.outcomes[1].points,190);
  assert.deepEqual(r.grants,[{teamId:1,districtId:'souk'},{teamId:2,districtId:'river'}]);
});
test('missing members do not vote; entirely missing team scores zero',()=>{
  const r=resolve([answer(1,1,2,2000),answer(2,1,0,20000,true),answer(3,2,2,20000,true)]);
  assert.equal(r.outcomes[0].points,195);assert.equal(r.outcomes[1].points,0);
  assert.equal(r.grants.length,1);
});
test('wrong majority earns no territory or speed points',()=>{
  const r=resolve([answer(1,1,2,100),answer(2,1,1,200),answer(3,1,1,300)]);
  assert.equal(r.outcomes[0].points,0);assert.deepEqual(r.grants,[]);
});
