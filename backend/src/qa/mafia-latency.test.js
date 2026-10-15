import test from 'node:test';
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { writeFile } from 'node:fs/promises';
import { pool, q } from '../config/db.js';
import { createMafiaRoom, getMafiaSnapshot, sendMafiaMessage } from '../modules/games/mafia.service.js';

test('opt-in local Mafia latency measurement', {skip:process.env.MAFIA_BENCH !== '1'}, async () => {
  const url = new URL(process.env.DATABASE_URL);
  assert.ok(['localhost','127.0.0.1'].includes(url.hostname) && url.pathname.startsWith('/qa_f_'));
  const user = Number((await q(`INSERT INTO app_user(full_name,username,phone,pin_hash,block,building_number,apartment,role)
    VALUES('Mafia latency','mafia_latency','qa_mafia_latency','x','A','1','1','user') RETURNING id`)).rows[0].id);
  const room = (await createMafiaRoom(user, {})).room.id;
  const client = await pool.connect();
  const proto = Object.getPrototypeOf(client), original = proto.query;
  client.release();
  let queries = 0;
  const delay = Number(process.env.MAFIA_BENCH_RTT_MS || 8);
  proto.query = async function (...args) {
    queries++;
    await new Promise(resolve => setTimeout(resolve, delay));
    return original.apply(this, args);
  };
  const report = { syntheticDatabaseRoundTripMs:delay, samples:10, results:{} };
  try {
    for (const [name, run] of Object.entries({
      snapshot: () => getMafiaSnapshot(room, user),
      message: () => sendMafiaMessage(user, room, {body:'Local latency check',channel:'public'}),
    })) {
      const times=[],counts=[];
      for(let i=0;i<10;i++) {
        queries=0; const start=performance.now(); await run();
        times.push(performance.now()-start); counts.push(queries);
      }
      times.sort((a,b)=>a-b);
      report.results[name]={p50Ms:+times[4].toFixed(2),p95Ms:+times[9].toFixed(2),queries:counts};
    }
  } finally {proto.query=original;await pool.end();}
  const label=process.env.MAFIA_BENCH_LABEL==='after'?'after':'before';
  await writeFile(`../docs/qa/mafia-latency-${label}.json`,JSON.stringify(report,null,2));
  console.log(JSON.stringify(report));
});
