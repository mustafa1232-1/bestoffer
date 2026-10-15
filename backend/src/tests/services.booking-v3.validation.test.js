import assert from 'node:assert/strict';
import test from 'node:test';

import { normalizeServiceBookingStatus } from '../modules/services/services.booking.constants.js';
import {
  validateServiceMessageBody,
  validateServicePaymentBody,
  validateServicePriceAdjustmentBody,
  validateServiceRequestBody,
} from '../modules/services/services.validators.js';

test('service booking accepts contact, location, and optional medical details', () => {
  const result = validateServiceRequestBody({
    offeringId: 12,
    providerId: 8,
    pricingType: 'per_visit',
    requestedExecutionMode: 'home',
    requestedDate: '2026-10-01',
    requestedTime: '10:30',
    addressLine: 'بسماية، B1، العمارة 22، الشقة 4',
    latitude: 33.245,
    longitude: 44.541,
    preferredContact: 'whatsapp',
    contactPhone: '07700000000',
    medicalInfo: {
      conditions: 'ضغط الدم',
      medications: 'دواء موصوف',
      allergies: 'لا توجد',
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.preferredContact, 'whatsapp');
  assert.equal(result.value.contactPhone, '07700000000');
  assert.equal(result.value.medicalInfo.conditions, 'ضغط الدم');
});

test('phone and WhatsApp booking require a contact number', () => {
  const result = validateServiceRequestBody({
    offeringId: 12,
    providerId: 8,
    preferredContact: 'phone',
  });

  assert.equal(result.ok, false);
  assert.ok(result.errors.includes('contactPhone'));
});

test('service invoice adjustment rejects a discount above the price', () => {
  const result = validateServicePriceAdjustmentBody({
    totalIqd: 10000,
    discountIqd: 11000,
  });
  assert.equal(result.ok, false);
  assert.ok(result.errors.includes('discountIqd'));
});

test('payment and request chat payloads are normalized', () => {
  const payment = validateServicePaymentBody({
    paymentMethod: 'cash',
    note: 'تم الدفع نقداً',
  });
  const message = validateServiceMessageBody({ message: '  أنا في الموقع  ' });

  assert.equal(payment.ok, true);
  assert.equal(payment.value.paymentMethod, 'cash');
  assert.equal(message.ok, true);
  assert.equal(message.value.message, 'أنا في الموقع');
});

test('payment aliases do not reopen the legacy completion path', () => {
  assert.equal(
    normalizeServiceBookingStatus('payment_submitted'),
    'PROVIDER_COMPLETED',
  );
  assert.equal(normalizeServiceBookingStatus('payment_confirmed'), 'COMPLETED');
});
