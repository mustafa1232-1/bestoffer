import 'dotenv/config';

import assert from 'node:assert/strict';
import { randomInt, randomUUID } from 'node:crypto';
import test from 'node:test';

import { q } from '../config/db.js';
import { createUser } from '../modules/auth/auth.repo.js';
import {
  createOfferingForProvider,
  createProviderProfile,
  createQuoteForRequest,
  createServiceRequestByCustomer,
  respondToQuoteByCustomer,
  updateRequestStatusByCustomer,
  updateRequestStatusByProviderUser,
} from '../modules/services/services.repo.js';
import { hashPin } from '../shared/utils/hash.js';

function makeSeed(prefix) {
  return `${prefix}_${Date.now().toString(36)}_${randomUUID().slice(0, 8)}`;
}

function makeUsername(prefix) {
  return `${prefix}_${randomUUID().replace(/-/g, '').slice(0, 6)}`;
}

function makePhone(prefix) {
  return `${prefix}${String(randomInt(0, 10_000_000)).padStart(7, '0')}`;
}

async function createAuthUser({ role, fullName, phone, username }) {
  const pinHash = await hashPin('1234');
  return createUser({
    fullName,
    username,
    phone,
    pinHash,
    block: 'A',
    buildingNumber: '1',
    apartment: '1',
    imageUrl: null,
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: 'services_legacy_test',
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
}

async function seedFixture() {
  const categoryR = await q(
    `SELECT id
     FROM service_categories
     WHERE level = 1
     ORDER BY id ASC
     LIMIT 1`
  );
  const mainCategoryId = Number(categoryR.rows[0]?.id || 0);
  assert.ok(mainCategoryId > 0, 'expected at least one seeded service category');

  const providerUser = await createAuthUser({
    role: 'service_provider',
    fullName: makeSeed('provider').slice(0, 20),
    phone: makePhone('077'),
    username: makeUsername('prov'),
  });
  const customerUser = await createAuthUser({
    role: 'user',
    fullName: makeSeed('customer').slice(0, 20),
    phone: makePhone('078'),
    username: makeUsername('cust'),
  });

  const provider = await createProviderProfile({
    userId: Number(providerUser.id),
    dto: {
      businessName: `${makeSeed('service')} Co`,
      mainCategoryId,
      bio: 'services legacy compatibility test provider',
      phone: providerUser.phone,
      city: 'Baghdad',
      area: 'Karrada',
      addressLine: 'Test street',
      servesAtHome: true,
      servesAtShop: false,
      servesRemote: false,
      hasEmergencyService: false,
      bookingPolicy: 'approval_required',
      pricingMode: 'mixed',
      yearsExperience: 4,
      hasTeam: false,
      teamSize: 0,
      acceptsCash: true,
      acceptsElectronic: true,
      averageResponseMinutes: 20,
      available247: true,
      providerGender: 'mixed',
      languages: ['ar'],
      areas: [{ city: 'Baghdad', area: 'Karrada' }],
      availabilityRules: [],
    },
    moderation: {
      approvalStatus: 'approved',
      approvedByUserId: 1,
      approvedAt: new Date().toISOString(),
    },
  });

  const offering = await createOfferingForProvider({
    userId: Number(providerUser.id),
    dto: {
      mainCategoryId,
      subcategoryId: null,
      name: `${makeSeed('hourly')} maintenance`,
      description: 'hourly pricing test offering',
      executionMode: 'both',
      requiresSchedule: false,
      requiresProviderApproval: true,
      estimatedDurationMinutes: 240,
      hasFixedPrice: false,
      startsFromPrice: 5000,
      inspectionRequired: false,
      customQuoteOnly: false,
      workersCount: 1,
      includesText: 'service scope',
      excludesText: null,
      materialsText: null,
      notes: 'test note',
      supportsHourlyBooking: true,
      supportsDailyBooking: false,
      supportsVisitBooking: true,
      supportsFullDayBooking: false,
      searchText: 'hourly maintenance',
      pricingOptions: [
        {
          pricingModel: 'per_hour',
          pricingUnit: 'hour',
          label: 'Hourly rate',
          amount: 5000,
          currency: 'IQD',
          minQuantity: 1,
          maxQuantity: 8,
          inspectionRequired: false,
          isDefault: true,
          isActive: true,
          sortOrder: 0,
        },
      ],
    },
  });

  return {
    providerUser,
    customerUser,
    provider,
    offering,
  };
}

async function cleanupFixture(fixture, requestIds = []) {
  const providerUserId = Number(fixture.providerUser.id);
  const customerUserId = Number(fixture.customerUser.id);
  const offeringId = Number(fixture.offering.id);
  const providerId = Number(fixture.provider.id);

  for (const requestId of requestIds) {
    await q(`DELETE FROM service_request_quotes WHERE request_id = $1`, [
      Number(requestId),
    ]).catch(() => {});
    await q(`DELETE FROM service_request_status_history WHERE request_id = $1`, [
      Number(requestId),
    ]).catch(() => {});
    await q(`DELETE FROM service_request_attachments WHERE request_id = $1`, [
      Number(requestId),
    ]).catch(() => {});
    await q(`DELETE FROM service_reviews WHERE request_id = $1`, [
      Number(requestId),
    ]).catch(() => {});
    await q(`DELETE FROM service_requests WHERE id = $1`, [Number(requestId)]).catch(
      () => {}
    );
  }

  await q(`DELETE FROM service_pricing_options WHERE offering_id = $1`, [
    offeringId,
  ]).catch(() => {});
  await q(`DELETE FROM service_offerings WHERE id = $1`, [offeringId]).catch(
    () => {}
  );
  await q(`DELETE FROM service_provider_areas WHERE provider_id = $1`, [
    providerId,
  ]).catch(() => {});
  await q(`DELETE FROM service_provider_availability_rules WHERE provider_id = $1`, [
    providerId,
  ]).catch(() => {});
  await q(`DELETE FROM service_provider_profiles WHERE id = $1`, [providerId]).catch(
    () => {}
  );
  await q(`DELETE FROM app_user WHERE id IN ($1, $2)`, [
    providerUserId,
    customerUserId,
  ]).catch(() => {});
}

test('legacy V1 completed stays on the legacy quote path even with promotion snapshot metadata', async (t) => {
  const fixture = await seedFixture();
  const requestIds = [];
  t.after(async () => {
    await cleanupFixture(fixture, requestIds);
  });

  const created = await createServiceRequestByCustomer({
    customerUserId: Number(fixture.customerUser.id),
    dto: {
      offeringId: Number(fixture.offering.id),
      providerId: Number(fixture.offering.providerId),
      requestedExecutionMode: 'home',
      requestedDate: '2026-07-20',
      requestedTime: '11:00',
      quantity: 2,
      durationHours: 1.5,
      notes: 'legacy quote request',
      addressLine: 'Phase legacy street',
      city: 'Baghdad',
      area: 'Bismayah',
      latitude: 33.3152,
      longitude: 44.3661,
      requiresHomeService: true,
      requiresQuote: true,
    },
  });
  requestIds.push(Number(created.id));
  assert.equal(created.bookingVersion, 1);
  assert.equal(created.bookingFlowKind, 'LEGACY');

  await q(
    `UPDATE service_requests
     SET booking_promotion_snapshot = $2::jsonb,
         booking_pricing_type = 'HOURLY',
         booking_price_version = 'legacy-v1',
         booking_unit_price_iqd = 5000,
         booking_quantity = 4,
         booking_duration_minutes = 240,
         booking_subtotal_iqd = 20000,
         booking_discount_iqd = 0,
         booking_service_fee_iqd = 0,
         booking_total_iqd = 20000
     WHERE id = $1`,
    [Number(created.id), JSON.stringify({ legacy: true, note: 'metadata present' })]
  );

  const quote = await createQuoteForRequest({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    dto: {
      pricingModel: 'custom_quote',
      pricingUnit: 'visit',
      amount: 45000,
      currency: 'IQD',
      note: 'legacy quote',
    },
  });
  assert.ok(quote?.id);

  const accepted = await respondToQuoteByCustomer({
    userId: Number(fixture.customerUser.id),
    requestId: Number(created.id),
    quoteId: Number(quote.id),
    action: 'accepted',
    note: 'Accepted in legacy compatibility test',
  });
  assert.equal(String(accepted.status || ''), 'accepted');
  assert.equal(Number(accepted.bookingVersion || 0), 2);
  assert.equal(accepted.bookingFlowKind, 'LEGACY');

  const providerAccepted = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'accepted',
    note: 'provider acknowledged',
  });
  assert.equal(Number(providerAccepted.bookingVersion || 0), 3);
  assert.equal(String(providerAccepted.status || ''), 'accepted');
  assert.equal(providerAccepted.bookingFlowKind, 'LEGACY');

  const providerInProgress = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'in_progress',
    note: 'provider started',
  });
  assert.equal(Number(providerInProgress.bookingVersion || 0), 4);
  assert.equal(String(providerInProgress.status || ''), 'in_progress');
  assert.equal(providerInProgress.bookingFlowKind, 'LEGACY');

  const completed = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'completed',
    note: 'provider completed',
  });
  assert.equal(Number(completed.bookingVersion || 0), 5);
  assert.equal(String(completed.status || ''), 'completed');
  assert.equal(completed.bookingFlowKind, 'LEGACY');
});

test('legacy V1 without promotion still uses the legacy quote path', async (t) => {
  const fixture = await seedFixture();
  const requestIds = [];
  t.after(async () => {
    await cleanupFixture(fixture, requestIds);
  });

  const created = await createServiceRequestByCustomer({
    customerUserId: Number(fixture.customerUser.id),
    dto: {
      offeringId: Number(fixture.offering.id),
      providerId: Number(fixture.offering.providerId),
      requestedExecutionMode: 'home',
      requestedDate: '2026-07-20',
      requestedTime: '13:00',
      quantity: 1,
      durationHours: 1,
      notes: 'legacy no promotion',
      addressLine: 'Phase legacy street',
      city: 'Baghdad',
      area: 'Bismayah',
      latitude: 33.3152,
      longitude: 44.3661,
      requiresHomeService: true,
      requiresQuote: false,
    },
  });
  requestIds.push(Number(created.id));
  assert.equal(created.bookingVersion, 1);
  assert.equal(created.bookingFlowKind, 'LEGACY');

  const accepted = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'accepted',
    note: 'legacy accepted without promotion',
  });
  assert.equal(Number(accepted.bookingVersion || 0), 2);
  assert.equal(String(accepted.status || ''), 'accepted');
  assert.equal(accepted.bookingFlowKind, 'LEGACY');

  const inProgress = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'in_progress',
    note: 'legacy started without promotion',
  });
  assert.equal(Number(inProgress.bookingVersion || 0), 3);
  assert.equal(String(inProgress.status || ''), 'in_progress');
  assert.equal(inProgress.bookingFlowKind, 'LEGACY');

  const completed = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'completed',
    note: 'legacy completed without promotion',
  });
  assert.equal(Number(completed.bookingVersion || 0), 4);
  assert.equal(String(completed.status || ''), 'completed');
  assert.equal(completed.bookingFlowKind, 'LEGACY');
});

test('legacy V1 with extra booking metadata still stays on the quote path', async (t) => {
  const fixture = await seedFixture();
  const requestIds = [];
  t.after(async () => {
    await cleanupFixture(fixture, requestIds);
  });

  const created = await createServiceRequestByCustomer({
    customerUserId: Number(fixture.customerUser.id),
    dto: {
      offeringId: Number(fixture.offering.id),
      providerId: Number(fixture.offering.providerId),
      requestedExecutionMode: 'home',
      requestedDate: '2026-07-20',
      requestedTime: '15:00',
      quantity: 3,
      durationHours: 2,
      notes: 'legacy extra metadata',
      addressLine: 'Phase legacy street',
      city: 'Baghdad',
      area: 'Bismayah',
      latitude: 33.3152,
      longitude: 44.3661,
      requiresHomeService: true,
      requiresQuote: true,
    },
  });
  requestIds.push(Number(created.id));
  assert.equal(created.bookingFlowKind, 'LEGACY');

  await q(
    `UPDATE service_requests
     SET booking_promotion_snapshot = $2::jsonb,
         booking_pricing_type = 'HOURLY',
         booking_price_version = 'legacy-v1-extra',
         booking_unit_price_iqd = 5000,
         booking_quantity = 4,
         booking_duration_minutes = 240,
         booking_subtotal_iqd = 20000,
         booking_discount_iqd = 500,
         booking_service_fee_iqd = 0,
         booking_total_iqd = 19500
     WHERE id = $1`,
    [Number(created.id), JSON.stringify({ meta: 'present' })]
  );

  const providerAccepted = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'accepted',
    note: 'metadata should not force V2',
  });
  assert.equal(Number(providerAccepted.bookingVersion || 0), 2);
  assert.equal(String(providerAccepted.status || ''), 'accepted');
  assert.equal(providerAccepted.bookingFlowKind, 'LEGACY');

  const completed = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'completed',
    note: 'metadata should still be legacy',
  });
  assert.equal(Number(completed.bookingVersion || 0), 3);
  assert.equal(String(completed.status || ''), 'completed');
  assert.equal(completed.bookingFlowKind, 'LEGACY');
});

test('canonical booking_version=2 transitions succeed through the V2 state machine', async (t) => {
  const fixture = await seedFixture();
  const requestIds = [];
  t.after(async () => {
    await cleanupFixture(fixture, requestIds);
  });

  const created = await createServiceRequestByCustomer({
    customerUserId: Number(fixture.customerUser.id),
    dto: {
      offeringId: Number(fixture.offering.id),
      providerId: Number(fixture.offering.providerId),
      pricingType: 'per_hour',
      durationMinutes: 240,
      durationHours: 4,
      quantity: 4,
      requestedExecutionMode: 'home',
      requestedDate: '2026-07-20',
      requestedTime: '10:00',
      requiresHomeService: true,
      requiresQuote: false,
      expectedPriceVersion: null,
      idempotencyKey: `${makeSeed('booking')}-canonical`,
    },
    attachments: [],
  });
  requestIds.push(Number(created.id));
  assert.equal(created.bookingVersion, 2);
  assert.equal(created.bookingFlowKind, 'V2');
  assert.equal(created.bookingStatus, 'PENDING_PROVIDER_CONFIRMATION');

  const confirmed = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'CONFIRMED',
    note: 'provider confirmed',
    expectedVersion: 2,
    idempotencyKey: `${makeSeed('booking')}-confirm`,
  });
  assert.equal(confirmed.bookingStatus, 'CONFIRMED');
  assert.equal(confirmed.bookingVersion, 3);

  const inProgress = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'IN_PROGRESS',
    note: 'provider started',
    expectedVersion: 3,
    idempotencyKey: `${makeSeed('booking')}-start`,
  });
  assert.equal(inProgress.bookingStatus, 'IN_PROGRESS');
  assert.equal(inProgress.bookingVersion, 4);

  const providerCompleted = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'PROVIDER_COMPLETED',
    note: 'provider completed',
    expectedVersion: 4,
    idempotencyKey: `${makeSeed('booking')}-provider-complete`,
  });
  assert.equal(providerCompleted.bookingStatus, 'PROVIDER_COMPLETED');
  assert.equal(providerCompleted.bookingVersion, 5);
  assert.ok(providerCompleted.bookingProviderCompletedAt);
  assert.ok(providerCompleted.bookingFinalizationDueAt);

  const completed = await updateRequestStatusByCustomer({
    userId: Number(fixture.customerUser.id),
    requestId: Number(created.id),
    dto: {
      status: 'COMPLETED',
      note: 'customer accepted',
      expectedVersion: 5,
      idempotencyKey: `${makeSeed('booking')}-customer-complete`,
    },
  });
  assert.equal(completed.bookingStatus, 'COMPLETED');
  assert.equal(completed.bookingVersion, 6);
  assert.ok(completed.bookingFinalizedAt);
});

test('canonical booking_version=2 rejects invalid terminal shortcuts', async (t) => {
  const fixture = await seedFixture();
  const requestIds = [];
  t.after(async () => {
    await cleanupFixture(fixture, requestIds);
  });

  const created = await createServiceRequestByCustomer({
    customerUserId: Number(fixture.customerUser.id),
    dto: {
      offeringId: Number(fixture.offering.id),
      providerId: Number(fixture.offering.providerId),
      pricingType: 'per_hour',
      durationMinutes: 240,
      durationHours: 4,
      quantity: 4,
      requestedExecutionMode: 'home',
      requestedDate: '2026-07-20',
      requestedTime: '10:00',
      requiresHomeService: true,
      requiresQuote: false,
      expectedPriceVersion: null,
      idempotencyKey: `${makeSeed('booking')}-invalid`,
    },
    attachments: [],
  });
  requestIds.push(Number(created.id));

  await assert.rejects(
    () =>
      updateRequestStatusByProviderUser({
        userId: Number(fixture.providerUser.id),
        requestId: Number(created.id),
        status: 'COMPLETED',
        note: 'invalid shortcut',
        expectedVersion: 2,
        idempotencyKey: `${makeSeed('booking')}-invalid-shortcut`,
      }),
    (error) => {
      assert.equal(error.status, 409);
      assert.equal(error.code, 'SERVICE_BOOKING_INVALID_TRANSITION');
      return true;
    }
  );
});

test('canonical booking_version=2 keeps a lowercase corrupted status on the canonical path', async (t) => {
  const fixture = await seedFixture();
  const requestIds = [];
  t.after(async () => {
    await cleanupFixture(fixture, requestIds);
  });

  const created = await createServiceRequestByCustomer({
    customerUserId: Number(fixture.customerUser.id),
    dto: {
      offeringId: Number(fixture.offering.id),
      providerId: Number(fixture.offering.providerId),
      pricingType: 'per_hour',
      durationMinutes: 240,
      durationHours: 4,
      quantity: 4,
      requestedExecutionMode: 'home',
      requestedDate: '2026-07-20',
      requestedTime: '10:00',
      requiresHomeService: true,
      requiresQuote: false,
      expectedPriceVersion: null,
      idempotencyKey: `${makeSeed('booking')}-corrupted`,
    },
    attachments: [],
  });
  requestIds.push(Number(created.id));
  assert.equal(created.bookingFlowKind, 'V2');

  await q(
    `UPDATE service_requests
     SET status = 'in_progress'
     WHERE id = $1`,
    [Number(created.id)]
  );

  const providerCompleted = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'PROVIDER_COMPLETED',
    note: 'corrupted lowercase status should not force legacy',
    expectedVersion: 2,
    idempotencyKey: `${makeSeed('booking')}-corrupted-complete`,
  });
  assert.equal(providerCompleted.bookingStatus, 'PROVIDER_COMPLETED');
  assert.equal(providerCompleted.bookingVersion, 3);
  assert.equal(providerCompleted.bookingFlowKind, 'V2');
});

test('legacy uppercase accidental status remains legacy while version increments', async (t) => {
  const fixture = await seedFixture();
  const requestIds = [];
  t.after(async () => {
    await cleanupFixture(fixture, requestIds);
  });

  const created = await createServiceRequestByCustomer({
    customerUserId: Number(fixture.customerUser.id),
    dto: {
      offeringId: Number(fixture.offering.id),
      providerId: Number(fixture.offering.providerId),
      requestedExecutionMode: 'home',
      requestedDate: '2026-07-20',
      requestedTime: '17:00',
      quantity: 1,
      durationHours: 1,
      notes: 'legacy accidental uppercase',
      addressLine: 'Phase legacy street',
      city: 'Baghdad',
      area: 'Bismayah',
      latitude: 33.3152,
      longitude: 44.3661,
      requiresHomeService: true,
      requiresQuote: true,
    },
  });
  requestIds.push(Number(created.id));
  assert.equal(created.bookingFlowKind, 'LEGACY');

  await q(
    `UPDATE service_requests
     SET status = 'IN_PROGRESS'
     WHERE id = $1`,
    [Number(created.id)]
  );

  const completed = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'completed',
    note: 'legacy uppercase row should stay legacy',
  });
  assert.equal(Number(completed.bookingVersion || 0), 2);
  assert.equal(String(completed.status || ''), 'completed');
  assert.equal(completed.bookingFlowKind, 'LEGACY');
});

test('full legacy quote lifecycle remains legacy while version increments', async (t) => {
  const fixture = await seedFixture();
  const requestIds = [];
  t.after(async () => {
    await cleanupFixture(fixture, requestIds);
  });

  const created = await createServiceRequestByCustomer({
    customerUserId: Number(fixture.customerUser.id),
    dto: {
      offeringId: Number(fixture.offering.id),
      providerId: Number(fixture.offering.providerId),
      requestedExecutionMode: 'home',
      requestedDate: '2026-07-20',
      requestedTime: '19:00',
      quantity: 2,
      durationHours: 1.5,
      notes: 'legacy quote lifecycle',
      addressLine: 'Phase legacy street',
      city: 'Baghdad',
      area: 'Bismayah',
      latitude: 33.3152,
      longitude: 44.3661,
      requiresHomeService: true,
      requiresQuote: true,
    },
  });
  requestIds.push(Number(created.id));
  assert.equal(created.bookingFlowKind, 'LEGACY');

  const quote = await createQuoteForRequest({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    dto: {
      pricingModel: 'custom_quote',
      pricingUnit: 'visit',
      amount: 45000,
      currency: 'IQD',
      note: 'legacy quote lifecycle',
    },
  });
  assert.ok(quote?.id);

  const accepted = await respondToQuoteByCustomer({
    userId: Number(fixture.customerUser.id),
    requestId: Number(created.id),
    quoteId: Number(quote.id),
    action: 'accepted',
    note: 'Accepted in legacy quote lifecycle test',
  });
  assert.equal(String(accepted.status || ''), 'accepted');
  assert.equal(Number(accepted.bookingVersion || 0), 2);
  assert.equal(accepted.bookingFlowKind, 'LEGACY');

  const providerAccepted = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'accepted',
    note: 'provider acknowledged quote acceptance',
  });
  assert.equal(Number(providerAccepted.bookingVersion || 0), 3);
  assert.equal(providerAccepted.bookingFlowKind, 'LEGACY');

  const providerInProgress = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'in_progress',
    note: 'provider started quote lifecycle',
  });
  assert.equal(Number(providerInProgress.bookingVersion || 0), 4);
  assert.equal(providerInProgress.bookingFlowKind, 'LEGACY');

  const completed = await updateRequestStatusByProviderUser({
    userId: Number(fixture.providerUser.id),
    requestId: Number(created.id),
    status: 'completed',
    note: 'provider completed quote lifecycle',
  });
  assert.equal(Number(completed.bookingVersion || 0), 5);
  assert.equal(String(completed.status || ''), 'completed');
  assert.equal(completed.bookingFlowKind, 'LEGACY');
});
