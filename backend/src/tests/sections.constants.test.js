import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getDefaultSectionDefinition,
  listDefaultSectionsForSurface,
  normalizeSectionStatus,
  normalizeSurfaceScope,
  USER_APP_SECTION_KEYS,
} from '../modules/sections/sections.constants.js';

test('normalizeSectionStatus falls back to open for unknown values', () => {
  assert.equal(normalizeSectionStatus('maintenance'), 'maintenance');
  assert.equal(normalizeSectionStatus('COMING_SOON'), 'coming_soon');
  assert.equal(normalizeSectionStatus('unknown-status'), 'open');
  assert.equal(normalizeSectionStatus(null), 'open');
});

test('normalizeSurfaceScope only allows supported user scope', () => {
  assert.equal(normalizeSurfaceScope('user'), 'user');
  assert.equal(normalizeSurfaceScope('USER'), 'user');
  assert.equal(normalizeSurfaceScope('admin'), 'user');
});

test('user section registry contains all launch-controlled modules', () => {
  for (const key of [
    'shopping',
    'services',
    'taxi',
    'community',
    'jobs',
    'real_estate',
    'cars',
    'pharmacy',
  ]) {
    assert.equal(USER_APP_SECTION_KEYS.includes(key), true);
  }
});

test('default user section definitions are available for admin availability setup', () => {
  const sections = listDefaultSectionsForSurface('user');
  assert.equal(sections.length >= USER_APP_SECTION_KEYS.length, true);
  assert.equal(
    getDefaultSectionDefinition('shopping')?.displayName,
    'التسوق',
  );
  assert.equal(
    getDefaultSectionDefinition('taxi')?.sortOrder < getDefaultSectionDefinition('cars')?.sortOrder,
    true,
  );
});
