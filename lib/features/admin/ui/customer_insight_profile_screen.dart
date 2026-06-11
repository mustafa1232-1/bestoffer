import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';

class CustomerInsightProfileScreen extends StatelessWidget {
  final Map<String, dynamic> details;

  const CustomerInsightProfileScreen({super.key, required this.details});

  String _t(BuildContext context, String ar, String en) =>
      context.localizedText(ar: ar, en: en);

  TextDirection _dir(BuildContext context) => context.appTextDirection;

  CrossAxisAlignment _textCrossAxis(BuildContext context) =>
      context.isEnglishLocale
      ? CrossAxisAlignment.start
      : CrossAxisAlignment.end;

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
      crossAxisAlignment: _textCrossAxis(context),
      children: [
        Text(
          title,
          textDirection: _dir(context),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            textDirection: _dir(context),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metricTile(
    BuildContext context, {
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
        textDirection: _dir(context),
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: _textCrossAxis(context),
              children: [
                Text(
                  label,
                  textDirection: _dir(context),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  textDirection: _dir(context),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopRows(
    BuildContext context, {
    required String emptyText,
    required List<Map<String, dynamic>> rows,
    required String titleKey,
    required String valueKey,
    String? valueSuffix,
  }) {
    if (rows.isEmpty) {
      return Text(emptyText, textDirection: _dir(context));
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
            textDirection: _dir(context),
            children: [
              Expanded(
                child: Text(
                  title,
                  textDirection: _dir(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                valueSuffix == null
                    ? displayValue
                    : '$displayValue $valueSuffix',
                textDirection: _dir(context),
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
    final socialInsights = _asMap(behaviorProfile['socialInsights']);
    final socialSummary = _asMap(socialInsights['summary']);
    final socialEngagement = _asMap(socialInsights['engagement']);
    final socialKeywords = _asMap(socialInsights['keywords']);

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
    final socialTopKeywords = _asList(socialKeywords['topKeywords']);
    final socialTopTopics = _asList(socialKeywords['topTopics']);
    final socialReviewedMerchants = _asList(
      socialInsights['reviewedMerchants'],
    );
    final consentNotice = '${customer['consentNotice'] ?? ''}'.trim();

    final fullName = '${customer['fullName'] ?? '-'}';
    final phone = '${customer['phone'] ?? '-'}';
    final address = _t(
      context,
      'بلك ${customer['block'] ?? '-'} - عمارة ${customer['buildingNumber'] ?? '-'} - شقة ${customer['apartment'] ?? '-'}',
      'Block ${customer['block'] ?? '-'} - Building ${customer['buildingNumber'] ?? '-'} - Apt ${customer['apartment'] ?? '-'}',
    );

    return Directionality(
      textDirection: _dir(context),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _t(context, 'ملف العميل الذكي', 'Smart Customer Profile'),
          ),
        ),
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
                        subtitle: _t(
                          context,
                          'رقم الهاتف: $phone',
                          'Phone: $phone',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(address, textDirection: _dir(context)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: context.isEnglishLocale
                            ? WrapAlignment.start
                            : WrapAlignment.end,
                        children: [
                          Chip(
                            label: Text(
                              customer['analyticsConsent'] is Map &&
                                      (customer['analyticsConsent']['granted'] ==
                                          true)
                                  ? _t(
                                      context,
                                      'وافق على التحليل',
                                      'Analytics consent granted',
                                    )
                                  : _t(
                                      context,
                                      'بدون موافقة تحليل',
                                      'No analytics consent',
                                    ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              _t(
                                context,
                                'أُنشئ: ${_fmtDate(customer['createdAt'])}',
                                'Created: ${_fmtDate(customer['createdAt'])}',
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              _t(
                                context,
                                'آخر تحديث ملف: ${_fmtDate(customer['profileLastUpdatedAt'])}',
                                'Profile updated: ${_fmtDate(customer['profileLastUpdatedAt'])}',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (consentNotice.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          consentNotice,
                          textDirection: _dir(context),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
                        'تحليل السوشال (منشورات وستوريات)',
                        subtitle: 'يفعّل فقط بعد موافقة المستخدم على التحليلات',
                      ),
                      const SizedBox(height: 10),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.2,
                        children: [
                          _metricTile(
                            context,
                            icon: Icons.article_outlined,
                            label: _t(
                              context,
                              'إجمالي المنشورات',
                              'Total posts',
                            ),
                            value: '${_asInt(socialSummary['postsCount'])}',
                          ),
                          _metricTile(
                            context,
                            icon: Icons.auto_stories_outlined,
                            label: _t(
                              context,
                              'إجمالي الستوريات',
                              'Total stories',
                            ),
                            value: '${_asInt(socialSummary['storiesCount'])}',
                          ),
                          _metricTile(
                            context,
                            icon: Icons.history_rounded,
                            label: _t(
                              context,
                              'ستوريات مؤرشفة',
                              'Archived stories',
                            ),
                            value:
                                '${_asInt(socialSummary['archivedStoriesCount'])}',
                          ),
                          _metricTile(
                            context,
                            icon: Icons.favorite_outline_rounded,
                            label: _t(
                              context,
                              'إعجابات مستلمة',
                              'Likes received',
                            ),
                            value:
                                '${_asInt(socialEngagement['likesReceived'])}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'تعليقات مستلمة: ${_asInt(socialEngagement['commentsReceived'])} | تعليقات كتبها: ${_asInt(socialEngagement['commentsWritten'])}',
                          'Comments received: ${_asInt(socialEngagement['commentsReceived'])} | Comments written: ${_asInt(socialEngagement['commentsWritten'])}',
                        ),
                        textDirection: _dir(context),
                      ),
                      Text(
                        _t(
                          context,
                          'آخر منشور: ${_fmtDate(socialSummary['lastPostAt'])} | آخر ستوري: ${_fmtDate(socialSummary['lastStoryAt'])}',
                          'Last post: ${_fmtDate(socialSummary['lastPostAt'])} | Last story: ${_fmtDate(socialSummary['lastStoryAt'])}',
                        ),
                        textDirection: _dir(context),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'أكثر الكلمات استخدامًا',
                          'Top used keywords',
                        ),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(
                          context,
                          'لا توجد كلمات كافية',
                          'Not enough keywords yet',
                        ),
                        rows: socialTopKeywords,
                        titleKey: 'keyword',
                        valueKey: 'count',
                        valueSuffix: context.isEnglishLocale ? 'times' : 'مرة',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'أكثر المواضيع التي ينشر عنها',
                          'Top topics',
                        ),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(
                          context,
                          'لا توجد مواضيع واضحة',
                          'No clear topics yet',
                        ),
                        rows: socialTopTopics,
                        titleKey: 'topic',
                        valueKey: 'count',
                        valueSuffix: context.isEnglishLocale
                            ? 'posts'
                            : 'منشور',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'متاجر راجعها عبر المنشورات',
                          'Reviewed merchants',
                        ),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(
                          context,
                          'لا توجد مراجعات منشورة',
                          'No published reviews yet',
                        ),
                        rows: socialReviewedMerchants,
                        titleKey: 'merchantName',
                        valueKey: 'reviewsCount',
                        valueSuffix: context.isEnglishLocale
                            ? 'reviews'
                            : 'مراجعة',
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
                        _t(
                          context,
                          'مؤشرات الطلبات والإنفاق',
                          'Orders and Spending',
                        ),
                      ),
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
                            context,
                            icon: Icons.shopping_bag_outlined,
                            label: _t(
                              context,
                              'إجمالي الطلبات',
                              'Total orders',
                            ),
                            value: '${_asInt(orderProfile['ordersCount'])}',
                          ),
                          _metricTile(
                            context,
                            icon: Icons.check_circle_outline,
                            label: _t(
                              context,
                              'طلبات مكتملة',
                              'Delivered orders',
                            ),
                            value:
                                '${_asInt(orderProfile['deliveredOrdersCount'])}',
                          ),
                          _metricTile(
                            context,
                            icon: Icons.wallet_outlined,
                            label: _t(context, 'إجمالي الصرف', 'Total spent'),
                            value: formatIqd(
                              _asDouble(orderProfile['totalSpent']),
                            ),
                          ),
                          _metricTile(
                            context,
                            icon: Icons.shopping_cart_outlined,
                            label: _t(context, 'متوسط السلة', 'Average basket'),
                            value: formatIqd(
                              _asDouble(orderProfile['avgBasket']),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'آخر طلب: ${_fmtDate(orderProfile['lastOrderAt'])}',
                          'Last order: ${_fmtDate(orderProfile['lastOrderAt'])}',
                        ),
                        textDirection: _dir(context),
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
                        Text(
                          _t(
                            context,
                            'لا توجد بيانات كافية',
                            'Not enough data',
                          ),
                          textDirection: _dir(context),
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
                                  textDirection: _dir(context),
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
                      _sectionTitle(
                        context,
                        _t(context, 'سلوك البحث', 'Search Behavior'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'إجمالي أحداث البحث: ${_asInt(searchSignals['totalSearchEvents'])}',
                          'Total search events: ${_asInt(searchSignals['totalSearchEvents'])}',
                        ),
                        textDirection: _dir(context),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(context, 'أكثر كلمات البحث', 'Top search terms'),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(
                          context,
                          'لا توجد كلمات بحث',
                          'No search terms yet',
                        ),
                        rows: topSearchTerms,
                        titleKey: 'term',
                        valueKey: 'count',
                        valueSuffix: context.isEnglishLocale ? 'times' : 'مرة',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(context, 'مجالات البحث', 'Search domains'),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(
                          context,
                          'لا توجد مجالات بحث',
                          'No search domains yet',
                        ),
                        rows: topSearchDomains,
                        titleKey: 'domain',
                        valueKey: 'count',
                        valueSuffix: context.isEnglishLocale ? 'times' : 'مرة',
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
                        _t(
                          context,
                          'ملخص الخوارزمية التسويقية',
                          'Marketing Persona Summary',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'مستوى الإنفاق: ${persona['spendingTier'] ?? '-'}',
                          'Spending tier: ${persona['spendingTier'] ?? '-'}',
                        ),
                        textDirection: _dir(context),
                      ),
                      Text(
                        _t(
                          context,
                          'مستوى التفاعل: ${persona['engagementLevel'] ?? '-'}',
                          'Engagement level: ${persona['engagementLevel'] ?? '-'}',
                        ),
                        textDirection: _dir(context),
                      ),
                      Text(
                        _t(
                          context,
                          'نمط القرار: ${persona['decisionStyle'] ?? '-'}',
                          'Decision style: ${persona['decisionStyle'] ?? '-'}',
                        ),
                        textDirection: _dir(context),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(context, 'اقتراحات الاستهداف', 'Campaign hints'),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      ...campaignHints.map(
                        (hint) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('- $hint', textDirection: _dir(context)),
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
                      _sectionTitle(
                        context,
                        _t(context, 'الأنماط المفضلة', 'Favorite Patterns'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'أنواع المتاجر المفضلة',
                          'Preferred merchant types',
                        ),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(context, 'لا توجد بيانات', 'No data yet'),
                        rows: topMerchantTypes,
                        titleKey: 'type',
                        valueKey: 'ordersCount',
                        valueSuffix: context.isEnglishLocale ? 'orders' : 'طلب',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(context, 'أفضل المتاجر للعميل', 'Top merchants'),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(context, 'لا توجد بيانات', 'No data yet'),
                        rows: topMerchants,
                        titleKey: 'merchantName',
                        valueKey: 'ordersCount',
                        valueSuffix: context.isEnglishLocale ? 'orders' : 'طلب',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'المنتجات الأكثر تكراراً',
                          'Most repeated products',
                        ),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(context, 'لا توجد بيانات', 'No data yet'),
                        rows: topProducts,
                        titleKey: 'productName',
                        valueKey: 'unitsCount',
                        valueSuffix: context.isEnglishLocale ? 'units' : 'وحدة',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'الفئات الأكثر شراءً',
                          'Top order categories',
                        ),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(context, 'لا توجد بيانات', 'No data yet'),
                        rows: topOrderCategories,
                        titleKey: 'categoryName',
                        valueKey: 'itemsCount',
                        valueSuffix: context.isEnglishLocale ? 'items' : 'عنصر',
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
                        _t(
                          context,
                          'إشارات السيارات والنشاط',
                          'Cars and Activity Signals',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'عمليات تفضيل سيارات: ${_asInt(carSignals['samplesCount'])}',
                          'Car preference samples: ${_asInt(carSignals['samplesCount'])}',
                        ),
                        textDirection: _dir(context),
                      ),
                      Text(
                        _t(
                          context,
                          'أيام نشاط خلال 30 يوم: ${_asInt(activityPattern['activeDays30d'])}',
                          'Active days in 30d: ${_asInt(activityPattern['activeDays30d'])}',
                        ),
                        textDirection: _dir(context),
                      ),
                      Text(
                        _t(
                          context,
                          'أحداث خلال 7 أيام: ${_asInt(activityPattern['events7d'])}',
                          'Events in 7d: ${_asInt(activityPattern['events7d'])}',
                        ),
                        textDirection: _dir(context),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(context, 'أكثر ماركات السيارات', 'Top car brands'),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(
                          context,
                          'لا توجد إشارات كافية',
                          'Not enough signals yet',
                        ),
                        rows: topCarBrands,
                        titleKey: 'name',
                        valueKey: 'count',
                        valueSuffix: context.isEnglishLocale ? 'times' : 'مرة',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(context, 'أكثر موديلات السيارات', 'Top car models'),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(
                          context,
                          'لا توجد إشارات كافية',
                          'Not enough signals yet',
                        ),
                        rows: topCarModels,
                        titleKey: 'name',
                        valueKey: 'count',
                        valueSuffix: context.isEnglishLocale ? 'times' : 'مرة',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'ساعات الذروة داخل التطبيق',
                          'Top in-app hours',
                        ),
                        textDirection: _dir(context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _buildTopRows(
                        context,
                        emptyText: _t(context, 'لا توجد بيانات', 'No data yet'),
                        rows: topHours,
                        titleKey: 'hour',
                        valueKey: 'eventsCount',
                        valueSuffix: context.isEnglishLocale ? 'events' : 'حدث',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          context,
                          'المفضلة المحفوظة: ${_asInt(favoritesSummary['favoritesCount'])}',
                          'Saved favorites: ${_asInt(favoritesSummary['favoritesCount'])}',
                        ),
                        textDirection: _dir(context),
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
                        _t(context, 'آخر النشاطات', 'Recent Events'),
                      ),
                      const SizedBox(height: 8),
                      if (recentEvents.isEmpty)
                        Text(
                          _t(
                            context,
                            'لا توجد أحداث حديثة',
                            'No recent events',
                          ),
                          textDirection: _dir(context),
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
                                textDirection: _dir(context),
                                children: [
                                  const Icon(Icons.bolt_rounded, size: 17),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: _textCrossAxis(
                                        context,
                                      ),
                                      children: [
                                        Text(
                                          title,
                                          textDirection: _dir(context),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _t(
                                            context,
                                            'الفئة: $category',
                                            'Category: $category',
                                          ),
                                          textDirection: _dir(context),
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
