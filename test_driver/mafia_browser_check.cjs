const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs/promises');
(async()=>{
  for(let attempt=0;attempt<60;attempt++) {
    try { if((await fetch('http://127.0.0.1:4880/fixture')).ok) break; } catch {}
    if(attempt===59) throw Error('QA backend is not ready');
    await new Promise(r=>setTimeout(r,500));
  }
  const browser=await chromium.launch({headless:true,channel:'chrome'});
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
  const errors=[],responses=[];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('response',r=>{if(r.url().includes('/api/games/'))responses.push({url:r.url(),status:r.status()});});
  try{
    console.log('Opening Mafia preview');
    await page.goto('http://127.0.0.1:4881/',{waitUntil:'domcontentloaded',timeout:120000});
    await page.locator('flutter-view').waitFor({timeout:90000});
    await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
    await page.getByRole('button',{name:'المحادثة',exact:true}).waitFor({timeout:60000});
    await page.screenshot({path:'docs/qa/mafia-phone.png'});
    await page.getByRole('button',{name:'المحادثة',exact:true}).click();
    console.log('Posting peer message');
    const peerText=`أهلاً بالفريق ${Date.now()}`;
    const ownText=`وصلت الرسالة ${Date.now()}`;
    const start=Date.now();
    const posted=await page.request.post('http://127.0.0.1:4880/peer-message',{data:{body:peerText}});
    if(!posted.ok())throw Error(`Peer message failed: ${posted.status()} ${await posted.text()}`);
    await page.getByText(peerText,{exact:false}).first().waitFor({timeout:10000});
    const incomingMs=Date.now()-start;
    await page.getByRole('textbox').fill(ownText);
    const confirmation=page.waitForResponse(r=>r.url().endsWith('/messages')&&r.request().method()==='POST');
    await page.getByRole('button',{name:'إرسال',exact:true}).click();
    const receipt=await confirmation;
    if(receipt.status()!==201 || (await receipt.json()).message.body!==ownText)throw Error('Missing authoritative message receipt');
    await page.getByText(ownText,{exact:false}).first().waitFor({timeout:10000});
    await page.screenshot({path:'docs/qa/mafia-chat.png'});
    await page.setViewportSize({width:1200,height:900});
    await page.waitForTimeout(300);
    await page.screenshot({path:'docs/qa/mafia-desktop.png'});
    if(errors.length||responses.some(r=>r.status>=400))throw Error(JSON.stringify({errors,responses}));
    await fs.writeFile('docs/qa/mafia-browser.json',JSON.stringify({errors,incomingMs,responses},null,2));
    console.log(JSON.stringify({incomingMs,errors,checks:'real HTTP message receipt, open-sheet SSE update, phone and desktop'}));
  }catch(error){console.log(JSON.stringify({errors,responses}));await page.screenshot({path:'docs/qa/mafia-browser-failure.png'});await fs.writeFile('docs/qa/mafia-browser-dom.txt',await page.locator('body').innerHTML());throw error;}
  finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
