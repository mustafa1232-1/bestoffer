import assert from 'node:assert/strict';
import test from 'node:test';
import { normalizeCatalogQuery } from '../modules/merchants/merchant-catalog-query.js';

test('catalog query bounds pagination and permits only known ordering', () => {
  const normalized = normalizeCatalogQuery({ limit: '999', offset: '-10', sort: 'price; DROP TABLE product' });
  assert.equal(normalized.limit, 200);
  assert.equal(normalized.offset, 0);
  assert.equal(normalized.sort, 'recommended');
  assert.equal(normalizeCatalogQuery({ offset: 'Infinity' }).offset, 0);
  assert.equal(normalizeCatalogQuery({ limit: 'NaN' }).limit, 200);
  assert.equal(normalizeCatalogQuery({ limit: 24, offset: 24 }).offset, 24);
});

test('catalog query preserves empty favorites, validates ids and search', () => {
  assert.equal(normalizeCatalogQuery().productIds, null);
  assert.deepEqual(normalizeCatalogQuery({ productIds: '' }).productIds, []);
  const query = normalizeCatalogQuery({ productIds: '1,2,2,-1,bad,0,1.5', search: '  shirt  ', onlyAvailable: 'true', categoryId: '5' });
  assert.deepEqual(query.productIds, [1, 2]);
  assert.equal(query.search, 'shirt');
  assert.equal(query.categoryId, 5);
  assert.equal(query.onlyAvailable, true);
});
