import 'package:flutter/foundation.dart';

class OrderRefreshEvent {
  const OrderRefreshEvent({
    required this.source,
    this.orderId,
  });

  final String source;
  final int? orderId;
}

class OrderRefreshBus extends ChangeNotifier {
  OrderRefreshBus._();

  static final OrderRefreshBus instance = OrderRefreshBus._();

  OrderRefreshEvent? _lastEvent;
  int _version = 0;

  OrderRefreshEvent? get lastEvent => _lastEvent;
  int get version => _version;

  void notifyOrderChanged({
    int? orderId,
    String source = 'unknown',
  }) {
    _lastEvent = OrderRefreshEvent(source: source, orderId: orderId);
    _version += 1;
    notifyListeners();
  }
}
