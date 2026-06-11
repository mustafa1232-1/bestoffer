class OrderChatMessageModel {
  final int id;
  final int orderId;
  final int senderUserId;
  final String senderRole;
  final String message;
  final DateTime? createdAt;

  const OrderChatMessageModel({
    required this.id,
    required this.orderId,
    required this.senderUserId,
    required this.senderRole,
    required this.message,
    required this.createdAt,
  });

  factory OrderChatMessageModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      final text = '$raw'.trim();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    int parseInt(dynamic raw) => int.tryParse('$raw') ?? 0;

    return OrderChatMessageModel(
      id: parseInt(json['id']),
      orderId: parseInt(json['order_id'] ?? json['orderId']),
      senderUserId: parseInt(json['sender_user_id'] ?? json['senderUserId']),
      senderRole: '${json['sender_role'] ?? json['senderRole'] ?? ''}'.trim(),
      message: '${json['message_text'] ?? json['message'] ?? ''}'.trim(),
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
    );
  }
}
