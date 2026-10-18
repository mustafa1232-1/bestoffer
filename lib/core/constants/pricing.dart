// Temporary UI estimate only. Backend preview remains the source of truth
// before order confirmation and final reporting.
const int estimatedServiceFeeIqd = 500;
const int deliveryFeeIqd = 1000;
const int maximumGroupedDeliveryFeeIqd = 2000;

double calcGroupedDeliveryFee(Iterable<double> storeDeliveryFees) {
  final fees = storeDeliveryFees.map((fee) => fee < 0 ? 0.0 : fee).toList();
  if (fees.isEmpty) return 0;
  if (fees.length == 1) return fees.first;

  var total = fees.first;
  for (final fee in fees.skip(1)) {
    total += fee * 0.5;
    if (total >= maximumGroupedDeliveryFeeIqd) {
      return maximumGroupedDeliveryFeeIqd.toDouble();
    }
  }
  return total.clamp(0, maximumGroupedDeliveryFeeIqd).toDouble();
}

double calcEstimatedServiceFee(double subtotal) {
  if (subtotal <= 0) return 0;
  return estimatedServiceFeeIqd.toDouble();
}

double calcOrderTotal(double subtotal) {
  return subtotal + calcEstimatedServiceFee(subtotal) + deliveryFeeIqd;
}
