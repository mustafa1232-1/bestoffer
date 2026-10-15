const fs=require('node:fs/promises');
const {randomUUID}=require('node:crypto');
const {performance}=require('node:perf_hooks');
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const percentile=(values,p)=>values.sort((a,b)=>a-b)[Math.ceil(values.length*p)-1];
(async()=>{
  const results=[];
  for(const rtt of [0,100,250]){
    const samples=[];
    for(let round=0;round<5;round++){
      const f=await(await fetch('http://127.0.0.1:4878/fixture?size=4&open=true')).json();
      await Promise.all(f.tokens.map(async token=>{
        const start=performance.now();await sleep(rtt/2);
        const response=await fetch(`http://127.0.0.1:4878/api/games/knowledge/matches/${f.matchId}/answers`,{
          method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
          body:JSON.stringify({roundId:f.snapshot.round.id,questionId:f.snapshot.question.id,idempotencyKey:randomUUID(),answerIndex:0,districtId:'souk'})});
        const body=await response.text();await sleep(rtt/2);
        samples.push({ms:performance.now()-start,status:response.status,bytes:Buffer.byteLength(body)});
      }));
    }
    results.push({injectedRttMs:rtt,samples:samples.length,p50:percentile(samples.map(s=>s.ms),.5),p95:percentile(samples.map(s=>s.ms),.95),
      p99:percentile(samples.map(s=>s.ms),.99),errors:samples.filter(s=>s.status!==200),maxBytes:Math.max(...samples.map(s=>s.bytes))});
  }
  const report={mode:'Loopback HTTP + signed QA JWT + real games router + PostgreSQL; 4v4; application-level half-RTT delays each side; zero jitter/loss; not a mobile radio test',results};
  await fs.writeFile('docs/qa/knowledge-http-latency.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
})().catch(error=>{console.error(error);process.exitCode=1;});
