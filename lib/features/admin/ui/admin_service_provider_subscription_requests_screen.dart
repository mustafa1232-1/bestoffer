import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

class AdminServiceProviderSubscriptionRequestsScreen
    extends ConsumerStatefulWidget {
  const AdminServiceProviderSubscriptionRequestsScreen({super.key});

  @override
  ConsumerState<AdminServiceProviderSubscriptionRequestsScreen> createState() =>
      _AdminServiceProviderSubscriptionRequestsScreenState();
}

class _AdminServiceProviderSubscriptionRequestsScreenState
    extends ConsumerState<AdminServiceProviderSubscriptionRequestsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _statusFilter = 'all';
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

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
      final rows = await ref
          .read(adminApiProvider)
          .serviceProviderSubscriptionRequests(
            status: _statusFilter == 'all' ? null : _statusFilter,
            limit: 200,
          );
      if (!mounted) return;
      setState(() {
        _items = rows
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(e, fallback: 'تعذر تحميل طلبات الاشتراك.');
      });
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  String _asText(dynamic value) => '${value ?? ''}'.trim();

  Future<void> _sendOffer(Map<String, dynamic> row) async {
    final amountCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final validUntilCtrl = TextEditingController();
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('إرسال عرض اشتراك'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ (IQD)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'عنوان العرض (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'وصف العرض (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: validUntilCtrl,
                    decoration: const InputDecoration(
                      labelText: 'صالح لغاية ISO (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة إدارية (اختياري)',
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
                child: const Text('إرسال'),
              ),
            ],
          );
        },
      );
      if (approved != true) return;
      final amount = num.tryParse(amountCtrl.text.trim());
      if (amount == null || amount < 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('المبلغ غير صالح.')));
        return;
      }

      setState(() => _saving = true);
      await ref
          .read(adminApiProvider)
          .sendServiceProviderSubscriptionOffer(
            requestId: _asInt(row['id']),
            amount: amount,
            currency: 'IQD',
            title: titleCtrl.text.trim(),
            description: descCtrl.text.trim(),
            validUntilIso: validUntilCtrl.text.trim(),
            note: noteCtrl.text.trim(),
          );
      await _load();
      if (!mounted) return;
      await ref.read(adminControllerProvider.notifier).bootstrap();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إرسال العرض بنجاح.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapAnyError(e, fallback: 'تعذر إرسال العرض.'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
      amountCtrl.dispose();
      titleCtrl.dispose();
      descCtrl.dispose();
      noteCtrl.dispose();
      validUntilCtrl.dispose();
    }
  }

  Future<void> _rejectRequest(Map<String, dynamic> row) async {
    final noteCtrl = TextEditingController();
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('رفض الطلب'),
          content: TextField(
            controller: noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'سبب الرفض (اختياري)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      setState(() => _saving = true);
      await ref
          .read(adminApiProvider)
          .rejectServiceProviderSubscriptionRequest(
            requestId: _asInt(row['id']),
            note: noteCtrl.text.trim(),
          );
      await _load();
      if (!mounted) return;
      await ref.read(adminControllerProvider.notifier).bootstrap();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم رفض الطلب.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapAnyError(e, fallback: 'تعذر رفض الطلب.'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
      noteCtrl.dispose();
    }
  }

  Future<void> _confirmCashPayment(Map<String, dynamic> row) async {
    final noteCtrl = TextEditingController();
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد استلام نقدي'),
          content: TextField(
            controller: noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'ملاحظة الاستلام (اختياري)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('تأكيد وإنشاء الحساب'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      setState(() => _saving = true);
      await ref
          .read(adminApiProvider)
          .confirmServiceProviderSubscriptionCashPayment(
            requestId: _asInt(row['id']),
            note: noteCtrl.text.trim(),
          );
      await _load();
      if (!mounted) return;
      await ref.read(adminControllerProvider.notifier).bootstrap();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد الدفع وإنشاء الحساب.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapAnyError(e, fallback: 'تعذر تأكيد الدفع.'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
      noteCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات اشتراك أصحاب الخدمة'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('كل الحالات')),
                DropdownMenuItem(
                  value: 'pending_offer',
                  child: Text('بانتظار عرض'),
                ),
                DropdownMenuItem(value: 'offer_sent', child: Text('عرض مرسل')),
                DropdownMenuItem(
                  value: 'offer_accepted',
                  child: Text('عرض مقبول'),
                ),
                DropdownMenuItem(
                  value: 'offer_rejected',
                  child: Text('عرض مرفوض'),
                ),
                DropdownMenuItem(
                  value: 'account_created',
                  child: Text('تم إنشاء الحساب'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _statusFilter = value);
                _load();
              },
              decoration: const InputDecoration(labelText: 'فلترة حسب الحالة'),
            ),
          ),
          if (_saving) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text(_error!)),
                      ],
                    )
                  : _items.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('لا توجد طلبات حالياً.')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final row = _items[index];
                        final status = _asText(row['status']);
                        final offer = row['activeOffer'] is Map
                            ? Map<String, dynamic>.from(
                                row['activeOffer'] as Map,
                              )
                            : null;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _asText(row['businessName']).isEmpty
                                      ? _asText(row['fullName'])
                                      : _asText(row['businessName']),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('الهاتف: ${_asText(row['phone'])}'),
                                Text('المدينة: ${_asText(row['city'])}'),
                                Text('الحالة: $status'),
                                if (offer != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'آخر عرض: ${offer['amount'] ?? '-'} ${offer['currency'] ?? 'IQD'}',
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _saving
                                          ? null
                                          : () => _sendOffer(row),
                                      icon: const Icon(Icons.sell_outlined),
                                      label: const Text('إرسال/تحديث عرض'),
                                    ),
                                    if (status == 'offer_accepted' ||
                                        status ==
                                            'payment_pending_confirmation')
                                      FilledButton.icon(
                                        onPressed: _saving
                                            ? null
                                            : () => _confirmCashPayment(row),
                                        icon: const Icon(
                                          Icons.payments_outlined,
                                        ),
                                        label: const Text('تأكيد استلام نقدي'),
                                      ),
                                    if (status != 'account_created' &&
                                        status != 'rejected')
                                      TextButton.icon(
                                        onPressed: _saving
                                            ? null
                                            : () => _rejectRequest(row),
                                        icon: const Icon(Icons.block_rounded),
                                        label: const Text('رفض الطلب'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
