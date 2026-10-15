import 'dotenv/config';

import assert from 'node:assert/strict';
import { randomInt, randomUUID } from 'node:crypto';
import test from 'node:test';

import { q } from '../config/db.js';
import { createUser } from '../modules/auth/auth.repo.js';
import {
  appendEmergencyLocation,
  appendEmergencyMessage,
  getEmergencyThread,
  listEmergencyRequestsForAdmin,
} from '../modules/services/services.repo.js';
import { hashPin } from '../shared/utils/hash.js';

function unique(prefix) {
  return `${prefix}_${Date.now().toString(36)}_${randomUUID().slice(0, 8)}`;
}

async function createTestUser(role, prefix) {
  return createUser({
    fullName: unique(prefix),
    username: `${prefix.slice(0, 8)}_${randomUUID().replace(/-/g, '').slice(0, 8)}`,
    phone: `077${String(randomInt(0, 100_000_000)).padStart(8, '0')}`,
    pinHash: await hashPin('199711'),
    block: 'A',
    buildingNumber: 'A101',
    apartment: '101',
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: 'emergency_tracking_test',
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
}

test('SOS location and conversation remain private to the customer and visible to super admin', async () => {
  const users = [];
  let categoryId = null;

  try {
    const customer = await createTestUser('user', 'sos_customer');
    const outsider = await createTestUser('user', 'sos_outsider');
    const providerUser = await createTestUser('service_provider', 'sos_provider');
    const admin = await createTestUser('admin', 'sos_admin');
    users.push(customer, outsider, providerUser, admin);
    await q(`UPDATE app_user SET is_super_admin = TRUE WHERE id = $1`, [admin.id]);

    const category = await q(
      `INSERT INTO service_categories (level, name, sort_order)
       VALUES (1, $1, 9999)
       RETURNING id`,
      [unique('Emergency category')]
    );
    categoryId = Number(category.rows[0].id);

    const provider = await q(
      `INSERT INTO service_provider_profiles
         (user_id, business_name, main_category_id, phone, city,
          has_emergency_service, provider_approval_status)
       VALUES ($1,$2,$3,$4,'Baghdad',TRUE,'approved')
       RETURNING id`,
      [providerUser.id, unique('Emergency desk'), categoryId, providerUser.phone]
    );
    const providerId = Number(provider.rows[0].id);

    const offering = await q(
      `INSERT INTO service_offerings
         (provider_id, main_category_id, name, execution_mode, moderation_status,
          service_key)
       VALUES ($1,$2,$3,'home','approved',$4)
       RETURNING id`,
      [providerId, categoryId, unique('SOS support'), unique('sos')]
    );
    const offeringId = Number(offering.rows[0].id);

    const emergency = await q(
      `INSERT INTO service_requests
         (request_code, customer_user_id, provider_id, offering_id, status,
          requested_execution_mode, city, area, urgency, service_key,
          service_title, emergency_target, latitude, longitude)
       VALUES ($1,$2,$3,$4,'pending','home','Baghdad','Basmaya','emergency',
               'emergency','Emergency assistance','ambulance',$5,$6)
       RETURNING id`,
      [unique('SOS'), customer.id, providerId, offeringId, 33.31456, 44.36611]
    );
    const requestId = Number(emergency.rows[0].id);

    const normal = await q(
      `INSERT INTO service_requests
         (request_code, customer_user_id, provider_id, offering_id, status,
          requested_execution_mode, urgency, service_key, service_title)
       VALUES ($1,$2,$3,$4,'pending','home','normal','maintenance','Maintenance')
       RETURNING id`,
      [unique('NORMAL'), customer.id, providerId, offeringId]
    );
    const normalRequestId = Number(normal.rows[0].id);

    const location = await appendEmergencyLocation({
      userId: customer.id,
      requestId,
      dto: {
        latitude: 33.31501,
        longitude: 44.36702,
        accuracyMeters: 4.5,
        speedMps: 1.2,
        headingDegrees: 95,
        capturedAt: new Date().toISOString(),
      },
    });
    assert.equal(location.requestId, requestId);
    assert.equal(location.latitude, 33.31501);
    assert.equal(location.longitude, 44.36702);

    assert.equal(
      await appendEmergencyLocation({
        userId: outsider.id,
        requestId,
        dto: {
          latitude: 33,
          longitude: 44,
          accuracyMeters: null,
          speedMps: null,
          headingDegrees: null,
          capturedAt: null,
        },
      }),
      null
    );

    const customerMessage = await appendEmergencyMessage({
      userId: customer.id,
      requestId,
      message: 'I need an ambulance at this location.',
    });
    const adminMessage = await appendEmergencyMessage({
      userId: admin.id,
      requestId,
      message: 'Your location was received. Help is being contacted.',
      admin: true,
    });
    assert.equal(customerMessage.senderRole, 'customer');
    assert.equal(adminMessage.senderRole, 'super_admin');

    const customerThread = await getEmergencyThread({
      requestId,
      userId: customer.id,
    });
    assert.equal(customerThread.request.id, requestId);
    assert.equal(customerThread.locations.length, 1);
    assert.deepEqual(
      customerThread.messages.map((message) => message.senderRole),
      ['customer', 'super_admin']
    );

    assert.equal(
      await getEmergencyThread({ requestId, userId: outsider.id }),
      null
    );
    assert.equal(
      await getEmergencyThread({ requestId: normalRequestId, userId: customer.id }),
      null
    );

    const adminThread = await getEmergencyThread({
      requestId,
      userId: admin.id,
      admin: true,
    });
    assert.equal(adminThread.request.customerPhone, customer.phone);
    assert.equal(adminThread.locations[0].accuracyMeters, 4.5);

    const adminList = await listEmergencyRequestsForAdmin({ limit: 20, offset: 0 });
    const listed = adminList.items.find((item) => Number(item.id) === requestId);
    assert.ok(listed, 'emergency request should be present in the admin queue');
    assert.equal(listed.latestLatitude, 33.31501);
    assert.equal(listed.latestLongitude, 44.36702);
    assert.equal(listed.messageCount, 2);
    assert.equal(
      adminList.items.some((item) => Number(item.id) === normalRequestId),
      false
    );
  } finally {
    const userIds = users.map((user) => Number(user.id)).filter(Number.isFinite);
    if (userIds.length > 0) {
      await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]).catch(
        () => {}
      );
    }
    if (categoryId != null) {
      await q(`DELETE FROM service_categories WHERE id = $1`, [categoryId]).catch(
        () => {}
      );
    }
  }
});
