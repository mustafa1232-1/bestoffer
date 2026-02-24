import '../../../core/utils/parsers.dart';

class AppNotificationModel {
  final int id;
  final int? orderId;
  final int? merchantId;
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
    required this.merchantId,
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
      merchantId: j['merchant_id'] == null ? null : parseInt(j['merchant_id']),
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
      merchantId: merchantId,
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
