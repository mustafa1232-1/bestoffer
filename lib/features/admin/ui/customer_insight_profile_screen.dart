import 'package:flutter/material.dart';

import '../../../core/utils/currency.dart';

class CustomerInsightProfileScreen extends StatelessWidget {
  final Map<String, dynamic> details;

  const CustomerInsightProfileScreen({super.key, required this.details});

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  List<String> _asStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item?.toString() ?? '')
        .where((v) => v.trim().isNotEmpty)
        .toList(growable: false);
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  String _fmtDate(dynamic value) {
    if (value == null) return '-';
    final raw = value.toString().trim();
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final d = parsed.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day  $h:$min';
  }

  Widget _sectionTitle(BuildContext context, String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          textDirection: TextDirection.rtl,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            textDirection: TextDirection.rtl,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metricTile({
    required String label,
    required String value,
    IconData icon = Icons.insights_outlined,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  label,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopRows({
    required String emptyText,
    required List<Map<String, dynamic>> rows,
    required String titleKey,
    required String valueKey,
    String? valueSuffix,
  }) {
    if (rows.isEmpty) {
      return Text(emptyText, textDirection: TextDirection.rtl);
    }

    return Column(
      children: rows.take(8).map((row) {
        final title = '${row[titleKey] ?? '-'}';
        final value = _asDouble(row[valueKey]);
        final displayValue = value % 1 == 0
            ? value.toInt().toString()
            : value.toStringAsFixed(1);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: Text(
                  title,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                valueSuffix == null
                    ? displayValue
                    : '$displayValue $valueSuffix',
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = _asMap(details['customer']);
    final orderProfile = _asMap(details['orderProfile']);
    final behaviorProfile = _asMap(details['behaviorProfile']);

    final affinity = _asMap(behaviorProfile['affinity']);
    final persona = _asMap(behaviorProfile['persona']);
    final searchSignals = _asMap(behaviorProfile['searchSignals']);
    final activityPattern = _asMap(behaviorProfile['activityPattern']);
    final favoritesSummary = _asMap(behaviorProfile['favoritesSummary']);
    final carSignals = _asMap(behaviorProfile['carSignals']);

    final topMerchantTypes = _asList(orderProfile['topMerchantTypes']);
    final topMerchants = _asList(orderProfile['topMerchants']);
    final topProducts = _asList(orderProfile['topProducts']);
    final topOrderCategories = _asList(orderProfile['topOrderCategories']);

    final affinityScores = _asList(affinity['scores']);
    final topSearchTerms = _asList(searchSignals['topTerms']);
    final topSearchDomains = _asList(searchSignals['topDomains']);
    final recentEvents = _asList(behaviorProfile['lastEvents']);
    final topHours = _asList(activityPattern['topHours']);
    final topCarBrands = _asList(carSignals['topBrands']);
    final topCarModels = _asList(carSignals['topModels']);
    final campaignHints = _asStringList(persona['campaignHints']);

    final fullName = '${customer['fullName'] ?? '-'}';
    final phone = '${customer['phone'] ?? '-'}';
    final address =
        'بلك ${customer['block'] ?? '-'} - عمارة ${customer['buildingNumber'] ?? '-'} - شقة ${customer['apartment'] ?? '-'}';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('ملف العميل الذكي')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle(
                        context,
                        fullName,
                        subtitle: 'رقم الهاتف: $phone',
                      ),
                      const SizedBox(height: 8),
                      Text(address, textDirection: TextDirection.rtl),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(
                              customer['analyticsConsent'] is Map &&
                                      (customer['analyticsConsent']['granted'] ==
                                          true)
                                  ? 'وافق على التحليل'
                                  : 'بدون موافقة تحليل',
                            ),
                          ),
                          Chip(
                            label: Text(
                              'أنشئ: ${_fmtDate(customer['createdAt'])}',
                            ),
                          ),
                          Chip(
                            label: Text(
                              'آخر تحديث ملف: ${_fmtDate(customer['profileLastUpdatedAt'])}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle(context, 'مؤشرات الطلبات والإنفاق'),
                      const SizedBox(height: 10),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.15,
                        children: [
                          _metricTile(
                            icon: Icons.shopping_bag_outlined,
                            label: 'إجمالي الطلبات',
                            value: '${_asInt(orderProfile['ordersCount'])}',
                          ),
                          _metricTile(
                            icon: Icons.check_circle_outline,
                            label: 'طلبات مكتملة',
                            value:
                                '${_asInt(orderProfile['deliveredOrdersCount'])}',
                          ),
                          _metricTile(
                            icon: Icons.wallet_outlined,
                            label: 'إجمالي الصرف',
                            value: formatIqd(
                              _asDouble(orderProfile['totalSpent']),
                            ),
                          ),
                          _metricTile(
                            icon: Icons.shopping_cart_outlined,
                            label: 'متوسط السلة',
                            value: formatIqd(
                              _asDouble(orderProfile['avgBasket']),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'آخر طلب: ${_fmtDate(orderProfile['lastOrderAt'])}',
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle(
                        context,
                        'تحليل الاهتمامات',
                        subtitle:
                            'النطاق الأقوى: ${affinity['dominantLabel'] ?? '-'}',
                      ),
                      const SizedBox(height: 10),
                      if (affinityScores.isEmpty)
                        const Text(
                          'لا توجد بيانات كافية',
                          textDirection: TextDirection.rtl,
                        )
                      else
                        ...affinityScores.take(6).map((item) {
                          final label =
                              '${item['label'] ?? item['domain'] ?? '-'}';
                          final score = _asDouble(item['score']).clamp(0, 100);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  textDirection: TextDirection.rtl,
                                  children: [
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text('${score.toStringAsFixed(0)}%'),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    minHeight: 8,
                                    value: score / 100,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle(context, 'سلوك البحث'),
                      const SizedBox(height: 8),
                      Text(
                        'إجمالي أحداث البحث: ${_asInt(searchSignals['totalSearchEvents'])}',
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'أكثر كلمات بحث',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        emptyText: 'لا توجد كلمات بحث',
                        rows: topSearchTerms,
                        titleKey: 'term',
                        valueKey: 'count',
                        valueSuffix: 'مرة',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'مجالات البحث',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        emptyText: 'لا توجد مجالات بحث',
                        rows: topSearchDomains,
                        titleKey: 'domain',
                        valueKey: 'count',
                        valueSuffix: 'مرة',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle(context, 'ملخص الخوارزمية التسويقية'),
                      const SizedBox(height: 8),
                      Text(
                        'مستوى الإنفاق: ${persona['spendingTier'] ?? '-'}',
                        textDirection: TextDirection.rtl,
                      ),
                      Text(
                        'مستوى التفاعل: ${persona['engagementLevel'] ?? '-'}',
                        textDirection: TextDirection.rtl,
                      ),
                      Text(
                        'نمط القرار: ${persona['decisionStyle'] ?? '-'}',
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'اقتراحات الاستهداف',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      ...campaignHints.map(
                        (hint) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '- $hint',
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle(context, 'الأنماط المفضلة'),
                      const SizedBox(height: 8),
                      const Text(
                        'أنواع المتاجر المفضلة',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        emptyText: 'لا توجد بيانات',
                        rows: topMerchantTypes,
                        titleKey: 'type',
                        valueKey: 'ordersCount',
                        valueSuffix: 'طلب',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'أفضل المتاجر للعميل',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        emptyText: 'لا توجد بيانات',
                        rows: topMerchants,
                        titleKey: 'merchantName',
                        valueKey: 'ordersCount',
                        valueSuffix: 'طلب',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'المنتجات الأكثر تكراراً',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        emptyText: 'لا توجد بيانات',
                        rows: topProducts,
                        titleKey: 'productName',
                        valueKey: 'unitsCount',
                        valueSuffix: 'وحدة',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'الفئات الأكثر شراءً',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        emptyText: 'لا توجد بيانات',
                        rows: topOrderCategories,
                        titleKey: 'categoryName',
                        valueKey: 'itemsCount',
                        valueSuffix: 'عنصر',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle(context, 'إشارات السيارات والنشاط'),
                      const SizedBox(height: 8),
                      Text(
                        'عمليات تفضيل سيارات: ${_asInt(carSignals['samplesCount'])}',
                        textDirection: TextDirection.rtl,
                      ),
                      Text(
                        'أيام نشاط خلال 30 يوم: ${_asInt(activityPattern['activeDays30d'])}',
                        textDirection: TextDirection.rtl,
                      ),
                      Text(
                        'أحداث خلال 7 أيام: ${_asInt(activityPattern['events7d'])}',
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'أكثر ماركات السيارات',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        emptyText: 'لا توجد إشارات كافية',
                        rows: topCarBrands,
                        titleKey: 'name',
                        valueKey: 'count',
                        valueSuffix: 'مرة',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'أكثر موديلات السيارات',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        emptyText: 'لا توجد إشارات كافية',
                        rows: topCarModels,
                        titleKey: 'name',
                        valueKey: 'count',
                        valueSuffix: 'مرة',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ساعات الذروة داخل التطبيق',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        emptyText: 'لا توجد بيانات',
                        rows: topHours,
                        titleKey: 'hour',
                        valueKey: 'eventsCount',
                        valueSuffix: 'حدث',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'المفضلة المحفوظة: ${_asInt(favoritesSummary['favoritesCount'])}',
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle(context, 'آخر النشاطات'),
                      const SizedBox(height: 8),
                      if (recentEvents.isEmpty)
                        const Text(
                          'لا توجد أحداث حديثة',
                          textDirection: TextDirection.rtl,
                        )
                      else
                        ...recentEvents.take(20).map((event) {
                          final title =
                              '${event['eventName'] ?? event['event_name'] ?? '-'}';
                          final category = '${event['category'] ?? '-'}';
                          final at = _fmtDate(
                            event['createdAt'] ?? event['created_at'],
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: Colors.white.withValues(alpha: 0.05),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Row(
                                textDirection: TextDirection.rtl,
                                children: [
                                  const Icon(Icons.bolt_rounded, size: 17),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          title,
                                          textDirection: TextDirection.rtl,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'الفئة: $category',
                                          textDirection: TextDirection.rtl,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white.withValues(
                                              alpha: 0.78,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    at,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
