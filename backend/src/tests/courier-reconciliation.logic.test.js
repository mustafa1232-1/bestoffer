import assert from 'node:assert/strict';
import test from 'node:test';

import { calculateCourierOrderReconciliation } from '../modules/commerce/courier-reconciliation.logic.js';

test('exact store and customer cash leaves only the service fee due to app', () => {
  const out = calculateCourierOrderReconciliation({
    totalAmount: 11500,
    productSubtotal: 10000,
    couponDiscountTotal: 0,
    serviceFee: 500,
    deliveryFee: 1000,
    merchantPaidActual: 10000,
    customerReceivedActual: 11500,
  });
  assert.equal(out.expectedStoreAmount, 10000);
  assert.equal(out.purchaseDifference, 0);
  assert.equal(out.appDueFromDelivery, 500);
  assert.equal(out.courierDueFromApp, 0);
});

test('extra store payment is offset by service fee before app owes courier', () => {
  const out = calculateCourierOrderReconciliation({
    totalAmount: 11500,
    productSubtotal: 10000,
    couponDiscountTotal: 0,
    serviceFee: 500,
    deliveryFee: 1000,
    merchantPaidActual: 11250,
    customerReceivedActual: 11500,
  });
  assert.equal(out.purchaseDifference, -1250);
  assert.equal(out.appDueFromDelivery, 0);
  assert.equal(out.courierDueFromApp, 750);
});

test('customer overpayment and cheaper purchase become app receivable', () => {
  const out = calculateCourierOrderReconciliation({
    totalAmount: 4850,
    productSubtotal: 3350,
    couponDiscountTotal: 0,
    serviceFee: 500,
    deliveryFee: 1000,
    merchantPaidActual: 3200,
    customerReceivedActual: 5000,
  });
  assert.equal(out.expectedStoreAmount, 3350);
  assert.equal(out.purchaseDifference, 150);
  assert.equal(out.collectionDifference, 150);
  assert.equal(out.appDueFromDelivery, 800);
  assert.equal(out.courierDueFromApp, 0);
});

test('app funded coupon is compensated to courier after full store payment', () => {
  const out = calculateCourierOrderReconciliation({
    totalAmount: 10500,
    productSubtotal: 10000,
    couponDiscountTotal: 1000,
    serviceFee: 500,
    deliveryFee: 1000,
    merchantPaidActual: 10000,
    customerReceivedActual: 10500,
  });
  assert.equal(out.expectedStoreAmount, 10000);
  assert.equal(out.expectedAppMargin, -500);
  assert.equal(out.appDueFromDelivery, 0);
  assert.equal(out.courierDueFromApp, 500);
});
