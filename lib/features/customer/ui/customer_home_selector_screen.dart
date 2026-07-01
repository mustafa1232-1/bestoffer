// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/auth/auth_guard.dart';
import '../../../core/sections/section_access_guard.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/parsers.dart';
import '../../../core/widgets/desktop_dashboard_frame.dart';
import '../../../core/widgets/maslaki_brand_mark.dart';
import '../../../core/widgets/maslaki_user_drawer.dart';
import '../../../core/widgets/maslaki_wordmark.dart';
import '../../../pages/map_page.dart';
import '../../auth/state/auth_controller.dart';
import '../../auth/ui/merchants_list_screen.dart';
import '../../customer/models/customer_ad_board_item.dart';
import '../../customer/models/recent_activity.dart';
import '../../customer/state/customer_ad_board_controller.dart';
import '../../customer/state/customer_smart_experience_provider.dart';
import '../../customer/state/recent_activity_controller.dart';
import '../../jobs/ui/jobs_hub_screen.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/state/merchants_controller.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../../notifications/ui/notifications_screen.dart';
import '../../orders/state/delivery_address_controller.dart';
import '../../orders/ui/delivery_addresses_screen.dart';
import '../../paid_upgrades/state/paid_upgrades_summary_provider.dart';
import '../../real_estate/ui/real_estate_marketplace_screen.dart';
import '../../real_estate/ui/real_estate_workspace_screen.dart';
import '../../services/ui/service_offering_details_screen.dart';
import '../../services/ui/service_provider_workspace_screen.dart';
import '../../services/ui/services_marketplace_screen.dart';
import '../../social/ui/social_shell_screen.dart';
import 'customer_cars_hub_screen.dart';
import 'customer_discovery_screen.dart';
import 'customer_main_market_screen.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class CustomerHomeSelectorScreen extends ConsumerStatefulWidget {
  const CustomerHomeSelectorScreen({super.key});

  @override
  ConsumerState<CustomerHomeSelectorScreen> createState() =>
      _CustomerHomeSelectorScreenState();
}

enum OpenStoresUiState { loading, ready, empty, error }

enum HomeMainSection {
  shopping,
  taxi,
  community,
  cars,
  jobs,
  services,
  realEstate,
}

class _CustomerHomeSelectorScreenState
    extends ConsumerState<CustomerHomeSelectorScreen>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  static final Set<String> _allowedAdHosts =
      const String.fromEnvironment('ADS_EXTERNAL_ALLOWED_HOSTS')
          .split(',')
          .map((host) => host.trim().toLowerCase())
          .where((host) => host.isNotEmpty)
          .toSet();

  OpenStoresUiState _openStoresState = OpenStoresUiState.loading;
  List<MerchantModel> _openStores = const <MerchantModel>[];
  MerchantModel? _bestStore;
  String? _openStoresError;
  DateTime? _lastAdsReloadAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(customerAdBoardControllerProvider.notifier).load());
      unawaited(
        ref
            .read(deliveryAddressControllerProvider.notifier)
            .bootstrap(silent: true),
      );
      unawaited(ref.read(recentActivityControllerProvider.notifier).load());
      unawaited(_loadOpenStores());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final now = DateTime.now();
    final elapsed = _lastAdsReloadAt == null
        ? const Duration(days: 1)
        : now.difference(_lastAdsReloadAt!);
    if (elapsed < const Duration(seconds: 20)) return;
    _lastAdsReloadAt = now;
    unawaited(
      ref.read(customerAdBoardControllerProvider.notifier).load(force: true),
    );
  }

  Future<void> _refreshHome() async {
    await Future.wait<void>([
      ref.read(customerAdBoardControllerProvider.notifier).load(force: true),
      ref.read(recentActivityControllerProvider.notifier).load(force: true),
      _loadOpenStores(),
    ]);
  }

  Future<void> _openShopping({
    String? type,
    String? activityType,
    String? discoverySubcategory,
    String query = '',
    String? title,
  }) async {
    if (!await _ensureSectionAccess(HomeMainSection.shopping)) return;
    if (!mounted) return;
    final hasScopedIntent =
        (type ?? '').trim().isNotEmpty ||
        (activityType ?? '').trim().isNotEmpty ||
        (discoverySubcategory ?? '').trim().isNotEmpty ||
        query.trim().isNotEmpty ||
        (title ?? '').trim().isNotEmpty;
    if (!hasScopedIntent) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CustomerMainMarketScreen()),
      );
      return;
    }
    final hasActivityScope =
        (activityType ?? '').trim().isNotEmpty ||
        (discoverySubcategory ?? '').trim().isNotEmpty;
    if (hasActivityScope) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MerchantsListScreen(
            initialType: type,
            initialActivityType: activityType,
            initialDiscoverySubcategory: discoverySubcategory,
            initialSearchQuery: query,
            overrideTitle: title,
            compactCustomerMode: true,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerDiscoveryScreen(
          mode: CustomerDiscoveryMode.shoppingOnly,
          initialType: type,
          initialSearchQuery: query,
          initialTitle: title,
        ),
      ),
    );
  }

  Future<void> _openNotifications() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'الإشعارات الشخصية',
      featureEnglish: 'personal notifications',
    )) {
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  Future<void> _openAddresses() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'العناوين المحفوظة',
      featureEnglish: 'saved addresses',
    )) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DeliveryAddressesScreen(selectOnTap: true),
      ),
    );
  }

  Future<void> _openSection(HomeMainSection section) async {
    if (!await _ensureSectionAccess(section)) return;
    if (!mounted) return;
    switch (section) {
      case HomeMainSection.shopping:
        await _openShopping();
        return;
      case HomeMainSection.taxi:
        if (!await requireAuthBeforeAction(
          context,
          featureArabic: 'خدمة التكسي',
          featureEnglish: 'taxi booking',
        )) {
          return;
        }
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MapPage()));
        return;
      case HomeMainSection.community:
        await _openCommunity();
        return;
      case HomeMainSection.cars:
        await _openCarsHub();
        return;
      case HomeMainSection.jobs:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const JobsHubScreen()));
        return;
      case HomeMainSection.services:
        await _openServicesEntry();
        return;
      case HomeMainSection.realEstate:
        await _openRealEstateEntry();
        return;
    }
  }

  Future<void> _openCommunity({
    SocialShellTab initialTab = SocialShellTab.home,
    int? initialReelId,
  }) async {
    if (!await _ensureSectionAccess(HomeMainSection.community)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SocialShellScreen(
          initialTab: initialTab,
          initialReelId: initialReelId,
        ),
      ),
    );
  }

  Future<void> _openRealEstateEntry() async {
    if (!await _ensureSectionAccess(HomeMainSection.realEstate)) return;
    var useWorkspace = false;
    try {
      final summary = await ref.read(myPaidUpgradesSummaryProvider.future);
      useWorkspace = summary.propertySellerMonthly || summary.premiumMonthly;
    } catch (_) {
      useWorkspace = false;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => useWorkspace
            ? const RealEstateWorkspaceScreen()
            : const RealEstateMarketplaceScreen(),
      ),
    );
  }

  Future<void> _openServicesEntry() async {
    if (!await _ensureSectionAccess(HomeMainSection.services)) return;
    if (!mounted) return;
    final auth = ref.read(authControllerProvider);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => auth.isServiceProvider
            ? const ServiceProviderWorkspaceScreen()
            : const ServicesMarketplaceScreen(),
      ),
    );
  }

  Future<void> _openMerchant(
    MerchantModel merchant, {
    String? promoCode,
  }) async {
    if (!await _ensureSectionAccess(HomeMainSection.shopping)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantProductsScreen(merchant: merchant),
      ),
    );
    if (!mounted) return;
    if ((promoCode ?? '').trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('كود الخصم: ${promoCode!.trim()}')),
      );
    }
  }

  Future<void> _openCarsHub() async {
    if (!await _ensureSectionAccess(HomeMainSection.cars)) return;
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CustomerCarsHubScreen()));
  }

  Future<void> _openSavedPlaceShortcut(Map<String, dynamic> place) async {
    if (!await _ensureSectionAccess(HomeMainSection.taxi)) return;
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'اختصار موقع محفوظ',
      featureEnglish: 'saved place shortcut',
    )) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MapPage(initialDropoffSnapshot: place)),
    );
  }

  Future<void> _openRideReuseShortcut(Map<String, dynamic> ride) async {
    if (!await _ensureSectionAccess(HomeMainSection.taxi)) return;
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'إعادة آخر مشوار',
      featureEnglish: 'rebook last ride',
    )) {
      return;
    }
    if (!mounted) return;
    final pickup = (ride['pickup'] as Map?)?.cast<String, dynamic>();
    final dropoff = (ride['dropoff'] as Map?)?.cast<String, dynamic>();
    final fare =
        tryParseLocalizedInt(ride['agreedFareIqd']) ??
        tryParseLocalizedInt(ride['fareAfterDiscountIqd']) ??
        tryParseLocalizedInt(ride['proposedFareIqd']);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapPage(
          initialPickupSnapshot: pickup,
          initialDropoffSnapshot: dropoff,
          initialFareIqd: fare,
        ),
      ),
    );
  }

  Future<void> _openBestForYouShortcut(String sectionKey) async {
    switch (sectionKey) {
      case 'services':
        await _openServicesEntry();
        return;
      case 'taxi':
        await _openSection(HomeMainSection.taxi);
        return;
      default:
        await _openShopping();
        return;
    }
  }

  String _sectionKeyFor(HomeMainSection section) {
    switch (section) {
      case HomeMainSection.shopping:
        return AppSectionKeys.shopping;
      case HomeMainSection.taxi:
        return AppSectionKeys.taxi;
      case HomeMainSection.community:
        return AppSectionKeys.community;
      case HomeMainSection.cars:
        return AppSectionKeys.cars;
      case HomeMainSection.jobs:
        return AppSectionKeys.jobs;
      case HomeMainSection.services:
        return AppSectionKeys.services;
      case HomeMainSection.realEstate:
        return AppSectionKeys.realEstate;
    }
  }

  String _sectionDisplayNameFor(HomeMainSection section) {
    switch (section) {
      case HomeMainSection.shopping:
        return 'التسوق';
      case HomeMainSection.taxi:
        return 'التكسي';
      case HomeMainSection.community:
        return 'المجتمع';
      case HomeMainSection.cars:
        return 'السيارات';
      case HomeMainSection.jobs:
        return 'الوظائف';
      case HomeMainSection.services:
        return 'الخدمات';
      case HomeMainSection.realEstate:
        return 'العقارات';
    }
  }

  Future<bool> _ensureSectionAccess(HomeMainSection section) {
    return guardSectionAccess(
      context,
      ref,
      sectionKey: _sectionKeyFor(section),
      displayName: _sectionDisplayNameFor(section),
    );
  }

  Future<void> _openMerchantById(int merchantId, {String? promoCode}) async {
    if (merchantId <= 0) {
      await _openShopping();
      return;
    }

    try {
      final raw = await ref.read(merchantsApiProvider).getById(merchantId);
      final merchant = MerchantModel.fromJson(raw);
      if (!mounted) return;
      await _openMerchant(merchant, promoCode: promoCode);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر فتح المتجر حالياً')));
    }
  }

  Future<void> _openCategoryFromAd(String? categoryRaw) async {
    final normalized = (categoryRaw ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      await _openShopping();
      return;
    }

    if (<String>{'taxi', 'ride'}.contains(normalized)) {
      await _openSection(HomeMainSection.taxi);
      return;
    }
    if (<String>{'community', 'social'}.contains(normalized)) {
      await _openCommunity();
      return;
    }
    if (<String>{'reels', 'reel'}.contains(normalized)) {
      await _openCommunity(initialTab: SocialShellTab.reels);
      return;
    }
    if (<String>{'cars', 'car'}.contains(normalized)) {
      await _openSection(HomeMainSection.cars);
      return;
    }
    if (<String>{'jobs', 'job'}.contains(normalized)) {
      await _openSection(HomeMainSection.jobs);
      return;
    }
    if (<String>{'services', 'service', 'خدمات'}.contains(normalized)) {
      await _openSection(HomeMainSection.services);
      return;
    }
    if (<String>{'real_estate', 'realestate', 'estate'}.contains(normalized)) {
      await _openSection(HomeMainSection.realEstate);
      return;
    }

    if (<String>{'restaurant', 'restaurants'}.contains(normalized)) {
      await _openShopping(type: 'restaurant', title: 'مطاعم');
      return;
    }
    if (<String>{'market', 'shopping', 'shop'}.contains(normalized)) {
      await _openShopping(type: 'market', title: 'تسوق');
      return;
    }

    await _openShopping(query: normalized, title: normalized);
  }

  Future<void> _openInternalRoute(String? routeRaw) async {
    final raw = (routeRaw ?? '').trim();
    if (raw.isEmpty) {
      await _openShopping();
      return;
    }

    final parsed = Uri.tryParse(raw);
    final pathCandidate = parsed == null
        ? raw
        : (parsed.path.isNotEmpty ? parsed.path : raw);
    final normalized = pathCandidate.toLowerCase().replaceFirst(
      RegExp(r'^/+'),
      '',
    );
    final query = parsed?.queryParameters ?? const <String, String>{};

    if (normalized.isEmpty) {
      await _openShopping();
      return;
    }

    if (<String>{
      'shopping',
      'market',
      'main_market',
      'all_market',
      'all_stores',
      'shopping/main_market',
      'customer_discovery',
    }.contains(normalized)) {
      final adType = query['type']?.trim();
      final adActivityType = query['activityType']?.trim();
      final adDiscoverySubcategory = query['discoverySubcategory']?.trim();
      final adTitle = query['title']?.trim();
      if ((adType ?? '').isNotEmpty ||
          (adActivityType ?? '').isNotEmpty ||
          (adDiscoverySubcategory ?? '').isNotEmpty ||
          (adTitle ?? '').isNotEmpty) {
        await _openShopping(
          type: adType,
          activityType: adActivityType,
          discoverySubcategory: adDiscoverySubcategory,
          title: adTitle,
        );
      } else {
        await _openSection(HomeMainSection.shopping);
      }
      return;
    }
    if (<String>{'taxi', 'map', 'taxi_home'}.contains(normalized)) {
      await _openSection(HomeMainSection.taxi);
      return;
    }
    if (<String>{'community', 'social'}.contains(normalized)) {
      await _openCommunity();
      return;
    }
    if (<String>{'reels', 'reel'}.contains(normalized)) {
      await _openCommunity(initialTab: SocialShellTab.reels);
      return;
    }
    if (<String>{'cars', 'cars_hub'}.contains(normalized)) {
      await _openSection(HomeMainSection.cars);
      return;
    }
    if (<String>{'jobs', 'jobs_hub'}.contains(normalized)) {
      await _openSection(HomeMainSection.jobs);
      return;
    }
    if (<String>{
      'services',
      'services_marketplace',
      'service',
    }.contains(normalized)) {
      await _openSection(HomeMainSection.services);
      return;
    }
    if (<String>{'real_estate', 'realestate'}.contains(normalized)) {
      await _openSection(HomeMainSection.realEstate);
      return;
    }
    if (<String>{'notifications'}.contains(normalized)) {
      await _openNotifications();
      return;
    }
    if (<String>{'addresses', 'delivery_addresses'}.contains(normalized)) {
      await _openAddresses();
      return;
    }

    await _openShopping();
  }

  Future<bool> _tryOpenActivityRoute(RecentActivityModel activity) async {
    final routeFromMetadata = '${activity.metadata['route'] ?? activity.route}'
        .trim();
    if (routeFromMetadata.isNotEmpty) {
      await _openInternalRoute(routeFromMetadata);
      return true;
    }
    return false;
  }

  bool _isAllowedExternalAdUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    if (_allowedAdHosts.isEmpty) return true;
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) return false;
    return _allowedAdHosts.any((allowed) {
      if (host == allowed) return true;
      return host.endsWith('.$allowed');
    });
  }

  Future<void> _handleAdTap(CustomerAdBoardItem item) async {
    final actionType =
        (item.type.trim().isNotEmpty ? item.type : item.ctaTargetType)
            .trim()
            .toLowerCase();

    switch (actionType) {
      case 'store_ad':
      case 'merchant':
        final merchantId = item.merchantId ?? item.targetId;
        if (merchantId != null && merchantId > 0) {
          await _openMerchantById(merchantId);
          return;
        }
        await _openShopping(title: item.title);
        return;
      case 'promo_code':
        final merchantId = item.merchantId ?? item.targetId;
        if (merchantId != null && merchantId > 0) {
          await _openMerchantById(merchantId, promoCode: item.promoCode);
          return;
        }
        if ((item.category ?? '').trim().isNotEmpty) {
          await _openCategoryFromAd(item.category);
          return;
        }
        await _openShopping(title: item.title);
        return;
      case 'category_ad':
      case 'category':
        await _openCategoryFromAd(item.category ?? item.ctaTargetValue);
        return;
      case 'external_link':
      case 'url':
        final raw = (item.externalLink ?? item.ctaTargetValue ?? '').trim();
        final uri = Uri.tryParse(raw);
        if (uri == null || !_isAllowedExternalAdUri(uri)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الرابط غير مسموح أو غير صالح')),
          );
          return;
        }
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
        return;
      case 'internal_route':
      case 'internal_campaign_page':
        await _openInternalRoute(item.targetRoute ?? item.ctaTargetValue);
        return;
      case 'taxi':
        await _openSection(HomeMainSection.taxi);
        return;
      case 'product':
        final merchantId = item.merchantId ?? item.targetId;
        if (merchantId != null && merchantId > 0) {
          await _openMerchantById(merchantId);
          return;
        }
        await _openShopping(title: item.title);
        return;
      case 'none':
      default:
        await _openShopping(title: item.title);
        return;
    }
  }

  Future<void> _openRecentActivity(RecentActivityModel activity) async {
    if (await _tryOpenActivityRoute(activity)) {
      return;
    }

    switch (activity.type) {
      case RecentActivityType.shopping:
        final merchantIdFromMetadata = int.tryParse(
          '${activity.metadata['merchantId'] ?? ''}',
        );
        final merchantId = activity.targetId ?? merchantIdFromMetadata;
        if (merchantId != null && merchantId > 0) {
          await _openMerchantById(merchantId);
          return;
        }
        await _openSection(HomeMainSection.shopping);
        return;
      case RecentActivityType.taxi:
        await _openSection(HomeMainSection.taxi);
        return;
      case RecentActivityType.community:
        await _openSection(HomeMainSection.community);
        return;
      case RecentActivityType.services:
        if (activity.targetId != null && activity.targetId! > 0) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ServiceOfferingDetailsScreen(offeringId: activity.targetId!),
            ),
          );
          return;
        }
        await _openSection(HomeMainSection.services);
        return;
      case RecentActivityType.cars:
        await _openSection(HomeMainSection.cars);
        return;
      case RecentActivityType.jobs:
        await _openSection(HomeMainSection.jobs);
        return;
      case RecentActivityType.realEstate:
        await _openSection(HomeMainSection.realEstate);
        return;
    }
  }

  double _storeScore(MerchantModel store) {
    final rating = store.avgMerchantRating ?? 0;
    final engagement = (store.ratingCount <= 0)
        ? 0.0
        : (store.ratingCount / 150).clamp(0.0, 1.0);
    final offerBonus =
        (store.hasDiscountOffer ? 0.28 : 0.0) +
        (store.hasFreeDeliveryOffer ? 0.2 : 0.0);
    return rating + engagement + offerBonus;
  }

  Future<void> _loadOpenStores() async {
    setState(() {
      _openStoresState = OpenStoresUiState.loading;
      _openStoresError = null;
    });

    try {
      final raw = await ref.read(merchantsApiProvider).list();

      final openStores =
          raw
              .whereType<Map>()
              .map((e) => MerchantModel.fromJson(Map<String, dynamic>.from(e)))
              .where((store) => store.isOpen)
              .toList()
            ..sort((a, b) {
              final scoreCompare = _storeScore(b).compareTo(_storeScore(a));
              if (scoreCompare != 0) return scoreCompare;
              final ratingCompare = (b.avgMerchantRating ?? 0).compareTo(
                a.avgMerchantRating ?? 0,
              );
              if (ratingCompare != 0) return ratingCompare;
              return b.ratingCount.compareTo(a.ratingCount);
            });

      if (!mounted) return;
      setState(() {
        _bestStore = openStores.isEmpty ? null : openStores.first;
        _openStores = openStores.take(8).toList(growable: false);
        _openStoresState = _openStores.isEmpty
            ? OpenStoresUiState.empty
            : OpenStoresUiState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _bestStore = null;
        _openStores = const <MerchantModel>[];
        _openStoresError = '$error';
        _openStoresState = OpenStoresUiState.error;
      });
    }
  }

  Future<void> _openBestStoreBrowsing() async {
    final bestStore = _bestStore;
    final normalizedType = (bestStore?.type ?? '').trim().toLowerCase();
    final type = normalizedType == 'market' || normalizedType == 'restaurant'
        ? normalizedType
        : null;

    await _openShopping(type: type, title: 'تصفح المتاجر');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sectionAvailability = ref.watch(
      sectionAvailabilityControllerProvider,
    );
    final tokens = context.maslakiTokens;
    final useDesktop = DesktopDashboardFrame.shouldUse(context);

    final adBoardState = ref.watch(customerAdBoardControllerProvider);
    final recentActivityState = ref.watch(recentActivityControllerProvider);
    final smartExperienceState = ref.watch(customerSmartExperienceProvider);

    final selectedAddress = ref.watch(
      deliveryAddressControllerProvider.select(
        (state) => state.selectedAddress,
      ),
    );
    final cityLabel = (selectedAddress?.city ?? '').trim().isNotEmpty
        ? selectedAddress!.city.trim()
        : l10n.deliveryAddressesDefaultCity;

    SectionAvailabilityEntry entryForSection(HomeMainSection section) {
      return sectionAvailability.entryFor(
        _sectionKeyFor(section),
        displayName: _sectionDisplayNameFor(section),
      );
    }

    MainCategoryItem buildCategoryItem({
      required HomeMainSection section,
      required String title,
      required String subtitle,
      required IconData icon,
      required List<Color> gradient,
    }) {
      final entry = entryForSection(section);
      return MainCategoryItem(
        title: title,
        subtitle: subtitle,
        icon: icon,
        gradient: gradient,
        onTap: () => _openSection(section),
        enabled: entry.isOpen,
        isVisible: entry.isVisible,
        badgeLabel: entry.badgeLabel,
      );
    }

    final mobileDrawer = const MaslakiUserDrawer();
    final desktopDrawer = const MaslakiUserDrawer(embedded: true);

    final categoryGradients = _homeCategoryGradients(context);

    final categories = <MainCategoryItem>[
      buildCategoryItem(
        section: HomeMainSection.shopping,
        title: 'التسوق',
        subtitle: 'متاجر ومطاعم وكل احتياجاتك',
        icon: Icons.storefront_rounded,
        gradient: categoryGradients[0],
      ),
      buildCategoryItem(
        section: HomeMainSection.taxi,
        title: 'التكسي',
        subtitle: 'تنقل بسرعة داخل بسماية',
        icon: Icons.local_taxi_rounded,
        gradient: categoryGradients[1],
      ),
      buildCategoryItem(
        section: HomeMainSection.community,
        title: 'المجتمع',
        subtitle: 'منشورات ومحادثات وتفاعل',
        icon: Icons.groups_rounded,
        gradient: categoryGradients[2],
      ),
      buildCategoryItem(
        section: HomeMainSection.cars,
        title: 'السيارات',
        subtitle: 'بيع وشراء وإعلانات سيارات',
        icon: Icons.directions_car_filled_rounded,
        gradient: categoryGradients[3],
      ),
      buildCategoryItem(
        section: HomeMainSection.jobs,
        title: 'الوظائف',
        subtitle: 'فرص عمل قريبة',
        icon: Icons.work_rounded,
        gradient: categoryGradients[4],
      ),
      buildCategoryItem(
        section: HomeMainSection.services,
        title: 'الخدمات',
        subtitle: 'فنيين وخدمات منزلية متنوعة',
        icon: Icons.handyman_rounded,
        gradient: categoryGradients[5],
      ),
      buildCategoryItem(
        section: HomeMainSection.realEstate,
        title: 'العقارات',
        subtitle: 'بيع وإيجار عقارات بسماية',
        icon: Icons.apartment_rounded,
        gradient: categoryGradients[6],
      ),
    ].where((item) => item.isVisible).toList(growable: false);

    final smartExperienceSection = smartExperienceState.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (snapshot) {
        final recentActivity = recentActivityState.valueOrNull;
        final shortcuts = <Widget>[];
        final bestForYouTitle = switch (snapshot.bestSectionKey) {
          'services' => context.lt(
            ar: 'الأفضل لك الآن في الخدمات',
            en: 'Best for you now in services',
          ),
          'taxi' => context.lt(
            ar: 'الأفضل لك الآن في التكسي',
            en: 'Best for you now in taxi',
          ),
          _ => context.lt(
            ar: 'الأفضل لك الآن في المتاجر',
            en: 'Best for you now in stores',
          ),
        };
        final bestForYouSubtitle = context.lt(
          ar: 'اختصارات وعروض مرتبة حسب نشاطك الفعلي وآخر استخداماتك.',
          en: 'Shortcuts and offers ranked by your actual activity and recent usage.',
        );

        if (snapshot.homePlace != null) {
          shortcuts.add(
            _HomeSmartShortcutCard(
              title: context.lt(ar: 'البيت', en: 'Home'),
              subtitle: context.lt(
                ar: 'حجز سريع إلى موقعك المحفوظ',
                en: 'Quick ride to your saved home location',
              ),
              icon: Icons.home_work_outlined,
              onTap: () => _openSavedPlaceShortcut(snapshot.homePlace!),
            ),
          );
        }
        if (snapshot.workPlace != null) {
          shortcuts.add(
            _HomeSmartShortcutCard(
              title: context.lt(ar: 'العمل', en: 'Work'),
              subtitle: context.lt(
                ar: 'عودة مباشرة إلى وجهة العمل',
                en: 'Return directly to your work destination',
              ),
              icon: Icons.work_history_outlined,
              onTap: () => _openSavedPlaceShortcut(snapshot.workPlace!),
            ),
          );
        }
        if (snapshot.lastRide != null) {
          shortcuts.add(
            _HomeSmartShortcutCard(
              title: context.lt(ar: 'إعادة آخر مشوار', en: 'Repeat last ride'),
              subtitle: context.lt(
                ar: 'افتح نفس المسار بضغطة واحدة',
                en: 'Open the same route in one tap',
              ),
              icon: Icons.local_taxi_outlined,
              onTap: () => _openRideReuseShortcut(snapshot.lastRide!),
            ),
          );
        }
        if (recentActivity != null) {
          shortcuts.add(
            _HomeSmartShortcutCard(
              title: context.lt(ar: 'آخر نشاط', en: 'Recent activity'),
              subtitle: recentActivity.resolveTitle(context),
              icon: Icons.history_toggle_off_rounded,
              onTap: () => _openRecentActivity(recentActivity),
            ),
          );
        }
        return Column(
          children: [
            MaslakiSectionHeader(
              title: context.lt(
                ar: 'اختصاراتك الذكية',
                en: 'Your smart shortcuts',
              ),
              subtitle: context.lt(
                ar: 'بناءً على أماكنك المحفوظة وآخر مشاويرك ونشاطك الفعلي داخل التطبيق',
                en: 'Based on your saved places, last rides, and actual in-app activity',
              ),
            ),
            const SizedBox(height: 12),
            MaslakiOfferBanner(
              title: bestForYouTitle,
              subtitle: bestForYouSubtitle,
              ctaLabel: context.lt(ar: 'افتح الآن', en: 'Open now'),
              onTap: () => _openBestForYouShortcut(snapshot.bestSectionKey),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              child: ListView.separated(
                reverse: true,
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) => shortcuts[index],
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemCount: shortcuts.length,
              ),
            ),
          ],
        );
      },
    );

    final scroll = SafeArea(
      child: RefreshIndicator(
        onRefresh: _refreshHome,
        displacement: 18,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Column(
                  children: [
                    HomeHeader(
                      cityLabel: cityLabel,
                      onMenuTap: useDesktop
                          ? null
                          : () {
                              _scaffoldKey.currentState?.openEndDrawer();
                            },
                      onNotificationsTap: _openNotifications,
                      onLocationTap: _openAddresses,
                    ),
                    const SizedBox(height: 16),
                    HomeAdCarousel(
                      state: adBoardState,
                      onTap: _handleAdTap,
                      onRetry: () => ref
                          .read(customerAdBoardControllerProvider.notifier)
                          .load(force: true),
                    ),
                    const SizedBox(height: 18),
                    MainCategoryGrid(items: categories),
                    const SizedBox(height: 18),
                    smartExperienceSection,
                    const SizedBox(height: 18),
                    BestStoreSpotlight(
                      state: _openStoresState,
                      store: _bestStore,
                      onTap: _openBestStoreBrowsing,
                      onRetry: _loadOpenStores,
                    ),
                    const SizedBox(height: 14),
                    OpenNowStoresSection(
                      state: _openStoresState,
                      stores: _openStores,
                      errorText: _openStoresError,
                      onRetry: _loadOpenStores,
                      onStoreTap: (store) => _openMerchant(store),
                    ),
                    const SizedBox(height: 18),
                    RecentActivitySection(
                      state: recentActivityState,
                      onTap: _openRecentActivity,
                    ),
                    const SizedBox(height: 96),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: tokens.backgroundPrimary,
      endDrawer: useDesktop ? null : mobileDrawer,
      body: useDesktop
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: DesktopDashboardFrame(
                sidebar: desktopDrawer,
                title: 'مسلكي',
                subtitle: 'واجهة رئيسية موحّدة للخدمات',
                child: scroll,
              ),
            )
          : scroll,
    );
  }
}

class HomeHeader extends StatelessWidget {
  final String cityLabel;
  final VoidCallback? onMenuTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onLocationTap;

  const HomeHeader({
    super.key,
    required this.cityLabel,
    this.onMenuTap,
    required this.onNotificationsTap,
    required this.onLocationTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    final cityWidth = (MediaQuery.sizeOf(context).width * 0.56)
        .clamp(170.0, 280.0)
        .toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          stops: const [0, 0.62, 1],
          colors: [
            Color.alphaBlend(
              visual.accentBlue.withValues(alpha: 0.16),
              tokens.cardPrimary.withValues(alpha: 0.98),
            ),
            tokens.cardElevated.withValues(alpha: 0.92),
            Color.alphaBlend(
              visual.accentViolet.withValues(alpha: 0.16),
              tokens.cardPrimary.withValues(alpha: 0.96),
            ),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        border: Border.all(color: tokens.borderSubtle.withValues(alpha: 0.62)),
        boxShadow: [
          BoxShadow(
            color: visual.accentBlue.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 11),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              const _HeaderBrandLogo(),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      l10n.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.customerHomeDrawerSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _HeaderMiniButton(
                icon: Icons.notifications_outlined,
                onTap: onNotificationsTap,
              ),
              if (onMenuTap != null) ...[
                const SizedBox(width: 8),
                _HeaderMiniButton(icon: Icons.menu_rounded, onTap: onMenuTap!),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onLocationTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: visual.accentCyan.withValues(alpha: 0.13),
                  border: Border.all(
                    color: visual.accentCyan.withValues(alpha: 0.38),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: cityWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        color: visual.accentCyan,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          cityLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: visual.accentCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderBrandLogo extends StatelessWidget {
  const _HeaderBrandLogo();

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;

    return Container(
      height: 60,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            visual.accentGold.withValues(alpha: 0.72),
            visual.accentViolet.withValues(alpha: 0.52),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: visual.accentGold.withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          color: tokens.cardPrimary.withValues(alpha: 0.92),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.rtl,
          children: [
            SizedBox(width: 4),
            MaslakiBrandMark(size: 54, borderRadius: 16),
            Padding(
              padding: EdgeInsetsDirectional.only(start: 8, end: 14),
              child: MaslakiWordmark(
                arabicSize: 24,
                latinSize: 10.5,
                latinLetterSpacing: 3.4,
                crossAxisAlignment: CrossAxisAlignment.start,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderMiniButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderMiniButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              Color.alphaBlend(
                visual.accentBlue.withValues(alpha: 0.2),
                tokens.surfaceSecondary.withValues(alpha: 0.9),
              ),
              Color.alphaBlend(
                visual.accentViolet.withValues(alpha: 0.18),
                tokens.cardPrimary.withValues(alpha: 0.88),
              ),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          border: Border.all(
            color: tokens.borderSubtle.withValues(alpha: 0.72),
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.96),
          size: 19,
        ),
      ),
    );
  }
}

class HomeAdCarousel extends StatefulWidget {
  final AsyncValue<List<CustomerAdBoardItem>> state;
  final Future<void> Function(CustomerAdBoardItem item) onTap;
  final Future<void> Function() onRetry;

  const HomeAdCarousel({
    super.key,
    required this.state,
    required this.onTap,
    required this.onRetry,
  });

  @override
  State<HomeAdCarousel> createState() => _HomeAdCarouselState();
}

class _HomeAdCarouselState extends State<HomeAdCarousel> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.94);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant HomeAdCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldItems =
        oldWidget.state.valueOrNull ?? const <CustomerAdBoardItem>[];
    final items = widget.state.valueOrNull ?? const <CustomerAdBoardItem>[];
    if (oldItems.length != items.length) {
      _currentPage = 0;
      _timer?.cancel();
      _startTimer();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      final items = widget.state.valueOrNull ?? const <CustomerAdBoardItem>[];
      if (items.length <= 1 || !_pageController.hasClients) return;
      final next = (_currentPage + 1) % items.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    final tokens = context.maslakiTokens;
    final items = widget.state.valueOrNull ?? const <CustomerAdBoardItem>[];

    if (widget.state.isLoading && !widget.state.hasValue) {
      return Container(
        height: 158,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: tokens.cardPrimary.withValues(alpha: 0.75),
          border: Border.all(
            color: tokens.borderSubtle.withValues(alpha: 0.55),
          ),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (widget.state.hasError && !widget.state.hasValue) {
      return _HomeAdFallbackCard(
        title: 'تعذر تحميل الإعلانات حاليًا',
        message: 'تحقق من اتصال الشبكة أو إعدادات الإعلانات ثم أعد المحاولة',
        buttonLabel: 'إعادة التحميل',
        accentIcon: Icons.warning_amber_rounded,
        accentColor: visual.accentGold,
        onPressed: widget.onRetry,
        filledButton: true,
      );
    }

    if (items.isEmpty) {
      return _HomeAdFallbackCard(
        title: 'لا توجد إعلانات مفعلة حاليًا',
        message: 'تأكد من تفعيل الإعلان والتاريخ وأن المتجر المرتبط موافق عليه',
        buttonLabel: 'تحديث الإعلانات',
        accentIcon: Icons.campaign_outlined,
        accentColor: visual.accentCyan,
        onPressed: widget.onRetry,
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 172,
          child: PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            onPageChanged: (value) {
              setState(() => _currentPage = value);
            },
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _AdCard(item: item, onTap: () => widget.onTap(item)),
              );
            },
          ),
        ),
        const SizedBox(height: 9),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(items.length, (index) {
            final active = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: active ? 18 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: active
                    ? visual.accentCyan
                    : visual.accentCyan.withValues(alpha: 0.28),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _HomeAdFallbackCard extends StatelessWidget {
  final String title;
  final String message;
  final String buttonLabel;
  final IconData accentIcon;
  final Color accentColor;
  final VoidCallback onPressed;
  final bool filledButton;

  const _HomeAdFallbackCard({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.accentIcon,
    required this.accentColor,
    required this.onPressed,
    this.filledButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final buttonStyle = ButtonStyle(
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      minimumSize: WidgetStateProperty.all(const Size(0, 38)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    final buttonChild = Text(
      buttonLabel,
      textDirection: TextDirection.rtl,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return Container(
      height: 158,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: tokens.cardPrimary.withValues(alpha: 0.75),
        border: Border.all(color: tokens.borderSubtle.withValues(alpha: 0.55)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: SizedBox(
                width: constraints.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      textDirection: TextDirection.rtl,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(accentIcon, color: accentColor, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            textDirection: TextDirection.rtl,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      message,
                      textDirection: TextDirection.rtl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: filledButton
                  ? FilledButton.icon(
                      onPressed: onPressed,
                      style: buttonStyle,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: buttonChild,
                    )
                  : OutlinedButton.icon(
                      onPressed: onPressed,
                      style: buttonStyle,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: buttonChild,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdCard extends StatelessWidget {
  final CustomerAdBoardItem item;
  final VoidCallback onTap;

  const _AdCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final image = (item.imageUrl ?? '').trim();
    final visual = context.visualTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Color.alphaBlend(
                visual.accentViolet.withValues(alpha: 0.56),
                const Color(0xFF1A2E59),
              ),
              Color.alphaBlend(
                visual.accentBlue.withValues(alpha: 0.52),
                const Color(0xFF142D51),
              ),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: CachedAppImage(
                  imageUrl: image,
                  cacheIdentity: 'ad_${item.id}',
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.58),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if ((item.badgeLabel ?? '').trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      child: Text(
                        item.badgeLabel!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    item.title,
                    textDirection: TextDirection.rtl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    textDirection: TextDirection.rtl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<List<Color>> _homeCategoryGradients(BuildContext context) {
  final visual = context.visualTheme;
  final tokens = context.maslakiTokens;
  final baseA = tokens.cardElevated;
  final baseB = tokens.cardPrimary;
  return <List<Color>>[
    <Color>[
      Color.alphaBlend(visual.accentViolet.withValues(alpha: 0.66), baseA),
      Color.alphaBlend(visual.accentCyan.withValues(alpha: 0.63), baseB),
    ],
    <Color>[
      Color.alphaBlend(visual.accentViolet.withValues(alpha: 0.72), baseA),
      Color.alphaBlend(visual.accentBlue.withValues(alpha: 0.61), baseB),
    ],
    <Color>[
      Color.alphaBlend(visual.accentBlue.withValues(alpha: 0.65), baseA),
      Color.alphaBlend(visual.accentCyan.withValues(alpha: 0.56), baseB),
    ],
    <Color>[
      Color.alphaBlend(visual.accentViolet.withValues(alpha: 0.58), baseA),
      Color.alphaBlend(visual.accentBlue.withValues(alpha: 0.68), baseB),
    ],
    <Color>[
      Color.alphaBlend(visual.accentBlue.withValues(alpha: 0.6), baseA),
      Color.alphaBlend(visual.accentCyan.withValues(alpha: 0.62), baseB),
    ],
    <Color>[
      Color.alphaBlend(visual.accentViolet.withValues(alpha: 0.7), baseA),
      Color.alphaBlend(visual.accentCyan.withValues(alpha: 0.55), baseB),
    ],
    <Color>[
      Color.alphaBlend(visual.accentBlue.withValues(alpha: 0.72), baseA),
      Color.alphaBlend(visual.accentViolet.withValues(alpha: 0.5), baseB),
    ],
  ];
}

BoxDecoration _homePanelDecoration(BuildContext context, {double radius = 18}) {
  final tokens = context.maslakiTokens;
  final visual = context.visualTheme;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [
        Color.alphaBlend(
          visual.accentBlue.withValues(alpha: 0.18),
          tokens.cardPrimary.withValues(alpha: 0.84),
        ),
        Color.alphaBlend(
          visual.accentViolet.withValues(alpha: 0.16),
          tokens.cardElevated.withValues(alpha: 0.84),
        ),
      ],
    ),
    border: Border.all(color: tokens.borderSubtle.withValues(alpha: 0.58)),
    boxShadow: [
      BoxShadow(
        color: visual.accentBlue.withValues(alpha: 0.08),
        blurRadius: 14,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

class MainCategoryItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;
  final bool enabled;
  final bool isVisible;
  final String? badgeLabel;

  const MainCategoryItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.enabled = true,
    this.isVisible = true,
    this.badgeLabel,
  });
}

class MainCategoryGrid extends StatelessWidget {
  final List<MainCategoryItem> items;

  const MainCategoryGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(title: 'الأقسام الرئيسية'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width >= 980
                ? 4
                : width >= 680
                ? 3
                : 2;
            final spacing = width < 360 ? 8.0 : 10.0;
            final targetHeight = width < 360
                ? 176.0
                : width < 440
                ? 188.0
                : 178.0;
            final itemWidth =
                (width - ((crossAxisCount - 1) * spacing)) / crossAxisCount;
            final aspectRatio = itemWidth / targetHeight;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: aspectRatio,
              ),
              itemBuilder: (context, index) {
                return MainCategoryCard(item: items[index]);
              },
            );
          },
        ),
      ],
    );
  }
}

class MainCategoryCard extends StatelessWidget {
  final MainCategoryItem item;

  const MainCategoryCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final isEnabled = item.enabled;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: item.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              item.gradient.first.withValues(alpha: isEnabled ? 0.94 : 0.46),
              item.gradient.last.withValues(alpha: isEnabled ? 0.94 : 0.42),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: isEnabled ? 0.18 : 0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: item.gradient.first.withValues(
                alpha: isEnabled ? 0.24 : 0.08,
              ),
              blurRadius: 20,
              offset: const Offset(0, 11),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -28,
              top: -36,
              child: Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            Positioned(
              left: -18,
              bottom: -22,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.12),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if ((item.badgeLabel ?? '').trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        child: Text(
                          item.badgeLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.26),
                            Colors.white.withValues(alpha: 0.12),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.36),
                        ),
                      ),
                      child: Icon(item.icon, color: Colors.white, size: 25),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomRight,
                      child: SizedBox(
                        width: 158,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              item.title,
                              textDirection: TextDirection.rtl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.subtitle,
                              textDirection: TextDirection.rtl,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(
                                  alpha: isEnabled ? 0.9 : 0.72,
                                ),
                                fontSize: 12,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BestStoreSpotlight extends StatelessWidget {
  final OpenStoresUiState state;
  final MerchantModel? store;
  final Future<void> Function() onTap;
  final Future<void> Function() onRetry;

  const BestStoreSpotlight({
    super.key,
    required this.state,
    required this.store,
    required this.onTap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    Widget content;
    switch (state) {
      case OpenStoresUiState.loading:
        content = const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
        break;
      case OpenStoresUiState.error:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              '\u062A\u0639\u0630\u0631 \u062A\u062D\u0645\u064A\u0644 \u0623\u0641\u0636\u0644 \u0645\u062A\u062C\u0631 \u062D\u0627\u0644\u064A\u0627\u064B',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(
                  '\u0625\u0639\u0627\u062F\u0629 \u0627\u0644\u0645\u062D\u0627\u0648\u0644\u0629',
                ),
              ),
            ),
          ],
        );
        break;
      case OpenStoresUiState.empty:
        content = const _SimpleEmptyState(
          title:
              '\u0644\u0627 \u062A\u0648\u062C\u062F \u0645\u062A\u0627\u062C\u0631 \u0645\u0641\u062A\u0648\u062D\u0629 \u0627\u0644\u0622\u0646',
          subtitle:
              '\u0633\u0646\u0639\u0631\u0636 \u0623\u0641\u0636\u0644 \u0645\u062A\u062C\u0631 \u0647\u0646\u0627 \u0641\u0648\u0631 \u062A\u0648\u0641\u0631 \u0645\u062A\u0627\u062C\u0631 \u0645\u0641\u062A\u0648\u062D\u0629.',
        );
        break;
      case OpenStoresUiState.ready:
        final bestStore = store;
        if (bestStore == null) {
          content = const _SimpleEmptyState(
            title:
                '\u0644\u0627 \u062A\u0648\u062C\u062F \u0645\u062A\u0627\u062C\u0631 \u0645\u0641\u062A\u0648\u062D\u0629 \u0627\u0644\u0622\u0646',
            subtitle:
                '\u064A\u0645\u0643\u0646\u0643 \u062A\u062D\u062F\u064A\u062B \u0627\u0644\u0635\u0641\u062D\u0629 \u0644\u0627\u062D\u0642\u0627\u064B.',
          );
          break;
        }
        content = InkWell(
          key: const Key('best-store-spotlight-card'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color.alphaBlend(
                    visual.accentGold.withValues(alpha: 0.24),
                    tokens.surfaceSecondary.withValues(alpha: 0.94),
                  ),
                  Color.alphaBlend(
                    visual.accentBlue.withValues(alpha: 0.18),
                    tokens.cardPrimary.withValues(alpha: 0.9),
                  ),
                ],
              ),
              border: Border.all(
                color: visual.accentGold.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  child: (bestStore.imageUrl ?? '').trim().isNotEmpty
                      ? CachedAppImage(
                          imageUrl: bestStore.imageUrl!,
                          cacheIdentity: 'best_store_${bestStore.id}',
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Icon(
                            Icons.storefront_rounded,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.local_fire_department_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 184,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '\u0623\u0641\u0636\u0644 \u0645\u062A\u062C\u0631 \u0627\u0644\u0622\u0646',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              bestStore.name,
                              textDirection: TextDirection.rtl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '\u0627\u0628\u062F\u0623 \u0627\u0644\u062A\u0635\u0641\u062D',
                                  style: TextStyle(
                                    color: visual.accentCyan,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Icon(
                                  Icons.arrow_back_rounded,
                                  size: 15,
                                  color: visual.accentCyan,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          title:
              '\u0648\u0627\u062C\u0647\u0629 \u0623\u0641\u0636\u0644 \u0645\u062A\u062C\u0631',
        ),
        const SizedBox(height: 12),
        Container(
          key: const Key('best-store-spotlight'),
          padding: const EdgeInsets.all(12),
          decoration: _homePanelDecoration(context),
          child: content,
        ),
      ],
    );
  }
}

class OpenNowStoresSection extends StatelessWidget {
  final OpenStoresUiState state;
  final List<MerchantModel> stores;
  final String? errorText;
  final Future<void> Function() onRetry;
  final Future<void> Function(MerchantModel store) onStoreTap;

  const OpenNowStoresSection({
    super.key,
    required this.state,
    required this.stores,
    required this.errorText,
    required this.onRetry,
    required this.onStoreTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    switch (state) {
      case OpenStoresUiState.loading:
        content = const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
        break;
      case OpenStoresUiState.ready:
        final cardWidth = (MediaQuery.of(context).size.width * 0.72)
            .clamp(200.0, 270.0)
            .toDouble();
        content = SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: stores.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              return SizedBox(
                width: cardWidth,
                child: OpenNowStoreCard(
                  store: stores[index],
                  onTap: () => onStoreTap(stores[index]),
                ),
              );
            },
          ),
        );
        break;
      case OpenStoresUiState.empty:
        content = const _SimpleEmptyState(
          title:
              '\u0644\u0627 \u062A\u0648\u062C\u062F \u0645\u062A\u0627\u062C\u0631 \u0645\u0641\u062A\u0648\u062D\u0629 \u0627\u0644\u0622\u0646',
          subtitle:
              '\u062C\u0631\u0651\u0628 \u0627\u0644\u062A\u062D\u062F\u064A\u062B \u0628\u0639\u062F \u0642\u0644\u064A\u0644 \u0644\u0639\u0631\u0636 \u0627\u0644\u0645\u062A\u0627\u062C\u0631 \u0627\u0644\u0645\u062A\u0627\u062D\u0629.',
        );
        break;
      case OpenStoresUiState.error:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              '\u062A\u0639\u0630\u0631 \u062A\u062D\u0645\u064A\u0644 \u0627\u0644\u0645\u062A\u0627\u062C\u0631 \u0627\u0644\u0645\u0641\u062A\u0648\u062D\u0629 \u0627\u0644\u0622\u0646',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              (errorText ?? '').trim().isEmpty
                  ? '\u062D\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062E\u0631\u0649'
                  : errorText!,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(
                  '\u0625\u0639\u0627\u062F\u0629 \u0627\u0644\u0645\u062D\u0627\u0648\u0644\u0629',
                ),
              ),
            ),
          ],
        );
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          title:
              '\u0627\u0644\u0645\u062A\u0627\u062C\u0631 \u0627\u0644\u0645\u0641\u062A\u0648\u062D\u0629 \u0627\u0644\u0622\u0646',
        ),
        const SizedBox(height: 12),
        Container(
          key: const Key('open-now-stores-section'),
          padding: const EdgeInsets.all(12),
          decoration: _homePanelDecoration(context),
          child: content,
        ),
      ],
    );
  }
}

class OpenNowStoreCard extends StatelessWidget {
  final MerchantModel store;
  final VoidCallback onTap;

  const OpenNowStoreCard({super.key, required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    final rating = store.avgMerchantRating;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color.alphaBlend(
                visual.accentBlue.withValues(alpha: 0.18),
                tokens.surfaceSecondary.withValues(alpha: 0.9),
              ),
              Color.alphaBlend(
                visual.accentViolet.withValues(alpha: 0.14),
                tokens.cardPrimary.withValues(alpha: 0.86),
              ),
            ],
          ),
          border: Border.all(
            color: tokens.borderSubtle.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              width: 58,
              height: 58,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: Colors.white.withValues(alpha: 0.1),
              ),
              child: (store.imageUrl ?? '').trim().isNotEmpty
                  ? CachedAppImage(
                      imageUrl: store.imageUrl!,
                      cacheIdentity: 'merchant_${store.id}',
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => const Icon(
                        Icons.storefront_rounded,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.storefront_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    store.name,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (store.activityType.isNotEmpty
                            ? store.activityType
                            : store.type)
                        .replaceAll('_', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomRight,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 9,
                          runSpacing: 5,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: const Color(
                                  0xFF0FA958,
                                ).withValues(alpha: 0.2),
                                border: Border.all(
                                  color: const Color(
                                    0xFF30C978,
                                  ).withValues(alpha: 0.45),
                                ),
                              ),
                              child: const Text(
                                '\u0645\u0641\u062A\u0648\u062D \u0627\u0644\u0622\u0646',
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  color: Color(0xFF7FF0AE),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (rating != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    size: 14,
                                    color: visual.accentGold,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    rating.toStringAsFixed(1),
                                    style: TextStyle(
                                      color: tokens.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecentActivitySection extends StatelessWidget {
  final AsyncValue<RecentActivityModel?> state;
  final Future<void> Function(RecentActivityModel activity) onTap;

  const RecentActivitySection({
    super.key,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (state.isLoading) {
      child = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      final activity = state.valueOrNull;
      if (activity == null) {
        child = _SimpleEmptyState(
          title: context.lt(
            ar: 'ابدأ رحلتك في مسلكي من الأقسام أعلاه',
            en: 'Start exploring Maslaki from the sections above',
          ),
          subtitle: context.lt(
            ar: 'سنُظهر هنا آخر ما تصفحته فور استخدامك لأي قسم',
            en: 'Your latest browsing activity will appear here as soon as you use any section',
          ),
        );
      } else {
        child = RecentActivityCard(
          activity: activity,
          onTap: () => onTap(activity),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: context.lt(ar: 'آخر ما تصفحت', en: 'Recently viewed'),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: _homePanelDecoration(context),
          child: child,
        ),
      ],
    );
  }
}

class RecentActivityCard extends StatelessWidget {
  final RecentActivityModel activity;
  final VoidCallback onTap;

  const RecentActivityCard({
    super.key,
    required this.activity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color.alphaBlend(
                visual.accentViolet.withValues(alpha: 0.2),
                tokens.surfaceSecondary.withValues(alpha: 0.92),
              ),
              Color.alphaBlend(
                visual.accentBlue.withValues(alpha: 0.16),
                tokens.cardPrimary.withValues(alpha: 0.88),
              ),
            ],
          ),
          border: Border.all(
            color: tokens.borderSubtle.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFF385472)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: const Icon(Icons.history_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 208,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          activity.resolveTitle(context),
                          textDirection: Directionality.of(context),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          activity.resolveSubtitle(context),
                          textDirection: Directionality.of(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 14,
              color: tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSmartShortcutCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _HomeSmartShortcutCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;

    return SizedBox(
      width: 208,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color.alphaBlend(
                  visual.accentGold.withValues(alpha: 0.12),
                  tokens.surfaceSecondary.withValues(alpha: 0.92),
                ),
                Color.alphaBlend(
                  visual.accentBlue.withValues(alpha: 0.18),
                  tokens.cardPrimary.withValues(alpha: 0.9),
                ),
              ],
            ),
            border: Border.all(
              color: tokens.borderSubtle.withValues(alpha: 0.65),
            ),
            boxShadow: [
              BoxShadow(
                color: visual.accentGold.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.primaryAccent.withValues(alpha: 0.14),
                    border: Border.all(
                      color: tokens.primaryAccent.withValues(alpha: 0.34),
                    ),
                  ),
                  child: Icon(icon, color: tokens.primaryAccent, size: 19),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomRight,
                    child: SizedBox(
                      width: 188,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            title,
                            textDirection: TextDirection.rtl,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              height: 1.12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            textDirection: TextDirection.rtl,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              height: 1.22,
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _SimpleEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SimpleEmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;

    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Expanded(
          child: Text(
            title,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}
