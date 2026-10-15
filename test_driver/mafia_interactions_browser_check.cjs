const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs/promises');
(async()=>{
  const browser=await chromium.launch({headless:true,channel:'chrome'});
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
  const errors=[], responses=[], assets=[];
  page.on('pageerror', e=>errors.push(e.message));
  page.on('console', m=>{if(m.type()==='error')errors.push(m.text());});
  page.on('response',r=>{
    if(r.url().includes('/api/games/'))responses.push({url:r.url(),status:r.status()});
    if(r.url().includes('/assets/games/mafia/'))assets.push({url:r.url(),status:r.status()});
  });
  try {
    await page.goto('http://127.0.0.1:4881/',{waitUntil:'domcontentloaded',timeout:120000});
    await page.locator('flutter-view').waitFor({timeout:90000});
    await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
    await page.getByRole('button',{name:'المحادثة',exact:true}).waitFor({timeout:60000});
    await page.waitForTimeout(1200);
    await page.screenshot({path:'docs/qa/mafia-courtyard-phone.png'});
    const frames=[];
    for(const [kind,sender] of [['egg',1],['rose',2],['tea',3],['laugh',4]]) {
      const started=performance.now();
      const response=await page.request.post('http://127.0.0.1:4880/peer-interaction',{data:{kind,sender}});
      if(!response.ok())throw Error(await response.text());
      const {event}=await response.json();
      const label=kind==='laugh' ? `${event.payload.senderName}: يضحك`
        : `${event.payload.senderName} أرسل ${kind==='egg'?'بيضة':kind==='rose'?'وردة':'كأس شاي'} إلى ${event.payload.targetName}`;
      await page.getByText(label,{exact:false}).first().waitFor({timeout:10000});
      const visibleAfterMs=Math.round(performance.now()-started);
      await page.waitForTimeout(260);
      const flight=await page.screenshot({path:`docs/qa/mafia-${kind}-flight.png`});
      await page.waitForTimeout(820);
      const impact=await page.screenshot({path:`docs/qa/mafia-${kind}-impact.png`});
      if(flight.equals(impact))throw Error(`${kind}: animation did not change rendered pixels`);
      frames.push({kind,eventId:event.id,pixelsChanged:true,visibleAfterMs});
      await page.waitForTimeout(1800);
    }
    // Own command is confirmed by HTTP and starts without a snapshot round trip.
    await page.getByRole('button',{name:'إهداء وتفاعل'}).first().click();
    const receipt=page.waitForResponse(r=>r.url().endsWith('/interactions')&&r.request().method()==='POST');
    await page.getByText('وردة',{exact:true}).click();
    const accepted=await receipt;
    if(accepted.status()!==201)throw Error(`Gift rejected: ${accepted.status()}`);
    await page.waitForTimeout(3000);
    await page.setViewportSize({width:1200,height:900});
    await page.waitForTimeout(400);
    await page.screenshot({path:'docs/qa/mafia-courtyard-desktop.png'});
    await page.setViewportSize({width:320,height:740});
    await page.waitForTimeout(400);
    await page.screenshot({path:'docs/qa/mafia-courtyard-narrow.png'});
    if(errors.length||responses.some(r=>r.status>=400)||assets.length<2||assets.some(r=>r.status>=400))throw Error(JSON.stringify({errors,responses,assets}));
    const result={errors,frames,assets,responses,viewports:['390x844','1200x900','320x740'],ownGiftStatus:accepted.status()};
    await fs.writeFile('docs/qa/mafia-interactions-browser.json',JSON.stringify(result,null,2));
    console.log(JSON.stringify(result));
  }catch(error){
    await page.screenshot({path:'docs/qa/mafia-interactions-failure.png'});
    await fs.writeFile('docs/qa/mafia-interactions-dom.txt',await page.locator('body').innerHTML());
    console.log(JSON.stringify({errors,responses,assets}));throw error;
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
