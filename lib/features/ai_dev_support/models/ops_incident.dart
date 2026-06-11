class OpsIncident {
  final int id;
  final String source;
  final String severity;
  final String status;
  final String riskLevel;
  final String? affectedService;
  final String? affectedModule;
  final String title;
  final String? summary;
  final List<dynamic> symptoms;
  final List<dynamic> evidence;
  final String? probableRootCause;
  final String? suggestedMitigation;
  final String? longTermFix;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;

  const OpsIncident({
    required this.id,
    required this.source,
    required this.severity,
    required this.status,
    required this.riskLevel,
    required this.title,
    required this.symptoms,
    required this.evidence,
    this.affectedService,
    this.affectedModule,
    this.summary,
    this.probableRootCause,
    this.suggestedMitigation,
    this.longTermFix,
    this.createdAt,
    this.updatedAt,
    this.resolvedAt,
  });

  factory OpsIncident.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse('$value');
    }

    List<dynamic> parseList(dynamic value) {
      if (value is List) return value;
      return const <dynamic>[];
    }

    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('${value ?? ''}') ?? 0;
    }

    return OpsIncident(
      id: parseInt(json['id']),
      source: '${json['source'] ?? ''}',
      severity: '${json['severity'] ?? 'SEV3'}',
      status: '${json['status'] ?? 'open'}',
      riskLevel: '${json['risk_level'] ?? json['riskLevel'] ?? 'medium'}',
      affectedService: json['affected_service']?.toString(),
      affectedModule: json['affected_module']?.toString(),
      title: '${json['title'] ?? ''}',
      summary: json['summary']?.toString(),
      symptoms: parseList(json['symptoms_json'] ?? json['symptoms']),
      evidence: parseList(json['evidence_json'] ?? json['evidence']),
      probableRootCause:
          json['probable_root_cause']?.toString() ??
          json['probableRootCause']?.toString(),
      suggestedMitigation:
          json['suggested_mitigation']?.toString() ??
          json['suggestedMitigation']?.toString(),
      longTermFix:
          json['long_term_fix']?.toString() ?? json['longTermFix']?.toString(),
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
      resolvedAt: parseDate(json['resolved_at'] ?? json['resolvedAt']),
    );
  }
}
