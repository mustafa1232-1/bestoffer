const PACKAGE_PRICE_IQD = 10000;

export function evaluateCaptainRideCredits(raw, support = {}) {
  const packagePriceIqd = Math.max(0, Number(raw?.package_price_iqd) || PACKAGE_PRICE_IQD);
  const packageRideLimit = Math.max(1, Number(raw?.package_ride_count) || 15);
  const purchased = Math.max(0, Number(raw?.purchased_ride_credits) || 0);
  const usedRides = Math.max(0, Number(raw?.consumed_ride_credits) || 0);
  const remainingRides = Math.max(0, purchased - usedRides);
  // Ride packages have a fixed commercial price. Legacy discount columns are
  // retained in the schema only for backwards compatibility and must not
  // change the amount due for a 15-ride package.
  const discountPercent = 0;
  const discountedMonthlyFeeIqd = packagePriceIqd;
  const canAcceptRides = remainingRides > 0;
  return {
    canAccess: canAcceptRides, canAcceptRides,
    phase: canAcceptRides ? "ride_credits" : "exhausted",
    packagePriceIqd, packageRideLimit,
    completedRidesInPackage: usedRides, usedRides, remainingRides,
    isLastRide: remainingRides === 1,
    monthlyFeeIqd: packagePriceIqd, discountPercent, discountedMonthlyFeeIqd,
    dueAmountIqd: canAcceptRides ? 0 : discountedMonthlyFeeIqd,
    cashPaymentPending: raw?.cash_payment_pending === true,
    cashPaymentRequestedAt: raw?.cash_payment_requested_at || null,
    lastCashPaymentConfirmedAt: raw?.last_cash_payment_confirmed_at || null,
    lastExpiryReminderOn: raw?.last_expiry_reminder_on || null,
    support,
    // Keep the structured object for future clients while exposing the
    // established flat fields consumed by the current Flutter captain UI.
    supportPhone: support?.phone || null,
    supportWhatsapp: support?.whatsapp || null,
  };
}
