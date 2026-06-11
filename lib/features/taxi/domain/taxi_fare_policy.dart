class TaxiFareEstimateRange {
  const TaxiFareEstimateRange({
    required this.lowIqd,
    required this.highIqd,
    required this.suggestedIqd,
  });

  final int lowIqd;
  final int highIqd;
  final int suggestedIqd;
}

class TaxiFarePolicy {
  const TaxiFarePolicy._();

  static const int minimumFareIqd = 1500;
  static const int farePerKmIqd = 500;
  static const int roundStepIqd = 500;
  static const int minimumRangeBufferIqd = 1000;
  static const double percentRangeBuffer = 0.15;

  static int roundUpToStep(int value, {int step = roundStepIqd}) {
    if (value <= 0) return step;
    final safeStep = step <= 0 ? roundStepIqd : step;
    final remainder = value % safeStep;
    if (remainder == 0) return value;
    return value + (safeStep - remainder);
  }

  static TaxiFareEstimateRange estimateFromDistanceMeters(
    double? distanceMeters, {
    int? durationSeconds,
  }) {
    final distanceKm = ((distanceMeters ?? 0) / 1000).clamp(0, 5000).toDouble();
    final rawEstimate = minimumFareIqd + (distanceKm * farePerKmIqd);
    final lowEstimate = roundUpToStep(
      rawEstimate < minimumFareIqd ? minimumFareIqd : rawEstimate.round(),
    );

    final dynamicBuffer = (lowEstimate * percentRangeBuffer).round();
    var highEstimate = roundUpToStep(
      lowEstimate + (dynamicBuffer > minimumRangeBufferIqd
          ? dynamicBuffer
          : minimumRangeBufferIqd),
    );

    if (durationSeconds != null && durationSeconds > 0) {
      final trafficFactor = (durationSeconds / 60).round();
      if (trafficFactor >= 35) {
        highEstimate = roundUpToStep(highEstimate + 500);
      }
    }

    return TaxiFareEstimateRange(
      lowIqd: lowEstimate,
      highIqd: highEstimate,
      suggestedIqd: lowEstimate,
    );
  }
}
