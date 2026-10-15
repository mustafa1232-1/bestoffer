import test from 'node:test';
import express from 'express';
import cors from 'cors';
import { randomUUID } from 'node:crypto';
import { pool, q } from '../config/db.js';
import { gamesRouter } from '../modules/games/games.routes.js';
import { signAccessToken } from '../shared/utils/jwt.js';
import { createUserSession } from '../modules/auth/auth.repo.js';
import { extractDeviceContext } from '../shared/utils/device-fingerprint.js';
import { withRequestContext } from '../shared/middleware/request-context.middleware.js';
import * as mafia from '../modules/games/mafia.service.js';
import { runMafiaPhases, deliverMafiaChanges } from '../modules/games/mafia.worker.js';

// Isolated loopback fixture only. Never provision preview accounts in production.
test('manual Mafia browser preview', { skip: process.env.MAFIA_PREVIEW !== '1' }, async () => {
  const url = new URL(process.env.DATABASE_URL);
  if (!['127.0.0.1','localhost'].includes(url.hostname) || !url.pathname.startsWith('/qa_f_') || process.env.NODE_ENV==='production') throw Error('LOCAL_ONLY');
  const users=[];
  for(let i=0;i<7;i++) users.push(Number((await q(`INSERT INTO app_user(full_name,username,phone,pin_hash,block,building_number,apartment,role)
    VALUES($1,$2,$2,'x','A','1','1','user') RETURNING id`,[['مصطفى','علي','نور','سارة','حسين','مريم','عمر'][i],`mafia_preview_${i}`])).rows[0].id));
  const fixture=await mafia.createMafiaRoom(users[0],{pace:'quick'}),room=fixture.room.id;
  for(const user of users.slice(1)) await mafia.joinMafiaRoom(user,fixture.room.inviteCode);
  for(const user of users) await mafia.setMafiaReady(user,room,true);
  await mafia.startMafiaRoom(users[0],room);
  await mafia.advanceMafiaRoom(room,{force:true});await mafia.advanceMafiaRoom(room,{force:true});
  const streams=new Set();
  const app=express();app.use(cors({origin:/^http:\/\/(127\.0\.0\.1|localhost):/}));
  app.use(express.json());app.use(withRequestContext);
  app.get('/fixture',async(req,res,next)=>{try {
    // Keep the manual visual/chat scenario stable across slow debug compiles.
    await q(`UPDATE mafia_room SET status='day_discussion',phase_started_at=NOW(),phase_ends_at=NOW()+INTERVAL '10 minutes',phase_version=phase_version+1 WHERE id=$1`,[room]);
    const tokenJti=randomUUID(),device=extractDeviceContext(req);
    const session=await createUserSession({userId:users[0],refreshToken:randomUUID(),tokenJti,
      deviceFingerprint:device.deviceFingerprint,expiresAt:new Date(Date.now()+3600000),
      accessExpiresAt:new Date(Date.now()+3600000),appSurface:'user'});
    res.json({roomId:room,token:signAccessToken({id:users[0],role:'user',appSurface:'user'},
      {sessionId:session.id,tokenJti,deviceFingerprint:device.deviceFingerprint})});
  }catch(e){next(e);}});
  app.get('/events',(req,res)=>{res.set({'Content-Type':'text/event-stream','Cache-Control':'no-cache'});res.flushHeaders();streams.add(res);req.on('close',()=>streams.delete(res));});
  app.post('/peer-message',async(req,res,next)=>{try {res.json(await mafia.sendMafiaMessage(users[1],room,{channel:'public',body:String(req.body.body||'أهلاً بالفريق، الصوت واضح؟').slice(0,300)}));}catch(e){next(e);}});
  app.post('/peer-interaction',async(req,res,next)=>{try {
    const snapshot=await mafia.getMafiaSnapshot(room,users[0]);
    const kind=String(req.body.kind||'egg');
    const sender=Math.min(6,Math.max(1,Number(req.body.sender)||1));
    const target=snapshot.players.find(p=>p.userId===users[0]);
    res.json(await mafia.sendMafiaInteraction(users[sender],room,{
      kind, interactionType:['egg','rose','tea'].includes(kind)?'gift':'reaction',
      targetPlayerId:['egg','rose','tea'].includes(kind)?target.playerId:null,
      commandId:randomUUID(),
    }));
  }catch(e){next(e);}});
  app.post('/phase',async(_req,res,next)=>{try {res.json(await mafia.advanceMafiaRoom(room,{force:true}));}catch(e){next(e);}});
  app.use('/api/games',gamesRouter);
  app.use((e,_req,res,_next)=>res.status(e.status||500).json({code:e.code||e.message}));
  const server=app.listen(4880,'127.0.0.1');
  let busy=false;
  const interval=setInterval(async()=>{
    if(busy)return;busy=true;
    try {await runMafiaPhases(); await deliverMafiaChanges('notify',{publish:async(_users,event,data)=>{
      for(const stream of streams) stream.write(`data: ${JSON.stringify({event,data})}\n\n`);
    }});}catch(e){console.error(e.code||e.message);}finally{busy=false;}
  },150);
  console.log('Mafia QA http://127.0.0.1:4880');
  await new Promise(resolve=>{app.post('/shutdown',(_req,res)=>{res.json({ok:true});resolve();});process.once('SIGTERM',resolve);});
  clearInterval(interval);for(const stream of streams)stream.end();
  await new Promise(resolve=>server.close(resolve));await pool.end();
});
