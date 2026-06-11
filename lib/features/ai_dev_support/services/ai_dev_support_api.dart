import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../models/ops_action.dart';
import '../models/ops_incident.dart';
import '../models/ops_status.dart';

final aiDevSupportApiProvider = Provider<AiDevSupportApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return AiDevSupportApi(dio);
});

class AiDevSupportApi {
  final Dio dio;

  AiDevSupportApi(this.dio);

  static const String _opsServiceBaseUrl = String.fromEnvironment(
    'OPS_API_BASE_URL',
    defaultValue: 'https://ai-ops-production-40b6.up.railway.app',
  );
  static const String _opsBasePath = '/api/admin/ops';

  String _opsEndpoint(String path) {
    final suffix = path.startsWith('/') ? path : '/$path';
    final base = _opsServiceBaseUrl.trim();
    if (base.isEmpty) {
      return '$_opsBasePath$suffix';
    }
    final normalizedBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$normalizedBase$_opsBasePath$suffix';
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asListOfMaps(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<OpsStatus> status() async {
    final response = await dio.get(_opsEndpoint('/status'));
    return OpsStatus.fromJson(_asMap(response.data));
  }

  Future<List<OpsIncident>> incidents({
    String severity = 'all',
    String status = 'all',
    String source = 'all',
    String affectedModule = 'all',
    String? search,
    String? dateFrom,
    String? dateTo,
  }) async {
    final response = await dio.get(
      _opsEndpoint('/incidents'),
      queryParameters: {
        'severity': severity,
        'status': status,
        'source': source,
        'affectedModule': affectedModule,
        if ((search ?? '').trim().isNotEmpty) 'search': search,
        if ((dateFrom ?? '').trim().isNotEmpty) 'dateFrom': dateFrom,
        if ((dateTo ?? '').trim().isNotEmpty) 'dateTo': dateTo,
      },
    );

    final data = _asMap(response.data);
    final items = _asListOfMaps(data['items']);
    return items.map(OpsIncident.fromJson).toList();
  }

  Future<Map<String, dynamic>> incidentDetails(int incidentId) async {
    final response = await dio.get(_opsEndpoint('/incidents/$incidentId'));
    return _asMap(response.data);
  }

  Future<List<OpsAction>> pendingActions() async {
    final response = await dio.get(_opsEndpoint('/actions/pending'));
    final data = _asMap(response.data);
    final items = _asListOfMaps(data['items']);
    return items.map(OpsAction.fromJson).toList();
  }

  Future<Map<String, dynamic>> approveAction({
    required int incidentId,
    int? actionId,
    String confirmationText = '',
    String? comment,
  }) async {
    final payload = <String, dynamic>{
      'actionId': actionId,
      'confirmationText': confirmationText.trim(),
      'comment': comment?.trim(),
    };
    payload.removeWhere((key, value) {
      if (value == null) return true;
      return value is String && value.isEmpty;
    });
    final response = await dio.post(
      _opsEndpoint('/incidents/$incidentId/approve-action'),
      data: payload,
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> rejectAction({
    required int incidentId,
    String? reason,
  }) async {
    final response = await dio.post(
      _opsEndpoint('/incidents/$incidentId/reject-action'),
      data: {if ((reason ?? '').trim().isNotEmpty) 'reason': reason},
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> createGithubIssue({
    required int incidentId,
  }) async {
    final response = await dio.post(
      _opsEndpoint('/incidents/$incidentId/create-github-issue'),
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> requestCodeFix({
    required int incidentId,
    String? prompt,
    String? head,
    String? branchName,
    String? base,
  }) async {
    final response = await dio.post(
      _opsEndpoint('/incidents/$incidentId/request-code-fix'),
      data: {
        if ((prompt ?? '').trim().isNotEmpty) 'prompt': prompt,
        if ((head ?? '').trim().isNotEmpty) 'head': head,
        if ((branchName ?? '').trim().isNotEmpty) 'branchName': branchName,
        if ((base ?? '').trim().isNotEmpty) 'base': base,
      },
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> markResolved({
    required int incidentId,
    String? reason,
  }) async {
    final response = await dio.post(
      _opsEndpoint('/incidents/$incidentId/mark-resolved'),
      data: {if ((reason ?? '').trim().isNotEmpty) 'reason': reason},
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getSettings() async {
    final response = await dio.get(_opsEndpoint('/settings'));
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> updateSettings(
    Map<String, dynamic> settings,
  ) async {
    final response = await dio.put(
      _opsEndpoint('/settings'),
      data: {'settings': settings},
    );
    return _asMap(response.data);
  }

  Future<List<Map<String, dynamic>>> auditLogs({int? incidentId}) async {
    final query = <String, dynamic>{'incidentId': incidentId}
      ..removeWhere((key, value) => value == null);
    final response = await dio.get(
      _opsEndpoint('/audit-logs'),
      queryParameters: query,
    );
    final data = _asMap(response.data);
    return _asListOfMaps(data['items']);
  }
}
