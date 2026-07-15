/// Grouped multi-store delivery models (delivery closure client phase §3).
///
/// One [GroupedDeliveryJob] binds one courier to N [DeliveryPickupStop]s (one
/// per store) and a single customer drop-off. The parser tolerates BOTH the
/// snake_case list rows and the camelCase detail payload the backend returns.
library;

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

int? _asIntOrNull(Object? v) {
  if (v == null) return null;
  final i = _asInt(v);
  return i == 0 && v is! num && v is! int ? null : i;
}

double _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

String _asString(Object? v) => v == null ? '' : '$v';

/// Reads the first present key (camelCase or snake_case) from a map.
Object? _pick(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    if (m.containsKey(k) && m[k] != null) return m[k];
  }
  return null;
}

/// A single store pickup within a grouped job.
class DeliveryPickupStop {
  final int stopId;
  final int childOrderId;
  final int storeId;
  final String storeName;
  final String? storePhoto;
  final String? storePhone;
  final Object? storeAddress;
  final double? latitude;
  final double? longitude;
  final int sequence;
  final String preparationStatus;
  final String pickupStatus;
  final DateTime? arrivedAt;
  final DateTime? collectedAt;

  const DeliveryPickupStop({
    required this.stopId,
    required this.childOrderId,
    required this.storeId,
    required this.storeName,
    required this.sequence,
    required this.preparationStatus,
    required this.pickupStatus,
    this.storePhoto,
    this.storePhone,
    this.storeAddress,
    this.latitude,
    this.longitude,
    this.arrivedAt,
    this.collectedAt,
  });

  bool get isCollected => pickupStatus.toUpperCase() == 'COLLECTED';
  bool get isCancelled => pickupStatus.toUpperCase() == 'CANCELLED';
  bool get hasArrived => pickupStatus.toUpperCase() == 'COURIER_ARRIVED' || isCollected;

  static DateTime? _dt(Object? v) =>
      v == null ? null : DateTime.tryParse('$v')?.toLocal();

  factory DeliveryPickupStop.fromMap(Map<String, dynamic> m) {
    return DeliveryPickupStop(
      stopId: _asInt(_pick(m, ['stopId', 'id'])),
      childOrderId: _asInt(_pick(m, ['childOrderId', 'child_order_id'])),
      storeId: _asInt(_pick(m, ['storeId', 'store_id'])),
      storeName: _asString(_pick(m, ['storeName', 'store_name'])),
      storePhoto: _pick(m, ['storePhoto', 'store_photo'])?.toString(),
      storePhone: _pick(m, ['storePhone', 'store_phone'])?.toString(),
      storeAddress: _pick(m, ['storeAddress', 'address_snapshot_json']),
      latitude: _pick(m, ['latitude']) == null ? null : _asDouble(m['latitude']),
      longitude: _pick(m, ['longitude']) == null ? null : _asDouble(m['longitude']),
      sequence: _asInt(_pick(m, ['sequence', 'sequence_number']) ?? 1),
      preparationStatus:
          _asString(_pick(m, ['preparationStatus', 'preparation_status'])),
      pickupStatus: _asString(_pick(m, ['pickupStatus', 'pickup_status'])),
      arrivedAt: _dt(_pick(m, ['arrivedAt', 'arrived_at'])),
      collectedAt: _dt(_pick(m, ['collectedAt', 'collected_at'])),
    );
  }

  DeliveryPickupStop copyWith({String? pickupStatus, DateTime? arrivedAt, DateTime? collectedAt}) {
    return DeliveryPickupStop(
      stopId: stopId,
      childOrderId: childOrderId,
      storeId: storeId,
      storeName: storeName,
      storePhoto: storePhoto,
      storePhone: storePhone,
      storeAddress: storeAddress,
      latitude: latitude,
      longitude: longitude,
      sequence: sequence,
      preparationStatus: preparationStatus,
      pickupStatus: pickupStatus ?? this.pickupStatus,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      collectedAt: collectedAt ?? this.collectedAt,
    );
  }
}

/// Courier grouped-job lifecycle (mirrors the server state machine).
enum GroupedJobLifecycle {
  pendingStores,
  readyForAssignment,
  assigned,
  acknowledged,
  headingToPickups,
  headingToCustomer,
  delivered,
  cancelled,
  failed,
  unknown;

  static GroupedJobLifecycle parse(String? v) {
    switch ((v ?? '').toUpperCase()) {
      case 'PENDING_STORES':
        return GroupedJobLifecycle.pendingStores;
      case 'READY_FOR_ASSIGNMENT':
        return GroupedJobLifecycle.readyForAssignment;
      case 'ASSIGNED':
        return GroupedJobLifecycle.assigned;
      case 'ACKNOWLEDGED':
        return GroupedJobLifecycle.acknowledged;
      case 'HEADING_TO_PICKUPS':
        return GroupedJobLifecycle.headingToPickups;
      case 'HEADING_TO_CUSTOMER':
        return GroupedJobLifecycle.headingToCustomer;
      case 'DELIVERED':
        return GroupedJobLifecycle.delivered;
      case 'CANCELLED':
        return GroupedJobLifecycle.cancelled;
      case 'FAILED':
        return GroupedJobLifecycle.failed;
      default:
        return GroupedJobLifecycle.unknown;
    }
  }

  bool get isTerminal =>
      this == GroupedJobLifecycle.delivered ||
      this == GroupedJobLifecycle.cancelled ||
      this == GroupedJobLifecycle.failed;
}

class GroupedDeliveryJob {
  final int deliveryJobId;
  final int? assignmentId;
  final int orderGroupId;
  final GroupedJobLifecycle lifecycle;
  final String assignmentStatus;
  final String? paymentMethod;
  final double courierEarning;
  final int version;
  final List<DeliveryPickupStop> pickupStops;

  const GroupedDeliveryJob({
    required this.deliveryJobId,
    required this.orderGroupId,
    required this.lifecycle,
    required this.assignmentStatus,
    required this.version,
    required this.pickupStops,
    this.assignmentId,
    this.paymentMethod,
    this.courierEarning = 0,
  });

  /// Active (non-cancelled) stops in sequence order.
  List<DeliveryPickupStop> get activeStops =>
      pickupStops.where((s) => !s.isCancelled).toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));

  int get numberOfStores => activeStops.length;
  int get collectedCount => activeStops.where((s) => s.isCollected).length;

  /// True only when EVERY active stop is collected — the server enforces this
  /// too, but the client disables the action to avoid a pointless 409.
  bool get allCollected =>
      activeStops.isNotEmpty && activeStops.every((s) => s.isCollected);

  bool get canHeadToCustomer =>
      allCollected && lifecycle != GroupedJobLifecycle.headingToCustomer;

  bool get canDeliver => lifecycle == GroupedJobLifecycle.headingToCustomer;

  bool get isTerminal => lifecycle.isTerminal;

  /// "طلب من X متاجر"
  String get storesLabel => 'طلب من $numberOfStores متاجر';

  static double _earning(Map<String, dynamic> m) =>
      _asDouble(_pick(m, ['courierEarning', 'courier_earning']) ?? 0);

  factory GroupedDeliveryJob.fromMap(Map<String, dynamic> m) {
    final rawStops = _pick(m, ['pickupStops', 'pickup_stops']);
    final stops = (rawStops is List)
        ? rawStops
            .map((e) => DeliveryPickupStop.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <DeliveryPickupStop>[];
    return GroupedDeliveryJob(
      deliveryJobId: _asInt(_pick(m, ['deliveryJobId', 'delivery_job_id'])),
      assignmentId: _asIntOrNull(_pick(m, ['assignmentId', 'assignment_id'])),
      orderGroupId: _asInt(_pick(m, ['orderGroupId', 'order_group_id'])),
      lifecycle: GroupedJobLifecycle.parse(
        _asString(_pick(m, ['lifecycleStatus', 'lifecycle_status'])),
      ),
      assignmentStatus: _asString(_pick(m, ['assignmentStatus', 'assignment_status'])),
      paymentMethod: _pick(m, ['paymentMethod', 'payment_method'])?.toString(),
      courierEarning: _earning(m),
      version: _asInt(_pick(m, ['version']) ?? 0),
      pickupStops: stops,
    );
  }

  GroupedDeliveryJob copyWith({
    GroupedJobLifecycle? lifecycle,
    int? version,
    List<DeliveryPickupStop>? pickupStops,
  }) {
    return GroupedDeliveryJob(
      deliveryJobId: deliveryJobId,
      assignmentId: assignmentId,
      orderGroupId: orderGroupId,
      lifecycle: lifecycle ?? this.lifecycle,
      assignmentStatus: assignmentStatus,
      paymentMethod: paymentMethod,
      courierEarning: courierEarning,
      version: version ?? this.version,
      pickupStops: pickupStops ?? this.pickupStops,
    );
  }

  /// Optimistic local update: mark a stop collected/arrived without a round-trip.
  GroupedDeliveryJob withStopStatus(int stopId, String status) {
    return copyWith(
      pickupStops: pickupStops
          .map((s) => s.stopId == stopId ? s.copyWith(pickupStatus: status) : s)
          .toList(),
    );
  }
}
