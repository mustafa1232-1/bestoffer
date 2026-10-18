import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_design_system/core_design_system.dart'
    show showMaslakiBottomSheet;

import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../../coupons/data/coupons_api.dart';

class AdminInfluencerReferralsScreen extends ConsumerStatefulWidget {
  const AdminInfluencerReferralsScreen({super.key});

  @override
  ConsumerState<AdminInfluencerReferralsScreen> createState() =>
      _AdminInfluencerReferralsScreenState();
}

class _AdminInfluencerReferralsScreenState
    extends ConsumerState<AdminInfluencerReferralsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _influencers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await ref.read(couponsApiProvider).listInfluencerProfiles();
      if (!mounted) return;
      setState(() {
        _influencers = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = mapAnyError(error, fallback: 'تعذر تحميل قائمة المؤثرين.');
        _loading = false;
      });
    }
  }

  Future<void> _createInfluencer() async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CreateInfluencerDialog(),
    );
    if (payload == null || !mounted) return;
    try {
      final response = await ref
          .read(couponsApiProvider)
          .createInfluencerProfile(payload);
      final raw = response['influencer'];
      final influencer = raw is Map
          ? Map<String, dynamic>.from(raw)
          : const <String, dynamic>{};
      if (!mounted) return;
      await _showGeneratedCode(
        title: 'تم إنشاء المؤثر ورمز الإحالة',
        code: '${influencer['trackingCode'] ?? ''}',
        description:
            'هذا رمز إحالة وتتبع فقط، ويُدخل أثناء إنشاء حساب المستخدم. لا يمنح خصمًا.',
      );
      await _load();
    } catch (error) {
      _showError(error, 'تعذر إنشاء المؤثر.');
    }
  }

  Future<void> _createCoupon(Map<String, dynamic> influencer) async {
    final influencerId = _int(influencer['influencerId']);
    if (influencerId <= 0) return;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CreateInfluencerCouponDialog(
        influencerName: '${influencer['influencerName'] ?? ''}',
      ),
    );
    if (payload == null || !mounted) return;
    try {
      final response = await ref
          .read(couponsApiProvider)
          .createInfluencerMarketingCoupon(
            influencerId: influencerId,
            body: payload,
          );
      final raw = response['coupon'];
      final coupon = raw is Map
          ? Map<String, dynamic>.from(raw)
          : const <String, dynamic>{};
      if (!mounted) return;
      await _showGeneratedCode(
        title: 'تم إنشاء كوبون التسويق',
        code: '${coupon['code'] ?? ''}',
        description:
            'هذا كوبون خصم مستقل عن رمز الإحالة، ويمكن لكل مستخدم استعماله مرة واحدة فقط.',
      );
      await _load();
    } catch (error) {
      _showError(error, 'تعذر إنشاء كوبون المؤثر.');
    }
  }

  Future<void> _showGeneratedCode({
    required String title,
    required String code,
    required String description,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(description),
              const SizedBox(height: 14),
              SelectableText(
                code,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('نسخ وإغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleInfluencer(
    Map<String, dynamic> influencer,
    bool isActive,
  ) async {
    final id = _int(influencer['influencerId']);
    if (id <= 0) return;
    try {
      await ref
          .read(couponsApiProvider)
          .toggleInfluencerProfile(influencerId: id, isActive: isActive);
      if (!mounted) return;
      setState(() => influencer['isActive'] = isActive);
    } catch (error) {
      _showError(error, 'تعذر تحديث حالة المؤثر.');
    }
  }

  Future<void> _toggleCoupon(Map<String, dynamic> coupon, bool isActive) async {
    final couponId = _int(coupon['couponId']);
    if (couponId <= 0) return;
    try {
      await ref
          .read(couponsApiProvider)
          .toggleCouponActive(couponId: couponId, isActive: isActive);
      if (!mounted) return;
      setState(() => coupon['isActive'] = isActive);
    } catch (error) {
      _showError(error, 'تعذر تحديث حالة الكوبون.');
    }
  }

  Future<void> _showReport(Map<String, dynamic> influencer) async {
    final id = _int(influencer['influencerId']);
    if (id <= 0) return;
    List<Map<String, dynamic>> rows;
    try {
      rows = await ref.read(couponsApiProvider).getInfluencerReferrals(id);
    } catch (error) {
      _showError(error, 'تعذر تحميل تقرير الإحالات.');
      return;
    }
    if (!mounted) return;
    await showMaslakiBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _InfluencerReportSheet(influencer: influencer, rows: rows),
    );
  }

  void _showError(Object error, String fallback) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mapAnyError(error, fallback: fallback))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المؤثرون والمشاهير')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _createInfluencer,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('إنشاء مؤثر'),
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
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
                : _influencers.isEmpty
                ? ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(36),
                        child: Text(
                          'لا يوجد مؤثرون بعد. أنشئ مؤثرًا ليولّد الخادم رمز إحالة آمنًا وفريدًا له.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: _influencers.length,
                    itemBuilder: (_, index) => _InfluencerCard(
                      influencer: _influencers[index],
                      onToggleInfluencer: (value) =>
                          _toggleInfluencer(_influencers[index], value),
                      onShowReport: () => _showReport(_influencers[index]),
                      onCreateCoupon: () => _createCoupon(_influencers[index]),
                      onToggleCoupon: _toggleCoupon,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _InfluencerCard extends StatelessWidget {
  final Map<String, dynamic> influencer;
  final ValueChanged<bool> onToggleInfluencer;
  final VoidCallback onShowReport;
  final VoidCallback onCreateCoupon;
  final Future<void> Function(Map<String, dynamic>, bool) onToggleCoupon;

  const _InfluencerCard({
    required this.influencer,
    required this.onToggleInfluencer,
    required this.onShowReport,
    required this.onCreateCoupon,
    required this.onToggleCoupon,
  });

  @override
  Widget build(BuildContext context) {
    final coupons = (influencer['coupons'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onShowReport,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      _initial('${influencer['influencerName'] ?? ''}'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${influencer['influencerName'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if ('${influencer['influencerHandle'] ?? ''}'
                            .isNotEmpty)
                          Text(
                            '${influencer['influencerHandle']}',
                            textDirection: TextDirection.ltr,
                          ),
                        if ('${influencer['contactPhone'] ?? ''}'.isNotEmpty)
                          Text('${influencer['contactPhone']}'),
                      ],
                    ),
                  ),
                  Switch(
                    value: influencer['isActive'] == true,
                    onChanged: onToggleInfluencer,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hub_rounded),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'رمز الإحالة والتتبع — ليس كوبون خصم',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SelectableText(
                            '${influencer['trackingCode'] ?? ''}',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'نسخ رمز الإحالة',
                      onPressed: () => Clipboard.setData(
                        ClipboardData(
                          text: '${influencer['trackingCode'] ?? ''}',
                        ),
                      ),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Metric(
                    label: 'المستخدمون',
                    value: '${influencer['attributedUsers'] ?? 0}',
                  ),
                  _Metric(
                    label: 'أكملوا طلبًا',
                    value: '${influencer['convertedUsers'] ?? 0}',
                  ),
                  _Metric(
                    label: 'الطلبات',
                    value: '${influencer['completedOrders'] ?? 0}',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SummaryTile(
                      label: 'إجمالي إنفاق العملاء',
                      value: formatIqd(_number(influencer['totalSpent'])),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryTile(
                      label: 'المستحق المحسوب',
                      value: formatIqd(_number(influencer['payableAmount'])),
                    ),
                  ),
                ],
              ),
              if ('${influencer['notes'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('ملاحظات: ${influencer['notes']}'),
              ],
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: onShowReport,
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('فتح التقرير المفصل للمستخدمين والإنفاق'),
              ),
              const Divider(height: 26),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'كوبونات التسويق المنفصلة',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onCreateCoupon,
                    icon: const Icon(Icons.add_card_rounded),
                    label: const Text('إنشاء كوبون'),
                  ),
                ],
              ),
              const Text(
                'الكوبون يمنح خصمًا ويُستخدم مرة واحدة لكل مستخدم. لا يغيّر عداد رمز الإحالة.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              if (coupons.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('لا توجد كوبونات تسويقية لهذا المؤثر.'),
                )
              else
                ...coupons.map(
                  (coupon) => _CouponRow(
                    coupon: coupon,
                    onToggle: (value) => onToggleCoupon(coupon, value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CouponRow extends StatelessWidget {
  final Map<String, dynamic> coupon;
  final ValueChanged<bool> onToggle;

  const _CouponRow({required this.coupon, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final type = coupon['discountType'] == 'fixed' ? 'fixed' : 'percent';
    final value = _number(coupon['discountValue']);
    final discount = type == 'fixed'
        ? formatIqd(value)
        : '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: SelectableText(
                        '${coupon['code'] ?? ''}',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: '${coupon['code'] ?? ''}'),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                    ),
                  ],
                ),
                Text(
                  'الخصم: $discount • الاستخدامات: ${coupon['usesCount'] ?? 0}'
                  '${coupon['maxUses'] == null ? '' : '/${coupon['maxUses']}'}',
                ),
                const Text(
                  'الحد لكل مستخدم: مرة واحدة',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(value: coupon['isActive'] == true, onChanged: onToggle),
        ],
      ),
    );
  }
}

class _InfluencerReportSheet extends StatelessWidget {
  final Map<String, dynamic> influencer;
  final List<Map<String, dynamic>> rows;

  const _InfluencerReportSheet({required this.influencer, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'تقرير ${influencer['influencerName'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'المستخدمون: ${influencer['attributedUsers'] ?? 0} • '
                    'إجمالي الإنفاق: ${formatIqd(_number(influencer['totalSpent']))}',
                  ),
                  Text(
                    'رمز الإحالة: ${influencer['trackingCode'] ?? ''}',
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('لا توجد إحالات بعد.'))
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.only(bottom: 20),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final row = rows[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              _initial('${row['customerName'] ?? ''}'),
                            ),
                          ),
                          title: Text('${row['customerName'] ?? 'مستخدم'}'),
                          subtitle: Text(
                            '${row['customerPhone'] ?? ''}\n'
                            'الطلبات المكتملة: ${row['completedOrders'] ?? 0} • '
                            'الإنفاق: ${formatIqd(_number(row['totalSpent']))}',
                          ),
                          isThreeLine: true,
                          trailing: Icon(
                            row['qualified'] == true
                                ? Icons.verified_rounded
                                : Icons.hourglass_top_rounded,
                            color: row['qualified'] == true
                                ? Colors.green
                                : Colors.orange,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateInfluencerDialog extends StatefulWidget {
  const _CreateInfluencerDialog();

  @override
  State<_CreateInfluencerDialog> createState() =>
      _CreateInfluencerDialogState();
}

class _CreateInfluencerDialogState extends State<_CreateInfluencerDialog> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  final _reward = TextEditingController(text: '0');
  String _qualificationRule = 'first_completed_order';

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _phone.dispose();
    _notes.dispose();
    _reward.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().length < 2) return;
    Navigator.pop(context, <String, dynamic>{
      'influencerName': _name.text.trim(),
      'influencerHandle': _handle.text.trim(),
      'contactPhone': _phone.text.trim(),
      'notes': _notes.text.trim(),
      'rewardPerQualifiedUser': num.tryParse(_reward.text.trim()) ?? 0,
      'qualificationRule': _qualificationRule,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('إنشاء مؤثر أو مشهور جديد'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'الاسم *'),
                ),
                TextField(
                  controller: _handle,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'اسم الحساب أو المعرّف',
                  ),
                ),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                ),
                TextField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'معلومات وملاحظات',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'سيولّد الخادم رمز إحالة قصيرًا وفريدًا من حرفين ورقمين مثل AB12.',
                  ),
                ),
                TextField(
                  controller: _reward,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'استحقاق المؤثر لكل مستخدم مؤهل (د.ع)',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _qualificationRule,
                  decoration: const InputDecoration(
                    labelText: 'شرط احتساب الاستحقاق',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'first_completed_order',
                      child: Text('بعد أول طلب مكتمل'),
                    ),
                    DropdownMenuItem(
                      value: 'claim',
                      child: Text('فور إنشاء الحساب برمز الإحالة'),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _qualificationRule = value ?? 'first_completed_order',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('إنشاء رمز الإحالة'),
          ),
        ],
      ),
    );
  }
}

class _CreateInfluencerCouponDialog extends StatefulWidget {
  final String influencerName;

  const _CreateInfluencerCouponDialog({required this.influencerName});

  @override
  State<_CreateInfluencerCouponDialog> createState() =>
      _CreateInfluencerCouponDialogState();
}

class _CreateInfluencerCouponDialogState
    extends State<_CreateInfluencerCouponDialog> {
  final _label = TextEditingController();
  final _prefix = TextEditingController();
  final _discount = TextEditingController(text: '10');
  final _minimum = TextEditingController(text: '0');
  final _maxUses = TextEditingController();
  String _discountType = 'percent';

  @override
  void dispose() {
    _label.dispose();
    _prefix.dispose();
    _discount.dispose();
    _minimum.dispose();
    _maxUses.dispose();
    super.dispose();
  }

  void _submit() {
    final discount = num.tryParse(_discount.text.trim()) ?? 0;
    if (discount <= 0) return;
    Navigator.pop(context, <String, dynamic>{
      'label': _label.text.trim(),
      'codePrefix': _prefix.text.trim(),
      'discountType': _discountType,
      'discountValue': discount,
      'minOrderTotal': num.tryParse(_minimum.text.trim()) ?? 0,
      if (_maxUses.text.trim().isNotEmpty)
        'maxUses': int.tryParse(_maxUses.text.trim()),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('كوبون تسويق — ${widget.influencerName}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'هذا الكوبون منفصل عن رمز الإحالة، ويستعمله كل مستخدم مرة واحدة فقط.',
                ),
                TextField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: 'اسم الحملة (اختياري)',
                  ),
                ),
                TextField(
                  controller: _prefix,
                  textDirection: TextDirection.ltr,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'بادئة الكوبون (اختياري)',
                    helperText: 'الخادم يولد الكوبون تلقائيًا.',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _discountType,
                  decoration: const InputDecoration(labelText: 'نوع الخصم'),
                  items: const [
                    DropdownMenuItem(value: 'percent', child: Text('نسبة %')),
                    DropdownMenuItem(value: 'fixed', child: Text('مبلغ ثابت')),
                  ],
                  onChanged: (value) =>
                      setState(() => _discountType = value ?? 'percent'),
                ),
                TextField(
                  controller: _discount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'قيمة الخصم *'),
                ),
                TextField(
                  controller: _minimum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الحد الأدنى للطلب',
                  ),
                ),
                TextField(
                  controller: _maxUses,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'إجمالي مرات الاستخدام (اختياري)',
                    helperText: 'يظل الحد لكل مستخدم مرة واحدة دائمًا.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.local_offer_rounded),
            label: const Text('إنشاء الكوبون'),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    ),
  );
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    ),
  );
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

num _number(Object? value) =>
    value is num ? value : num.tryParse('$value') ?? 0;

String _initial(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'م' : String.fromCharCode(trimmed.runes.first);
}
