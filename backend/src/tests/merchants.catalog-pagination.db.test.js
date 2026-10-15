import assert from 'node:assert/strict';
import test, { after } from 'node:test';
import { q, pool } from '../config/db.js';
import { listMerchantProducts } from '../modules/merchants/merchants.service.js';
import { app } from '../app.js';
import { createActor, request, startLocalServer, stopLocalServer } from '../scripts/e2eTestUtils.js';

after(() => pool.end());

test('catalog filters and sorting apply before pagination across the entire store', async () => {
  assert.match(new URL(process.env.DATABASE_URL).pathname, /\/qa_f_/);
  const merchant = await q(`INSERT INTO merchant(name,type,is_approved,is_disabled,is_open)
    VALUES ('Pagination QA','market',TRUE,FALSE,TRUE) RETURNING id`);
  const merchantId = Number(merchant.rows[0].id);
  const categories = await q(`INSERT INTO merchant_category(merchant_id,name,sort_order)
    VALUES ($1,'First',0),($1,'Second',1) RETURNING id`, [merchantId]);
  const [firstCategory,secondCategory] = categories.rows.map((r) => Number(r.id));
  const products = await q(`INSERT INTO product(merchant_id,category_id,name,price,sort_order,is_available)
    SELECT $1,CASE WHEN i <= 24 THEN $2::bigint ELSE $3::bigint END,'Product ' || i,1000+i,i,i <> 26
    FROM generate_series(1,30) i RETURNING id,name`, [merchantId,firstCategory,secondCategory]);
  const first = await listMerchantProducts(merchantId,{limit:24});
  const second = await listMerchantProducts(merchantId,{limit:24,offset:24});
  assert.equal(first.length,24);
  assert.equal(second.length,6);
  assert.equal(new Set([...first,...second].map((p) => p.id)).size,30);
  const search = await listMerchantProducts(merchantId,{search:'Product 30',limit:24});
  assert.deepEqual(search.map((p) => p.name),['Product 30']);
  const category = await listMerchantProducts(merchantId,{categoryId:secondCategory,onlyAvailable:true});
  assert.equal(category.length,5);
  assert.ok(category.every((p) => p.name !== 'Product 26'));
  const favoriteId = Number(products.rows.find((p) => p.name === 'Product 30').id);
  assert.deepEqual((await listMerchantProducts(merchantId,{productIds:[favoriteId]})).map((p) => Number(p.id)),[favoriteId]);
  assert.deepEqual(await listMerchantProducts(merchantId,{productIds:[]}),[]);
  assert.equal((await listMerchantProducts(merchantId,{sort:'priceHighToLow',limit:1}))[0].name,'Product 30');
  assert.equal((await listMerchantProducts(merchantId,{sort:'priceLowToHigh',limit:1}))[0].name,'Product 1');
  await q(`UPDATE product SET discounted_price=10 WHERE id=$1`,[favoriteId]);
  assert.equal((await listMerchantProducts(merchantId,{sort:'biggestDiscount',limit:1}))[0].name,'Product 30');

  const offer = await q(`INSERT INTO merchant_offer(merchant_id,title,offer_type,discount_value,status)
    VALUES ($1,'QA active discount','percentage',99,'active') RETURNING id`,[merchantId]);
  const firstId = Number(products.rows.find((p) => p.name === 'Product 1').id);
  await q(`INSERT INTO merchant_offer_product(offer_id,product_id) VALUES ($1,$2)`,[offer.rows[0].id,firstId]);
  const priced = await listMerchantProducts(merchantId,{sort:'priceLowToHigh',limit:2});
  assert.deepEqual(priced.map((p) => p.name),['Product 30','Product 1']);
  assert.equal(Number(priced[1].discounted_price),10.01);

  const {server,baseUrl} = await startLocalServer(app);
  try {
    const actor = createActor('catalog-guest','catalog-pagination');
    actor.appFlavor = 'user';
    const base = `/api/merchants/${merchantId}/products?limit=1`;
    const low = await request(baseUrl,actor,'GET',`${base}&sort=priceLowToHigh`);
    const high = await request(baseUrl,actor,'GET',`${base}&sort=priceHighToLow`);
    const empty = await request(baseUrl,actor,'GET',`${base}&productIds=`);
    assert.equal(low.status,200);
    assert.equal(high.status,200);
    assert.equal(empty.status,200);
    assert.equal(low.data[0].name,'Product 30');
    assert.equal(high.data[0].name,'Product 29');
    assert.deepEqual(empty.data,[], 'distinct query filters must not share a hot-cache response');
  } finally { await stopLocalServer(server); }

  await q(`INSERT INTO inventory_settings(merchant_id,inventory_enabled) VALUES ($1,TRUE)
    ON CONFLICT (merchant_id) DO UPDATE SET inventory_enabled=TRUE`,[merchantId]);
  await q(`INSERT INTO product_variant(product_id,signature,selections_json,stock_quantity,is_available)
    VALUES ($1,'size:m','[{"groupCode":"size","optionCode":"m"}]'::jsonb,2,TRUE)`,[favoriteId]);
  const available = await listMerchantProducts(merchantId,{onlyAvailable:true,productIds:[favoriteId]});
  assert.equal(available.length,1);
  assert.equal(available[0].variants.length,1);
  assert.equal(available[0].variants[0].stockQuantity,2);
  await q(`UPDATE merchant SET is_disabled=TRUE WHERE id=$1`,[merchantId]);
  assert.deepEqual(await listMerchantProducts(merchantId,{limit:3}),[]);
});
