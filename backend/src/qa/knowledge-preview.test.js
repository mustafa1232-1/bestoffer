import test from 'node:test';
import express from 'express';
import cors from 'cors';
import { randomUUID } from 'node:crypto';
import { pool,q } from '../config/db.js';
import { gamesRouter } from '../modules/games/games.routes.js';
import { signAccessToken } from '../shared/utils/jwt.js';
import { withRequestContext } from '../shared/middleware/request-context.middleware.js';
import * as game from '../modules/games/knowledge.service.js';
import { advanceKnowledgeMatch,runKnowledgeCycle } from '../modules/games/knowledge-rounds.service.js';

// Manual loopback preview, outside the unit-test glob so suite provisioning
// cannot drop its database while a browser session is using it.
test('local knowledge browser fixture', {skip:process.env.KNOWLEDGE_PREVIEW !== '1'}, async () => {
  const url=new URL(process.env.DATABASE_URL);
  if(!['localhost','127.0.0.1'].includes(url.hostname) || !url.pathname.startsWith('/qa_f_') || process.env.NODE_ENV==='production') throw new Error('LOCAL_QA_ONLY');
  const users=[];
  for(let i=0;i<12;i++) {
    const row=await q(`INSERT INTO app_user(full_name,username,phone,pin_hash,block,building_number,apartment,role)
      VALUES($1,$2,$3,'x','A','1','1','user') RETURNING id`,[i ? 'فريق النخيل' : 'فريق دجلة',`preview_${i}`,`07800000${i}`]);
    users.push(Number(row.rows[0].id));
  }
  await game.seedKnowledgeQuestionBank();
  let matchId;
  async function create({size=1,open=false}={}) {
    size=Number(size)===4?4:1;
    const room=await game.createDuel(users[0],{teamSize:size,bestOf:3});
    for(let i=0;i<size*2;i++) await game.joinKnowledgeRoomSeat(users[i],room.eventId,i<size?'a':'b');
    const id=Number((await q('SELECT id FROM maslaki_quiz_match WHERE event_id=$1',[room.eventId])).rows[0].id);
    await advanceKnowledgeMatch(id);
    if(open){
      await q("UPDATE maslaki_quiz_round SET starts_at=clock_timestamp(),deadline_at=clock_timestamp()+INTERVAL '30 seconds',phase='question_open' WHERE match_id=$1",[id]);
      await q('UPDATE maslaki_quiz_match SET question_started_at=(SELECT starts_at FROM maslaki_quiz_round WHERE match_id=$1) WHERE id=$1',[id]);
    } else {matchId=id;}
    const tokens=users.slice(0,size*2).map(id=>signAccessToken({id,role:'user',appSurface:'user'}));
    return {matchId:id,token:tokens[0],tokens,snapshot:await game.knowledgeMatchSnapshot(users[0],id)};
  }
  const app=express();
  app.use(cors({origin:/^http:\/\/(localhost|127\.0\.0\.1):/}));
  app.use(express.json());app.use(withRequestContext);
  app.get('/fixture',async(req,res,next)=>{try{res.json(await create({size:req.query.size,open:req.query.open==='true'}));}catch(e){next(e);}});
  let tournament;
  app.get('/tournament',async(req,res,next)=>{
    try {
      if(!tournament) tournament=(async()=>{
        const actor={userId:users[0],canManageGames:true};
        const event=await game.createKnowledgeTournament(actor,{title:'كأس مسلكي للمعرفة',teamSize:1,maxTeams:12,bestOf:3,prizeTitle:'كأس أبطال مسلكي'});
        const names=['دجلة','النخيل','بغداد','الرافدين','البصرة','بابل','سامراء','أور','الموصل','الكوت','النجف','ديالى'];
        for(let i=0;i<12;i++) await game.registerTeam(users[i],event.id,'فريق '+names[i]);
        await game.startKnowledgeTournament(actor,event.id);
        return {event,token:signAccessToken({id:users[0],role:'user',appSurface:'user'})};
      })();
      res.json(await tournament);
    } catch(e){tournament=null;next(e);}
  });
  app.use('/api/games',gamesRouter);
  app.use((error,req,res,next)=>res.status(error.status||500).json({code:error.code||'SERVER_ERROR',requestId:req.requestId}));
  const server=app.listen(4878,'127.0.0.1');
  let running=false;
  const interval=setInterval(async()=>{
    if(running)return; running=true;
    try{
      await runKnowledgeCycle({publish:async()=>{}});
      if(matchId){
        const snapshot=await game.knowledgeMatchSnapshot(users[1],matchId);
        if(snapshot.phase==='question_open'&&!snapshot.answered&&Date.now()-new Date(snapshot.round.startsAt)>5000)
          await game.answerKnowledgeQuestion(users[1],matchId,{roundId:snapshot.round.id,questionId:snapshot.question.id,
            answerIndex:1,districtId:snapshot.match.availableDistricts[0]?.id||'none',idempotencyKey:randomUUID()});
      }
    }catch(error){console.error(error.code||error.message);}finally{running=false;}
  },200);
  console.log('Knowledge QA HTTP: http://127.0.0.1:4878');
  await new Promise(resolve=>{process.once('SIGINT',resolve);process.once('SIGTERM',resolve);});
  clearInterval(interval); await new Promise(resolve=>server.close(resolve)); await pool.end();
});
