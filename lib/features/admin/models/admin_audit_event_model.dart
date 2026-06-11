import '../../../core/utils/parsers.dart';

class AdminAuditEventModel {
  final int id;
  final int? actorUserId;
  final String? actorFullName;
  final String? actorPhone;
  final String? actorRole;
  final String actionKey;
  final String summary;
  final String? targetType;
  final int? targetId;
  final String? targetLabel;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  const AdminAuditEventModel({
    required this.id,
    required this.actorUserId,
    required this.actorFullName,
    required this.actorPhone,
    required this.actorRole,
    required this.actionKey,
    required this.summary,
    required this.targetType,
    required this.targetId,
    required this.targetLabel,
    required this.metadata,
    required this.createdAt,
  });

  factory AdminAuditEventModel.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['metadata'];
    final metadata = rawMetadata is Map
        ? Map<String, dynamic>.from(rawMetadata)
        : const <String, dynamic>{};

    return AdminAuditEventModel(
      id: parseInt(json['id']),
      actorUserId: (json['actorUserId'] ?? json['actor_user_id']) == null
          ? null
          : parseInt(json['actorUserId'] ?? json['actor_user_id']),
      actorFullName: parseNullableString(
        json['actorFullName'] ?? json['actor_full_name'],
      ),
      actorPhone: parseNullableString(
        json['actorPhone'] ?? json['actor_phone'],
      ),
      actorRole: parseNullableString(json['actorRole'] ?? json['actor_role']),
      actionKey: parseString(json['actionKey'] ?? json['action_key']),
      summary: parseString(json['summary']),
      targetType: parseNullableString(
        json['targetType'] ?? json['target_type'],
      ),
      targetId: (json['targetId'] ?? json['target_id']) == null
          ? null
          : parseInt(json['targetId'] ?? json['target_id']),
      targetLabel: parseNullableString(
        json['targetLabel'] ?? json['target_label'],
      ),
      metadata: metadata,
      createdAt: parseNullableDateTime(json['createdAt'] ?? json['created_at']),
    );
  }
}
