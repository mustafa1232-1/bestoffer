import 'dotenv/config';

import assert from 'node:assert/strict';
import { randomInt, randomUUID } from 'node:crypto';
import test from 'node:test';

import { q } from '../config/db.js';
import { createUser } from '../modules/auth/auth.repo.js';
import {
  createOfferingForProvider,
  createProviderProfile,
  createServiceRequestByCustomer,
  previewServiceBookingByCustomer,
  updateRequestStatusByCustomer,
  updateRequestStatusByProviderUser,
} from '../modules/services/services.repo.js';
import {
  assertValidServiceBookingTransition,
  buildServiceBookingPreview,
} from '../modules/services/services.booking.core.js';
import { validateServiceRequestBody } from '../modules/services/services.validators.js';
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

async function createAuthUser({
  role,
  fullName,
  phone,
  username,
}) {
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
    analyticsConsentVersion: 'services_booking_contract_test',
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
}

async function seedBookingFixture() {
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
    fullName: makeSeed('provider'),
    phone: makePhone('077'),
    username: makeUsername('prov'),
  });
  const customerUser = await createAuthUser({
    role: 'user',
    fullName: makeSeed('customer'),
    phone: makePhone('078'),
    username: makeUsername('cust'),
  });
  // Seed the approver instead of assuming user id 1 exists: a freshly migrated
  // QA database has no admin row, and the hardcoded id violated
  // service_provider_profiles_approved_by_user_id_fkey (23503).
  const approverUser = await createAuthUser({
    role: 'admin',
    fullName: makeSeed('approver'),
    phone: makePhone('079'),
    username: makeUsername('appr'),
  });

  const provider = await createProviderProfile({
    userId: Number(providerUser.id),
    dto: {
      businessName: `${makeSeed('service')} Co`,
      mainCategoryId,
      bio: 'service booking contract test provider',
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
      approvedByUserId: Number(approverUser.id),
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
    approverUser,
    provider,
    offering,
  };
}

async function cleanupBookingFixture(fixture, requestIds = []) {
  const providerUserId = Number(fixture.providerUser.id);
  const customerUserId = Number(fixture.customerUser.id);
  const offeringId = Number(fixture.offering.id);
  const providerId = Number(fixture.provider.id);

  for (const requestId of requestIds) {
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
  await q(`DELETE FROM app_user WHERE id IN ($1, $2, $3)`, [
    providerUserId,
    customerUserId,
    Number(fixture.approverUser.id),
  ]).catch(() => {});
}

test('canonical booking pricing preview computes the 4-hour fixture', () => {
  const preview = buildServiceBookingPreview({
    offering: { id: 10, providerId: 20 },
    pricingOption: {
      id: 1,
      pricingModel: 'per_hour',
      pricingUnit: 'hour',
      amount: 5000,
      isDefault: true,
      isActive: true,
    },
    pricingType: 'per_hour',
    durationMinutes: 240,
  });

  assert.equal(preview.pricingType, 'HOURLY');
  assert.equal(preview.unitPriceIqd, 5000);
  assert.equal(preview.quantity, 4);
  assert.equal(preview.durationMinutes, 240);
  assert.equal(preview.subtotalIqd, 20000);
  assert.equal(preview.discountIqd, 0);
  assert.equal(preview.serviceFeeIqd, 0);
  assert.equal(preview.totalIqd, 20000);
  assert.ok(preview.priceVersion);
});

test('service request validation rejects client-supplied booking_flow_kind', () => {
  const v = validateServiceRequestBody({
    offeringId: 1,
    providerId: 2,
    booking_flow_kind: 'V2',
    pricingType: 'per_hour',
    durationMinutes: 240,
  });

  assert.equal(v.ok, false);
  assert.ok(v.errors.includes('booking_flow_kind'));
});

test('service booking preview/create persists the price snapshot and rejects stale pricing', async (t) => {
  const fixture = await seedBookingFixture();
  const requestIds = [];
  t.after(async () => {
    await cleanupBookingFixture(fixture, requestIds);
  });

  const preview = await previewServiceBookingByCustomer({
    customerUserId: Number(fixture.customerUser.id),
    dto: {
      offeringId: Number(fixture.offering.id),
      providerId: Number(fixture.offering.providerId),
      pricingType: 'per_hour',
      durationMinutes: 240,
    },
  });

  assert.ok(preview);
  assert.equal(preview.preview.pricingType, 'HOURLY');
  assert.equal(preview.preview.unitPriceIqd, 5000);
  assert.equal(preview.preview.quantity, 4);
  assert.equal(preview.preview.totalIqd, 20000);

  const createDto = {
    offeringId: Number(fixture.offering.id),
    providerId: Number(fixture.offering.providerId),
    pricingType: 'per_hour',
    durationMinutes: 240,
    durationHours: 4,
    quantity: 4,
    requestedExecutionMode: 'home',
    requestedDate: '2026-07-18',
    requestedTime: '10:00',
    requiresHomeService: true,
    requiresQuote: false,
    expectedPriceVersion: preview.preview.priceVersion,
    idempotencyKey: `${makeSeed('booking')}-one`,
  };

  const created = await createServiceRequestByCustomer({
    customerUserId: Number(fixture.customerUser.id),
    dto: createDto,
    attachments: [],
  });
  requestIds.push(Number(created.id));

  assert.ok(created);
  assert.equal(created.bookingStatus, 'PENDING_PROVIDER_CONFIRMATION');
  assert.equal(created.bookingVersion, 2);
  assert.equal(created.bookingFlowKind, 'V2');
  assert.equal(created.bookingSubtotalIqd, 20000);
  assert.equal(created.bookingTotalIqd, 20000);
  assert.equal(created.finalPrice, 20000);
  assert.equal(created.finalCurrency, 'IQD');
  assert.equal(created.bookingIdempotencyKey, createDto.idempotencyKey);

  const replay = await createServiceRequestByCustomer({
    customerUserId: Number(fixture.customerUser.id),
    dto: createDto,
    attachments: [],
  });
  assert.equal(replay.id, created.id);
  assert.equal(replay.bookingFlowKind, 'V2');
  assert.equal(replay.bookingIdempotencyKey, createDto.idempotencyKey);

  await q(
    `UPDATE service_pricing_options
     SET amount = 6000
     WHERE offering_id = $1`,
    [Number(fixture.offering.id)]
  );

  await assert.rejects(
    () =>
      createServiceRequestByCustomer({
        customerUserId: Number(fixture.customerUser.id),
        dto: {
          ...createDto,
          idempotencyKey: `${makeSeed('booking')}-two`,
        },
        attachments: [],
      }),
    (error) => {
      assert.equal(error.status, 409);
      assert.equal(error.message, 'SERVICE_PRICE_CHANGED');
      return true;
    }
  );
});
test('booking_flow_kind is immutable for persisted bookings', async (t) => {
  const fixture = await seedBookingFixture();
  const requestIds = [];
  t.after(async () => {
    await cleanupBookingFixture(fixture, requestIds);
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
      requestedDate: '2026-07-18',
      requestedTime: '10:00',
      requiresHomeService: true,
      requiresQuote: false,
      expectedPriceVersion: null,
      idempotencyKey: `${makeSeed('booking')}-immutable`,
    },
    attachments: [],
  });
  requestIds.push(Number(created.id));

  await assert.rejects(
    () =>
      q(
        `UPDATE service_requests
         SET booking_flow_kind = 'LEGACY'
         WHERE id = $1`,
        [Number(created.id)]
      ),
    (error) => {
      assert.ok(String(error.message || '').includes('booking_flow_kind'));
      return true;
    }
  );
});

test('provider confirmation and customer finalization move through the booking state machine', async (t) => {
  const fixture = await seedBookingFixture();
  const requestIds = [];
  t.after(async () => {
    await cleanupBookingFixture(fixture, requestIds);
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
      requestedDate: '2026-07-18',
      requestedTime: '10:00',
      requiresHomeService: true,
      requiresQuote: false,
      expectedPriceVersion: null,
      idempotencyKey: `${makeSeed('booking')}-state`,
    },
    attachments: [],
  });
  requestIds.push(Number(created.id));

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

  await assert.rejects(
    () =>
      updateRequestStatusByCustomer({
        userId: Number(fixture.customerUser.id),
        requestId: Number(created.id),
        dto: {
          status: 'DISPUTED',
          note: 'duplicate',
          expectedVersion: 4,
          idempotencyKey: `${makeSeed('booking')}-bad-version`,
        },
      }),
    (error) => {
      assert.equal(error.status, 409);
      return true;
    }
  );
});

test('assertValidServiceBookingTransition rejects invalid inputs', () => {
  assert.throws(
    () => assertValidServiceBookingTransition(null, ''),
    (error) => {
      assert.equal(error.status, 400);
      return true;
    }
  );
});
