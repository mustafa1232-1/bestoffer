import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/session_invalidation.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import 'admin_approvals_hub_screen.dart';
import 'admin_dashboard_screen.dart';
import '../state/admin_controller.dart';
import 'admin_service_provider_subscription_requests_screen.dart';

const _servicesRecoveryMessage = 'جارٍ استعادة الجلسة وتحديث البيانات...';
const _servicesPermissionDeniedMessage =
    'لا تملك صلاحية الوصول إلى إدارة الخدمات.';
const _servicesNetworkMessage =
    'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مجدداً.';
const _servicesServerMessage = 'تعذر تحميل بيانات الخدمات حالياً.';

enum _ServicesLoadPhase {
  loading,
  recoveringSession,
  loadedEmpty,
  loadedWithData,
  permissionDenied,
  networkError,
  serverError,
}

class AdminServicesHubScreen extends ConsumerStatefulWidget {
  const AdminServicesHubScreen({super.key});

  @override
  ConsumerState<AdminServicesHubScreen> createState() =>
      _AdminServicesHubScreenState();
}

class _AdminServicesHubScreenState
    extends ConsumerState<AdminServicesHubScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  _ServicesLoadPhase _phase = _ServicesLoadPhase.loading;
  Future<void>? _loadInFlight;
  Map<String, dynamic> _stats = const <String, dynamic>{};
  List<Map<String, dynamic>> _providers = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _offerings = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _suggestions = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _reports = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _requests = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _settings = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;
    final future = _loadOnce();
    _loadInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_loadInFlight, future)) {
        _loadInFlight = null;
      }
    }
  }

  Future<void> _loadOnce() async {
    setState(() {
      _loading = true;
      _error = null;
      _phase = SessionRecoveryCoordinator.instance.recoveryPending
          ? _ServicesLoadPhase.recoveringSession
          : _ServicesLoadPhase.loading;
    });
    try {
      final api = ref.read(adminApiProvider);
      final results = await Future.wait<dynamic>([
        api.getServiceAdminStats(),
        api.listPendingServiceProviders(),
        api.listPendingServiceOfferings(),
        api.listServiceCategorySuggestions(),
        api.listServiceReports(),
        api.listServiceAdminRequests(limit: 40),
        api.listServiceModuleSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = _asMap(results[0]);
        _providers = _itemsFromAny(results[1]);
        _offerings = _itemsFromAny(results[2]);
        _suggestions = _itemsFromAny(results[3]);
        _reports = _itemsFromAny(results[4]);
        _requests = _itemsFromAny(results[5]);
        _settings = _itemsFromList(results[6]);
        _loading = false;
        _phase = _hasAnyData
            ? _ServicesLoadPhase.loadedWithData
            : _ServicesLoadPhase.loadedEmpty;
      });
    } catch (error) {
      if (!mounted) return;
      final mapped = _mapServicesError(error);
      setState(() {
        _loading = false;
        _error = mapped.message;
        _phase = mapped.phase;
      });
    }
  }

  bool get _hasAnyData =>
      _stats.isNotEmpty ||
      _providers.isNotEmpty ||
      _offerings.isNotEmpty ||
      _suggestions.isNotEmpty ||
      _reports.isNotEmpty ||
      _requests.isNotEmpty ||
      _settings.isNotEmpty;

  ({_ServicesLoadPhase phase, String message}) _mapServicesError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode ?? 0;
      if (status == 401) {
        return (
          phase: _ServicesLoadPhase.recoveringSession,
          message: _servicesRecoveryMessage,
        );
      }
      if (status == 403) {
        return (
          phase: _ServicesLoadPhase.permissionDenied,
          message: _servicesPermissionDeniedMessage,
        );
      }
      if (_isNetworkError(error)) {
        return (
          phase: _ServicesLoadPhase.networkError,
          message: _servicesNetworkMessage,
        );
      }
      if (status >= 500) {
        return (
          phase: _ServicesLoadPhase.serverError,
          message: _servicesServerMessage,
        );
      }
      return (
        phase: _ServicesLoadPhase.serverError,
        message: mapDioError(error, fallback: _servicesServerMessage),
      );
    }
    return (
      phase: _ServicesLoadPhase.serverError,
      message: mapAnyError(error, fallback: _servicesServerMessage),
    );
  }

  bool _isNetworkError(DioException error) {
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }

  bool _isBlockingErrorPhase(_ServicesLoadPhase phase) {
    return phase == _ServicesLoadPhase.recoveringSession ||
        phase == _ServicesLoadPhase.permissionDenied ||
        phase == _ServicesLoadPhase.networkError ||
        phase == _ServicesLoadPhase.serverError;
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _itemsFromAny(dynamic raw) {
    final map = _asMap(raw);
    if (map['items'] is List) {
      return _itemsFromList(map['items'] as List);
    }
    if (raw is List) return _itemsFromList(raw);
    return const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _itemsFromList(List<dynamic> raw) {
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _text(dynamic value, [String fallback = '']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? fallback : text;
  }

  int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  Future<void> _reviewProvider(Map<String, dynamic> row) async {
    await _showStatusActionDialog(
      title: 'مراجعة مقدم الخدمة',
      statusOptions: const ['approved', 'rejected', 'suspended', 'pending'],
      initialStatus: _text(row['providerApprovalStatus'], 'pending'),
      onSubmit: (status, note) => ref
          .read(adminApiProvider)
          .updateServiceProviderModeration(
            providerId: _int(row['id']),
            status: status,
            note: note,
          ),
    );
  }

  Future<void> _reviewOffering(Map<String, dynamic> row) async {
    await _showStatusActionDialog(
      title: 'مراجعة الخدمة',
      statusOptions: const [
        'approved',
        'rejected',
        'changes_requested',
        'hidden',
        'pending',
      ],
      initialStatus: _text(row['moderationStatus'], 'pending'),
      optionLabelBuilder: _offeringStatusLabel,
      onSubmit: (status, note) => ref
          .read(adminApiProvider)
          .updateServiceOfferingModeration(
            offeringId: _int(row['id']),
            status: status,
            note: note,
          ),
    );
  }

  Future<void> _reviewSuggestion(Map<String, dynamic> row) async {
    await _showStatusActionDialog(
      title: 'مراجعة اقتراح الفئة',
      statusOptions: const ['approved', 'rejected', 'merged'],
      initialStatus: 'approved',
      statusLabel: 'الإجراء',
      onSubmit: (status, note) => ref
          .read(adminApiProvider)
          .reviewServiceCategorySuggestion(
            suggestionId: _int(row['id']),
            action: status,
            reviewNote: note,
          ),
    );
  }

  Future<void> _reviewReport(Map<String, dynamic> row) async {
    await _showStatusActionDialog(
      title: 'مراجعة البلاغ',
      statusOptions: const ['resolved', 'rejected', 'pending'],
      initialStatus: _text(row['status'], 'pending'),
      onSubmit: (status, note) => ref
          .read(adminApiProvider)
          .reviewServiceReport(
            reportId: _int(row['id']),
            status: status,
            reviewNote: note,
          ),
    );
  }

  Future<void> _editSetting(Map<String, dynamic> row) async {
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(row['value'] ?? {}),
    );
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('إعداد: ${_text(row['key'])}'),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: controller,
              maxLines: 12,
              decoration: const InputDecoration(labelText: 'قيمة JSON'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      dynamic value;
      try {
        value = jsonDecode(controller.text);
      } catch (_) {
        value = controller.text;
      }
      setState(() => _saving = true);
      await ref
          .read(adminApiProvider)
          .upsertServiceModuleSetting(key: _text(row['key']), value: value);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث الإعداد.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mapServicesError(error).message)));
    } finally {
      controller.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showStatusActionDialog({
    required String title,
    required List<String> statusOptions,
    required String initialStatus,
    String statusLabel = 'الحالة',
    String Function(String status)? optionLabelBuilder,
    required Future<void> Function(String status, String? note) onSubmit,
  }) async {
    final noteCtrl = TextEditingController();
    var selectedStatus = initialStatus;
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      decoration: InputDecoration(labelText: statusLabel),
                      items: statusOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(
                                optionLabelBuilder?.call(value) ?? value,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedStatus = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظة إدارية',
                        hintText: 'اختيارية',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        ),
      );
      if (approved != true) return;
      setState(() => _saving = true);
      await onSubmit(
        selectedStatus,
        noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ التحديث.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mapServicesError(error).message)));
    } finally {
      noteCtrl.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  String _offeringStatusLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'approved':
        return 'منشورة';
      case 'rejected':
        return 'مرفوضة';
      case 'changes_requested':
        return 'تحتاج تعديلات';
      case 'hidden':
        return 'مخفية';
      case 'pending':
        return 'بانتظار المراجعة';
      default:
        return value;
    }
  }

  Widget _buildAdminDrawer() {
    final auth = ref.watch(authControllerProvider);
    return AppUserDrawer(
      title: 'لوحة الإدارة',
      subtitle: auth.user?.fullName,
      showCommunitySection: false,
      showSettings: false,
      enableItemSearch: false,
      items: [
        AppUserDrawerItem(
          icon: Icons.space_dashboard_rounded,
          label: 'لوحة التحكم',
          subtitle: 'الصفحة الرئيسية للأدمن',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(
                builder: (_) => const AdminDashboardScreen(),
              ),
              (route) => false,
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.verified_user_outlined,
          label: 'حوض الموافقات',
          subtitle: 'مراجعة كل الطلبات المعلقة',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminApprovalsHubScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.home_repair_service_outlined,
          label: 'إدارة الخدمات',
          subtitle: 'ملخص الطلبات والعروض',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminServicesHubScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.description_outlined,
          label: 'طلبات الاشتراك',
          subtitle: 'عرض طلبات أصحاب الخدمة',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const AdminServiceProviderSubscriptionRequestsScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.refresh_rounded,
          label: 'تحديث الصفحة',
          subtitle: 'إعادة تحميل إحصائيات الخدمات',
          group: 'الإجراءات',
          onTap: (_) async {
            await _load();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(child: _buildAdminDrawer()),
      appBar: AppBar(
        title: const Text('إدارة الخدمات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: (_saving || _loading) ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            if (_error != null)
              _ServicesStatusCard(
                phase: _phase,
                message: _error!,
                loading: _loading,
                onRetry: (_saving || _loading) ? null : _load,
              ),
            if (_loading)
              Padding(
                padding: const EdgeInsets.only(top: 120),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      if (_phase == _ServicesLoadPhase.recoveringSession) ...[
                        const SizedBox(height: 12),
                        const Text(_servicesRecoveryMessage),
                      ],
                    ],
                  ),
                ),
              )
            else if (_isBlockingErrorPhase(_phase) && !_hasAnyData)
              const SizedBox.shrink()
            else ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const AdminServiceProviderSubscriptionRequestsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.home_repair_service_outlined),
                label: const Text('فتح شاشة اشتراكات أصحاب الخدمة'),
              ),
              const SizedBox(height: 14),
              _StatsSection(stats: _stats),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'مقدمو الخدمة بانتظار المراجعة',
                count: _providers.length,
                children: _providers
                    .map(
                      (row) => ListTile(
                        title: Text(_text(row['businessName'], 'مقدم خدمة')),
                        subtitle: Text(
                          [
                            _text(row['ownerFullName']),
                            _text(row['city']),
                            _text(row['mainCategoryName']),
                            'الحالة: ${_text(row['providerApprovalStatus'])}',
                          ].where((item) => item.isNotEmpty).join(' • '),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.rule_folder_outlined),
                          onPressed: _saving
                              ? null
                              : () => _reviewProvider(row),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'الخدمات بانتظار المراجعة',
                count: _offerings.length,
                children: _offerings
                    .map(
                      (row) => ListTile(
                        title: Text(_text(row['name'], 'خدمة')),
                        subtitle: Text(
                          [
                            _text(row['providerBusinessName']),
                            _text(row['mainCategoryName']),
                            'الحالة: ${_text(row['moderationStatus'])}',
                          ].where((item) => item.isNotEmpty).join(' • '),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.rule_folder_outlined),
                          onPressed: _saving
                              ? null
                              : () => _reviewOffering(row),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'اقتراحات الفئات',
                count: _suggestions.length,
                children: _suggestions
                    .map(
                      (row) => ListTile(
                        title: Text(_text(row['name'], 'اقتراح فئة')),
                        subtitle: Text(
                          [
                            _text(row['suggestedByName']),
                            _text(row['suggestionType']),
                            'الحالة: ${_text(row['status'])}',
                          ].where((item) => item.isNotEmpty).join(' • '),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.rule_folder_outlined),
                          onPressed: _saving
                              ? null
                              : () => _reviewSuggestion(row),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'بلاغات الخدمات',
                count: _reports.length,
                children: _reports
                    .map(
                      (row) => ListTile(
                        title: Text(
                          '${_text(row['targetType'])} #${_int(row['targetId'])}',
                        ),
                        subtitle: Text(
                          [
                            _text(row['reason']),
                            'الحالة: ${_text(row['status'])}',
                          ].where((item) => item.isNotEmpty).join(' • '),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.rule_folder_outlined),
                          onPressed: _saving ? null : () => _reviewReport(row),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'أحدث طلبات الخدمة',
                count: _requests.length,
                children: _requests
                    .map(
                      (row) => ListTile(
                        title: Text(_text(row['requestCode'], 'طلب خدمة')),
                        subtitle: Text(
                          [
                            _text(row['offeringName']),
                            _text(row['providerBusinessName']),
                            _text(row['customerFullName']),
                            'الحالة: ${_text(row['status'])}',
                          ].where((item) => item.isNotEmpty).join(' • '),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'إعدادات مودل الخدمات',
                count: _settings.length,
                children: _settings
                    .map(
                      (row) => ListTile(
                        title: Text(_text(row['key'])),
                        subtitle: Text(
                          const JsonEncoder.withIndent(
                            '  ',
                          ).convert(row['value'] ?? const <String, dynamic>{}),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: _saving ? null : () => _editSetting(row),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServicesStatusCard extends StatelessWidget {
  final _ServicesLoadPhase phase;
  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  const _ServicesStatusCard({
    required this.phase,
    required this.message,
    required this.loading,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isRecovering = phase == _ServicesLoadPhase.recoveringSession;
    final color = isRecovering
        ? Colors.blue
        : phase == _ServicesLoadPhase.permissionDenied
        ? Colors.orange
        : Colors.red;
    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              Icon(
                isRecovering
                    ? Icons.sync_problem_rounded
                    : phase == _ServicesLoadPhase.permissionDenied
                    ? Icons.lock_outline
                    : Icons.error_outline,
                color: color,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: TextStyle(color: color.shade700)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsSection extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _StatsSection({required this.stats});

  String _text(dynamic value, [String fallback = '']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? fallback : text;
  }

  String _formatListValue(List<dynamic> values) {
    if (values.isEmpty) return '—';
    final mapRows = values
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    if (mapRows.isNotEmpty) {
      return mapRows
          .take(4)
          .map((row) {
            final name = _text(row['name'], _text(row['title'], 'عنصر'));
            final count =
                row['offeringsCount'] ?? row['count'] ?? row['itemsCount'];
            if (count == null) return name;
            return '$name · ${_text(count)}';
          })
          .join(' • ');
    }
    return values.take(4).map((value) => _text(value, '—')).join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    stats.forEach((key, value) {
      if (value is Map) {
        value.forEach((childKey, childValue) {
          cards.add(_StatChip(label: '$key.$childKey', value: '$childValue'));
        });
      } else if (value is List) {
        cards.add(_StatChip(label: key, value: _formatListValue(value)));
      } else {
        cards.add(_StatChip(label: key, value: '$value'));
      }
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إحصائيات الخدمات',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (cards.isEmpty) const Text('لا توجد بيانات إحصائية حاليًا.'),
            if (cards.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: cards),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final int count;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.count,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(title),
        subtitle: Text('$count عنصر'),
        children: children.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('لا توجد بيانات حالية.'),
                  ),
                ),
              ]
            : children,
      ),
    );
  }
}
