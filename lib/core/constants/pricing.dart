// Temporary UI estimate only. Backend preview remains the source of truth
// before order confirmation and final reporting.
const int estimatedServiceFeeIqd = 500;
const int deliveryFeeIqd = 1000;

double calcEstimatedServiceFee(double subtotal) {
  if (subtotal <= 0) return 0;
  return estimatedServiceFeeIqd.toDouble();
}

double calcOrderTotal(double subtotal) {
  return subtotal + calcEstimatedServiceFee(subtotal) + deliveryFeeIqd;
}
