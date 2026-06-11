class OpsAction {
  final int id;
  final int incidentId;
  final String actionType;
  final String riskLevel;
  final String status;
  final Map<String, dynamic> input;
  final Map<String, dynamic> output;
  final String? rejectionReason;
  final DateTime? createdAt;

  const OpsAction({
    required this.id,
    required this.incidentId,
    required this.actionType,
    required this.riskLevel,
    required this.status,
    required this.input,
    required this.output,
    this.rejectionReason,
    this.createdAt,
  });

  factory OpsAction.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('${value ?? ''}') ?? 0;
    }

    Map<String, dynamic> parseMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) {
        return value.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      return const <String, dynamic>{};
    }

    return OpsAction(
      id: parseInt(json['id']),
      incidentId: parseInt(json['incident_id'] ?? json['incidentId']),
      actionType: '${json['action_type'] ?? json['actionType'] ?? ''}',
      riskLevel: '${json['risk_level'] ?? json['riskLevel'] ?? 'medium'}',
      status: '${json['status'] ?? 'pending_approval'}',
      input: parseMap(json['input_json'] ?? json['input']),
      output: parseMap(json['output_json'] ?? json['output']),
      rejectionReason:
          json['rejection_reason']?.toString() ??
          json['rejectionReason']?.toString(),
      createdAt: DateTime.tryParse(
        '${json['created_at'] ?? json['createdAt'] ?? ''}',
      ),
    );
  }
}
