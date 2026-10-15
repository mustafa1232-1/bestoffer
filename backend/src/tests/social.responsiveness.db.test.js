import assert from "node:assert/strict";
import test, { before, after } from "node:test";
import { readFile } from "node:fs/promises";
import { q, pool } from "../config/db.js";
import { env } from "../config/env.js";
import * as repo from "../modules/feed/feed.repo.js";
import * as service from "../modules/feed/feed.service.js";
import { recordContentImpressions } from "../modules/feed/feed.analytics.repo.js";
import { assertSocialCallVoiceAccess } from "../modules/feed/feed.call-voice.js";

let a, b, outsider, threadId;
before(async () => {
  assert.match(new URL(process.env.DATABASE_URL).pathname, /\/qa_f_/);
  await q(await readFile(new URL("../../sql/232_social_call_livekit.sql", import.meta.url), "utf8"));
  const users = await q(`INSERT INTO app_user(full_name, phone, username, pin_hash, role, block, building_number, apartment)
    SELECT 'Social regression ' || i, '077social' || i, 'social_test_' || i, 'test', 'user', 'A', 'A203', '1'
    FROM generate_series(1,3) i RETURNING id`);
  [a, b, outsider] = users.rows.map((row) => Number(row.id));
  await q(`INSERT INTO social_user_relation(user_a_id, user_b_id, initiator_user_id, status)
    VALUES ($1,$2,$1,'accepted')`, [a,b]);
  const thread = await repo.createOrGetThread({ userAId:a, userBId:b });
  threadId = Number(thread.id);
});
after(() => pool.end());

test("one batched impression query stores all rows and viewer identity", async () => {
  const posts = await q(`INSERT INTO social_post(user_id, post_kind, caption)
    SELECT $1, 'text', 'Caption regression ' || i FROM generate_series(1,20) i RETURNING id`, [a]);
  let queries = 0;
  const original = pool.query.bind(pool);
  pool.query = (...args) => { queries++; return original(...args); };
  try {
    await recordContentImpressions({ viewerUserId:a, context:"regression",
      items:posts.rows.map((row) => ({contentType:'post',contentId:Number(row.id)})) });
  } finally { pool.query = original; }
  assert.equal(queries, 1, "20 impressions must not consume 20 pool requests");
  const result = await q(`SELECT COUNT(*)::int AS count FROM social_content_impression WHERE viewer_user_id=$1 AND impression_context='regression'`, [a]);
  assert.equal(result.rows[0].count,20);
});

test("reaction summary uses one query and preserves private myReaction", async () => {
  const message = await repo.insertThreadMessage({threadId,senderUserId:a,body:'Hello'});
  await repo.toggleMessageReaction({messageId:message.id,userId:a,reaction:'heart'});
  await repo.toggleMessageReaction({messageId:message.id,userId:b,reaction:'like'});
  let queries = 0;
  const original = pool.query.bind(pool);
  pool.query = (...args) => { queries++; return original(...args); };
  let reactions;
  try { reactions = await repo.listMessageReactionsForMessages({messageIds:[message.id],userId:a}); }
  finally { pool.query = original; }
  assert.equal(queries,1);
  assert.deepEqual(reactions[message.id],{counts:{heart:1,like:1},myReaction:'heart',totalCount:2});
  const read = await service.listMessages({userId:b,threadId,query:{limit:40}});
  assert.equal(read.messages[0].body,'Hello');
  assert.equal(read.messages[0].sender.fullName,'Social regression 1');
  await assert.rejects(service.listMessages({userId:outsider,threadId,query:{limit:40}}), {code:'THREAD_NOT_FOUND'});
});

test("voice access never grants outsiders, ringing or ended sessions", () => {
  const session={id:1, callerUserId:a,calleeUserId:b,status:'active',voiceTransport:'livekit'};
  assert.doesNotThrow(() => assertSocialCallVoiceAccess(session,a));
  assert.doesNotThrow(() => assertSocialCallVoiceAccess(session,b));
  assert.throws(() => assertSocialCallVoiceAccess(session,outsider), {code:'SOCIAL_CALL_FORBIDDEN'});
  for (const status of ['ringing','ended','declined','missed']) {
    assert.throws(() => assertSocialCallVoiceAccess({...session,status},a), {code:'SOCIAL_CALL_NOT_ACTIVE'});
  }
});

test("new peers negotiate LiveKit; old peers keep WebRTC; terminal sessions cannot revive", async () => {
  const saved = [env.livekitUrl,env.livekitApiKey,env.livekitApiSecret];
  Object.assign(env,{livekitUrl:'wss://localhost',livekitApiKey:'test-key',livekitApiSecret:'test-secret-not-production'});
  try {
    const session=await repo.createThreadCallSession({threadId,callerUserId:a,calleeUserId:b,voiceTransport:'auto'});
    const capability = await service.sendThreadCallSignal({userId:b,threadId,
      dto:{sessionId:session.id,signalType:'ringing',signalPayload:{transport:'livekit'}}});
    assert.equal(capability.session.status,'ringing','capability acknowledgement must not accept a call');
    await assert.rejects(service.sendThreadCallSignal({userId:a,threadId,dto:{sessionId:session.id,signalType:'accept',signalPayload:{transport:'livekit'}}}),{code:'SOCIAL_CALL_FORBIDDEN'});
    await assert.rejects(service.getThreadCallVoiceToken({userId:outsider,threadId,sessionId:session.id}),{code:'THREAD_NOT_FOUND'});
    await assert.rejects(service.getThreadCallVoiceToken({userId:a,threadId,sessionId:session.id}),{code:'SOCIAL_CALL_NOT_ACTIVE'});
    const accepted=await service.sendThreadCallSignal({userId:b,threadId,dto:{sessionId:session.id,signalType:'accept',signalPayload:{transport:'livekit'}}});
    assert.equal(accepted.session.voiceTransport,'livekit');
    const access=await service.getThreadCallVoiceToken({userId:a,threadId,sessionId:session.id});
    const jwt=JSON.parse(Buffer.from(access.token.split('.')[1],'base64url'));
    assert.equal(jwt.video.room,`maslaki-social-call-${session.id}`);
    assert.deepEqual(jwt.video.canPublishSources,['microphone']);
    assert.equal(jwt.video.canPublishData,false);
    const peerAccess=await service.getThreadCallVoiceToken({userId:b,threadId,sessionId:session.id});
    const peerJwt=JSON.parse(Buffer.from(peerAccess.token.split('.')[1],'base64url'));
    assert.equal(peerJwt.video.room,jwt.video.room);
    assert.notEqual(peerJwt.sub,jwt.sub);
    assert.deepEqual(peerJwt.video.canPublishSources,['microphone']);
    const signals=await repo.listThreadCallSignals(session.id);
    assert.deepEqual(signals.map((entry)=>entry.signalType).sort(),['accept','ringing'],'LiveKit negotiation needs no legacy SDP');
    await service.endThreadCall({userId:b,threadId,dto:{status:'ended'}});
    assert.equal((await q('SELECT session_id FROM social_call_voice_cleanup WHERE session_id=$1',[session.id])).rowCount,1);
    await assert.rejects(service.getThreadCallVoiceToken({userId:a,threadId,sessionId:session.id}),{code:'SOCIAL_CALL_NOT_ACTIVE'});
    await assert.rejects(service.sendThreadCallSignal({userId:b,threadId,dto:{sessionId:session.id,signalType:'accept'}}),{code:'SOCIAL_CALL_NOT_ACTIVE'});
    const legacy=await repo.createThreadCallSession({threadId,callerUserId:a,calleeUserId:b,voiceTransport:'auto'});
    const answer=await service.sendThreadCallSignal({userId:b,threadId,dto:{sessionId:legacy.id,signalType:'answer',signalPayload:{sdp:'legacy answer',type:'answer'}}});
    assert.equal(answer.session.voiceTransport,'webrtc');
  } finally {
    [env.livekitUrl,env.livekitApiKey,env.livekitApiSecret]=saved;
  }
});

test("post details preserve both author name and the exact stored caption", async () => {
  const caption = 'Caption regression: line one\nline two';
  const row = await q(`INSERT INTO social_post(user_id,post_kind,caption)
    VALUES ($1,'text',$2) RETURNING id`, [a,caption]);
  const result = await service.getPostById(b,Number(row.rows[0].id));
  assert.equal(result.post.caption,caption);
  assert.equal(result.post.author.fullName,'Social regression 1');
});
