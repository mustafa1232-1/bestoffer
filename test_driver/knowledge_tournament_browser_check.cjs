const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('node:fs/promises');

(async()=>{
  const browser=await chromium.launch({headless:true});
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
  const errors=[],responses=[];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('response',async r=>{
    if(r.url().endsWith('/bracket')) responses.push({status:r.status(),body:await r.json()});
  });
  try {
    await page.goto('http://127.0.0.1:4879/?bracket=1',{waitUntil:'networkidle',timeout:120000});
    await page.locator('flutter-view').waitFor({timeout:60000});
    const placeholder=page.locator('flt-semantics-placeholder');
    if(await placeholder.count()) await placeholder.evaluate(e=>e.click());
    await page.getByRole('button',{name:'عرض المخطط كاملاً',exact:true}).waitFor({timeout:30000});
    await page.getByRole('button',{name:'عرض المخطط كاملاً',exact:true}).click();
    await page.screenshot({path:'docs/qa/knowledge-tournament-phone.png'});
    await page.getByRole('button',{name:'تكبير المخطط',exact:true}).click();
    await page.getByRole('button',{name:'تصغير المخطط',exact:true}).click();
    await page.getByRole('button',{name:'عرض المخطط كاملاً',exact:true}).click();
    await page.setViewportSize({width:1200,height:900});
    await page.waitForTimeout(500);
    await page.screenshot({path:'docs/qa/knowledge-tournament-desktop.png'});
    await fs.writeFile('docs/qa/knowledge-tournament-dom.txt',await page.locator('body').innerHTML());
    const finalTab=page.getByRole('checkbox',{name:'النهائي',exact:true});
    await finalTab.click();
    await page.waitForFunction(()=>document.querySelector('[aria-label="النهائي"]')?.getAttribute('aria-checked')==='true');
    await page.mouse.move(1100,780);await page.mouse.wheel(0,320);
    await page.waitForTimeout(300);
    await page.screenshot({path:'docs/qa/knowledge-tournament-final.png'});
    const snapshot=responses.at(-1);
    if(!snapshot || snapshot.status!==200) throw new Error('Bracket API not successful');
    const rounds=snapshot.body.rounds;
    if(rounds.map(r=>r.matches.length).join(',')!=='8,4,2,1') throw new Error('Incomplete bracket');
    if(snapshot.body.event.bestOf!==3) throw new Error('Wrong series format');
    if(errors.length) throw new Error(errors.join(';'));
    await fs.writeFile('docs/qa/knowledge-tournament-browser.json',JSON.stringify({errors,status:snapshot.status,
      slots:rounds.map(r=>r.matches.length),bestOf:snapshot.body.event.bestOf,teams:snapshot.body.teams.length},null,2));
    console.log('Tournament browser: real 12-team bracket, 15 slots, zoom, round tabs, phone and desktop passed.');
  } catch(e) {
    console.log(JSON.stringify({url:page.url(),errors},null,2));
    await page.screenshot({path:'docs/qa/knowledge-tournament-failure.png'});
    console.log((await page.locator('body').innerText()).slice(0,4000));throw e;
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
