import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coupons/data/coupons_api.dart';

/// Super-admin monitoring of employee referral coupons: each employee, their
/// coupon, how many customers/orders came through them, and a control to attach
/// or change the coupon's discount.
class AdminReferralCouponsScreen extends ConsumerStatefulWidget {
  const AdminReferralCouponsScreen({super.key});

  @override
  ConsumerState<AdminReferralCouponsScreen> createState() =>
      _AdminReferralCouponsScreenState();
}

class _AdminReferralCouponsScreenState
    extends ConsumerState<AdminReferralCouponsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _agents = const [];

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
      final agents =
          await ref.read(couponsApiProvider).listAgentReferralCoupons();
      if (!mounted) return;
      setState(() {
        _agents = agents;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _discountLabel(Map<String, dynamic> a) {
    final v = (a['discountValue'] as num?) ?? 0;
    if (v <= 0) return 'تتبّع فقط (بلا خصم)';
    return '${a['discountType']}' == 'percent' ? 'خصم $v%' : 'خصم $v';
  }

  Future<void> _editDiscount(Map<String, dynamic> a) async {
    final couponId = (a['couponId'] as num).toInt();
    final ctrl =
        TextEditingController(text: '${(a['discountValue'] as num?) ?? 0}');
    String type = '${a['discountType'] ?? 'percent'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('تعديل خصم كوبون ${a['code']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'نوع الخصم'),
                items: const [
                  DropdownMenuItem(value: 'percent', child: Text('نسبة %')),
                  DropdownMenuItem(value: 'fixed', child: Text('مبلغ ثابت')),
                ],
                onChanged: (v) => setLocal(() => type = v ?? 'percent'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'القيمة (0 = تتبّع فقط)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final value = num.tryParse(ctrl.text.trim()) ?? 0;
    try {
      await ref.read(couponsApiProvider).updateCouponDiscount(
            couponId: couponId,
            discountType: type,
            discountValue: value,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث الخصم')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر التحديث: $e')),
      );
    }
  }

  Future<void> _showRedemptions(Map<String, dynamic> a) async {
    final couponId = (a['couponId'] as num).toInt();
    List<Map<String, dynamic>> rows = const [];
    try {
      rows =
          await ref.read(couponsApiProvider).getAgentCouponRedemptions(couponId);
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'الزبائن عبر ${a['agentName'] ?? ''} — كوبون ${a['code']}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا يوجد استخدام بعد'),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${r['customerName'] ?? 'زبون'} — ${r['customerPhone'] ?? ''}',
                        ),
                        subtitle: Text('طلب #${r['orderId'] ?? '-'}'),
                        trailing: Text('${r['discountAmount'] ?? 0}'),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('كوبونات الموظفين')),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(
                            'تعذّر التحميل: $_error',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : _agents.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'لا يوجد كوبونات موظفين بعد. فعّل «أنشئ كوبون إحالة» عند إنشاء موظف.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _agents.length,
                  itemBuilder: (context, i) {
                    final a = _agents[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${a['agentName'] ?? 'موظف'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Chip(label: Text('${a['code']}')),
                              ],
                            ),
                            Text(
                              '${a['agentPhone'] ?? ''} · ${a['agentRole'] ?? ''}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _discountLabel(a),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _stat('طلبات', '${a['redemptions'] ?? 0}'),
                                _stat('زبائن', '${a['uniqueCustomers'] ?? 0}'),
                                _stat(
                                  'إجمالي الخصم',
                                  '${a['totalDiscount'] ?? 0}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _showRedemptions(a),
                                  icon: const Icon(
                                    Icons.people_outline,
                                    size: 18,
                                  ),
                                  label: const Text('الزبائن'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _editDiscount(a),
                                  icon: const Icon(Icons.percent, size: 18),
                                  label: const Text('تعديل الخصم'),
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
    );
  }
}
