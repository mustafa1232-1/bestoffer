import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sections/section_availability_models.dart';
import '../state/admin_controller.dart';

class AdminSectionAvailabilityScreen extends ConsumerStatefulWidget {
  const AdminSectionAvailabilityScreen({super.key});

  @override
  ConsumerState<AdminSectionAvailabilityScreen> createState() =>
      _AdminSectionAvailabilityScreenState();
}

class _AdminSectionAvailabilityScreenState
    extends ConsumerState<AdminSectionAvailabilityScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<SectionAvailabilityEntry> _items = const <SectionAvailabilityEntry>[];
  List<Map<String, dynamic>> _audit = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(adminApiProvider);
      final results = await Future.wait<dynamic>([
        api.listSectionAvailability(),
        api.listSectionAvailabilityAudit(limit: 60),
      ]);
      final availability = List<dynamic>.from(results[0] as List)
          .whereType<Map>()
          .map((row) => SectionAvailabilityEntry.fromJson(
                Map<String, dynamic>.from(row),
              ))
          .toList(growable: false)
        ..sort((a, b) {
          final bySort = a.sortOrder.compareTo(b.sortOrder);
          if (bySort != 0) return bySort;
          return a.sectionKey.compareTo(b.sectionKey);
        });
      final audit = List<dynamic>.from(results[1] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = availability;
        _audit = audit;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _editEntry(SectionAvailabilityEntry entry) async {
    final displayNameCtrl = TextEditingController(text: entry.displayName);
    final sortOrderCtrl = TextEditingController(text: '${entry.sortOrder}');
    final messageCtrl = TextEditingController(text: entry.userMessage ?? '');
    var status = entry.status;
    var isVisible = entry.isVisible;
    var allowExistingActiveAccess = entry.allowExistingActiveAccess;
    var changed = false;
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('إدارة ${entry.displayName}'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: displayNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم القسم',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<SectionAvailabilityStatus>(
                        initialValue: status,
                        decoration: const InputDecoration(
                          labelText: 'الحالة',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: SectionAvailabilityStatus.open,
                            child: Text('مفتوح'),
                          ),
                          DropdownMenuItem(
                            value: SectionAvailabilityStatus.comingSoon,
                            child: Text('قريبًا'),
                          ),
                          DropdownMenuItem(
                            value: SectionAvailabilityStatus.maintenance,
                            child: Text('تحت الصيانة'),
                          ),
                          DropdownMenuItem(
                            value: SectionAvailabilityStatus.temporarilyClosed,
                            child: Text('مغلق مؤقتًا'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => status = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: messageCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'رسالة المستخدم',
                          hintText: 'اختيارية',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: sortOrderCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'ترتيب الظهور',
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isVisible,
                        onChanged: (value) =>
                            setDialogState(() => isVisible = value),
                        title: const Text('إظهار القسم في التطبيق'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: allowExistingActiveAccess,
                        onChanged: (value) => setDialogState(
                          () => allowExistingActiveAccess = value,
                        ),
                        title: const Text('السماح للمعاملات النشطة فقط'),
                      ),
                    ],
                  ),
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
      await ref.read(adminApiProvider).updateSectionAvailability(
            sectionKey: entry.sectionKey,
            displayName: displayNameCtrl.text.trim().isEmpty
                ? entry.displayName
                : displayNameCtrl.text.trim(),
            status: status.apiValue,
            isVisible: isVisible,
            surfaceScope: entry.surfaceScope,
            parentSectionKey: entry.parentSectionKey,
            userMessage: messageCtrl.text.trim(),
            sortOrder: int.tryParse(sortOrderCtrl.text.trim()) ?? entry.sortOrder,
            allowExistingActiveAccess: allowExistingActiveAccess,
            metadata: entry.metadata,
          );
      changed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث حالة القسم.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      displayNameCtrl.dispose();
      sortOrderCtrl.dispose();
      messageCtrl.dispose();
      if (mounted) setState(() => _saving = false);
    }
    if (changed) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إتاحة الأقسام'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _saving ? null : _load,
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
              Card(
                color: Colors.red.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              const Text(
                'الأقسام الرئيسية',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              ..._items.map(
                (entry) => Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    title: Text(entry.displayName),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المفتاح: ${entry.sectionKey}'),
                          Text('الحالة: ${_statusLabel(entry.status)}'),
                          Text(entry.isVisible ? 'ظاهر للمستخدم' : 'مخفي'),
                          Text(
                            entry.allowExistingActiveAccess
                                ? 'يسمح بالمعاملات النشطة'
                                : 'يمنع الوصول بالكامل',
                          ),
                          if ((entry.userMessage ?? '').trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('الرسالة: ${entry.userMessage}'),
                            ),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: _saving ? null : () => _editEntry(entry),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'سجل التغييرات',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              if (_audit.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('لا توجد تغييرات مسجلة حتى الآن.'),
                  ),
                ),
              ..._audit.take(40).map(
                (row) => Card(
                  child: ListTile(
                    title: Text(_auditTitle(row)),
                    subtitle: Text(_auditSubtitle(row)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _statusLabel(SectionAvailabilityStatus status) {
  switch (status) {
    case SectionAvailabilityStatus.open:
      return 'مفتوح';
    case SectionAvailabilityStatus.comingSoon:
      return 'قريبًا';
    case SectionAvailabilityStatus.maintenance:
      return 'تحت الصيانة';
    case SectionAvailabilityStatus.temporarilyClosed:
      return 'مغلق مؤقتًا';
  }
}

String _auditTitle(Map<String, dynamic> row) {
  final name = '${row['sectionKey'] ?? row['section_key'] ?? 'section'}'.trim();
  final fromStatus = '${row['fromStatus'] ?? row['from_status'] ?? '-'}'.trim();
  final toStatus = '${row['toStatus'] ?? row['to_status'] ?? '-'}'.trim();
  return '$name: $fromStatus → $toStatus';
}

String _auditSubtitle(Map<String, dynamic> row) {
  final actor = '${row['actorUserId'] ?? row['actor_user_id'] ?? '-'}'.trim();
  final createdAt = '${row['createdAt'] ?? row['created_at'] ?? ''}'.trim();
  return 'المستخدم: $actor • $createdAt';
}
