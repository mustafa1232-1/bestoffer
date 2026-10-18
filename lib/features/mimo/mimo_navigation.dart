import 'package:flutter/foundation.dart';

/// Something Mimo wants the app to open (a section, a store, a product).
///
/// The home screen listens and opens it with its own access checks (section
/// availability, login), so Mimo never bypasses the app's rules.
class MimoNavRequest {
  const MimoNavRequest.section(this.section)
    : store = null,
      productId = null,
      serviceId = null,
      ticketId = null;

  const MimoNavRequest.store(Map<String, dynamic> this.store, {this.productId})
    : section = null,
      serviceId = null,
      ticketId = null;

  const MimoNavRequest.service(int this.serviceId)
    : section = null,
      store = null,
      productId = null,
      ticketId = null;

  const MimoNavRequest.ticket(int this.ticketId)
    : section = null,
      store = null,
      productId = null,
      serviceId = null;

  /// shopping, taxi, services, pharmacy, community, offers, cars,
  /// real_estate, jobs, orders, cart, login
  final String? section;
  final Map<String, dynamic>? store;
  final int? productId;
  final int? serviceId;
  final int? ticketId;
}

class MimoNavigation {
  MimoNavigation._();

  static final ValueNotifier<MimoNavRequest?> requests = ValueNotifier(null);

  static void open(MimoNavRequest request) {
    // A new object each time so listeners fire even for the same target.
    requests.value = null;
    requests.value = request;
  }
}
