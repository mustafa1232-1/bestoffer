import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../state/admin_controller.dart';

enum _CheckStatus { healthy, warning, failed }

class _MaintenanceCheck {
  const _MaintenanceCheck({
    required this.key,
    required this.title,
    required this.details,
    required this.status,
    required this.elapsedMs,
    this.fixHint,
  });

  final String key;
  final String title;
  final String details;
  final _CheckStatus status;
  final int elapsedMs;
  final String? fixHint;
}

class AdminMaintenanceScreen extends ConsumerStatefulWidget {
  const AdminMaintenanceScreen({super.key});

  @override
  ConsumerState<AdminMaintenanceScreen> createState() =>
      _AdminMaintenanceScreenState();
}

class _AdminMaintenanceScreenState
    extends ConsumerState<AdminMaintenanceScreen> {
  bool _loading = true;
  bool _runningFix = false;
  String? _error;
  List<_MaintenanceCheck> _checks = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_runDiagnostics);
  }

  Color _statusColor(_CheckStatus status) {
    switch (status) {
      case _CheckStatus.healthy:
        return const Color(0xFF16A34A);
      case _CheckStatus.warning:
        return const Color(0xFFF59E0B);
      case _CheckStatus.failed:
        return const Color(0xFFDC2626);
    }
  }

  String _statusLabel(_CheckStatus status) {
    final l10n = context.l10n;
    switch (status) {
      case _CheckStatus.healthy:
        return l10n.adminMaintenanceStatusHealthy;
      case _CheckStatus.warning:
        return l10n.adminMaintenanceStatusWarning;
      case _CheckStatus.failed:
        return l10n.adminMaintenanceStatusFailed;
    }
  }

  Future<_MaintenanceCheck> _probe({
    required String key,
    required String title,
    required Future<({_CheckStatus status, String details, String? fixHint})>
    Function()
    body,
  }) async {
    final l10n = context.l10n;
    final sw = Stopwatch()..start();
    try {
      final result = await body();
      return _MaintenanceCheck(
        key: key,
        title: title,
        details: result.details,
        status: result.status,
        elapsedMs: sw.elapsedMilliseconds,
        fixHint: result.fixHint,
      );
    } catch (e) {
      return _MaintenanceCheck(
        key: key,
        title: title,
        details: l10n.adminMaintenanceProbeFailed(
          mapAnyError(e, fallback: l10n.commonUnexpectedError),
        ),
        status: _CheckStatus.failed,
        elapsedMs: sw.elapsedMilliseconds,
        fixHint: l10n.adminMaintenanceRetryHint,
      );
    }
  }

  Future<void> _runDiagnostics() async {
    final l10n = context.l10n;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(adminApiProvider);
      final dio = ref.read(dioClientProvider).dio;

      final checks = <_MaintenanceCheck>[
        await _probe(
          key: 'server',
          title: l10n.adminMaintenanceServerConnectivity,
          body: () async {
            final response = await dio
                .get<dynamic>('/health')
                .timeout(const Duration(seconds: 8));
            final code = response.statusCode ?? 0;
            final payload = response.data is Map
                ? Map<String, dynamic>.from(response.data as Map)
                : const <String, dynamic>{};
            final db = '${payload['db'] ?? 'unknown'}';
            final ok = code >= 200 && code < 300;
            return (
              status: ok ? _CheckStatus.healthy : _CheckStatus.failed,
              details: ok
                  ? l10n.adminMaintenanceServerReachable(code, db)
                  : l10n.adminMaintenanceServerUnreachable(code),
              fixHint: ok ? null : l10n.adminMaintenanceServerFixHint,
            );
          },
        ),
        await _probe(
          key: 'session',
          title: l10n.adminMaintenanceAdminSession,
          body: () async {
            final auth = ref.read(authControllerProvider);
            final hasToken = (auth.token ?? '').trim().isNotEmpty;
            final isAdmin =
                auth.isAdmin || auth.isSuperAdmin || auth.isDeputyAdmin;
            final ok = hasToken && isAdmin;
            return (
              status: ok ? _CheckStatus.healthy : _CheckStatus.warning,
              details: ok
                  ? l10n.adminMaintenanceSessionValid
                  : l10n.adminMaintenanceSessionInvalid,
              fixHint: ok ? null : l10n.adminMaintenanceSessionFixHint,
            );
          },
        ),
        await _probe(
          key: 'analytics',
          title: l10n.adminMaintenanceAnalytics,
          body: () async {
            final out = await api.analytics();
            final hasDay = out['day'] is Map;
            return (
              status: hasDay ? _CheckStatus.healthy : _CheckStatus.warning,
              details: hasDay
                  ? l10n.adminMaintenanceAnalyticsLoaded
                  : l10n.adminMaintenanceAnalyticsPartial,
              fixHint: hasDay ? null : l10n.adminMaintenanceAnalyticsFixHint,
            );
          },
        ),
        await _probe(
          key: 'approvals',
          title: l10n.adminMaintenanceApprovalInbox,
          body: () async {
            final out = await api.approvalInbox(limit: 20);
            final items = List<dynamic>.from(out['items'] as List? ?? const []);
            return (
              status: _CheckStatus.healthy,
              details: l10n.adminMaintenanceApprovalInboxLoaded(items.length),
              fixHint: null,
            );
          },
        ),
        await _probe(
          key: 'audit',
          title: l10n.adminMaintenanceAuditFeed,
          body: () async {
            final out = await api.auditFeed(limit: 20);
            final items = List<dynamic>.from(out['items'] as List? ?? const []);
            return (
              status: _CheckStatus.healthy,
              details: l10n.adminMaintenanceAuditFeedLoaded(items.length),
              fixHint: null,
            );
          },
        ),
      ];

      if (!mounted) return;
      setState(() {
        _checks = checks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(e, fallback: l10n.adminMaintenanceLoadFailed);
      });
    }
  }

  Future<void> _quickFix(_MaintenanceCheck check) async {
    final l10n = context.l10n;
    if (_runningFix) return;
    setState(() => _runningFix = true);
    try {
      if (check.key == 'session') {
        await ref.read(authControllerProvider.notifier).bootstrap();
      } else {
        await ref.read(adminControllerProvider.notifier).bootstrap();
      }
      if (!mounted) return;
      await _runDiagnostics();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminMaintenanceQuickFixDone)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: l10n.adminMaintenanceQuickFixFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _runningFix = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final okCount = _checks
        .where((e) => e.status == _CheckStatus.healthy)
        .length;
    final warnCount = _checks
        .where((e) => e.status == _CheckStatus.warning)
        .length;
    final failCount = _checks
        .where((e) => e.status == _CheckStatus.failed)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminMaintenanceScreenTitle),
        actions: [
          IconButton(
            tooltip: l10n.adminMaintenanceRunDiagnostics,
            onPressed: _loading ? null : _runDiagnostics,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textDirection: Directionality.of(context),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _runDiagnostics,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(l10n.commonRetry),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _runDiagnostics,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            l10n.adminMaintenanceHealthSummary,
                            textDirection: Directionality.of(context),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
                              Chip(
                                label: Text(
                                  l10n.adminMaintenanceHealthyCount(okCount),
                                ),
                                backgroundColor: const Color(0x1616A34A),
                              ),
                              Chip(
                                label: Text(
                                  l10n.adminMaintenanceWarningCount(warnCount),
                                ),
                                backgroundColor: const Color(0x16F59E0B),
                              ),
                              Chip(
                                label: Text(
                                  l10n.adminMaintenanceFailedCount(failCount),
                                ),
                                backgroundColor: const Color(0x16DC2626),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final check in _checks)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              textDirection: Directionality.of(context),
                              children: [
                                Expanded(
                                  child: Text(
                                    check.title,
                                    textDirection: Directionality.of(context),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(
                                      check.status,
                                    ).withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _statusLabel(check.status),
                                    style: TextStyle(
                                      color: _statusColor(check.status),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              check.details,
                              textDirection: Directionality.of(context),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.adminMaintenanceProbeTime(check.elapsedMs),
                              textDirection: Directionality.of(context),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if ((check.fixHint ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                check.fixHint!,
                                textDirection: Directionality.of(context),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  onPressed: _runningFix
                                      ? null
                                      : () => _quickFix(check),
                                  icon: _runningFix
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.build_circle_outlined),
                                  label: Text(
                                    l10n.adminMaintenanceQuickFixAction,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
