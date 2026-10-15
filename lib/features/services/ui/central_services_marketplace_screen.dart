import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/cached_app_image.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../auth/presentation/login_screen.dart';
import '../../auth/state/auth_controller.dart';
import '../data/services_api.dart';
import '../domain/service_category_matcher.dart';
import '../models/service_models.dart';
import 'central_service_request_screen.dart';
import 'service_my_requests_screen.dart';
import 'service_offering_details_screen.dart';

class CentralServicesMarketplaceScreen extends ConsumerStatefulWidget {
  const CentralServicesMarketplaceScreen({super.key});

  @override
  ConsumerState<CentralServicesMarketplaceScreen> createState() =>
      _CentralServicesMarketplaceScreenState();
}

class _CentralServicesMarketplaceScreenState
    extends ConsumerState<CentralServicesMarketplaceScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  List<CentralServiceCatalogItem> _items = const [];
  List<ServiceOfferingModel> _offerings = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _refreshPublishedOfferings() async {
    try {
      final rows = await ref
          .read(servicesApiProvider)
          .searchPublicOfferings(limit: 100, sort: 'newest');
      if (!mounted) return;
      setState(() {
        _offerings = rows.map(ServiceOfferingModel.fromJson).toList();
      });
    } catch (_) {
      // Keep the last successful list so category navigation still works offline.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    var catalog = _fallbackCatalog;
    var offerings = const <ServiceOfferingModel>[];
    final failures = <String>[];
    try {
      final rows = await ref.read(servicesApiProvider).listCentralCatalog();
      catalog = rows.map(CentralServiceCatalogItem.fromJson).toList();
    } catch (_) {
      failures.add('قائمة الأقسام');
    }
    try {
      final rows = await ref
          .read(servicesApiProvider)
          .searchPublicOfferings(limit: 100, sort: 'newest');
      offerings = rows.map(ServiceOfferingModel.fromJson).toList();
    } catch (_) {
      failures.add('الخدمات المنشورة');
    }
    if (!mounted) return;
    setState(() {
      _items = catalog;
      _offerings = offerings;
      _loading = false;
      _error = failures.isEmpty
          ? null
          : 'تعذر تحديث ${failures.join(' و')} الآن. اسحب للأسفل للمحاولة مجدداً.';
    });
  }

  Future<void> _open(CentralServiceCatalogItem item) async {
    await _refreshPublishedOfferings();
    if (!mounted) return;
    if (_offerings.any(
      (offering) => offeringBelongsToCategory(item, offering),
    )) {
      await _openCategory(item);
      return;
    }
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed || auth.isGuest) {
      final login = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'سجّل الدخول لإرسال الطلب',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'نحتاج حسابك لنتابع الطلب معك ونرسل لك تحديثات تعيين المختص.',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.login_rounded),
                label: const Text('تسجيل الدخول'),
              ),
            ],
          ),
        ),
      );
      if (login == true && mounted) {
        final loggedIn = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => const LoginScreen(popOnSuccess: true),
          ),
        );
        if (!mounted) return;
        final authAfterLogin = ref.read(authControllerProvider);
        if (loggedIn == true &&
            authAfterLogin.isAuthed &&
            !authAfterLogin.isGuest) {
          await _openCategory(item);
        }
      }
      return;
    }
    await _openCategory(item);
  }

  Future<void> _openCategory(CentralServiceCatalogItem item) async {
    final categoryOfferings = _offerings
        .where((offering) => offeringBelongsToCategory(item, offering))
        .toList(growable: false);
    if (categoryOfferings.isEmpty) {
      await _openRequest(item);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CentralCategoryServicesScreen(
          category: item,
          offerings: categoryOfferings,
          onCustomRequest: () => _openRequest(item),
        ),
      ),
    );
  }

  Future<void> _openRequest(CentralServiceCatalogItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CentralServiceRequestScreen(service: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.services, displayName: 'الخدمات');
    if (section.isBlocked && !section.allowExistingActiveAccess) {
      return SectionUnavailableScreen(entry: section);
    }

    final query = _searchController.text.trim().toLowerCase();
    final visible = _items.where((item) {
      if (query.isEmpty) return true;
      return '${item.title} ${item.subtitle} ${item.quickIssues.join(' ')}'
          .toLowerCase()
          .contains(query);
    }).toList();
    final visibleOfferings = _offerings
        .where((offering) {
          if (query.isEmpty) return true;
          return '${offering.name} ${offering.description ?? ''} '
                  '${offering.mainCategoryName ?? ''} ${offering.subcategoryName ?? ''}'
              .toLowerCase()
              .contains(query);
        })
        .toList(growable: false);
    final regular = visible.where((item) => !item.emergency).toList();
    final emergencyItems = visible.where((item) => item.emergency).toList();
    final emergency = emergencyItems.isEmpty ? null : emergencyItems.first;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('خدمات مسلكي', style: TextStyle(fontWeight: FontWeight.w900)),
            Text(
              'طلب واحد، ونحن نوجّه المختص المناسب',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'طلباتي',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ServiceMyRequestsScreen(),
              ),
            ),
            icon: const Icon(Icons.receipt_long_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            _ServicesIntro(
              onEmergency: emergency == null ? null : () => _open(emergency),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              textDirection: TextDirection.rtl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ما الخدمة التي تحتاجها؟',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: Text(
                    'اختر نوع المساعدة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (_loading)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_loading && visible.isEmpty)
              const _EmptySearch()
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 650;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: regular.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: wide ? 3 : 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: wide ? 1.32 : 0.95,
                    ),
                    itemBuilder: (context, index) =>
                        TweenAnimationBuilder<double>(
                          duration: Duration(milliseconds: 260 + (index * 45)),
                          tween: Tween(begin: 0, end: 1),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) =>
                              Transform.translate(
                                offset: Offset(0, 12 * (1 - value)),
                                child: Opacity(opacity: value, child: child),
                              ),
                          child: _ServiceCard(
                            item: regular[index],
                            onTap: () => _open(regular[index]),
                          ),
                        ),
                  );
                },
              ),
            if (emergency != null) ...[
              const SizedBox(height: 14),
              _EmergencyStrip(item: emergency, onTap: () => _open(emergency)),
            ],
            if (visibleOfferings.isNotEmpty) ...[
              const SizedBox(height: 22),
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: Text(
                      query.isEmpty
                          ? 'خدمات متاحة للحجز'
                          : 'نتائج الخدمات المنشورة',
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${visibleOfferings.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...visibleOfferings.map(
                (offering) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PublishedOfferingCard(
                    offering: offering,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ServiceOfferingDetailsScreen(
                          offeringId: offering.id,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const _HowItWorks(),
          ],
        ),
      ),
    );
  }
}

class _ServicesIntro extends StatelessWidget {
  const _ServicesIntro({required this.onEmergency});

  final VoidCallback? onEmergency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF244F3D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'صف مشكلتك، والباقي علينا',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'فريق مسلكي يراجع طلبك ويوجّهه إلى المختص المناسب ويتابع التنفيذ معك.',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.88)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          IconButton.filledTonal(
            tooltip: 'مساعدة عاجلة',
            onPressed: onEmergency,
            style: IconButton.styleFrom(
              backgroundColor: scheme.errorContainer,
              foregroundColor: scheme.onErrorContainer,
            ),
            icon: const Icon(Icons.sos_rounded),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.item, required this.onTap});

  final CentralServiceCatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _hexColor(item.color);
    return Card(
      margin: EdgeInsets.zero,
      color: Color.alphaBlend(color.withValues(alpha: 0.12), Colors.white),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_icon(item.icon), color: Colors.white),
                ),
              ),
              const Spacer(),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                item.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.76),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyStrip extends StatelessWidget {
  const _EmergencyStrip({required this.item, required this.onTap});

  final CentralServiceCatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              CircleAvatar(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
                child: const Icon(Icons.sos_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.title,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      item.subtitle,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'كيف يعمل الطلب؟',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        const Row(
          textDirection: TextDirection.rtl,
          children: [
            Expanded(
              child: _Step(icon: Icons.edit_note_rounded, text: 'صف احتياجك'),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _Step(icon: Icons.route_rounded, text: 'نعيّن المختص'),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _Step(
                icon: Icons.notifications_active_outlined,
                text: 'تابع التنفيذ',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 5),
        Text(
          text,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        ),
      ],
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 42),
          SizedBox(height: 8),
          Text('لم نجد خدمة بهذا الاسم', textDirection: TextDirection.rtl),
        ],
      ),
    );
  }
}

class _CentralCategoryServicesScreen extends StatelessWidget {
  const _CentralCategoryServicesScreen({
    required this.category,
    required this.offerings,
    required this.onCustomRequest,
  });

  final CentralServiceCatalogItem category;
  final List<ServiceOfferingModel> offerings;
  final Future<void> Function() onCustomRequest;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Text(
            'اختر الخدمة المناسبة',
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            'اطلع على الصور والتفاصيل والسعر، ثم أكمل الحجز بخطوات قصيرة.',
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          ...offerings.map(
            (offering) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PublishedOfferingCard(
                offering: offering,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ServiceOfferingDetailsScreen(offeringId: offering.id),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: onCustomRequest,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('لم تجد خدمتك؟ أرسل طلباً مخصصاً'),
          ),
        ],
      ),
    );
  }
}

class _PublishedOfferingCard extends StatelessWidget {
  const _PublishedOfferingCard({required this.offering, required this.onTap});

  final ServiceOfferingModel offering;
  final VoidCallback onTap;

  String? get _coverUrl {
    for (final media in offering.media) {
      if (media.mediaKind.toLowerCase() != 'video' &&
          media.mediaUrl.trim().isNotEmpty) {
        return media.mediaUrl;
      }
    }
    return offering.provider.logoUrl;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverUrl = _coverUrl;
    final description = (offering.description ?? '').trim();
    final basePrice = offering.baseUnitPrice;
    final discountedPrice = offering.discountedUnitPrice;
    final unit = offering.pricingOptions.isEmpty
        ? ''
        : offering.pricingOptions
              .firstWhere(
                (item) => item.isDefault,
                orElse: () => offering.pricingOptions.first,
              )
              .unitDisplayText();
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 150,
          child: Row(
            textDirection: TextDirection.rtl,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 118,
                child: coverUrl == null || coverUrl.trim().isEmpty
                    ? ColoredBox(
                        color: scheme.primaryContainer,
                        child: Icon(
                          Icons.design_services_outlined,
                          color: scheme.primary,
                          size: 36,
                        ),
                      )
                    : CachedAppImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => ColoredBox(
                          color: scheme.primaryContainer,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: scheme.primary,
                          ),
                        ),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Expanded(
                            child: Text(
                              offering.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          if (offering.hasActivePromotion) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.local_offer_rounded,
                              color: scheme.tertiary,
                              size: 20,
                            ),
                          ],
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const Spacer(),
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Expanded(
                            child: discountedPrice == null || basePrice == null
                                ? Text(
                                    offering.displayPriceText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${_formatServiceMoney(basePrice)} د.ع',
                                        textDirection: TextDirection.rtl,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              decoration:
                                                  TextDecoration.lineThrough,
                                            ),
                                      ),
                                      Text(
                                        '${_formatServiceMoney(discountedPrice)} د.ع${unit.isEmpty ? '' : ' $unit'}',
                                        textDirection: TextDirection.rtl,
                                        style: TextStyle(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const Icon(Icons.chevron_left_rounded, size: 20),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatServiceMoney(double value) {
  final digits = value.round().toString();
  return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

Color _hexColor(String value) {
  final normalized = value.replaceAll('#', '').trim();
  final parsed = int.tryParse(normalized, radix: 16);
  return parsed == null ? const Color(0xFF2F684F) : Color(0xFF000000 | parsed);
}

IconData _icon(String key) => switch (key) {
  'balance' => Icons.balance_rounded,
  'medical_services' => Icons.medical_services_rounded,
  'home_repair_service' => Icons.home_repair_service_rounded,
  'car_repair' => Icons.car_repair_rounded,
  'cleaning_services' => Icons.cleaning_services_rounded,
  'spa' => Icons.spa_rounded,
  'sos' => Icons.sos_rounded,
  _ => Icons.support_agent_rounded,
};

const _fallbackCatalog = <CentralServiceCatalogItem>[
  CentralServiceCatalogItem(
    key: 'legal',
    title: 'خدمات قانونية',
    subtitle: 'استشارة ومعاملات وعقود',
    icon: 'balance',
    color: '#6E5845',
    emergency: false,
    executionModes: ['remote', 'provider_location'],
    quickIssues: ['استشارة قانونية', 'مراجعة عقد', 'متابعة معاملة'],
    questions: [],
  ),
  CentralServiceCatalogItem(
    key: 'medical',
    title: 'خدمات طبية',
    subtitle: 'مساعدة صحية منزلية وحجز مختص',
    icon: 'medical_services',
    color: '#2F6F68',
    emergency: false,
    executionModes: ['home', 'remote'],
    quickIssues: ['طبيب منزلي', 'ممرض', 'تحاليل منزلية'],
    questions: [],
  ),
  CentralServiceCatalogItem(
    key: 'home_maintenance',
    title: 'صيانة منزلية',
    subtitle: 'كهرباء وسباكة وتبريد وتصليحات',
    icon: 'home_repair_service',
    color: '#3F6550',
    emergency: false,
    executionModes: ['home'],
    quickIssues: ['كهرباء', 'سباكة', 'تبريد وتكييف'],
    questions: [],
  ),
  CentralServiceCatalogItem(
    key: 'roadside',
    title: 'صيانة سيارات متنقلة',
    subtitle: 'فني يصل إلى موقع السيارة',
    icon: 'car_repair',
    color: '#384F67',
    emergency: false,
    executionModes: ['home'],
    quickIssues: ['بطارية', 'إطار مثقوب', 'عطل مفاجئ'],
    questions: [],
  ),
  CentralServiceCatalogItem(
    key: 'cleaning',
    title: 'تنظيف الشقق',
    subtitle: 'تنظيف دوري أو عميق حسب الموعد',
    icon: 'cleaning_services',
    color: '#5B7180',
    emergency: false,
    executionModes: ['home'],
    quickIssues: ['تنظيف شامل', 'تنظيف عميق'],
    questions: [],
  ),
  CentralServiceCatalogItem(
    key: 'wellbeing',
    title: 'خدمات الرفاهية',
    subtitle: 'عناية شخصية ومناسبات وخدمات منزلية',
    icon: 'spa',
    color: '#76566C',
    emergency: false,
    executionModes: ['home', 'provider_location'],
    quickIssues: ['عناية شخصية', 'تنظيم مناسبة'],
    questions: [],
  ),
  CentralServiceCatalogItem(
    key: 'sos',
    title: 'SOS مساعدة عاجلة',
    subtitle: 'أرسل موقعك وتفاصيل الحالة فوراً',
    icon: 'sos',
    color: '#A33A32',
    emergency: true,
    executionModes: ['home'],
    quickIssues: ['إسعاف', 'إطفاء', 'شرطة', 'عطل سيارة خطر'],
    questions: [],
  ),
];
