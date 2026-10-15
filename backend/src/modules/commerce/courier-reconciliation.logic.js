function money(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.round(parsed * 100) / 100;
}

function nonNegative(value) {
  return Math.max(0, money(value));
}

/**
 * Canonical cash reconciliation for a courier order.
 *
 * The signed purchase difference is positive when the courier paid the store
 * less than the product value stored on the app invoice, and negative when the
 * courier advanced extra cash. A positive customer collection difference is
 * also app money. Service fees first offset any courier advance; only the
 * remaining signed balance is exposed as an app due or a courier due.
 */
export function calculateCourierOrderReconciliation({
  totalAmount,
  productSubtotal,
  couponDiscountTotal,
  serviceFee,
  deliveryFee,
  merchantPaidActual,
  customerReceivedActual,
}) {
  const invoiceTotal = nonNegative(totalAmount);
  const expectedStoreAmount = nonNegative(productSubtotal);
  const couponDiscount = nonNegative(couponDiscountTotal);
  const appServiceFee = nonNegative(serviceFee);
  const courierDeliveryFee = nonNegative(deliveryFee);
  const merchantPaid = nonNegative(merchantPaidActual);
  const customerReceived = nonNegative(customerReceivedActual);

  const purchaseDifference = money(expectedStoreAmount - merchantPaid);
  const collectionDifference = money(customerReceived - invoiceTotal);
  // This cash identity is deliberately the source of truth. It naturally
  // charges app-funded coupons to the app while preserving the courier's
  // delivery fee: cash collected - cash paid to store - courier fee.
  const netAppBalance = money(
    customerReceived - merchantPaid - courierDeliveryFee,
  );
  const expectedAppMargin = money(
    invoiceTotal - expectedStoreAmount - courierDeliveryFee,
  );

  return {
    invoiceTotal,
    expectedStoreAmount,
    couponDiscountTotal: couponDiscount,
    merchantPaidActual: merchantPaid,
    customerReceivedActual: customerReceived,
    purchaseDifference,
    collectionDifference,
    expectedAppMargin,
    serviceFeeAmount: appServiceFee,
    deliveryFeeAmount: courierDeliveryFee,
    appDueFromDelivery: Math.max(0, netAppBalance),
    courierDueFromApp: Math.max(0, money(-netAppBalance)),
    netAppBalance,
  };
}
