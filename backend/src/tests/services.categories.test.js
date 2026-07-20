import assert from 'node:assert/strict';
import test from 'node:test';

import { q } from '../config/db.js';
import { createUser } from '../modules/auth/auth.repo.js';
import {
  createPublicCategory,
  listPublicCategories,
} from '../modules/services/services.service.js';
import { validatePublicCategoryBody } from '../modules/services/services.validators.js';
import { hashPin } from '../shared/utils/hash.js';

// Seed the acting admin instead of assuming user id 1 exists. A freshly
// migrated QA database has no such row, and the hardcoded id violated
// service_categories_created_by_user_id_fkey (23503) — it only ever passed
// when an unrelated parallel test file happened to own id 1.
let actorPromise = null;
function actorUserId() {
  actorPromise ??= (async () => {
    const suffix = `${Date.now().toString(36)}${Math.random()
      .toString(36)
      .slice(2, 8)}`;
    const user = await createUser({
      fullName: 'Services Category Admin',
      username: `svc_cat_${suffix}`.slice(0, 24),
      phone: `07${String(Date.now()).slice(-9)}`,
      pinHash: await hashPin('1234'),
      block: 'A',
      buildingNumber: '1',
      apartment: '1',
      role: 'admin',
    });
    return Number(user.id);
  })();
  return actorPromise;
}

test('validatePublicCategoryBody requires a category name', () => {
  const empty = validatePublicCategoryBody({});
  assert.equal(empty.ok, false);
  assert.ok(empty.errors.includes('name'));

  const valid = validatePublicCategoryBody({ name: 'خدمات توصيل' });
  assert.equal(valid.ok, true);
  assert.equal(valid.value.name, 'خدمات توصيل');
});

test('service public categories can be created and listed immediately', async () => {
  const uniqueName = `نوع خدمة اختبار ${Date.now()}`;
  const created = await createPublicCategory({
    userId: await actorUserId(),
    dto: { name: uniqueName },
  });

  assert.ok(created);
  assert.equal(created.name, uniqueName);
  assert.equal(created.level, 1);
  assert.equal(created.isActive, true);
  assert.equal(created.isPublic, true);

  const again = await createPublicCategory({
    userId: await actorUserId(),
    dto: { name: uniqueName },
  });

  assert.ok(again);
  assert.equal(again.id, created.id);

  const roots = await listPublicCategories();
  assert.ok(roots.length >= 25);
  const seededRoot = roots.find((item) => item.name === 'تنظيف شقق');
  assert.ok(seededRoot, 'expected seeded root category تنظيف شقق');
  assert.ok(
    seededRoot.children.length >= 5,
    'expected تنظيف شقق to have seeded subcategories'
  );
  const matches = roots.filter((item) => item.name === uniqueName);
  assert.equal(matches.length, 1);
  assert.equal(matches[0].children.length, 0);

  await q('DELETE FROM service_categories WHERE id = $1', [created.id]);
});

test('service public subcategories can be created under an existing root category', async () => {
  const rootResult = await q(
    `SELECT id
     FROM service_categories
     WHERE name = $1
       AND level = 1
       AND parent_id IS NULL
     LIMIT 1`,
    ['تنظيف شقق']
  );
  const root = rootResult.rows[0] || null;
  assert.ok(root, 'expected seeded root category تنظيف شقق');

  const uniqueName = `فئة فرعية اختبار ${Date.now()}`;
  const created = await createPublicCategory({
    userId: await actorUserId(),
    dto: { name: uniqueName, parentCategoryId: Number(root.id) },
  });

  assert.ok(created);
  assert.equal(created.name, uniqueName);
  assert.equal(created.level, 2);
  assert.equal(created.parentId, Number(root.id));

  const roots = await listPublicCategories();
  const matchingRoot = roots.find((item) => item.id === Number(root.id));
  assert.ok(matchingRoot);
  assert.ok(
    matchingRoot.children.some((item) => item.name === uniqueName),
    'expected new subcategory to be returned with the root tree'
  );

  await q('DELETE FROM service_categories WHERE id = $1', [created.id]);
});
