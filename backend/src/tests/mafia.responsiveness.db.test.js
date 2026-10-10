import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import { pool, q } from '../config/db.js';
import { env } from '../config/env.js';
import { createMafiaRoom, getMafiaSnapshot, getMafiaVoiceAccess, joinMafiaRoom, sendMafiaMessage, submitMafiaAction } from '../modules/games/mafia.service.js';
import { deliverMafiaChanges, runMafiaPhases, publishMafiaRoom } from '../modules/games/mafia.worker.js';
import { mafiaVoicePermissions, syncMafiaVoicePermissions } from '../modules/games/mafia.voice.js';

async function fixture(t) {
  const users=[];
  for (let i=0;i<3;i++) {
    const key=randomUUID().replaceAll('-','').slice(0,18);
    users.push(Number((await q(`INSERT INTO app_user(full_name,phone,pin_hash,block,building_number,apartment,username,role)
      VALUES('Mafia responsiveness',$1,'x','A','1','1',$1,'user') RETURNING id`,[key])).rows[0].id));
  }
  const snapshot=await createMafiaRoom(users[0],{pace:'quick'});
  for(const user of users.slice(1)) await joinMafiaRoom(user,snapshot.room.inviteCode);
  const room=snapshot.room.id;
  const players=(await q('SELECT * FROM mafia_player WHERE room_id=$1 ORDER BY seat_number',[room])).rows;
  t.after(async()=>{
    await q('DELETE FROM mafia_room WHERE id=$1',[room]);
    await q('DELETE FROM app_user WHERE id=ANY($1::bigint[])',[users]);
  });
  return {users,room,players};
}

test('snapshot is one read query and cannot advance an expired phase or write presence',async t=>{
  const {users,room}=await fixture(t);
  await q(`UPDATE mafia_room SET status='role_reveal',phase_ends_at=NOW()-INTERVAL '1 second' WHERE id=$1`,[room]);
  const before=(await q('SELECT last_seen_at FROM mafia_player WHERE room_id=$1 AND user_id=$2',[room,users[0]])).rows[0];
  const client=await pool.connect(),proto=Object.getPrototypeOf(client), original=proto.query;
  client.release();let queries=0;
  proto.query=function(...args){queries++;assert.match(args[0],/^SELECT/);return original.apply(this,args);};
  try { assert.equal((await getMafiaSnapshot(room,users[0])).room.status,'role_reveal'); assert.equal(queries,1); }
  finally{proto.query=original;}
  assert.deepEqual((await q('SELECT last_seen_at FROM mafia_player WHERE room_id=$1 AND user_id=$2',[room,users[0]])).rows[0],before);
  const changed=await Promise.all([runMafiaPhases(),runMafiaPhases()]);
  assert.equal(changed.reduce((a,b)=>a+b,0),1);
  assert.equal((await getMafiaSnapshot(room,users[0])).room.status,'night');
});

test('chat retries are one message, receipt is immediate, and private channels stay private',async t=>{
  const {users,room,players}=await fixture(t);
  const input={channel:'public',body:'Hello',clientMessageId:randomUUID()};
  const replies=await Promise.all([sendMafiaMessage(users[0],room,input),sendMafiaMessage(users[0],room,input)]);
  assert.equal(replies[0].message.id,replies[1].message.id);
  assert.equal((await q('SELECT id FROM mafia_message WHERE room_id=$1',[room])).rowCount,1);
  await q(`UPDATE mafia_player SET team='mafia',role='mafia' WHERE id=$1`,[players[0].id]);
  await q(`UPDATE mafia_room SET status='night',day_number=1 WHERE id=$1`,[room]);
  await sendMafiaMessage(users[0],room,{channel:'mafia',body:'Secret',clientMessageId:randomUUID()});
  assert.ok((await getMafiaSnapshot(room,users[0])).messages.some(m=>m.body==='Secret'));
  assert.ok(!(await getMafiaSnapshot(room,users[1])).messages.some(m=>m.body==='Secret'));
  await assert.rejects(sendMafiaMessage(users[1],room,{channel:'mafia',body:'Spy'}),/MAFIA_MESSAGE_FORBIDDEN/);
  await q(`UPDATE mafia_player SET life_status='left' WHERE id=$1`,[players[0].id]);
  await assert.rejects(sendMafiaMessage(users[0],room,{channel:'public',body:'Left'}),/MAFIA_MESSAGE_FORBIDDEN/);
});

test('action receipts cannot overwrite a newer choice or act in a stale phase',async t=>{
  const {users,room,players}=await fixture(t);
  await q(`UPDATE mafia_room SET status='day_nomination',day_number=1,phase_version=9,phase_ends_at=NOW()+INTERVAL '1 minute' WHERE id=$1`,[room]);
  const first={type:'nominate',targetPlayerId:Number(players[1].id),phaseVersion:9,commandId:randomUUID()};
  const second={...first,targetPlayerId:Number(players[2].id),commandId:randomUUID()};
  await submitMafiaAction(users[0],room,first);
  await submitMafiaAction(users[0],room,second);
  await submitMafiaAction(users[0],room,first);
  assert.equal(Number((await q('SELECT target_player_id FROM mafia_ballot WHERE room_id=$1',[room])).rows[0].target_player_id),second.targetPlayerId);
  await assert.rejects(submitMafiaAction(users[0],room,{...first,targetPlayerId:second.targetPlayerId}),/MAFIA_COMMAND_CONFLICT/);
  await assert.rejects(submitMafiaAction(users[0],room,{...first,phaseVersion:8,commandId:randomUUID()}),/MAFIA_PHASE_CHANGED/);
});

test('durable delivery retries provider failure and preserves a concurrent newer revision',async t=>{
  const {users,room}=await fixture(t);
  const failed=await deliverMafiaChanges('notify',{publish:async()=>{throw Error('offline');}});
  assert.equal(failed.failed,1);
  assert.equal((await q('SELECT notify_pending FROM mafia_room_delivery WHERE room_id=$1',[room])).rows[0].notify_pending,true);
  await q(`UPDATE mafia_room_delivery SET notify_lease_until='-infinity' WHERE room_id=$1`,[room]);
  await deliverMafiaChanges('notify',{publish:async()=>sendMafiaMessage(users[0],room,{channel:'public',body:'During broadcast'})});
  assert.equal((await q('SELECT notify_pending FROM mafia_room_delivery WHERE room_id=$1',[room])).rows[0].notify_pending,true);
  const events=[];
  await deliverMafiaChanges('notify',{publish:async(...args)=>events.push(args)});
  assert.equal(events.length,1);
  assert.equal(events[0][3].requireDurable,true);
  assert.equal((await q('SELECT notify_pending FROM mafia_room_delivery WHERE room_id=$1',[room])).rows[0].notify_pending,false);
});

test('voice lag does not block chat, snapshots or the independent phase worker',async t=>{
  const {users,room}=await fixture(t);
  let release,started;
  const entered=new Promise(r=>{started=r;});
  const gate=new Promise(r=>{release=r;});
  const pending=deliverMafiaChanges('voice',{voice:async()=>{started();await gate;}});
  await entered;
  try {
    await sendMafiaMessage(users[0],room,{channel:'public',body:'Not blocked'});
    assert.ok((await getMafiaSnapshot(room,users[0])).messages.some(m=>m.body==='Not blocked'));
    await q(`UPDATE mafia_room SET status='role_reveal',phase_ends_at=NOW()-INTERVAL '1 second' WHERE id=$1`,[room]);
    assert.equal(await runMafiaPhases(),1);
  } finally {release();await pending;}
  assert.equal((await q('SELECT voice_pending FROM mafia_room_delivery WHERE room_id=$1',[room])).rows[0].voice_pending,true);
});

test('new quick reveal advances after everyone acknowledges; old quick timings are unaffected',async t=>{
  const {room}=await fixture(t);
  await q(`UPDATE mafia_room SET status='role_reveal',phase_started_at=NOW()-INTERVAL '5 seconds',phase_ends_at=NOW()+INTERVAL '20 seconds' WHERE id=$1`,[room]);
  assert.equal(await runMafiaPhases(),0);
  await q('UPDATE mafia_player SET role_acknowledged=TRUE WHERE room_id=$1',[room]);
  assert.equal(await runMafiaPhases(),1);
});

test('voice revokes before grants, bounds concurrency, and blocks left/data-channel bypass',async()=>{
  // Three eliminated players lose the microphone; eleven living players speak.
  const players=Array.from({length:14},(_,i)=>({id:i,user_id:i,life_status:i<3?'dead':'alive',team:i<3?'mafia':'town'}));
  const room={id:1,status:'day_discussion',voice_room_name:'qa'};
  let inFlight=0,max=0;const calls=[];
  await syncMafiaVoicePermissions(room,players,[],{updateParticipant:async(_,identity,{permission})=>{
    inFlight++;max=Math.max(max,inFlight);await new Promise(r=>setTimeout(r,2));
    calls.push(permission);inFlight--;
  }});
  assert.ok(max>1 && max<=4);
  assert.ok(calls.slice(0,3).every(p=>!p.canPublish&&p.canSubscribe));
  assert.ok(calls.slice(3).every(p=>p.canPublish));
  // At night nobody speaks on the shared table (mafia use the night room).
  const night=[];
  await syncMafiaVoicePermissions({...room,status:'night'},players,[],{updateParticipant:async(_,__,{permission})=>{night.push(permission);}});
  assert.ok(night.length===14 && night.every(p=>!p.canPublish));
  assert.ok(calls.every(p=>!p.canPublishData));
  assert.equal(mafiaVoicePermissions({...room,status:'lobby'},{life_status:'left'}).roomJoin,false);
});

test('chat during voice work does not schedule redundant permission writes',async t=>{
  const {users,room}=await fixture(t);
  const result=await deliverMafiaChanges('voice',{voice:async()=>{
    for(let i=0;i<5;i++)await sendMafiaMessage(users[0],room,{channel:'public',body:`Burst ${i}`});
  }});
  assert.equal(result.failed,0);
  const row=(await q('SELECT voice_pending,notify_pending FROM mafia_room_delivery WHERE room_id=$1',[room])).rows[0];
  assert.equal(row.voice_pending,false);assert.equal(row.notify_pending,true);
});

test('superseded voice work cannot grant the old phase permissions',async()=>{
  let current=true;const permissions=[];
  const players=[{id:1,user_id:1,life_status:'dead',team:'town'},{id:2,user_id:2,life_status:'alive',team:'mafia'}];
  await assert.rejects(syncMafiaVoicePermissions({id:1,status:'day_discussion',voice_room_name:'qa'},players,[],{
    updateParticipant:async(_room,_identity,{permission})=>{permissions.push(permission);current=false;},
  },{isCurrent:async()=>current}),/MAFIA_VOICE_SUPERSEDED/);
  assert.equal(permissions.length,1);assert.equal(permissions[0].canPublish,false);
});

test('a slow recipient cannot delay the hints for the other seats',async()=>{
  let release;
  const waiting=new Promise(r=>{release=r;});const reached=[];
  const publishing=publishMafiaRoom([1,2,3],'mafia_room_updated',{}, {},async user=>{
    reached.push(user);if(user===1)await waiting;
  });
  assert.deepEqual(reached,[1,2,3]);release();await publishing;
});

test('token refresh queues reconciliation without contacting a provider and completed players publish only once',async t=>{
  const {users,room,players}=await fixture(t);
  const original={livekitUrl:env.livekitUrl,livekitApiKey:env.livekitApiKey,livekitApiSecret:env.livekitApiSecret};
  Object.assign(env,{livekitUrl:'wss://local-qa.invalid',livekitApiKey:'APILOCALQA',livekitApiSecret:'local-only-signature-not-a-production-secret'});
  try {
    await q(`UPDATE mafia_room SET status='completed',winner='town',phase_ends_at=NULL WHERE id=$1`,[room]);
    await q(`UPDATE mafia_player SET life_status='dead' WHERE id=$1`,[players[0].id]);
    await q('UPDATE mafia_room_delivery SET voice_pending=FALSE WHERE room_id=$1',[room]);
    const access=await getMafiaVoiceAccess(users[0],room);
    assert.equal(access.enabled,true);assert.equal(access.afterlife,undefined);
    assert.equal(access.permissions.canPublish,true);
    const claims=JSON.parse(Buffer.from(access.token.split('.')[1],'base64url').toString());
    assert.equal(claims.video.canPublishData,false);
    assert.equal((await q('SELECT voice_pending FROM mafia_room_delivery WHERE room_id=$1',[room])).rows[0].voice_pending,true);
  } finally {Object.assign(env,original);}
});
