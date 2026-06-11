class OpsStatusOverview {
  final int openIncidents;
  final int sev1Open;
  final int sev2Open;
  final int pendingApprovals;

  const OpsStatusOverview({
    required this.openIncidents,
    required this.sev1Open,
    required this.sev2Open,
    required this.pendingApprovals,
  });

  factory OpsStatusOverview.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('${value ?? ''}') ?? 0;
    }

    return OpsStatusOverview(
      openIncidents: parseInt(json['openIncidents']),
      sev1Open: parseInt(json['sev1Open']),
      sev2Open: parseInt(json['sev2Open']),
      pendingApprovals: parseInt(json['pendingApprovals']),
    );
  }
}

class OpsStatus {
  final OpsStatusOverview overview;
  final Map<String, dynamic> integrations;
  final Map<String, dynamic> release;

  const OpsStatus({
    required this.overview,
    required this.integrations,
    required this.release,
  });

  factory OpsStatus.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) {
        return value.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      return const <String, dynamic>{};
    }

    return OpsStatus(
      overview: OpsStatusOverview.fromJson(asMap(json['overview'])),
      integrations: asMap(json['integrations']),
      release: asMap(json['release']),
    );
  }
}
