/* eslint-disable no-console */
import 'dotenv/config';

import assert from 'node:assert/strict';

import { app } from '../app.js';
import { q } from '../config/db.js';
import { env } from '../config/env.js';
import {
  assertStatus,
  buildPhone,
  buildRunTag,
  createActor,
  readId,
  request,
  startLocalServer,
  stopLocalServer,
} from './e2eTestUtils.js';

async function cleanup({ customerUserId, requestIds }) {
  const ids = requestIds.filter((id) => Number(id) > 0).map(Number);
  if (ids.length) {
    await q(
      `DELETE FROM app_notification
       WHERE payload->>'requestId' = ANY($1::text[])`,
      [ids.map(String)],
    );
    await q(
      `DELETE FROM service_request_status_history
       WHERE request_id = ANY($1::bigint[])`,
      [ids],
    );
    await q(
      `DELETE FROM service_request_attachments
       WHERE request_id = ANY($1::bigint[])`,
      [ids],
    );
    await q(`DELETE FROM service_requests WHERE id = ANY($1::bigint[])`, [ids]);
  }
  if (customerUserId) {
    await q(`DELETE FROM app_notification WHERE user_id = $1`, [customerUserId]);
    await q(`DELETE FROM app_user WHERE id = $1`, [customerUserId]);
  }
}

async function main() {
  const runTag = buildRunTag('central-services-e2e');
  const seed = Number(String(Date.now()).slice(-8));
  const customerPhone = buildPhone('078', seed + 71);
  const customerPin = '1234';
  const customer = createActor('central-customer', runTag, 'central-services-e2e/1');
  const operator = createActor('central-operator', runTag, 'central-services-e2e/1');
  let server = null;
  let customerUserId = null;
  const requestIds = [];

  try {
    const started = await startLocalServer(app);
    server = started.server;
    const { baseUrl } = started;

    let response = await request(
      baseUrl,
      customer,
      'GET',
      '/api/services/public/catalog',
    );
    assertStatus(response, 200, 'central catalog');
    assert.equal(response.data?.items?.length, 7);

    response = await request(baseUrl, customer, 'POST', '/api/auth/register', {
      fullName: `Central Services Customer ${runTag}`,
      phone: customerPhone,
      pin: customerPin,
      block: 'A1',
      buildingNumber: 'A101',
      apartment: '101',
      analyticsConsentAccepted: true,
      analyticsConsentVersion: 'analytics_v1',
    });
    assertStatus(response, 201, 'central customer register');
    customer.token = String(response.data?.token || '');
    customerUserId = readId(response.data?.user);
    assert.ok(customerUserId, 'central customer id missing');

    const idempotencyKey = `${runTag}:home-maintenance`;
    const payload = {
      serviceKey: 'home_maintenance',
      quickIssue: 'كهرباء',
      description: 'فحص عطل كهربائي تجريبي',
      urgency: 'urgent',
      requestedExecutionMode: 'home',
      city: 'بسماية',
      area: 'A1',
      addressLine: 'A101',
      latitude: 33.19302,
      longitude: 44.62071,
      preferredContact: 'phone',
      contactPhone: customerPhone,
      intakeAnswers: { faultType: 'كهرباء' },
      idempotencyKey,
    };
    response = await request(
      baseUrl,
      customer,
      'POST',
      '/api/services/requests/central',
      payload,
    );
    assertStatus(response, 201, 'central request create');
    const requestId = readId(response.data);
    assert.ok(requestId, 'central request id missing');
    requestIds.push(requestId);
    assert.equal(response.data?.serviceKey, 'home_maintenance');
    assert.equal(response.data?.urgency, 'urgent');

    response = await request(
      baseUrl,
      customer,
      'POST',
      '/api/services/requests/central',
      payload,
    );
    assertStatus(response, 201, 'central request idempotent replay');
    assert.equal(readId(response.data), requestId);

    response = await request(baseUrl, operator, 'POST', '/api/auth/login', {
      phone: env.servicesOperatorPhone,
      pin: env.servicesOperatorPin,
    });
    assertStatus(response, 200, 'central operator login');
    operator.token = String(response.data?.token || '');

    response = await request(
      baseUrl,
      operator,
      'POST',
      `/api/services/provider/requests/${requestId}/status`,
      {
        status: 'accepted',
        note: 'قبول مباشر من إدارة خدمات مسلكي',
      },
    );
    assertStatus(response, 200, 'central request direct acceptance');
    assert.equal(response.data?.bookingFlowKind, 'V2');
    assert.equal(response.data?.bookingStatus, 'CONFIRMED');
    assert.equal(response.data?.status, 'accepted');

    response = await request(
      baseUrl,
      operator,
      'POST',
      `/api/services/provider/requests/${requestId}/status`,
      { status: 'in_progress', note: 'إدارة خدمات مسلكي في الطريق' },
    );
    assertStatus(response, 200, 'central request en route');
    assert.equal(response.data?.bookingStatus, 'IN_PROGRESS');
    assert.equal(response.data?.status, 'in_progress');

    response = await request(
      baseUrl,
      customer,
      'GET',
      `/api/services/requests/${requestId}`,
    );
    assertStatus(response, 200, 'central customer request details');
    assert.equal(response.data?.bookingFlowKind, 'V2');
    assert.equal(response.data?.bookingStatus, 'IN_PROGRESS');
    assert.equal(response.data?.assignedProfessionalName, null);

    console.log(
      `[central-services-e2e] passed customerUserId=${customerUserId} requestId=${requestId}`,
    );
  } finally {
    await cleanup({ customerUserId, requestIds }).catch((error) => {
      console.warn('[central-services-e2e] cleanup failed', error?.message || error);
    });
    await stopLocalServer(server);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('[central-services-e2e] failed', error);
    process.exit(1);
  });
