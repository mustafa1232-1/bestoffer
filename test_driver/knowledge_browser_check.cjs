const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('node:fs/promises');

(async () => {
  const browser = await chromium.launch({headless:true});
  const page = await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
  const errors=[];
  const answers=[];
  let snapshot;
  page.on('pageerror',e=>errors.push(e.message));
  page.on('response',async response=>{
    if(response.url().endsWith('/answers')) answers.push({status:response.status(),body:await response.json()});
    if(/\/matches\/\d+$/.test(response.url())&&response.ok()) snapshot=await response.json();
  });
  try {
    await page.goto('http://127.0.0.1:4879',{waitUntil:'networkidle',timeout:120000});
    await page.locator('flutter-view').waitFor({timeout:60000});
    const semantics=page.locator('flt-semantics-placeholder');
    if(await semantics.count()) await semantics.evaluate(el=>el.click());
    await page.getByText('اختر منطقة وإجابة',{exact:true}).waitFor({timeout:30000});
    await page.screenshot({path:'docs/qa/knowledge-web-phone.png'});
    await page.getByText(snapshot.question.options[0],{exact:true}).click();
    await page.mouse.move(190,600);
    await page.mouse.wheel(0,270);
    await page.waitForTimeout(350);
    const territory=page.getByRole('button',{name:/^سوق المعرفة/}).first();
    const bounds=await territory.boundingBox();
    console.log('Territory bounds',bounds);
    await page.screenshot({path:'docs/qa/knowledge-web-before-selection.png'});
    if(!bounds || bounds.x<0 || bounds.x+bounds.width>390 || bounds.y<0 || bounds.y+bounds.height>780) {
      console.log(await territory.evaluate(el=>el.outerHTML+'\n'+el.parentElement.outerHTML));
      throw new Error('Territory not in viewport after scroll');
    }
    await page.mouse.click(bounds.x+bounds.width/2,bounds.y+bounds.height/2);
    await page.getByText('اعتماد الإجابة',{exact:true}).click();
    await page.getByText('تم تسجيل إجابتك',{exact:true}).waitFor({timeout:12000});
    await page.screenshot({path:'docs/qa/knowledge-web-confirmed.png'});
    await page.mouse.wheel(0,200);
    await page.screenshot({path:'docs/qa/knowledge-theme-map-browser.png'});
    if(answers.length!==1 || answers[0].status!==200 || answers[0].body.submitted!==true) throw new Error('Missing persisted HTTP receipt');
    await page.getByRole('button',{name:'إعدادات الحركة والصوت',exact:true}).click();
    await page.getByRole('switch',{name:/تقليل الحركة/}).waitFor();
    await page.getByRole('switch',{name:/تقليل الحركة/}).click();
    await page.screenshot({path:'docs/qa/knowledge-web-settings.png'});
    await page.keyboard.press('Escape');
    await page.setViewportSize({width:1100,height:800});
    await page.screenshot({path:'docs/qa/knowledge-web-desktop.png'});
    for(let i=0;i<6 && !await page.getByText('دردشة الفريق والصوت',{exact:true}).isVisible();i++) {
      await page.mouse.move(550,550);
      await page.mouse.wheel(0,260);
      await page.waitForTimeout(100);
    }
    await page.getByText('دردشة الفريق والصوت',{exact:true}).click();
    await page.waitForTimeout(300);
    await page.mouse.move(550,550);
    await page.mouse.wheel(0,500);
    await page.getByText('صوت الفريق',{exact:true}).waitFor();
    if(errors.length) throw new Error('Browser errors: '+errors.join('; '));
    console.log('Real Flutter web + local PostgreSQL: selection, persisted answer, chat and settings passed.');
    await fs.writeFile('docs/qa/knowledge-web-report.json',JSON.stringify({errors,answers},null,2));
  } catch(error) {
    await page.screenshot({path:'docs/qa/knowledge-web-failure.png'});
    console.log((await page.locator('body').innerText()).slice(0,6000));
    throw error;
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});
