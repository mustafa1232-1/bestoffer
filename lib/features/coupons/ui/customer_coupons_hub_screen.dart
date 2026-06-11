import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/parsers.dart';
import '../../../pages/map_page.dart';
import '../../auth/state/auth_controller.dart';
import '../../customer/ui/customer_discovery_screen.dart';
import '../../taxi/data/taxi_api.dart';
import '../data/coupons_api.dart';

enum CustomerCouponCategory { shopping, taxi }

final _customerCouponTaxiApiProvider = Provider<TaxiApi>(
  (ref) => TaxiApi(ref.read(dioClientProvider).dio),
);

class CustomerCouponsHubScreen extends StatelessWidget {
  const CustomerCouponsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'الكوبونات', en: 'Coupons')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.lt(
              ar: 'اختر نوع الكوبونات التي تريد تصفحها',
              en: 'Choose which coupons you want to browse',
            ),
            textDirection: context.appTextDirection,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          _CategoryEntryCard(
            title: context.lt(ar: 'كوبونات التسوق', en: 'Shopping coupons'),
            subtitle: context.lt(
              ar: 'كوبونات التطبيق وكوبونات المتاجر الصالحة للتسوق',
              en: 'App and store coupons for shopping',
            ),
            icon: Icons.storefront_rounded,
            gradient: const LinearGradient(
              colors: [Color(0xFF3964E8), Color(0xFF4BB0FF)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomerCouponListScreen(
                    category: CustomerCouponCategory.shopping,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _CategoryEntryCard(
            title: context.lt(ar: 'كوبونات التكسي', en: 'Taxi coupons'),
            subtitle: context.lt(
              ar: 'كوبونات الرحلات المفعّلة على حسابك',
              en: 'Ride coupons currently active for your account',
            ),
            icon: Icons.local_taxi_rounded,
            gradient: const LinearGradient(
              colors: [Color(0xFF5A4BE4), Color(0xFF3AD5D9)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomerCouponListScreen(
                    category: CustomerCouponCategory.taxi,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class CustomerCouponListScreen extends ConsumerStatefulWidget {
  final CustomerCouponCategory category;

  const CustomerCouponListScreen({super.key, required this.category});

  @override
  ConsumerState<CustomerCouponListScreen> createState() =>
      _CustomerCouponListScreenState();
}

class _CustomerCouponListScreenState
    extends ConsumerState<CustomerCouponListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

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
      final items = widget.category == CustomerCouponCategory.shopping
          ? await ref.read(couponsApiProvider).listMyCoupons(limit: 100)
          : await ref.read(_customerCouponTaxiApiProvider).listMyCoupons();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) => context.lt(
            ar: 'تعذر تحميل الكوبونات حالياً.',
            en: 'Unable to load coupons right now.',
          ),
        );
      });
    }
  }

  String get _title => widget.category == CustomerCouponCategory.shopping
      ? context.lt(ar: 'كوبونات التسوق', en: 'Shopping coupons')
      : context.lt(ar: 'كوبونات التكسي', en: 'Taxi coupons');

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  textDirection: context.appTextDirection,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.l10n.commonRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  widget.category == CustomerCouponCategory.shopping
                      ? context.lt(
                          ar: 'لا توجد كوبونات تسوق فعالة حالياً.',
                          en: 'No active shopping coupons right now.',
                        )
                      : context.l10n.taxiMyCouponsEmpty,
                  textAlign: TextAlign.center,
                  textDirection: context.appTextDirection,
                ),
              ),
            for (final item in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CouponListCard(
                  category: widget.category,
                  item: item,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CustomerCouponDetailsScreen(
                          category: widget.category,
                          item: item,
                        ),
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

class CustomerCouponDetailsScreen extends StatelessWidget {
  final CustomerCouponCategory category;
  final Map<String, dynamic> item;

  const CustomerCouponDetailsScreen({
    super.key,
    required this.category,
    required this.item,
  });

  String _code() => parseString(item['code'], fallback: '-').trim();

  String _title(BuildContext context) {
    if (category == CustomerCouponCategory.taxi) {
      final title = parseString(item['title'], fallback: '').trim();
      if (title.isNotEmpty) return title;
    }
    final code = _code();
    if (code != '-') return code;
    final id = parseInt(item['id']);
    return context.lt(ar: 'كوبون #$id', en: 'Coupon #$id');
  }

  String _description(BuildContext context) {
    final raw = parseString(item['description'], fallback: '').trim();
    if (raw.isNotEmpty) return raw;
    return context.lt(
      ar: 'يمكنك استخدام هذا الكوبون وفق الشروط الموضحة أدناه.',
      en: 'You can use this coupon according to the conditions below.',
    );
  }

  String _discountText(BuildContext context) {
    if (category == CustomerCouponCategory.taxi) {
      final discountType = parseString(item['nextDiscountType'], fallback: '');
      final value = tryParseLocalizedDouble(item['nextDiscountValue']) ?? 0;
      if (discountType == 'percent') {
        return context.lt(ar: 'خصم $value%', en: '$value% discount');
      }
      if (discountType == 'amount') {
        return context.lt(
          ar: 'خصم ${formatIqd(value)}',
          en: 'Discount ${formatIqd(value)}',
        );
      }
      return context.lt(ar: 'حسب شروط الكوبون', en: 'Depends on coupon rules');
    }

    final discountType = parseString(item['discountType'], fallback: '');
    final value = tryParseLocalizedDouble(item['discountValue']) ?? 0;
    if (discountType == 'percent') {
      return context.lt(ar: 'خصم $value%', en: '$value% discount');
    }
    return context.lt(
      ar: 'خصم ${formatIqd(value)}',
      en: 'Discount ${formatIqd(value)}',
    );
  }

  String _scopeText(BuildContext context) {
    if (category == CustomerCouponCategory.taxi) {
      final applyWholeApp = item['applyWholeApp'] == true;
      return applyWholeApp
          ? context.lt(
              ar: 'يُستخدم داخل خدمة التكسي على مستوى التطبيق.',
              en: 'Usable in taxi service across the app.',
            )
          : context.lt(
              ar: 'يُستخدم داخل خدمة التكسي حسب استهداف حسابك.',
              en: 'Usable in taxi service based on your account targeting.',
            );
    }

    final scopeKind = parseString(item['scopeKind'], fallback: 'global');
    if (scopeKind == 'merchant') {
      final merchantName = parseString(item['merchantName'], fallback: '-');
      return context.lt(
        ar: 'صالح في متجر: $merchantName',
        en: 'Valid in store: $merchantName',
      );
    }
    if (scopeKind == 'company') {
      final companyName = parseString(item['companyName'], fallback: '-');
      final allBranches = item['companyAppliesToAllBranches'] == true;
      return allBranches
          ? context.lt(
              ar: 'صالح في كل فروع: $companyName',
              en: 'Valid in all branches of: $companyName',
            )
          : context.lt(
              ar: 'صالح في فروع محددة من: $companyName',
              en: 'Valid in selected branches of: $companyName',
            );
    }
    return context.lt(
      ar: 'كوبون عام على التطبيق (التسوق).',
      en: 'Global shopping coupon in the app.',
    );
  }

  List<Map<String, dynamic>> _targetMerchants() {
    final raw = item['targetMerchants'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  String? _validUntilText() {
    final raw = parseString(item['validUntil'], fallback: '').trim();
    if (raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> _copyCode(BuildContext context) async {
    final code = _code();
    if (code.isEmpty || code == '-') return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.lt(ar: 'تم نسخ رمز الكوبون', en: 'Coupon code copied'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = _code();
    final targets = _targetMerchants();
    final validUntil = _validUntilText();
    final remainingUses = parseNullableInt(
      category == CustomerCouponCategory.shopping
          ? item['remainingUsesTotal']
          : item['remainingUses'],
    );
    final minOrder = tryParseLocalizedDouble(item['minOrderTotal']);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'تفاصيل الكوبون', en: 'Coupon details')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.09),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _title(context),
                  textDirection: context.appTextDirection,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  code,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _description(context),
                  textDirection: context.appTextDirection,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    _InfoChip(
                      icon: Icons.percent_rounded,
                      label: _discountText(context),
                    ),
                    if (remainingUses != null)
                      _InfoChip(
                        icon: Icons.repeat_rounded,
                        label: context.lt(
                          ar: 'الاستخدامات المتبقية: $remainingUses',
                          en: 'Remaining uses: $remainingUses',
                        ),
                      ),
                    if (validUntil != null)
                      _InfoChip(
                        icon: Icons.event_available_rounded,
                        label: context.lt(
                          ar: 'ينتهي: $validUntil',
                          en: 'Expires: $validUntil',
                        ),
                      ),
                    if (category == CustomerCouponCategory.shopping &&
                        minOrder != null &&
                        minOrder > 0)
                      _InfoChip(
                        icon: Icons.shopping_cart_checkout_rounded,
                        label: context.lt(
                          ar: 'الحد الأدنى: ${formatIqd(minOrder)}',
                          en: 'Min order: ${formatIqd(minOrder)}',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.lt(ar: 'أين يمكن استخدامه؟', en: 'Where can I use it?'),
            textDirection: context.appTextDirection,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _scopeText(context),
                    textDirection: context.appTextDirection,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (targets.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      context.lt(ar: 'المتاجر المستهدفة', en: 'Target stores'),
                      textDirection: context.appTextDirection,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final target in targets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            const Icon(
                              Icons.store_mall_directory_outlined,
                              size: 16,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                parseString(target['name'], fallback: '-'),
                                textDirection: context.appTextDirection,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _copyCode(context),
            icon: const Icon(Icons.copy_rounded),
            label: Text(
              context.lt(ar: 'نسخ رمز الكوبون', en: 'Copy coupon code'),
            ),
          ),
          const SizedBox(height: 8),
          if (category == CustomerCouponCategory.taxi)
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MapPage(initialCouponCode: code),
                  ),
                );
              },
              icon: const Icon(Icons.local_taxi_rounded),
              label: Text(
                context.lt(ar: 'استخدامه في رحلة تكسي', en: 'Use in taxi ride'),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomerDiscoveryScreen(
                      mode: CustomerDiscoveryMode.shoppingOnly,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.storefront_rounded),
              label: Text(
                context.lt(ar: 'الذهاب إلى التسوق', en: 'Go to shopping'),
              ),
            ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _CategoryEntryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _CategoryEntryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: gradient,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withValues(alpha: 0.18),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withValues(alpha: 0.9),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _CouponListCard extends StatelessWidget {
  final CustomerCouponCategory category;
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _CouponListCard({
    required this.category,
    required this.item,
    required this.onTap,
  });

  String _code() => parseString(item['code'], fallback: '-');

  String _title(BuildContext context) {
    if (category == CustomerCouponCategory.taxi) {
      final title = parseString(item['title'], fallback: '').trim();
      if (title.isNotEmpty) return title;
    }
    return _code();
  }

  String _subtitle(BuildContext context) {
    if (category == CustomerCouponCategory.taxi) {
      final remaining = parseInt(item['remainingUses']);
      return context.lt(
        ar: 'متاح للتكسي • المتبقي: $remaining',
        en: 'Taxi coupon • Remaining: $remaining',
      );
    }
    final discountType = parseString(item['discountType'], fallback: '');
    final discountValue = tryParseLocalizedDouble(item['discountValue']) ?? 0;
    final scopeKind = parseString(item['scopeKind'], fallback: 'global');

    final discount = discountType == 'percent'
        ? context.lt(ar: 'خصم $discountValue%', en: '$discountValue% discount')
        : context.lt(
            ar: 'خصم ${formatIqd(discountValue)}',
            en: 'Discount ${formatIqd(discountValue)}',
          );
    final scope = switch (scopeKind) {
      'merchant' => context.lt(
        ar: 'متجر: ${parseString(item['merchantName'], fallback: '-')}',
        en: 'Store: ${parseString(item['merchantName'], fallback: '-')}',
      ),
      'company' => context.lt(
        ar: 'شركة: ${parseString(item['companyName'], fallback: '-')}',
        en: 'Company: ${parseString(item['companyName'], fallback: '-')}',
      ),
      _ => context.lt(ar: 'عام', en: 'Global'),
    };
    return '$discount • $scope';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          category == CustomerCouponCategory.shopping
              ? Icons.storefront_rounded
              : Icons.local_taxi_rounded,
        ),
        title: Text(
          _title(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: context.appTextDirection,
        ),
        subtitle: Text(
          _subtitle(context),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textDirection: context.appTextDirection,
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            textDirection: context.appTextDirection,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
