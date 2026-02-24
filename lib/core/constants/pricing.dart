const int serviceFeeIqd = 500;
const int deliveryFeeIqd = 1000;

double calcServiceFee(double subtotal) {
  if (subtotal <= 0) return 0;
  return serviceFeeIqd.toDouble();
}

double calcOrderTotal(double subtotal) {
  return subtotal + calcServiceFee(subtotal) + deliveryFeeIqd;
}
