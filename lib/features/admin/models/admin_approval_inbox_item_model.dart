import '../../../core/utils/parsers.dart';

class AdminApprovalInboxItemModel {
  final String id;
  final String kind;
  final int targetId;
  final String title;
  final String subject;
  final String? subtitle;
  final String? meta;
  final DateTime? createdAt;

  const AdminApprovalInboxItemModel({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.title,
    required this.subject,
    required this.subtitle,
    required this.meta,
    required this.createdAt,
  });

  factory AdminApprovalInboxItemModel.fromJson(Map<String, dynamic> json) {
    return AdminApprovalInboxItemModel(
      id: parseString(json['id']),
      kind: parseString(json['kind']),
      targetId: parseInt(json['targetId'] ?? json['target_id']),
      title: parseString(json['title']),
      subject: parseString(json['subject']),
      subtitle: parseNullableString(json['subtitle']),
      meta: parseNullableString(json['meta']),
      createdAt: parseNullableDateTime(json['createdAt'] ?? json['created_at']),
    );
  }
}
