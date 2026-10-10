import test from "node:test";
import { performance, monitorEventLoopDelay } from "node:perf_hooks";
import { AsyncLocalStorage } from "node:async_hooks";
import fs from "node:fs/promises";
import { pool, q } from "../config/db.js";
import * as game from "../modules/games/knowledge.service.js";
import { advanceKnowledgeMatch } from '../modules/games/knowledge-rounds.service.js';

// Opt-in, isolated per-file QA database. Never run against a production URL.
test("knowledge answer benchmark", { skip: process.env.KNOWLEDGE_BENCHMARK !== "1" }, async () => {
  const context = new AsyncLocalStorage();
  const instrument = (client) => {
    if (client.knowledgeMeasured) return;
    client.knowledgeMeasured = true;
    const original = client.query.bind(client);
    client.query = function (...args) {
      const measurement = context.getStore();
      if (!measurement) return original(...args);
      measurement.queries++;
      const start = performance.now();
      const delay = Number(process.env.KNOWLEDGE_DB_DELAY_MS || 0);
      const callback = typeof args.at(-1) === "function" ? args.pop() : null;
      const run = () => original(...args);
      const pending = delay ? new Promise((r) => setTimeout(r, delay)).then(run) : run();
      const result = pending.finally(() => { measurement.queryMs += performance.now() - start; });
      if (callback) { result.then((value) => callback(null, value), callback); return; }
      return result;
    };
  };
  pool.on("connect", instrument);
  const warm = await pool.connect(); instrument(warm); warm.release();
  await game.seedKnowledgeQuestionBank();
  const lag = monitorEventLoopDelay({ resolution: 10 }); lag.enable();
  const cpu = process.cpuUsage();
  const results = [];
  let serial = 0;
  async function room(size) {
    const tag = `bench_${Date.now()}_${serial++}`;
    const users = [];
    for (let i = 0; i < size * 2; i++) {
      const row = await q(`INSERT INTO app_user(full_name,phone,pin_hash,block,building_number,apartment,username,role)
        VALUES($1,$2,'x','A','1','1',$1,'user') RETURNING id`, [`${tag}_${i}`, `078${String(serial).padStart(6, '0')}${i}`]);
      users.push(Number(row.rows[0].id));
    }
    const created = await game.createDuel(users[0], { teamSize: size });
    for (let i = 0; i < users.length; i++) await game.joinKnowledgeRoomSeat(users[i], created.eventId, i < size ? "a" : "b");
    const match = (await q("SELECT id FROM maslaki_quiz_match WHERE event_id=$1", [created.eventId])).rows[0];
    await advanceKnowledgeMatch(Number(match.id));
    const snapshot = await game.knowledgeMatchSnapshot(users[0], Number(match.id));
    return { users, matchId: Number(match.id), snapshot };
  }
  const percentile = (list, fraction) => list.sort((a, b) => a - b)[Math.max(0, Math.ceil(list.length * fraction) - 1)] || 0;
  for (const [size, count, repeats] of [[1, 1, 10], [4, 1, 10], [4, 25, 1]]) {
    const samples = [];
    const resolution = [];
    for (let iteration = 0; iteration < repeats; iteration++) {
      const rooms = [];
      for (let i = 0; i < count; i++) rooms.push(await room(size));
      // Begin every measured round together, independent of fixture setup time.
      await q("UPDATE maslaki_quiz_match SET question_started_at=NOW() WHERE id=ANY($1::bigint[])", [rooms.map((r) => r.matchId)]);
      await q("UPDATE maslaki_quiz_round SET starts_at=NOW(),deadline_at=NOW()+INTERVAL '30 seconds',phase='question_open' WHERE match_id=ANY($1::bigint[])", [rooms.map(r => r.matchId)]);
      await Promise.all(rooms.flatMap((r) => r.users.map(async (userId) => {
        const sample = { queries: 0, queryMs: 0, error: null };
        const start = performance.now();
        await context.run(sample, async () => {
          try { await game.answerKnowledgeQuestion(userId, r.matchId, { answerIndex: 0, districtId: "souk",
            roundId: r.snapshot.round.id, questionId: r.snapshot.question.id, idempotencyKey: `benchmark_${r.matchId}_${userId}` },
          { observe: metric => { sample.metric = metric; } }); }
          catch (error) { sample.error = error.message; }
        });
        sample.ms = performance.now() - start;
        samples.push(sample);
      })));
      // Separate real scoring work from the acknowledgement metric. Publication
      // and device/network time are deliberately not included in this number.
      for(let offset=0;offset<rooms.length;offset+=4) {
        await Promise.all(rooms.slice(offset,offset+4).map(async room=>{
          const sample={queries:0,queryMs:0};const start=performance.now();
          await context.run(sample,()=>advanceKnowledgeMatch(room.matchId));
          resolution.push({...sample,ms:performance.now()-start});
        }));
      }
    }
    results.push({ teamSize: size, rooms: count, simultaneousPlayers: count * size * 2, samples: samples.length,
      p50: percentile(samples.map((s) => s.ms), .5), p95: percentile(samples.map((s) => s.ms), .95),
      p99: percentile(samples.map((s) => s.ms), .99), errors: samples.filter((s) => s.error).map((s) => s.error),
      queryCount: { min: Math.min(...samples.map((s) => s.queries)), max: Math.max(...samples.map((s) => s.queries)) },
      timingP95: Object.fromEntries(['poolMs','queryCommitMs','gateMs'].map(k => [k,percentile(samples.map(s => s.metric?.[k] || 0),.95)])),
      resolution:{samples:resolution.length,p50:percentile(resolution.map(s=>s.ms),.5),p95:percentile(resolution.map(s=>s.ms),.95),
        p99:percentile(resolution.map(s=>s.ms),.99),queriesMax:Math.max(...resolution.map(s=>s.queries))} });
  }
  lag.disable();
  const indexDefinitions = (await q(`SELECT tablename,indexname,indexdef FROM pg_indexes
    WHERE tablename IN('maslaki_quiz_round','maslaki_quiz_submission','maslaki_quiz_event_outbox')
    ORDER BY tablename,indexname`)).rows;
  const queryPlans = {};
  for (const [name,sql] of Object.entries({
    latestRound: 'SELECT * FROM maslaki_quiz_round WHERE match_id=1 ORDER BY round_number DESC LIMIT 1',
    replayLookup: "SELECT * FROM maslaki_quiz_submission WHERE user_id=1 AND idempotency_key='benchmark_missing'",
    pendingEvents: 'SELECT id FROM maslaki_quiz_event_outbox WHERE published_at IS NULL AND retry_at<=NOW() ORDER BY id LIMIT 64',
  })) queryPlans[name] = (await q(`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${sql}`)).rows[0]['QUERY PLAN'];
  const report = { version: "round-protocol-2", databaseDelayMs: Number(process.env.KNOWLEDGE_DB_DELAY_MS || 0),
    runtime: process.version, mode: "service + local PostgreSQL; no HTTP or device RTT", results,
    eventLoopP99Ms: lag.percentile(99) / 1e6, cpu: process.cpuUsage(cpu), memory: process.memoryUsage(),
    indexDefinitions, queryPlans };
  console.log(JSON.stringify(report));
  if (process.env.KNOWLEDGE_BENCHMARK_OUTPUT) await fs.writeFile(process.env.KNOWLEDGE_BENCHMARK_OUTPUT, JSON.stringify(report, null, 2));
  await pool.end();
});
