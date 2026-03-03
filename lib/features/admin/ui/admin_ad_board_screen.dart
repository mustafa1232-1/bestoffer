import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ad_board_item_model.dart';
import '../state/admin_ad_board_controller.dart';
import '../state/admin_controller.dart';

class AdminAdBoardScreen extends ConsumerStatefulWidget {
  const AdminAdBoardScreen({super.key});

  @override
  ConsumerState<AdminAdBoardScreen> createState() => _AdminAdBoardScreenState();
}

class _AdminAdBoardScreenState extends ConsumerState<AdminAdBoardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(adminControllerProvider.notifier).bootstrap();
      await ref.read(adminAdBoardControllerProvider.notifier).bootstrap();
    });
  }

  Future<void> _openCreateSheet() async {
    final merchants = ref.read(adminControllerProvider).managedMerchants;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AdBoardUpsertSheet(
        initial: null,
        merchants: merchants,
        onSubmit: (payload) async {
          await ref
              .read(adminAdBoardControllerProvider.notifier)
              .createItem(payload);
        },
      ),
    );
  }

  Future<void> _openEditSheet(AdBoardItemModel item) async {
    final merchants = ref.read(adminControllerProvider).managedMerchants;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AdBoardUpsertSheet(
        initial: item,
        merchants: merchants,
        onSubmit: (payload) async {
          await ref
              .read(adminAdBoardControllerProvider.notifier)
              .updateItem(item.id, payload);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminAdBoardControllerProvider);

    ref.listen<AdminAdBoardState>(adminAdBoardControllerProvider, (prev, next) {
      final message = next.error ?? next.success;
      final prevMessage = prev?.error ?? prev?.success;
      if (message != null && message != prevMessage && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة إعلانات شكاكي'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () =>
                ref.read(adminAdBoardControllerProvider.notifier).bootstrap(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.saving ? null : _openCreateSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إعلان جديد'),
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(adminAdBoardControllerProvider.notifier).bootstrap(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.35),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.28),
                      ),
                    ),
                    child: const Text(
                      'اختر متجرًا أو أضف إعلانًا عامًا. أي إعلان نشط سيظهر مباشرة في واجهة الزبون.',
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (state.items.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 30),
                        child: Text(
                          'لا توجد إعلانات بعد',
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    )
                  else
                    ...state.items.map((item) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                textDirection: TextDirection.rtl,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          item.title,
                                          textDirection: TextDirection.rtl,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          item.subtitle,
                                          textDirection: TextDirection.rtl,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.82,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: item.isActive,
                                    onChanged: state.saving
                                        ? null
                                        : (value) {
                                            ref
                                                .read(
                                                  adminAdBoardControllerProvider
                                                      .notifier,
                                                )
                                                .updateItem(item.id, {
                                                  'isActive': value,
                                                });
                                          },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _MetaChip(
                                    label: 'الأولوية: ${item.priority}',
                                  ),
                                  if (item.merchantName != null)
                                    _MetaChip(
                                      label: 'المتجر: ${item.merchantName}',
                                    ),
                                  _MetaChip(
                                    label: 'CTA: ${item.ctaTargetType}',
                                  ),
                                ],
                              ),
                              if ((item.imageUrl ?? '').isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  item.imageUrl!,
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.68),
                                    fontSize: 11.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'حذف',
                                    onPressed: state.saving
                                        ? null
                                        : () {
                                            ref
                                                .read(
                                                  adminAdBoardControllerProvider
                                                      .notifier,
                                                )
                                                .deleteItem(item.id);
                                          },
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                  ),
                                  const Spacer(),
                                  FilledButton.icon(
                                    onPressed: state.saving
                                        ? null
                                        : () => _openEditSheet(item),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('تعديل'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;

  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        textDirection: TextDirection.rtl,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _AdBoardUpsertSheet extends StatefulWidget {
  final AdBoardItemModel? initial;
  final List<dynamic> merchants;
  final Future<void> Function(Map<String, dynamic> payload) onSubmit;

  const _AdBoardUpsertSheet({
    required this.initial,
    required this.merchants,
    required this.onSubmit,
  });

  @override
  State<_AdBoardUpsertSheet> createState() => _AdBoardUpsertSheetState();
}

class _AdBoardUpsertSheetState extends State<_AdBoardUpsertSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _badgeCtrl;
  late final TextEditingController _imageUrlCtrl;
  late final TextEditingController _ctaLabelCtrl;
  late final TextEditingController _ctaValueCtrl;
  late final TextEditingController _priorityCtrl;

  final _formKey = GlobalKey<FormState>();
  bool _isActive = true;
  int? _merchantId;
  String _ctaType = 'none';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _titleCtrl = TextEditingController(text: initial?.title ?? '');
    _subtitleCtrl = TextEditingController(text: initial?.subtitle ?? '');
    _badgeCtrl = TextEditingController(text: initial?.badgeLabel ?? '');
    _imageUrlCtrl = TextEditingController(text: initial?.imageUrl ?? '');
    _ctaLabelCtrl = TextEditingController(text: initial?.ctaLabel ?? '');
    _ctaValueCtrl = TextEditingController(text: initial?.ctaTargetValue ?? '');
    _priorityCtrl = TextEditingController(text: '${initial?.priority ?? 100}');
    _isActive = initial?.isActive ?? true;
    _merchantId = initial?.merchantId;
    _ctaType =
        initial?.ctaTargetType ?? (_merchantId == null ? 'none' : 'merchant');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _badgeCtrl.dispose();
    _imageUrlCtrl.dispose();
    _ctaLabelCtrl.dispose();
    _ctaValueCtrl.dispose();
    _priorityCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'subtitle': _subtitleCtrl.text.trim(),
        'badgeLabel': _badgeCtrl.text.trim().isEmpty
            ? null
            : _badgeCtrl.text.trim(),
        'imageUrl': _imageUrlCtrl.text.trim().isEmpty
            ? null
            : _imageUrlCtrl.text.trim(),
        'ctaLabel': _ctaLabelCtrl.text.trim().isEmpty
            ? null
            : _ctaLabelCtrl.text.trim(),
        'ctaTargetType': _ctaType,
        'ctaTargetValue': _ctaValueCtrl.text.trim().isEmpty
            ? null
            : _ctaValueCtrl.text.trim(),
        'merchantId': _merchantId,
        'priority': int.tryParse(_priorityCtrl.text.trim()) ?? 100,
        'isActive': _isActive,
      };
      await widget.onSubmit(payload);
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        padding: EdgeInsets.only(bottom: insets),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  widget.initial == null ? 'إضافة إعلان' : 'تعديل إعلان',
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _titleCtrl,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(labelText: 'عنوان الإعلان'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'أدخل عنوانًا'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _subtitleCtrl,
                  textDirection: TextDirection.rtl,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'الوصف المختصر'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'أدخل الوصف'
                      : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  key: ValueKey<int?>(_merchantId),
                  initialValue: _merchantId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'ربط بمتجر (اختياري)',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text(
                        'إعلان عام بدون متجر',
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                    ...widget.merchants.map((m) {
                      final id = m.id as int?;
                      final name = (m.name as String?) ?? '';
                      final type = (m.type as String?) ?? '';
                      return DropdownMenuItem<int?>(
                        value: id,
                        child: Text(
                          '$name (${type == 'restaurant' ? 'مطعم' : 'سوق'})',
                          textDirection: TextDirection.rtl,
                        ),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _merchantId = value;
                      if (_merchantId != null && _ctaType == 'none') {
                        _ctaType = 'merchant';
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _badgeCtrl,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          labelText: 'شارة صغيرة (اختياري)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _priorityCtrl,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'الأولوية',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _imageUrlCtrl,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'رابط صورة (اختياري)',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(_ctaType),
                  initialValue: _ctaType,
                  decoration: const InputDecoration(
                    labelText: 'نوع الإجراء عند الضغط',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('بدون إجراء')),
                    DropdownMenuItem(
                      value: 'merchant',
                      child: Text('فتح متجر'),
                    ),
                    DropdownMenuItem(
                      value: 'category',
                      child: Text('فتح تصنيف'),
                    ),
                    DropdownMenuItem(value: 'taxi', child: Text('فتح التكسي')),
                    DropdownMenuItem(
                      value: 'url',
                      child: Text('فتح رابط خارجي'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _ctaType = value);
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ctaLabelCtrl,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'نص زر الإعلان (اختياري)',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ctaValueCtrl,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'قيمة الإجراء (رابط/نوع/بحث) - اختياري',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('نشط ويظهر للزبائن'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'جاري الحفظ...' : 'حفظ الإعلان'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
