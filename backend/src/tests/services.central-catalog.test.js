import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getCentralServiceCatalogItem,
  listCentralServiceCatalog,
} from '../modules/services/services.catalog.js';
import {
  validateCentralServiceRequestBody,
  validateCentralServiceRoutingBody,
  validateOfferingBody,
} from '../modules/services/services.validators.js';

test('service offering preserves the custom text displayed beside its price', () => {
  const result = validateOfferingBody({
    name: 'تنظيف شقة',
    mainCategoryId: 1,
    subcategoryId: 2,
    pricingOptions: [
      {
        pricingModel: 'fixed_package',
        pricingUnit: 'job',
        label: 'للعملية كاملة',
        amount: 5000,
        isDefault: true,
      },
    ],
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.pricingOptions[0].label, 'للعملية كاملة');
});

test('service offering can be published under a main category only', () => {
  const result = validateOfferingBody({
    name: 'Main category service',
    mainCategoryId: 1,
    executionMode: 'home',
    startsFromPrice: 5000,
    pricingOptions: [
      {
        pricingModel: 'per_hour',
        pricingUnit: 'hour',
        label: 'Per hour',
        amount: 5000,
        isDefault: true,
      },
    ],
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.subcategoryId, null);
  assert.equal(result.value.pricingOptions[0].pricingModel, 'per_hour');
});

test('central services catalog exposes the supported service families', () => {
  const items = listCentralServiceCatalog();
  assert.deepEqual(
    items.map((item) => item.key),
    [
      'legal',
      'medical',
      'home_maintenance',
      'roadside',
      'cleaning',
      'wellbeing',
      'sos',
    ],
  );
  assert.equal(getCentralServiceCatalogItem('SOS')?.emergency, true);
});

test('normal central request accepts a quick issue and valid execution mode', () => {
  const result = validateCentralServiceRequestBody({
    serviceKey: 'home_maintenance',
    quickIssue: 'كهرباء',
    requestedExecutionMode: 'home',
    urgency: 'urgent',
    preferredContact: 'phone',
    contactPhone: '07700000000',
  });
  assert.equal(result.ok, true);
  assert.equal(result.value.urgency, 'urgent');
});

test('SOS requires an emergency target and precise coordinates', () => {
  const missing = validateCentralServiceRequestBody({
    serviceKey: 'sos',
    description: 'حالة عاجلة',
  });
  assert.equal(missing.ok, false);
  assert.ok(missing.errors.includes('emergencyTarget'));
  assert.ok(missing.errors.includes('location'));

  const valid = validateCentralServiceRequestBody({
    serviceKey: 'sos',
    description: 'حالة عاجلة',
    emergencyTarget: 'ambulance',
    latitude: 33.283,
    longitude: 44.486,
  });
  assert.equal(valid.ok, true);
  assert.equal(valid.value.urgency, 'emergency');
});

test('SOS accepts traffic, family protection, road and rescue categories', () => {
  for (const emergencyTarget of [
    'traffic_accident',
    'family_protection',
    'road_hazard',
    'rescue',
    'security_threat',
    'community_police',
    'drugs',
    'organized_crime',
    'national_security',
    'intelligence',
  ]) {
    const result = validateCentralServiceRequestBody({
      serviceKey: 'sos',
      quickIssue: 'حالة طارئة',
      emergencyTarget,
      latitude: 33.3152,
      longitude: 44.3661,
    });
    assert.equal(result.ok, true, emergencyTarget);
  }
});

test('routing assignment requires a professional contact', () => {
  const missing = validateCentralServiceRoutingBody({
    routingStatus: 'assigned',
  });
  assert.equal(missing.ok, false);
  assert.ok(missing.errors.includes('professional'));

  const valid = validateCentralServiceRoutingBody({
    routingStatus: 'assigned',
    professionalName: 'الفني المناوب',
  });
  assert.equal(valid.ok, true);
});
