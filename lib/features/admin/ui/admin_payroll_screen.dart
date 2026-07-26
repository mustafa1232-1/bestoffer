import 'package:core_design_system/core_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/parsers.dart';
import '../state/admin_controller.dart';

const _paymentMethods = <String>['cash', 'bank_transfer', 'wallet', 'card', 'other'];

String _payMethodLabel(BuildContext c, String key) {
  const ar = {
    'cash': 'نقدي', 'bank_transfer': 'حوالة بنكية', 'wallet': 'محفظة',
    'card': 'بطاقة', 'other': 'أخرى',
  };
  return c.lt(ar: ar[key] ?? key, en: key);
}

String payrollStatusLabel(BuildContext c, String key) {
  const ar = {
    'DRAFT': 'مسودة', 'CALCULATED': 'محسوبة', 'UNDER_REVIEW': 'قيد المراجعة',
    'APPROVED': 'معتمدة', 'RELEASED': 'مُطلَقة', 'PAID': 'مدفوعة',
    'ACKNOWLEDGED': 'مؤكَّد الاستلام', 'ARCHIVED': 'مؤرشفة',
  };
  return c.lt(ar: ar[key] ?? key, en: key);
}

class AdminPayrollScreen extends ConsumerStatefulWidget {
  const AdminPayrollScreen({super.key});

  @override
  ConsumerState<AdminPayrollScreen> createState() => _AdminPayrollScreenState();
}

class _AdminPayrollScreenState extends ConsumerState<AdminPayrollScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _runs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(adminApiProvider).payrollRuns();
      final runs = ((data['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _runs = runs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر تحميل الرواتب.')
          : 'تعذّر تحميل الرواتب.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createRun() async {
    final controller = TextEditingController();
    final period = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.lt(ar: 'دورة راتب جديدة', en: 'New payroll run')),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'YYYY-MM',
            hintText: '2026-07',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.lt(ar: 'إلغاء', en: 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(context.lt(ar: 'إنشاء', en: 'Create')),
          ),
        ],
      ),
    );
    if (period == null || !RegExp(r'^\d{4}-\d{2}$').hasMatch(period)) return;
    try {
      final data = await ref.read(adminApiProvider).createPayrollRun(period);
      final runId = parseInt(Map<String, dynamic>.from(data['run'] as Map)['id']);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AdminPayrollRunScreen(runId: runId)),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر إنشاء الدورة.')
          : 'تعذّر إنشاء الدورة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'الرواتب', en: 'Payroll')),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createRun,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.lt(ar: 'دورة جديدة', en: 'New run')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _runs.isEmpty
                  ? MaslakiEmptyState(
                      icon: Icons.payments_outlined,
                      title: context.lt(ar: 'لا توجد دورات رواتب', en: 'No payroll runs'),
                      body: context.lt(ar: 'أنشئ دورة راتب جديدة.', en: 'Create a new payroll run.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(MaslakiSpacing.md),
                      itemCount: _runs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: MaslakiSpacing.sm),
                      itemBuilder: (context, i) {
                        final r = _runs[i];
                        return MaslakiCard(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${r['period_month'] ?? ''}'),
                            subtitle: Text(payrollStatusLabel(context, '${r['status'] ?? ''}')),
                            trailing: const Icon(Icons.chevron_left_rounded),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AdminPayrollRunScreen(runId: parseInt(r['id'])),
                                ),
                              );
                              _load();
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}

class AdminPayrollRunScreen extends ConsumerStatefulWidget {
  const AdminPayrollRunScreen({super.key, required this.runId});
  final int runId;

  @override
  ConsumerState<AdminPayrollRunScreen> createState() => _AdminPayrollRunScreenState();
}

class _AdminPayrollRunScreenState extends ConsumerState<AdminPayrollRunScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _run = const {};
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(adminApiProvider).payrollRun(widget.runId);
      if (!mounted) return;
      setState(() {
        _run = Map<String, dynamic>.from(data['run'] as Map? ?? {});
        _items = ((data['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر تحميل الدورة.')
          : 'تعذّر تحميل الدورة.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run2(Future<Map<String, dynamic>> Function() op) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await op();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر تنفيذ العملية.')
          : 'تعذّر تنفيذ العملية.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markPaid() async {
    final api = ref.read(adminApiProvider);
    String method = 'cash';
    final reference = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(context.lt(ar: 'تسديد الرواتب', en: 'Mark paid')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: InputDecoration(labelText: context.lt(ar: 'طريقة الدفع', en: 'Payment method')),
                items: [
                  for (final m in _paymentMethods)
                    DropdownMenuItem(value: m, child: Text(_payMethodLabel(ctx, m))),
                ],
                onChanged: (v) => setLocal(() => method = v ?? method),
              ),
              TextField(
                controller: reference,
                decoration: InputDecoration(labelText: context.lt(ar: 'مرجع (اختياري)', en: 'Reference (optional)')),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.lt(ar: 'إلغاء', en: 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.lt(ar: 'تأكيد', en: 'Confirm'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run2(() => api.markPayrollRunPaid(
          widget.runId,
          paymentMethod: method,
          paymentReference: reference.text.trim(),
        ));
  }

  List<Widget> _actions(String status) {
    final api = ref.read(adminApiProvider);
    Widget btn(String label, VoidCallback onTap, {IconData icon = Icons.arrow_forward_rounded}) =>
        FilledButton.icon(onPressed: _busy ? null : onTap, icon: Icon(icon), label: Text(label));
    switch (status) {
      case 'DRAFT':
        return [btn(context.lt(ar: 'احتساب', en: 'Calculate'),
            () => _run2(() => api.calculatePayrollRun(widget.runId)), icon: Icons.calculate_rounded)];
      case 'CALCULATED':
        return [
          btn(context.lt(ar: 'إعادة الاحتساب', en: 'Recalculate'),
              () => _run2(() => api.calculatePayrollRun(widget.runId)), icon: Icons.calculate_rounded),
          btn(context.lt(ar: 'إرسال للمراجعة', en: 'Submit for review'),
              () => _run2(() => api.payrollRunAction(widget.runId, 'submit'))),
        ];
      case 'UNDER_REVIEW':
        return [btn(context.lt(ar: 'اعتماد', en: 'Approve'),
            () => _run2(() => api.payrollRunAction(widget.runId, 'approve')), icon: Icons.verified_rounded)];
      case 'APPROVED':
        return [btn(context.lt(ar: 'إطلاق', en: 'Release'),
            () => _run2(() => api.payrollRunAction(widget.runId, 'release')), icon: Icons.send_rounded)];
      case 'RELEASED':
        return [btn(context.lt(ar: 'تم التسديد', en: 'Mark paid'), _markPaid, icon: Icons.payments_rounded)];
      case 'PAID':
        return [btn(context.lt(ar: 'تأكيد الاستلام', en: 'Acknowledge'),
            () => _run2(() => api.payrollRunAction(widget.runId, 'acknowledge')), icon: Icons.done_all_rounded)];
      case 'ACKNOWLEDGED':
        return [btn(context.lt(ar: 'أرشفة', en: 'Archive'),
            () => _run2(() => api.payrollRunAction(widget.runId, 'archive')), icon: Icons.archive_rounded)];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = '${_run['status'] ?? ''}';
    final totalNet =
        _items.fold<int>(0, (s, it) => s + parseInt(it['net_iqd']));
    return Scaffold(
      appBar: AppBar(
        title: Text('${context.lt(ar: 'دورة', en: 'Run')} ${_run['period_month'] ?? ''}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(MaslakiSpacing.md),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                MaslakiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${context.lt(ar: 'الحالة', en: 'Status')}: ${payrollStatusLabel(context, status)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('${context.lt(ar: 'عدد الموظفين', en: 'Employees')}: ${_items.length}'),
                      Text('${context.lt(ar: 'إجمالي الصافي', en: 'Total net')}: $totalNet د.ع'),
                      if (_run['payment_method'] != null)
                        Text('${context.lt(ar: 'طريقة الدفع', en: 'Payment')}: '
                            '${_payMethodLabel(context, '${_run['payment_method']}')}'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: _actions(status)),
                const SizedBox(height: 12),
                Text(context.lt(ar: 'البنود', en: 'Items'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final it in _items)
                  MaslakiCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('${it['full_name'] ?? it['employee_user_id']}'),
                      subtitle: Text(
                        '${context.lt(ar: 'أساسي', en: 'Base')} ${it['base_salary_iqd']} + '
                        '${context.lt(ar: 'إضافات', en: 'Add')} ${it['additions_iqd']} - '
                        '${context.lt(ar: 'خصم', en: 'Ded')} ${it['deductions_iqd']}',
                      ),
                      trailing: Text('${it['net_iqd']} د.ع',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
    );
  }
}
