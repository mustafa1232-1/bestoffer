String formatIqd(num amount, {bool withCode = true}) {
  final rounded = amount.round();
  final isNegative = rounded < 0;
  final digits = rounded.abs().toString();

  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    out.write(digits[i]);
    final remaining = digits.length - i - 1;
    if (remaining > 0 && remaining % 3 == 0) {
      out.write(',');
    }
  }

  final signed = isNegative ? '-${out.toString()}' : out.toString();
  if (!withCode) return signed;
  return '$signed IQD';
}
