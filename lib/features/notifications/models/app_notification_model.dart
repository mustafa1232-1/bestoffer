import '../../../core/utils/parsers.dart';

class AppNotificationModel {
  final int id;
  final int? orderId;
  final int? rideId;
  final int? merchantId;
  final String? target;
  final String type;
  final String title;
  final String? body;
  final Map<String, dynamic>? payload;
  final bool isRead;
  final DateTime? createdAt;
  final DateTime? readAt;

  const AppNotificationModel({
    required this.id,
    required this.orderId,
    required this.rideId,
    required this.merchantId,
    required this.target,
    required this.type,
    required this.title,
    required this.body,
    required this.payload,
    required this.isRead,
    required this.createdAt,
    required this.readAt,
  });

  factory AppNotificationModel.fromJson(Map<String, dynamic> j) {
    final rawPayload = j['payload'];
    Map<String, dynamic>? payload;
    if (rawPayload is Map) {
      payload = Map<String, dynamic>.from(rawPayload);
    }

    return AppNotificationModel(
      id: parseInt(j['id']),
      orderId: j['order_id'] == null ? null : parseInt(j['order_id']),
      rideId: _parseRideId(j, payload),
      merchantId: j['merchant_id'] == null ? null : parseInt(j['merchant_id']),
      target: _parseTarget(j, payload),
      type: parseString(j['type']),
      title: parseString(j['title']),
      body: parseNullableString(j['body']),
      payload: payload,
      isRead: j['is_read'] == true,
      createdAt: _parseDate(j['created_at']),
      readAt: _parseDate(j['read_at']),
    );
  }

  AppNotificationModel copyWith({bool? isRead, DateTime? readAt}) {
    return AppNotificationModel(
      id: id,
      orderId: orderId,
      rideId: rideId,
      merchantId: merchantId,
      target: target,
      type: type,
      title: title,
      body: body,
      payload: payload,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

String? _parseTarget(Map<String, dynamic> json, Map<String, dynamic>? payload) {
  final raw =
      parseNullableString(json['target']) ??
      parseNullableString(payload?['target']);
  return raw?.toLowerCase();
}

int? _parseRideId(Map<String, dynamic> json, Map<String, dynamic>? payload) {
  final top = json['ride_id'] ?? json['rideId'];
  if (top != null) {
    final out = int.tryParse('$top');
    if (out != null && out > 0) return out;
  }

  final fromPayload = payload?['rideId'] ?? payload?['ride_id'];
  final parsed = int.tryParse('$fromPayload');
  if (parsed != null && parsed > 0) return parsed;
  return null;
}
