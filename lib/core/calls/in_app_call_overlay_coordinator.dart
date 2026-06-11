class InAppCallOverlayCoordinator {
  InAppCallOverlayCoordinator._();

  static final Set<String> _activeKeys = <String>{};

  static bool tryOpen(String key) {
    if (key.trim().isEmpty) return false;
    if (_activeKeys.contains(key)) return false;
    _activeKeys.add(key);
    return true;
  }

  static void close(String key) {
    _activeKeys.remove(key);
  }

  static String socialKey({required int threadId, int? sessionId}) =>
      'social:$threadId:${sessionId ?? 0}';

  static String taxiKey({required int rideId, int? sessionId}) =>
      'taxi:$rideId:${sessionId ?? 0}';

  static String deliveryKey({required int orderId}) => 'delivery:$orderId';
}
