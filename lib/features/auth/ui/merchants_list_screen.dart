import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/widgets/loading_skeletons.dart';
import '../../../core/utils/parsers.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/maslaki_user_drawer.dart';
import '../../behavior/data/behavior_api.dart';
import '../../merchants/models/merchant_discovery_model.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/models/store_activity_model.dart';
import '../../merchants/state/customer_merchant_prefs_controller.dart';
import '../../merchants/state/merchant_discovery_controller.dart';
import '../../merchants/state/merchants_controller.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../../orders/state/cart_controller.dart';
import '../../orders/state/delivery_address_controller.dart';
import '../../orders/ui/cart_screen.dart';
import '../../orders/ui/customer_orders_screen.dart';
import '../../orders/ui/delivery_addresses_screen.dart';
import '../../coupons/ui/customer_coupons_hub_screen.dart';
import '../../taxi/ui/taxi_customer_tools_screen.dart';
import '../../customer/models/customer_ad_board_item.dart';
import '../../customer/state/customer_ad_board_controller.dart';
import '../../customer/ui/widgets/marketplace_ad_card.dart';
import '../state/auth_controller.dart';
import 'add_merchant_screen.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class MerchantsListScreen extends ConsumerStatefulWidget {
  final String? initialType;
  final String? initialActivityType;
  final String? initialDiscoverySubcategory;
  final String? initialDepartment;
  final String initialSearchQuery;
  final List<String> requiredAnyKeywords;
  final String? overrideTitle;
  final bool compactCustomerMode;
  final bool applyInitialSearchQuery;

  /// When true this list is a strict single-category surface: unrelated stores
  /// are NEVER appended as fallback. Use for every specific category page so a
  /// pharmacy/restaurant/general store can never leak into e.g. the clothing
  /// page. The general "all stores" surface leaves this false.
  final bool strictCategoryMode;

  const MerchantsListScreen({
    super.key,
    this.initialType,
    this.initialActivityType,
    this.initialDiscoverySubcategory,
    this.initialDepartment,
    this.initialSearchQuery = '',
    this.requiredAnyKeywords = const [],
    this.overrideTitle,
    this.compactCustomerMode = false,
    this.applyInitialSearchQuery = true,
    this.strictCategoryMode = false,
  });

  @override
  ConsumerState<MerchantsListScreen> createState() =>
      _MerchantsListScreenState();
}

enum _CustomerMerchantSort { recommended, openFirst, offersFirst, alphabetical }

enum _DiscoveryMode { quick, savings, favorites, surprise }

class _MerchantsListScreenState extends ConsumerState<MerchantsListScreen> {
  static const int _promoItemCount = 3;

  static List<_PromoItem> _promoItems(BuildContext context) {
    final l10n = context.l10n;
    return <_PromoItem>[
      _PromoItem(
        title: l10n.customerDiscoveryBannerOfferTitle,
        subtitle: l10n.customerDiscoveryBannerOfferSubtitle,
        icon: Icons.local_offer_rounded,
      ),
      _PromoItem(
        title: l10n.merchantListPromoFastDeliveryTitle,
        subtitle: l10n.merchantListPromoFastDeliverySubtitle,
        icon: Icons.delivery_dining_rounded,
      ),
      _PromoItem(
        title: l10n.merchantListPromoNeighborhoodTitle,
        subtitle: l10n.merchantListPromoNeighborhoodSubtitle,
        icon: Icons.storefront_rounded,
      ),
    ];
  }

  String? filterType;
  String? selectedActivityType;
  String? selectedDiscoverySubcategory;
  String searchQuery = '';
  bool openNowOnly = false;
  bool favoritesOnly = false;
  _CustomerMerchantSort sortBy = _CustomerMerchantSort.recommended;
  _DiscoveryMode? activeDiscoveryMode;
  bool surprisePicking = false;
  int? highlightedMerchantId;
  String? _serverSideSearch;
  late final List<String> _requiredKeywords;
  late final bool _seededKeywordIntent;
  late final String _normalizedInitialSearchQuery;
  List<StoreActivityModel> _activities = const <StoreActivityModel>[];
  List<StoreDiscoveryOptionModel> _discoveryOptions =
      const <StoreDiscoveryOptionModel>[];

  final searchCtrl = TextEditingController();
  final promoController = PageController(viewportFraction: 0.92);
  Timer? promoTimer;
  int promoPage = 0;
  String? _lastTrackedBrowseSignature;

  String? _normalizeNullableToken(String? value) {
    final normalized = normalizeText(value ?? '').trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }

  @override
  void initState() {
    super.initState();
    filterType = widget.initialType;
    selectedActivityType = _normalizeNullableToken(widget.initialActivityType);
    selectedDiscoverySubcategory = _normalizeNullableToken(
      widget.initialDiscoverySubcategory,
    );
    _normalizedInitialSearchQuery = normalizeText(
      widget.initialSearchQuery,
    ).trim();
    _requiredKeywords = widget.requiredAnyKeywords
        .map((e) => normalizeText(e).trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    _seededKeywordIntent =
        widget.compactCustomerMode && _requiredKeywords.isNotEmpty;
    searchQuery = widget.applyInitialSearchQuery && !_seededKeywordIntent
        ? _normalizedInitialSearchQuery
        : '';
    _serverSideSearch = searchQuery.isEmpty ? null : searchQuery;
    if (searchQuery.isNotEmpty) {
      searchCtrl.text = searchQuery;
      searchCtrl.selection = TextSelection.collapsed(
        offset: searchQuery.length,
      );
    }
    Future.microtask(() async {
      final auth = ref.read(authControllerProvider);
      final userId = auth.user?.id;

      await ref
          .read(merchantsControllerProvider.notifier)
          .loadWithFilters(
            type: filterType,
            search: _serverSideSearch,
            activityType: selectedActivityType,
            discoverySubcategory: selectedDiscoverySubcategory,
            department: widget.initialDepartment,
          );
      await ref.read(deliveryAddressControllerProvider.notifier).bootstrap();
      await _loadDiscoveryForType(auth: auth, type: filterType);
      await _loadActivityFilters();
      if (!auth.isBackoffice &&
          !auth.isOwner &&
          !auth.isDelivery &&
          userId != null) {
        await ref
            .read(customerMerchantPrefsProvider.notifier)
            .bootstrap(userId: userId);
      }
      await _trackBrowseSurface();
    });
    promoTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !promoController.hasClients) return;
      promoPage = (promoPage + 1) % _promoItemCount;
      promoController.animateToPage(
        promoPage,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
      setState(() {});
    });
  }

  @override
  void dispose() {
    promoTimer?.cancel();
    promoController.dispose();
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCart() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  Future<void> _openOrders() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CustomerOrdersScreen()));
  }

  Future<void> _openTaxiTools(int tab) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaxiCustomerToolsScreen(initialTab: tab),
      ),
    );
  }

  Future<void> _openCouponsHub() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CustomerCouponsHubScreen()));
  }

  String _resolvedBrowseRoute() {
    final type = (filterType ?? widget.initialType ?? '').trim().toLowerCase();
    final route = type == 'market' ? 'main_market' : 'shopping';
    final params = <String, String>{};
    if ((filterType ?? widget.initialType ?? '').trim().isNotEmpty) {
      params['type'] = (filterType ?? widget.initialType ?? '').trim();
    }
    if ((selectedActivityType ?? '').trim().isNotEmpty) {
      params['activityType'] = selectedActivityType!.trim();
    }
    if ((selectedDiscoverySubcategory ?? '').trim().isNotEmpty) {
      params['discoverySubcategory'] = selectedDiscoverySubcategory!.trim();
    }
    final title = _resolvedBrowseTitle().trim();
    if (title.isNotEmpty) {
      params['title'] = title;
    }
    if (params.isEmpty) {
      return route;
    }
    return Uri(path: route, queryParameters: params).toString();
  }

  String _resolvedBrowseTitle() {
    final override = (widget.overrideTitle ?? '').trim();
    if (override.isNotEmpty) {
      return override;
    }
    final activity = selectedActivityType;
    if (activity != null && activity.isNotEmpty) {
      for (final item in _activities) {
        if (item.activityType == activity) {
          return item.localizedLabel(
            Directionality.of(context) == TextDirection.rtl,
          );
        }
      }
    }
    final type = (filterType ?? widget.initialType ?? '').trim().toLowerCase();
    if (type == 'market') {
      return 'كل السوق';
    }
    if (type == 'restaurant') {
      return 'المطاعم';
    }
    return 'التسوق';
  }

  Future<void> _trackBrowseSurface() async {
    if (!mounted) return;
    final title = _resolvedBrowseTitle();
    final signature = [
      filterType ?? widget.initialType ?? '',
      selectedActivityType ?? '',
      selectedDiscoverySubcategory ?? '',
      widget.overrideTitle ?? '',
    ].join('|');
    if (_lastTrackedBrowseSignature == signature) {
      return;
    }
    _lastTrackedBrowseSignature = signature;
    await ref
        .read(behaviorApiProvider)
        .trackEvent(
          eventName: 'shopping.catalog_open',
          category: 'shopping',
          action: 'browse_catalog',
          metadata: {
            'type': filterType ?? widget.initialType,
            'activityType': selectedActivityType,
            'discoverySubcategory': selectedDiscoverySubcategory,
            'route': _resolvedBrowseRoute(),
            'screenLabel': title,
            'recentTitle': 'كنت تتصفح $title',
            'recentSubtitle': 'اضغط للعودة إلى $title',
          },
        );
  }

  Future<void> _refresh() {
    final auth = ref.read(authControllerProvider);
    return Future.wait([
      ref
          .read(merchantsControllerProvider.notifier)
          .loadWithFilters(
            type: filterType,
            search: _serverSideSearch,
            activityType: selectedActivityType,
            discoverySubcategory: selectedDiscoverySubcategory,
          ),
      _loadDiscoveryForType(auth: auth, type: filterType, force: true),
      _loadActivityFilters(force: true),
    ]).then((_) => _trackBrowseSurface());
  }

  void _onChangeType(String? value) {
    if (filterType == value) return;
    setState(() {
      filterType = value;
      selectedActivityType = null;
      selectedDiscoverySubcategory = null;
      _discoveryOptions = const <StoreDiscoveryOptionModel>[];
    });
    ref
        .read(merchantsControllerProvider.notifier)
        .loadWithFilters(
          type: value,
          search: _serverSideSearch,
          activityType: selectedActivityType,
          discoverySubcategory: selectedDiscoverySubcategory,
        );
    _loadDiscoveryForType(auth: ref.read(authControllerProvider), type: value);
    _loadActivityFilters(force: true);
    unawaited(_trackBrowseSurface());
  }

  bool _isCustomerView(AuthState auth) {
    return !auth.isBackoffice && !auth.isOwner && !auth.isDelivery;
  }

  bool _shouldUseCategoryDiscovery(AuthState auth, String? type) {
    return _isCustomerView(auth) &&
        widget.compactCustomerMode &&
        type != null &&
        type.trim().isNotEmpty;
  }

  Future<void> _loadDiscoveryForType({
    required AuthState auth,
    required String? type,
    bool force = false,
  }) async {
    if (_shouldUseCategoryDiscovery(auth, type)) {
      await ref
          .read(merchantDiscoveryControllerProvider.notifier)
          .load(type: type, force: force);
      return;
    }
    await ref.read(merchantDiscoveryControllerProvider.notifier).clear();
  }

  Future<void> _loadActivityFilters({bool force = false}) async {
    try {
      if (_activities.isNotEmpty && !force) {
        await _loadDiscoveryOptionsForSelectedActivity(force: force);
        return;
      }
      final controller = ref.read(merchantsControllerProvider.notifier);
      final activities = await controller.listActivities();
      if (!mounted) return;
      final currentType = filterType?.trim();
      final visible = currentType == null || currentType.isEmpty
          ? activities
          : activities
                .where((activity) => activity.baseType == currentType)
                .toList();
      final prioritizedVisible = _prioritizeActivities(
        visible,
        currentType: currentType,
      );
      final hasSelected =
          selectedActivityType != null &&
          prioritizedVisible.any(
            (activity) => activity.activityType == selectedActivityType,
          );
      setState(() {
        _activities = prioritizedVisible;
        if (!hasSelected) {
          selectedActivityType = null;
          selectedDiscoverySubcategory = null;
        }
      });
      await _loadDiscoveryOptionsForSelectedActivity(force: force);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activities = const <StoreActivityModel>[];
        selectedActivityType = null;
        selectedDiscoverySubcategory = null;
        _discoveryOptions = const <StoreDiscoveryOptionModel>[];
      });
    }
  }

  List<StoreActivityModel> _prioritizeActivities(
    List<StoreActivityModel> source, {
    required String? currentType,
  }) {
    if (source.length <= 1) return source;
    final normalizedType = normalizeText(
      currentType ?? '',
    ).trim().toLowerCase();
    if (normalizedType.isNotEmpty && normalizedType != 'market') {
      return source;
    }
    final list = <StoreActivityModel>[...source];
    final pharmacyIndex = list.indexWhere(
      (item) => item.activityType == 'pharmacy',
    );
    if (pharmacyIndex <= 0) return list;
    final pharmacy = list.removeAt(pharmacyIndex);
    list.insert(0, pharmacy);
    return list;
  }

  Future<void> _loadDiscoveryOptionsForSelectedActivity({
    bool force = false,
  }) async {
    final activity = selectedActivityType;
    if (activity == null || activity.isEmpty) {
      if (!mounted) return;
      setState(() {
        _discoveryOptions = const <StoreDiscoveryOptionModel>[];
        selectedDiscoverySubcategory = null;
      });
      return;
    }
    StoreActivityModel? target;
    for (final item in _activities) {
      if (item.activityType == activity) {
        target = item;
        break;
      }
    }
    if (target == null || !target.hasDiscoverySubcategories) {
      if (!mounted) return;
      setState(() {
        _discoveryOptions = const <StoreDiscoveryOptionModel>[];
        selectedDiscoverySubcategory = null;
      });
      return;
    }
    if (_discoveryOptions.isNotEmpty && !force) return;
    try {
      final controller = ref.read(merchantsControllerProvider.notifier);
      final options = await controller.listDiscoveryOptions(
        activityType: activity,
      );
      if (!mounted) return;
      final hasSelected =
          selectedDiscoverySubcategory != null &&
          options.any((item) => item.code == selectedDiscoverySubcategory);
      setState(() {
        _discoveryOptions = options;
        if (!hasSelected) selectedDiscoverySubcategory = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _discoveryOptions = const <StoreDiscoveryOptionModel>[];
        selectedDiscoverySubcategory = null;
      });
    }
  }

  Future<void> _onSelectActivityType(String? value) async {
    final normalized = _normalizeNullableToken(value);
    if (selectedActivityType == normalized) return;
    setState(() {
      selectedActivityType = normalized;
      selectedDiscoverySubcategory = null;
      _discoveryOptions = const <StoreDiscoveryOptionModel>[];
    });
    await _loadDiscoveryOptionsForSelectedActivity(force: true);
    if (!mounted) return;
    await ref
        .read(merchantsControllerProvider.notifier)
        .loadWithFilters(
          type: filterType,
          search: _serverSideSearch,
          activityType: selectedActivityType,
          discoverySubcategory: selectedDiscoverySubcategory,
        );
    await _trackBrowseSurface();
  }

  Future<void> _onSelectDiscoverySubcategory(String? value) async {
    final normalized = _normalizeNullableToken(value);
    if (selectedDiscoverySubcategory == normalized) return;
    setState(() => selectedDiscoverySubcategory = normalized);
    await ref
        .read(merchantsControllerProvider.notifier)
        .loadWithFilters(
          type: filterType,
          search: _serverSideSearch,
          activityType: selectedActivityType,
          discoverySubcategory: selectedDiscoverySubcategory,
        );
    await _trackBrowseSurface();
  }

  String _resolvedSearchHintText() {
    final l10n = context.l10n;
    final title = (widget.overrideTitle ?? '').trim();
    if (title.isNotEmpty) {
      return l10n.merchantListSearchHintFor(title);
    }

    final currentType = filterType ?? widget.initialType;
    if (currentType == 'market') {
      return l10n.merchantListSearchHintMarket;
    }
    return l10n.merchantListSearchHintRestaurant;
  }

  List<MerchantModel> _applySearch(
    List<MerchantModel> list,
    Set<int> favoriteMerchantIds,
    Map<int, double> insightScoreByMerchantId,
  ) {
    final q = normalizeText(searchQuery).trim().toLowerCase();
    final hasExplicitSearch = q.isNotEmpty;
    var filtered = q.isEmpty
        ? list
        : list.where((merchant) {
            final haystack = normalizeText(
              '${merchant.name} ${merchant.description ?? ''} '
              '${merchant.tagline ?? ''} ${merchant.phone ?? ''}',
            ).toLowerCase();
            return haystack.contains(q);
          }).toList();

    if (openNowOnly) {
      filtered = filtered.where((merchant) => merchant.isOpen).toList();
    }
    if (favoritesOnly) {
      filtered = filtered
          .where((merchant) => favoriteMerchantIds.contains(merchant.id))
          .toList();
    }
    final sorted = _sortMerchants(
      filtered,
      favoriteMerchantIds,
      insightScoreByMerchantId,
    );
    if (_requiredKeywords.isEmpty || hasExplicitSearch) {
      return sorted;
    }

    final matched = <MerchantModel>[];
    final fallback = <MerchantModel>[];
    for (final merchant in sorted) {
      if (_matchesSeedIntent(merchant)) {
        matched.add(merchant);
      } else {
        fallback.add(merchant);
      }
    }
    // Strict category pages must never surface unrelated fallback stores.
    // The keyword intent is used only to rank within the already
    // activityType-filtered result set.
    if (widget.strictCategoryMode) {
      return matched;
    }
    return [...matched, ...fallback];
  }

  void _clearCustomerFilters() {
    searchCtrl.clear();
    setState(() {
      searchQuery = '';
      openNowOnly = false;
      favoritesOnly = false;
      sortBy = _CustomerMerchantSort.recommended;
      activeDiscoveryMode = null;
      highlightedMerchantId = null;
      selectedActivityType = null;
      selectedDiscoverySubcategory = null;
      _discoveryOptions = const <StoreDiscoveryOptionModel>[];
    });
    ref
        .read(merchantsControllerProvider.notifier)
        .loadWithFilters(
          type: filterType,
          search: _serverSideSearch,
          activityType: selectedActivityType,
          discoverySubcategory: selectedDiscoverySubcategory,
        );
  }

  bool _matchesSeedIntent(MerchantModel merchant) {
    if (_requiredKeywords.isEmpty) return false;
    final haystack = normalizeText(
      '${merchant.name} ${merchant.description ?? ''} ${merchant.tagline ?? ''} ${merchant.phone ?? ''}',
    ).toLowerCase();
    return _requiredKeywords.any(haystack.contains);
  }

  List<MerchantModel> _sortMerchants(
    List<MerchantModel> merchants,
    Set<int> favoriteMerchantIds,
    Map<int, double> insightScoreByMerchantId,
  ) {
    final sorted = [...merchants];
    int compareByName(MerchantModel a, MerchantModel b) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    int compareByOpen(MerchantModel a, MerchantModel b) {
      final openDiff = (b.isOpen ? 1 : 0).compareTo(a.isOpen ? 1 : 0);
      if (openDiff != 0) return openDiff;
      return compareByName(a, b);
    }

    switch (sortBy) {
      case _CustomerMerchantSort.openFirst:
        sorted.sort(compareByOpen);
        return sorted;
      case _CustomerMerchantSort.offersFirst:
        sorted.sort((a, b) {
          final offerA =
              ((a.hasDiscountOffer ? 1 : 0) + (a.hasFreeDeliveryOffer ? 1 : 0));
          final offerB =
              ((b.hasDiscountOffer ? 1 : 0) + (b.hasFreeDeliveryOffer ? 1 : 0));
          final offerDiff = offerB.compareTo(offerA);
          if (offerDiff != 0) return offerDiff;
          return compareByOpen(a, b);
        });
        return sorted;
      case _CustomerMerchantSort.alphabetical:
        sorted.sort(compareByName);
        return sorted;
      case _CustomerMerchantSort.recommended:
        sorted.sort((a, b) {
          final scoreA = _merchantScore(
            a,
            favoriteMerchantIds,
            insightScoreByMerchantId,
          );
          final scoreB = _merchantScore(
            b,
            favoriteMerchantIds,
            insightScoreByMerchantId,
          );
          final scoreDiff = scoreB.compareTo(scoreA);
          if (scoreDiff != 0) return scoreDiff;
          return compareByName(a, b);
        });
        return sorted;
    }
  }

  int _merchantScore(
    MerchantModel merchant,
    Set<int> favoriteMerchantIds,
    Map<int, double> insightScoreByMerchantId,
  ) {
    var score = insightScoreByMerchantId[merchant.id]?.round() ?? 0;
    if (favoriteMerchantIds.contains(merchant.id)) score += 80;
    if (merchant.isOpen) score += 40;
    if (merchant.hasDiscountOffer) score += 20;
    if (merchant.hasFreeDeliveryOffer) score += 16;
    if (merchant.type == 'restaurant') score += 4;
    return score;
  }

  List<MerchantModel> _recommendedMerchants(
    List<MerchantModel> list,
    Set<int> favoriteMerchantIds,
    Map<int, double> insightScoreByMerchantId,
  ) {
    final sorted = _sortMerchants(
      list,
      favoriteMerchantIds,
      insightScoreByMerchantId,
    );
    return sorted.take(5).toList();
  }

  List<MerchantModel> _recentlyViewedMerchants(
    List<MerchantModel> list,
    List<int> recentIds,
  ) {
    if (recentIds.isEmpty) return const <MerchantModel>[];
    final byId = <int, MerchantModel>{for (final m in list) m.id: m};
    return recentIds
        .map((id) => byId[id])
        .whereType<MerchantModel>()
        .take(8)
        .toList();
  }

  List<MerchantModel> _storyMerchants(
    List<MerchantModel> list,
    Set<int> favoriteMerchantIds,
    Map<int, double> insightScoreByMerchantId,
  ) {
    return _sortMerchants(
      list,
      favoriteMerchantIds,
      insightScoreByMerchantId,
    ).take(10).toList();
  }

  String _greetingByHour(BuildContext context, int hour) {
    final l10n = context.l10n;
    if (hour < 6) return l10n.merchantListGreetingLateNight;
    if (hour < 12) return l10n.merchantListGreetingMorning;
    if (hour < 17) return l10n.merchantListGreetingAfternoon;
    if (hour < 22) return l10n.merchantListGreetingEvening;
    return l10n.merchantListGreetingBismayahNight;
  }

  ({String label, Color color, double score}) _cityPulse(
    BuildContext context, {
    required int hour,
    required int openCount,
    required int offersCount,
    required int totalCount,
  }) {
    final l10n = context.l10n;
    final openRatio = totalCount <= 0 ? 0.0 : openCount / totalCount;
    final offerRatio = totalCount <= 0 ? 0.0 : offersCount / totalCount;
    final hourBias = (hour >= 12 && hour <= 23) ? 0.22 : 0.12;
    final score = (openRatio * 0.58 + offerRatio * 0.30 + hourBias).clamp(
      0.05,
      1.0,
    );
    if (score >= 0.72) {
      return (
        label: l10n.merchantListPulsePeakDemand,
        color: const Color(0xFF2DD881),
        score: score,
      );
    }
    if (score >= 0.42) {
      return (
        label: l10n.merchantListPulseModerate,
        color: const Color(0xFFF9C74F),
        score: score,
      );
    }
    return (
      label: l10n.merchantListPulseCalm,
      color: const Color(0xFF56CFE1),
      score: score,
    );
  }

  Future<void> _openMerchant(
    MerchantModel merchant, {
    required int? userId,
  }) async {
    if (userId != null) {
      await ref
          .read(customerMerchantPrefsProvider.notifier)
          .markVisited(userId: userId, merchantId: merchant.id);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantProductsScreen(merchant: merchant),
      ),
    );
  }

  /// Routes a tapped MARKETPLACE_CATEGORY ad to its target store. External links
  /// are handled inside the ad card; store targets are resolved here.
  Future<void> _handleCategoryAdTap(CustomerAdBoardItem ad) async {
    final merchantId = ad.merchantId ?? ad.targetId;
    if (merchantId == null || merchantId <= 0) return;
    try {
      final raw = await ref.read(merchantsApiProvider).getById(merchantId);
      final merchant = MerchantModel.fromJson(raw);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MerchantProductsScreen(merchant: merchant),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر فتح المتجر حالياً')));
    }
  }

  Future<void> _runSurprisePicker({
    required List<MerchantModel> source,
    required Set<int> favoriteMerchantIds,
    required Map<int, double> insightScoreByMerchantId,
    required int? userId,
  }) async {
    if (surprisePicking) return;
    final ranked = _sortMerchants(
      source,
      favoriteMerchantIds,
      insightScoreByMerchantId,
    );
    final openPool = ranked.where((merchant) => merchant.isOpen).toList();
    final pool = openPool.isNotEmpty ? openPool : ranked;

    if (pool.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.merchantListNoStores)),
      );
      return;
    }

    setState(() {
      surprisePicking = true;
      activeDiscoveryMode = _DiscoveryMode.surprise;
    });

    final rng = math.Random();
    for (var i = 0; i < 12; i++) {
      if (!mounted) return;
      final candidate = pool[rng.nextInt(pool.length)];
      setState(() => highlightedMerchantId = candidate.id);
      await Future.delayed(const Duration(milliseconds: 90));
    }

    if (!mounted) return;
    final chosen = pool[rng.nextInt(pool.length)];
    setState(() => highlightedMerchantId = chosen.id);
    await Future.delayed(const Duration(milliseconds: 340));
    if (!mounted) return;
    setState(() => surprisePicking = false);
    await _openMerchant(chosen, userId: userId);
  }

  Future<void> _applyDiscoveryMode(
    _DiscoveryMode mode, {
    required List<MerchantModel> source,
    required Set<int> favoriteMerchantIds,
    required Map<int, double> insightScoreByMerchantId,
    required int? userId,
  }) async {
    switch (mode) {
      case _DiscoveryMode.quick:
        setState(() {
          activeDiscoveryMode = mode;
          openNowOnly = true;
          favoritesOnly = false;
          sortBy = _CustomerMerchantSort.openFirst;
        });
        return;
      case _DiscoveryMode.savings:
        setState(() {
          activeDiscoveryMode = mode;
          openNowOnly = false;
          favoritesOnly = false;
          sortBy = _CustomerMerchantSort.offersFirst;
        });
        return;
      case _DiscoveryMode.favorites:
        setState(() {
          activeDiscoveryMode = mode;
          favoritesOnly = true;
          sortBy = _CustomerMerchantSort.recommended;
        });
        return;
      case _DiscoveryMode.surprise:
        await _runSurprisePicker(
          source: source,
          favoriteMerchantIds: favoriteMerchantIds,
          insightScoreByMerchantId: insightScoreByMerchantId,
          userId: userId,
        );
        return;
    }
  }

  List<MerchantModel> _resolveRankedMerchants(
    List<int> rankedIds,
    Map<int, MerchantModel> byId, {
    int limit = 8,
  }) {
    return rankedIds
        .map((id) => byId[id])
        .whereType<MerchantModel>()
        .take(limit)
        .toList();
  }

  List<MerchantModel> _resolveReorderMerchants(
    List<MerchantReorderCandidate> rankedItems,
    Map<int, MerchantModel> byId, {
    int limit = 8,
  }) {
    return rankedItems
        .map((item) => byId[item.merchantId])
        .whereType<MerchantModel>()
        .take(limit)
        .toList();
  }

  String _spendingBandText(String value) {
    final l10n = context.l10n;
    switch (value) {
      case 'budget':
        return l10n.merchantListSpendingBandBudget;
      case 'balanced':
        return l10n.merchantListSpendingBandBalanced;
      case 'premium':
        return l10n.merchantListSpendingBandPremium;
      default:
        return l10n.merchantListSpendingBandNew;
    }
  }

  String _priceSensitivityText(String value) {
    final l10n = context.l10n;
    switch (value) {
      case 'high':
        return l10n.merchantListPriceSensitivityHigh;
      case 'low':
        return l10n.merchantListPriceSensitivityLow;
      default:
        return l10n.merchantListPriceSensitivityBalanced;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final merchants = ref.watch(merchantsControllerProvider);
    final discovery = ref.watch(merchantDiscoveryControllerProvider);
    final cart = ref.watch(cartControllerProvider);
    final prefs = ref.watch(customerMerchantPrefsProvider);
    final showCustomerActions =
        !auth.isBackoffice && !auth.isOwner && !auth.isDelivery;
    final showRichDiscovery =
        showCustomerActions && !widget.compactCustomerMode;
    final lockTypeSelection =
        widget.compactCustomerMode && widget.initialType != null;
    final showSecondaryFilters = showCustomerActions && !lockTypeSelection;
    final hasInitialActivityContext = (widget.initialActivityType ?? '')
        .trim()
        .isNotEmpty;
    final normalizedInitialType = (widget.initialType ?? '')
        .trim()
        .toLowerCase();
    final isRestaurantLanding = normalizedInitialType == 'restaurant';
    final isActivityLockedContext =
        hasInitialActivityContext || isRestaurantLanding;
    final showActivityFilters = showCustomerActions && !isActivityLockedContext;
    Future<void> runDrawerAction(Future<void> Function() action) async {
      Navigator.of(context).pop();
      await action();
    }

    final extraDrawerSections = <MaslakiDrawerSection>[
      MaslakiDrawerSection(
        title: showCustomerActions ? 'السوق الحالي' : 'إدارة المتاجر',
        entries: [
          MaslakiDrawerEntry(
            icon: Icons.home_outlined,
            label: l10n.drawerHome,
            onTap: () => runDrawerAction(() async {
              Navigator.of(
                context,
                rootNavigator: true,
              ).popUntil((route) => route.isFirst);
            }),
          ),
          MaslakiDrawerEntry(
            icon: Icons.refresh_rounded,
            label: l10n.drawerRefresh,
            onTap: () => runDrawerAction(_refresh),
          ),
          if (showCustomerActions)
            MaslakiDrawerEntry(
              icon: Icons.receipt_long_rounded,
              label: l10n.customerDiscoveryOrders,
              onTap: () => runDrawerAction(_openOrders),
            ),
          if (showCustomerActions)
            MaslakiDrawerEntry(
              icon: Icons.shopping_cart_outlined,
              label: l10n.drawerCart,
              onTap: () => runDrawerAction(_openCart),
            ),
          if (showCustomerActions)
            MaslakiDrawerEntry(
              icon: Icons.schedule_outlined,
              label: l10n.taxiScheduledRidesTitle,
              onTap: () => runDrawerAction(() => _openTaxiTools(2)),
            ),
          if (showCustomerActions)
            MaslakiDrawerEntry(
              icon: Icons.discount_outlined,
              label: l10n.taxiMyCouponsTitle,
              onTap: () => runDrawerAction(_openCouponsHub),
            ),
          if (auth.isAdmin)
            MaslakiDrawerEntry(
              icon: Icons.add_business_rounded,
              label: l10n.drawerCreateMerchant,
              onTap: () => runDrawerAction(() async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const AddMerchantScreen()),
                );
                if (created == true) {
                  await _refresh();
                }
              }),
            ),
        ],
      ),
    ];

    return Scaffold(
      endDrawer: MaslakiUserDrawer(extraSections: extraDrawerSections),
      appBar: AppBar(
        title: Text(
          widget.overrideTitle ??
              (showCustomerActions
                  ? l10n.customerHomeTitle
                  : l10n.adminBackofficeMerchantsTitle),
        ),
        actions: [
          if (showCustomerActions)
            IconButton(
              tooltip: l10n.customerDiscoveryOrders,
              onPressed: _openOrders,
              icon: const Icon(Icons.receipt_long),
            ),
          if (showCustomerActions)
            IconButton(
              tooltip: l10n.drawerAddresses,
              onPressed: _openAddresses,
              icon: const Icon(Icons.location_on_outlined),
            ),
          if (showCustomerActions)
            _CartButton(totalItems: cart.totalItems, onPressed: _openCart),
          if (showCustomerActions) const NotificationsBellButton(),
          const MaslakiUserDrawerButton(),
        ],
      ),
      floatingActionButton: auth.isAdmin
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const AddMerchantScreen()),
                );
                if (created == true) {
                  await _refresh();
                }
              },
              label: Text(l10n.drawerCreateMerchant),
              icon: const Icon(Icons.add_business_rounded),
            )
          : null,
      body: merchants.when(
        data: (list) {
          if (!showCustomerActions) {
            return _BackofficeMerchantsView(
              merchants: list,
              selectedType: filterType,
              onSelectType: _onChangeType,
              onRefresh: _refresh,
              onOpenMerchant: (merchant) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MerchantProductsScreen(merchant: merchant),
                  ),
                );
              },
            );
          }

          final userId = auth.user?.id;
          final discoveryData = discovery.maybeWhen(
            data: (value) => value,
            orElse: () => null,
          );
          final insightScoreByMerchantId =
              discoveryData?.insightsByMerchantId.map(
                (key, value) => MapEntry(key, value.compositeScore),
              ) ??
              const <int, double>{};
          final filtered = _applySearch(
            list,
            prefs.favoriteMerchantIds,
            insightScoreByMerchantId,
          );
          final normalizedUserSearch = normalizeText(searchQuery).trim();
          final hasUserSearch = normalizedUserSearch.isNotEmpty;
          final hasUserFilters = hasUserSearch || openNowOnly || favoritesOnly;
          final showEmptyInventory = list.isEmpty;
          final showFilteredEmpty = list.isNotEmpty && filtered.isEmpty;
          final recommended = _recommendedMerchants(
            list,
            prefs.favoriteMerchantIds,
            insightScoreByMerchantId,
          );
          final storyMerchants = _storyMerchants(
            list,
            prefs.favoriteMerchantIds,
            insightScoreByMerchantId,
          );
          final recentViewed = _recentlyViewedMerchants(
            list,
            prefs.recentMerchantIds,
          );
          final byMerchantId = <int, MerchantModel>{
            for (final merchant in list) merchant.id: merchant,
          };
          final categoryDiscoveryEnabled =
              widget.compactCustomerMode &&
              (filterType ?? widget.initialType) != null;
          final fastestMerchants = discoveryData == null
              ? const <MerchantModel>[]
              : _resolveRankedMerchants(
                  discoveryData.ranking.fastest,
                  byMerchantId,
                );
          final topRatedMerchants = discoveryData == null
              ? const <MerchantModel>[]
              : _resolveRankedMerchants(
                  discoveryData.ranking.topRated,
                  byMerchantId,
                );
          final bestOffersMerchants = discoveryData == null
              ? const <MerchantModel>[]
              : _resolveRankedMerchants(
                  discoveryData.ranking.bestOffers,
                  byMerchantId,
                );
          final bestValueMerchants = discoveryData == null
              ? const <MerchantModel>[]
              : _resolveRankedMerchants(
                  discoveryData.ranking.bestValue,
                  byMerchantId,
                );
          final mostOrderedMerchants = discoveryData == null
              ? const <MerchantModel>[]
              : _resolveRankedMerchants(
                  discoveryData.ranking.mostOrdered,
                  byMerchantId,
                );
          final reorderMerchants = discoveryData == null
              ? const <MerchantModel>[]
              : _resolveReorderMerchants(
                  discoveryData.ranking.reorder,
                  byMerchantId,
                );
          final openCount = list.where((merchant) => merchant.isOpen).length;
          final offersCount = list
              .where(
                (merchant) =>
                    merchant.hasDiscountOffer || merchant.hasFreeDeliveryOffer,
              )
              .length;
          final cityPulse = _cityPulse(
            context,
            hour: DateTime.now().hour,
            openCount: openCount,
            offersCount: offersCount,
            totalCount: list.length,
          );
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 22),
              children: [
                _BasmayaLocationStrip(onOpenAddresses: _openAddresses),
                const SizedBox(height: 12),
                if (showRichDiscovery) ...[
                  _CityPulseCard(
                    greeting: _greetingByHour(context, DateTime.now().hour),
                    totalMerchants: list.length,
                    openMerchants: openCount,
                    offersCount: offersCount,
                    favoritesCount: prefs.favoriteMerchantIds.length,
                    recentCount: prefs.recentMerchantIds.length,
                    pulseLabel: cityPulse.label,
                    pulseColor: cityPulse.color,
                    pulseScore: cityPulse.score,
                  ),
                  const SizedBox(height: 10),
                ],
                _CustomerQuickActions(
                  openNowOnly: openNowOnly,
                  onToggleOpenNowOnly: (value) =>
                      setState(() => openNowOnly = value),
                  onOpenAddresses: () => _openAddresses(),
                  onOpenOrders: _openOrders,
                  onOpenCart: _openCart,
                  showOpenNowToggle: showRichDiscovery,
                ),
                const SizedBox(height: 10),
                if (showRichDiscovery) ...[
                  _DiscoveryModesPanel(
                    activeMode: activeDiscoveryMode,
                    surprisePicking: surprisePicking,
                    onSelectMode: (mode) => _applyDiscoveryMode(
                      mode,
                      source: list,
                      favoriteMerchantIds: prefs.favoriteMerchantIds,
                      insightScoreByMerchantId: insightScoreByMerchantId,
                      userId: userId,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // MARKETPLACE_CATEGORY ad: targeted at this page's category /
                // activity, with the general ad as fallback; sits above search
                // and collapses fully when there is no eligible ad.
                MarketplaceAdCard(
                  request: MarketplaceAdRequest(
                    placement: 'MARKETPLACE_CATEGORY',
                    type: (filterType ?? widget.initialType)?.trim().isNotEmpty ==
                            true
                        ? (filterType ?? widget.initialType)!.trim()
                        : null,
                    categoryKey:
                        (selectedActivityType ?? widget.initialActivityType)
                                    ?.trim()
                                    .isNotEmpty ==
                                true
                            ? (selectedActivityType ?? widget.initialActivityType)!
                                .trim()
                            : null,
                    activityType:
                        (selectedActivityType ?? widget.initialActivityType)
                                    ?.trim()
                                    .isNotEmpty ==
                                true
                            ? (selectedActivityType ?? widget.initialActivityType)!
                                .trim()
                            : null,
                  ),
                  onTapAd: _handleCategoryAdTap,
                ),
                TextField(
                  controller: searchCtrl,
                  textDirection: TextDirection.rtl,
                  onChanged: (value) => setState(() => searchQuery = value),
                  decoration: InputDecoration(
                    hintText: _resolvedSearchHintText(),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              searchCtrl.clear();
                              setState(() => searchQuery = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                if (showSecondaryFilters) ...[
                  _MerchantDiscoveryToolbar(
                    favoritesOnly: favoritesOnly,
                    sortBy: sortBy,
                    onToggleFavoritesOnly: (value) =>
                        setState(() => favoritesOnly = value),
                    onChangeSort: (value) => setState(() => sortBy = value),
                  ),
                  const SizedBox(height: 14),
                  _CustomerCategoryRail(
                    selectedType: filterType,
                    onSelectType: _onChangeType,
                  ),
                  const SizedBox(height: 10),
                ],
                if (showActivityFilters) ...[
                  _ActivityDiscoveryRail(
                    activities: _activities,
                    discoveryOptions: _discoveryOptions,
                    selectedActivityType: selectedActivityType,
                    selectedDiscoverySubcategory: selectedDiscoverySubcategory,
                    isArabic: Directionality.of(context) == TextDirection.rtl,
                    onSelectActivityType: _onSelectActivityType,
                    onSelectDiscoverySubcategory: _onSelectDiscoverySubcategory,
                  ),
                  const SizedBox(height: 10),
                ],
                if (showRichDiscovery) const SizedBox(height: 14),
                if (showRichDiscovery)
                  _PromoCarousel(
                    controller: promoController,
                    promoItems: _promoItems(context),
                    currentPage: promoPage,
                  ),
                if (categoryDiscoveryEnabled) ...[
                  const SizedBox(height: 14),
                  if (discovery.isLoading)
                    const _CategoryIntelligenceLoadingCard()
                  else if (discovery.hasError)
                    _CategoryIntelligenceErrorCard(
                      onRetry: () => _loadDiscoveryForType(
                        auth: auth,
                        type: filterType ?? widget.initialType,
                        force: true,
                      ),
                    )
                  else if (discoveryData case final data?) ...[
                    _CategoryProfileCard(
                      profile: data.profile,
                      spendingBandText: _spendingBandText(
                        data.profile.spendingBand,
                      ),
                      priceSensitivityText: _priceSensitivityText(
                        data.profile.priceSensitivity,
                      ),
                      merchantCount: list.length,
                    ),
                    const SizedBox(height: 12),
                    if (fastestMerchants.isNotEmpty) ...[
                      _MiniSectionHeader(
                        title: l10n.customerDiscoveryFastestDelivery,
                        subtitle: l10n.merchantListFastestDeliverySubtitle,
                      ),
                      const SizedBox(height: 8),
                      _MerchantQuickRail(
                        merchants: fastestMerchants,
                        favoriteIds: prefs.favoriteMerchantIds,
                        onOpen: (merchant) =>
                            _openMerchant(merchant, userId: userId),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (topRatedMerchants.isNotEmpty) ...[
                      _MiniSectionHeader(
                        title: l10n.customerDiscoveryTopRated,
                        subtitle: l10n.merchantListTopRatedSubtitle,
                      ),
                      const SizedBox(height: 8),
                      _MerchantQuickRail(
                        merchants: topRatedMerchants,
                        favoriteIds: prefs.favoriteMerchantIds,
                        onOpen: (merchant) =>
                            _openMerchant(merchant, userId: userId),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (bestValueMerchants.isNotEmpty) ...[
                      _MiniSectionHeader(
                        title: l10n.customerDiscoveryBestPrice,
                        subtitle: l10n.merchantListBestPriceSubtitle,
                      ),
                      const SizedBox(height: 8),
                      _MerchantQuickRail(
                        merchants: bestValueMerchants,
                        favoriteIds: prefs.favoriteMerchantIds,
                        onOpen: (merchant) =>
                            _openMerchant(merchant, userId: userId),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (bestOffersMerchants.isNotEmpty) ...[
                      _MiniSectionHeader(
                        title: l10n.customerDiscoveryTodayOffers,
                        subtitle: l10n.merchantListTodayOffersSubtitle,
                      ),
                      const SizedBox(height: 8),
                      _MerchantQuickRail(
                        merchants: bestOffersMerchants,
                        favoriteIds: prefs.favoriteMerchantIds,
                        onOpen: (merchant) =>
                            _openMerchant(merchant, userId: userId),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (mostOrderedMerchants.isNotEmpty) ...[
                      _MiniSectionHeader(
                        title: l10n.merchantListMostOrderedTitle,
                        subtitle: l10n.merchantListMostOrderedSubtitle,
                      ),
                      const SizedBox(height: 8),
                      _MerchantQuickRail(
                        merchants: mostOrderedMerchants,
                        favoriteIds: prefs.favoriteMerchantIds,
                        onOpen: (merchant) =>
                            _openMerchant(merchant, userId: userId),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (reorderMerchants.isNotEmpty) ...[
                      _MiniSectionHeader(
                        title: l10n.customerDiscoveryReorder,
                        subtitle: l10n.merchantListReorderSubtitle,
                      ),
                      const SizedBox(height: 8),
                      _MerchantQuickRail(
                        merchants: reorderMerchants,
                        favoriteIds: prefs.favoriteMerchantIds,
                        onOpen: (merchant) =>
                            _openMerchant(merchant, userId: userId),
                      ),
                    ],
                  ],
                ],
                const SizedBox(height: 18),
                _SectionHeader(
                  title: l10n.merchantListSectionTitle,
                  subtitle: l10n.merchantListSectionSubtitle(
                    filtered.length.toString(),
                    filtered.where((m) => m.isOpen).length.toString(),
                  ),
                ),
                const SizedBox(height: 8),
                if (showRichDiscovery && storyMerchants.isNotEmpty) ...[
                  _MiniSectionHeader(
                    title: l10n.merchantListQuickStatesTitle,
                    subtitle: l10n.merchantListQuickStatesSubtitle,
                  ),
                  const SizedBox(height: 8),
                  _MerchantStoriesRail(
                    merchants: storyMerchants,
                    favoriteIds: prefs.favoriteMerchantIds,
                    onOpen: (merchant) =>
                        _openMerchant(merchant, userId: userId),
                  ),
                  const SizedBox(height: 12),
                ],
                if (showRichDiscovery && recommended.isNotEmpty) ...[
                  _MiniSectionHeader(
                    title: l10n.merchantListSuggestedTitle,
                    subtitle: l10n.merchantListSuggestedSubtitle,
                  ),
                  const SizedBox(height: 8),
                  _MerchantQuickRail(
                    merchants: recommended,
                    favoriteIds: prefs.favoriteMerchantIds,
                    onOpen: (merchant) =>
                        _openMerchant(merchant, userId: userId),
                  ),
                  const SizedBox(height: 12),
                ],
                if (showRichDiscovery && recentViewed.isNotEmpty) ...[
                  _MiniSectionHeader(
                    title: l10n.merchantListRecentlyViewedTitle,
                    subtitle: l10n.merchantListRecentlyViewedSubtitle,
                    trailing: TextButton(
                      onPressed: userId == null
                          ? null
                          : () => ref
                                .read(customerMerchantPrefsProvider.notifier)
                                .clearRecent(userId: userId),
                      child: Text(l10n.commonClear),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _MerchantQuickRail(
                    merchants: recentViewed,
                    favoriteIds: prefs.favoriteMerchantIds,
                    onOpen: (merchant) =>
                        _openMerchant(merchant, userId: userId),
                  ),
                  const SizedBox(height: 12),
                ],
                if (showEmptyInventory)
                  _MerchantListEmptyState(
                    title: l10n.merchantListNoStores,
                    subtitle: l10n.merchantListNoStoresSubtitle,
                  )
                else if (showFilteredEmpty)
                  _MerchantListEmptyState(
                    title: l10n.merchantListNoMatching,
                    subtitle: hasUserFilters
                        ? l10n.merchantListTryChangingFilters
                        : l10n.merchantListNoStoresSubtitle,
                    actionLabel: hasUserFilters ? l10n.commonReset : null,
                    onAction: hasUserFilters ? _clearCustomerFilters : null,
                  )
                else
                  ...List.generate(filtered.length, (index) {
                    final merchant = filtered[index];
                    final isFavorite = prefs.favoriteMerchantIds.contains(
                      merchant.id,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TweenAnimationBuilder<double>(
                        duration: Duration(milliseconds: 260 + (index * 55)),
                        curve: Curves.easeOutCubic,
                        tween: Tween(begin: 0, end: 1),
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, (1 - value) * 14),
                              child: child,
                            ),
                          );
                        },
                        child: _MerchantTalabatCard(
                          merchant: merchant,
                          isFavorite: isFavorite,
                          highlightPulse: highlightedMerchantId == merchant.id,
                          onToggleFavorite:
                              !showCustomerActions || userId == null
                              ? null
                              : () => ref
                                    .read(
                                      customerMerchantPrefsProvider.notifier,
                                    )
                                    .toggleFavorite(
                                      userId: userId,
                                      merchantId: merchant.id,
                                    ),
                          onTap: () => _openMerchant(merchant, userId: userId),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
        loading: () => const StoreListSkeleton(),
        error: (error, _) => MaslakiErrorRetry(
          message: 'تعذّر تحميل المتاجر. تحقق من اتصالك ثم أعد المحاولة.',
          onRetry: _refresh,
        ),
      ),
    );
  }

  Future<void> _openAddresses({bool selectMode = false}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DeliveryAddressesScreen(selectOnTap: selectMode),
      ),
    );
    if (changed == true || selectMode) {
      await ref
          .read(deliveryAddressControllerProvider.notifier)
          .bootstrap(silent: true);
    }
  }
}

class _BackofficeMerchantsView extends StatelessWidget {
  final List<MerchantModel> merchants;
  final String? selectedType;
  final void Function(String? value) onSelectType;
  final Future<void> Function() onRefresh;
  final void Function(MerchantModel merchant) onOpenMerchant;

  const _BackofficeMerchantsView({
    required this.merchants,
    required this.selectedType,
    required this.onSelectType,
    required this.onRefresh,
    required this.onOpenMerchant,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Column(
        children: [
          const SizedBox(height: 10),
          _BackofficeFilters(
            selectedType: selectedType,
            onSelectType: onSelectType,
          ),
          Expanded(
            child: merchants.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 180),
                      Center(child: Text(l10n.merchantListNoStores)),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: merchants.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final merchant = merchants[index];
                      final typeLabel = merchant.type == 'restaurant'
                          ? l10n.merchantListTypeRestaurant
                          : l10n.merchantListTypeMarket;
                      return Card(
                        child: ListTile(
                          onTap: () => onOpenMerchant(merchant),
                          title: Text(
                            merchant.name,
                            textDirection: TextDirection.rtl,
                          ),
                          subtitle: Text(
                            '$typeLabel • ${merchant.phone ?? ''}',
                            textDirection: TextDirection.rtl,
                          ),
                          trailing: Text(
                            merchant.isOpen
                                ? l10n.commonOpen
                                : l10n.commonClosed,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CustomerQuickActions extends StatelessWidget {
  final bool openNowOnly;
  final ValueChanged<bool> onToggleOpenNowOnly;
  final Future<void> Function() onOpenAddresses;
  final Future<void> Function() onOpenOrders;
  final Future<void> Function() onOpenCart;
  final bool showOpenNowToggle;

  const _CustomerQuickActions({
    required this.openNowOnly,
    required this.onToggleOpenNowOnly,
    required this.onOpenAddresses,
    required this.onOpenOrders,
    required this.onOpenCart,
    required this.showOpenNowToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.location_on_outlined,
                    label: l10n.drawerAddresses,
                    onTap: onOpenAddresses,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.receipt_long_outlined,
                    label: l10n.customerDiscoveryOrders,
                    onTap: onOpenOrders,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.shopping_cart_outlined,
                    label: l10n.drawerCart,
                    onTap: onOpenCart,
                  ),
                ),
              ],
            ),
            if (showOpenNowToggle) ...[
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.merchantListOpenNowOnlyToggle),
                value: openNowOnly,
                onChanged: onToggleOpenNowOnly,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CityPulseCard extends StatelessWidget {
  final String greeting;
  final int totalMerchants;
  final int openMerchants;
  final int offersCount;
  final int favoritesCount;
  final int recentCount;
  final String pulseLabel;
  final Color pulseColor;
  final double pulseScore;

  const _CityPulseCard({
    required this.greeting,
    required this.totalMerchants,
    required this.openMerchants,
    required this.offersCount,
    required this.favoritesCount,
    required this.recentCount,
    required this.pulseLabel,
    required this.pulseColor,
    required this.pulseScore,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: pulseColor,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: pulseColor.withValues(alpha: 0.65),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  pulseLabel,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: pulseColor,
                  ),
                ),
                const Spacer(),
                Text(
                  greeting,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 680),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: pulseScore),
              builder: (context, value, _) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: value.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    color: pulseColor,
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                _PulseChip(
                  icon: Icons.storefront_rounded,
                  label: context.l10n.customerDiscoveryMerchants,
                  value: '$totalMerchants',
                ),
                _PulseChip(
                  icon: Icons.lock_open_rounded,
                  label: context.l10n.customerDiscoveryOpenNow,
                  value: '$openMerchants',
                ),
                _PulseChip(
                  icon: Icons.local_offer_rounded,
                  label: context.l10n.customerDiscoveryOffers,
                  value: '$offersCount',
                ),
                _PulseChip(
                  icon: Icons.favorite_rounded,
                  label: context.l10n.merchantListFavorites,
                  value: '$favoritesCount',
                ),
                _PulseChip(
                  icon: Icons.history_rounded,
                  label: context.l10n.merchantListRecentlyViewedShort,
                  value: '$recentCount',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PulseChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            '$value $label',
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _MerchantStoriesRail extends StatelessWidget {
  final List<MerchantModel> merchants;
  final Set<int> favoriteIds;
  final Future<void> Function(MerchantModel merchant) onOpen;

  const _MerchantStoriesRail({
    required this.merchants,
    required this.favoriteIds,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: merchants.length,
        separatorBuilder: (_, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final merchant = merchants[index];
          final isFavorite = favoriteIds.contains(merchant.id);
          return SizedBox(
            width: 82,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onOpen(merchant),
              child: Column(
                children: [
                  _MerchantStoryBubble(
                    merchant: merchant,
                    isFavorite: isFavorite,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    merchant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MerchantStoryBubble extends StatefulWidget {
  final MerchantModel merchant;
  final bool isFavorite;

  const _MerchantStoryBubble({
    required this.merchant,
    required this.isFavorite,
  });

  @override
  State<_MerchantStoryBubble> createState() => _MerchantStoryBubbleState();
}

class _MerchantStoryBubbleState extends State<_MerchantStoryBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.merchant.isOpen) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _MerchantStoryBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.merchant.isOpen && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
      return;
    }
    if (!widget.merchant.isOpen && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringColor = widget.merchant.isOpen
        ? const Color(0xFF2DD881)
        : Colors.white30;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1 + (_controller.value * 0.05);
        return Transform.scale(scale: scale, child: child);
      },
      child: Stack(
        children: [
          Container(
            width: 68,
            height: 68,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  ringColor.withValues(alpha: 0.85),
                  ringColor.withValues(alpha: 0.25),
                ],
              ),
            ),
            child: ClipOval(
              child: widget.merchant.imageUrl?.isNotEmpty == true
                  ? CachedAppImage(
                      imageUrl: widget.merchant.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (context, error, stackTrace) => Container(
                        color: Colors.white.withValues(alpha: 0.08),
                        alignment: Alignment.center,
                        child: const Icon(Icons.storefront_rounded, size: 24),
                      ),
                    )
                  : Container(
                      color: Colors.white.withValues(alpha: 0.08),
                      alignment: Alignment.center,
                      child: const Icon(Icons.storefront_rounded, size: 24),
                    ),
            ),
          ),
          if (widget.isFavorite)
            const Positioned(
              right: 0,
              top: 0,
              child: Icon(
                Icons.favorite_rounded,
                size: 16,
                color: Colors.redAccent,
              ),
            ),
        ],
      ),
    );
  }
}

class _DiscoveryModesPanel extends StatelessWidget {
  final _DiscoveryMode? activeMode;
  final bool surprisePicking;
  final ValueChanged<_DiscoveryMode> onSelectMode;

  const _DiscoveryModesPanel({
    required this.activeMode,
    required this.surprisePicking,
    required this.onSelectMode,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.merchantListDiscoveryModesTitle,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: surprisePicking
                      ? const SizedBox(
                          key: ValueKey('picking'),
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const SizedBox(key: ValueKey('idle')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                _DiscoveryModeChip(
                  mode: _DiscoveryMode.quick,
                  activeMode: activeMode,
                  icon: Icons.flash_on_rounded,
                  label: l10n.merchantListDiscoveryModeQuick,
                  onTap: onSelectMode,
                ),
                _DiscoveryModeChip(
                  mode: _DiscoveryMode.savings,
                  activeMode: activeMode,
                  icon: Icons.savings_rounded,
                  label: l10n.merchantListDiscoveryModeSavings,
                  onTap: onSelectMode,
                ),
                _DiscoveryModeChip(
                  mode: _DiscoveryMode.favorites,
                  activeMode: activeMode,
                  icon: Icons.favorite_rounded,
                  label: l10n.merchantListDiscoveryModeFavorites,
                  onTap: onSelectMode,
                ),
                _DiscoveryModeChip(
                  mode: _DiscoveryMode.surprise,
                  activeMode: activeMode,
                  icon: Icons.casino_rounded,
                  label: l10n.merchantListDiscoveryModeSurprise,
                  onTap: onSelectMode,
                  animated: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryModeChip extends StatefulWidget {
  final _DiscoveryMode mode;
  final _DiscoveryMode? activeMode;
  final IconData icon;
  final String label;
  final ValueChanged<_DiscoveryMode> onTap;
  final bool animated;

  const _DiscoveryModeChip({
    required this.mode,
    required this.activeMode,
    required this.icon,
    required this.label,
    required this.onTap,
    this.animated = false,
  });

  @override
  State<_DiscoveryModeChip> createState() => _DiscoveryModeChipState();
}

class _DiscoveryModeChipState extends State<_DiscoveryModeChip>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _configureAnimationController();
  }

  @override
  void didUpdateWidget(covariant _DiscoveryModeChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animated == widget.animated) return;
    if (widget.animated) {
      _configureAnimationController();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  void _configureAnimationController() {
    if (!widget.animated || _controller != null) return;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.activeMode == widget.mode;
    final chip = FilterChip(
      selected: selected,
      onSelected: (_) => widget.onTap(widget.mode),
      avatar: Icon(widget.icon, size: 16),
      label: Text(widget.label),
    );

    final animation = _controller;
    if (!widget.animated || selected || animation == null) {
      return chip;
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = 1 + (animation.value * 0.035);
        return Transform.scale(scale: value, child: child);
      },
      child: chip,
    );
  }
}

class _MerchantDiscoveryToolbar extends StatelessWidget {
  final bool favoritesOnly;
  final _CustomerMerchantSort sortBy;
  final ValueChanged<bool> onToggleFavoritesOnly;
  final ValueChanged<_CustomerMerchantSort> onChangeSort;

  const _MerchantDiscoveryToolbar({
    required this.favoritesOnly,
    required this.sortBy,
    required this.onToggleFavoritesOnly,
    required this.onChangeSort,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Compact sort/filter row (replaces the old "تخصيص عرض المتاجر" panel):
    // a lean, scrollable strip of Sort + Favorites controls.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true, // keep controls right-aligned (RTL start).
      child: Row(
        textDirection: TextDirection.rtl,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: TextDirection.rtl,
              children: [
                const Icon(Icons.sort_rounded, size: 16),
                const SizedBox(width: 4),
                DropdownButtonHideUnderline(
                  child: DropdownButton<_CustomerMerchantSort>(
                    value: sortBy,
                    isDense: true,
                    onChanged: (value) {
                      if (value == null) return;
                      onChangeSort(value);
                    },
                    items: [
                      DropdownMenuItem(
                        value: _CustomerMerchantSort.recommended,
                        child: Text(l10n.merchantListSortRecommended),
                      ),
                      DropdownMenuItem(
                        value: _CustomerMerchantSort.openFirst,
                        child: Text(l10n.merchantListSortOpenFirst),
                      ),
                      DropdownMenuItem(
                        value: _CustomerMerchantSort.offersFirst,
                        child: Text(l10n.merchantListSortOffersFirst),
                      ),
                      DropdownMenuItem(
                        value: _CustomerMerchantSort.alphabetical,
                        child: Text(l10n.merchantListSortAlphabetical),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            textDirection: TextDirection.rtl,
            mainAxisSize: MainAxisSize.min,
            children: [
              FilterChip(
                selected: favoritesOnly,
                onSelected: onToggleFavoritesOnly,
                label: Text(l10n.merchantListFavoritesOnly),
                avatar: const Icon(Icons.favorite_rounded, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _MiniSectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (trailing case final Widget action) ...[
          action,
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            subtitle,
            textAlign: TextAlign.left,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ],
    );
  }
}

class _CategoryIntelligenceLoadingCard extends StatelessWidget {
  const _CategoryIntelligenceLoadingCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.merchantListCategoryIntelLoading,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.90),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.auto_graph_rounded),
          ],
        ),
      ),
    );
  }
}

class _CategoryIntelligenceErrorCard extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _CategoryIntelligenceErrorCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            FilledButton.icon(
              onPressed: () {
                onRetry();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.commonRetry),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.merchantListCategoryIntelLoadFailed,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.86)),
              ),
            ),
            const Icon(Icons.warning_amber_rounded),
          ],
        ),
      ),
    );
  }
}

class _CategoryProfileCard extends StatelessWidget {
  final CustomerShoppingProfile profile;
  final String spendingBandText;
  final String priceSensitivityText;
  final int merchantCount;

  const _CategoryProfileCard({
    required this.profile,
    required this.spendingBandText,
    required this.priceSensitivityText,
    required this.merchantCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF183E70), Color(0xFF102C52)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded),
              const Spacer(),
              Text(
                l10n.merchantListCategoryIntelTitle,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.merchantListCategoryIntelSubtitle,
            textDirection: TextDirection.rtl,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.84)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              _MetricPill(
                icon: Icons.storefront_rounded,
                label: l10n.customerDiscoveryMerchants,
                value: '$merchantCount',
              ),
              _MetricPill(
                icon: Icons.shopping_cart_checkout_rounded,
                label: l10n.customerDiscoveryOrders,
                value: '${profile.ordersCountInCategory120d}',
              ),
              _MetricPill(
                icon: Icons.account_balance_wallet_outlined,
                label: l10n.merchantListPurchasingPower,
                value: spendingBandText,
              ),
              _MetricPill(
                icon: Icons.price_check_rounded,
                label: l10n.merchantListPricePreference,
                value: priceSensitivityText,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Icon(icon, size: 15),
        ],
      ),
    );
  }
}

class _MerchantQuickRail extends StatelessWidget {
  final List<MerchantModel> merchants;
  final Set<int> favoriteIds;
  final Future<void> Function(MerchantModel merchant) onOpen;

  const _MerchantQuickRail({
    required this.merchants,
    required this.favoriteIds,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 98,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: merchants.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final merchant = merchants[index];
          final isFavorite = favoriteIds.contains(merchant.id);
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              onOpen(merchant);
            },
            child: Ink(
              width: 188,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: merchant.imageUrl?.isNotEmpty == true
                          ? CachedAppImage(
                              imageUrl: merchant.imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (context, error, stackTrace) =>
                                  Container(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    child: const Icon(Icons.storefront_rounded),
                                  ),
                            )
                          : Container(
                              color: Colors.white.withValues(alpha: 0.08),
                              child: const Icon(Icons.storefront_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          merchant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (isFavorite)
                              const Icon(
                                Icons.favorite_rounded,
                                size: 14,
                                color: Colors.redAccent,
                              ),
                            if (isFavorite) const SizedBox(width: 4),
                            Icon(
                              merchant.isOpen
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 10,
                              color: merchant.isOpen
                                  ? Colors.green
                                  : Colors.white54,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              merchant.isOpen
                                  ? context.l10n.commonOpen
                                  : context.l10n.commonClosed,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _CartButton extends StatelessWidget {
  final int totalItems;
  final VoidCallback onPressed;

  const _CartButton({required this.totalItems, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          tooltip: context.l10n.customerDiscoveryCart,
          onPressed: onPressed,
          icon: const Icon(Icons.shopping_bag_outlined),
        ),
        if (totalItems > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$totalItems',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BasmayaLocationStrip extends ConsumerWidget {
  final Future<void> Function({bool selectMode}) onOpenAddresses;

  const _BasmayaLocationStrip({required this.onOpenAddresses});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final addressState = ref.watch(deliveryAddressControllerProvider);
    final selected = addressState.selectedAddress;

    final listItems = addressState.addresses
        .map(
          (a) => DropdownMenuItem<int>(
            value: a.id,
            child: Text(
              a.shortText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
            ),
          ),
        )
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1C4C89), Color(0xFF0D2A52)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.customerDiscoveryDeliveryAddresses,
            onPressed: () => onOpenAddresses(),
            icon: const Icon(Icons.edit_location_alt_outlined),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  l10n.deliveryAddressesDefaultCity,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.90),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                if (addressState.loading)
                  Text(
                    l10n.merchantListAddressesLoading,
                    textDirection: TextDirection.rtl,
                  )
                else if (selected == null && listItems.isEmpty)
                  InkWell(
                    onTap: () => onOpenAddresses(selectMode: true),
                    child: Text(
                      l10n.merchantListAddressesAddToStart,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                        color: Colors.white.withValues(alpha: 0.90),
                      ),
                    ),
                  )
                else
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: selected?.id,
                        hint: Text(l10n.merchantListAddressesChoose),
                        items: listItems,
                        onChanged: (value) {
                          if (value == null) return;
                          ref
                              .read(deliveryAddressControllerProvider.notifier)
                              .selectAddress(value);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.place_rounded),
        ],
      ),
    );
  }
}

class _CustomerCategoryRail extends StatelessWidget {
  final String? selectedType;
  final void Function(String? value) onSelectType;

  const _CustomerCategoryRail({
    required this.selectedType,
    required this.onSelectType,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _CategoryPill(
            label: l10n.commonAll,
            icon: Icons.grid_view_rounded,
            selected: selectedType == null,
            onTap: () => onSelectType(null),
          ),
          const SizedBox(width: 8),
          _CategoryPill(
            label: l10n.customerDiscoveryRestaurants,
            icon: Icons.restaurant_menu_rounded,
            selected: selectedType == 'restaurant',
            onTap: () => onSelectType('restaurant'),
          ),
          const SizedBox(width: 8),
          _CategoryPill(
            label: l10n.customerDiscoveryMarkets,
            icon: Icons.storefront_rounded,
            selected: selectedType == 'market',
            onTap: () => onSelectType('market'),
          ),
        ],
      ),
    );
  }
}

class _ActivityDiscoveryRail extends StatelessWidget {
  final List<StoreActivityModel> activities;
  final List<StoreDiscoveryOptionModel> discoveryOptions;
  final String? selectedActivityType;
  final String? selectedDiscoverySubcategory;
  final bool isArabic;
  final Future<void> Function(String? value) onSelectActivityType;
  final Future<void> Function(String? value) onSelectDiscoverySubcategory;

  const _ActivityDiscoveryRail({
    required this.activities,
    required this.discoveryOptions,
    required this.selectedActivityType,
    required this.selectedDiscoverySubcategory,
    required this.isArabic,
    required this.onSelectActivityType,
    required this.onSelectDiscoverySubcategory,
  });

  IconData _iconForActivity(String activityType) {
    switch (activityType) {
      case 'restaurant':
        return Icons.restaurant_menu_rounded;
      case 'pharmacy':
        return Icons.local_hospital_rounded;
      case 'supermarket':
        return Icons.local_grocery_store_rounded;
      case 'construction':
        return Icons.handyman_rounded;
      case 'electronics':
        return Icons.devices_other_rounded;
      case 'beauty':
        return Icons.spa_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.addMerchantActivityTypeLabel,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _CategoryPill(
                label: l10n.commonAll,
                icon: Icons.apps_rounded,
                selected: selectedActivityType == null,
                onTap: () => onSelectActivityType(null),
              ),
              const SizedBox(width: 8),
              ...activities.map(
                (activity) => Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: _CategoryPill(
                    label: activity.localizedLabel(isArabic),
                    icon: _iconForActivity(activity.activityType),
                    selected: selectedActivityType == activity.activityType,
                    onTap: () => onSelectActivityType(activity.activityType),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (discoveryOptions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            l10n.addMerchantDiscoverySubcategoryLabel,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _DiscoveryPill(
                  label: l10n.commonAll,
                  selected: selectedDiscoverySubcategory == null,
                  onTap: () => onSelectDiscoverySubcategory(null),
                ),
                const SizedBox(width: 8),
                ...discoveryOptions.map(
                  (option) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: _DiscoveryPill(
                      label: option.localizedLabel(isArabic),
                      selected: selectedDiscoverySubcategory == option.code,
                      onTap: () => onSelectDiscoverySubcategory(option.code),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DiscoveryPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DiscoveryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12.5)),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.22)
                : Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromoCarousel extends StatelessWidget {
  final PageController controller;
  final List<_PromoItem> promoItems;
  final int currentPage;

  const _PromoCarousel({
    required this.controller,
    required this.promoItems,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 138,
          child: PageView.builder(
            controller: controller,
            itemCount: promoItems.length,
            itemBuilder: (context, index) {
              final promo = promoItems[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF203E72), Color(0xFF0D2A4F)],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(promo.icon, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              promo.title,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              promo.subtitle,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(promoItems.length, (index) {
            final selected = index == currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: selected ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white.withValues(alpha: 0.24),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.70)),
        ),
        const Spacer(),
        Text(
          title,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ],
    );
  }
}

class _MerchantListEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MerchantListEmptyState({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, size: 34),
            const SizedBox(height: 8),
            Text(
              title,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textDirection: TextDirection.rtl,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.76)),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MerchantTalabatCard extends StatelessWidget {
  final MerchantModel merchant;
  final bool isFavorite;
  final bool highlightPulse;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onTap;

  const _MerchantTalabatCard({
    required this.merchant,
    required this.isFavorite,
    required this.highlightPulse,
    required this.onToggleFavorite,
    required this.onTap,
  });

  // --- Real-data resolvers (no fabricated ratings / ETA / fees / distance) ---

  String? get _coverSource {
    final cover = merchant.coverImageUrl?.trim();
    if (cover != null && cover.isNotEmpty) return cover;
    final image = merchant.imageUrl?.trim();
    return (image != null && image.isNotEmpty) ? image : null;
  }

  /// Distinct logo only. Never reuses the exact image already shown as cover
  /// (avoids an ugly duplicate); falls back to a Maslaki placeholder instead.
  String? get _logoSource {
    final logo = merchant.logoUrl?.trim();
    if (logo != null && logo.isNotEmpty) return logo;
    final image = merchant.imageUrl?.trim();
    final cover = merchant.coverImageUrl?.trim();
    if (image != null && image.isNotEmpty && image != cover) return image;
    return null;
  }

  String _statusLabel(BuildContext context) {
    final l10n = context.l10n;
    if (merchant.isOpen) return l10n.merchantListStatusOpenNow;
    final next = merchant.nextOpenAt;
    if (next != null) {
      final local = next.toLocal();
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return context.lt(
        ar: 'يفتح $hh:$mm',
        en: 'Opens $hh:$mm',
      );
    }
    return l10n.merchantListStatusClosedNow;
  }

  String? _etaLabel(BuildContext context) {
    if (!merchant.hasDeliveryEta) return null;
    final min = merchant.deliveryEtaMinMinutes;
    final max = merchant.deliveryEtaMaxMinutes;
    if (min != null && max != null) {
      return context.lt(ar: '$min–$max دقيقة', en: '$min–$max min');
    }
    if (max != null) {
      return context.lt(ar: 'حتى $max دقيقة', en: 'up to $max min');
    }
    return context.lt(ar: 'من $min دقيقة', en: 'from $min min');
  }

  String? _feeLabel(BuildContext context) {
    if (merchant.hasFreeDeliveryOffer ||
        (merchant.deliveryFee != null && merchant.deliveryFee == 0)) {
      return context.lt(ar: 'توصيل مجاني', en: 'Free delivery');
    }
    final fee = merchant.deliveryFee;
    if (fee != null && fee > 0) {
      return context.lt(
        ar: 'توصيل ${formatIqd(fee)}',
        en: 'Delivery ${formatIqd(fee)}',
      );
    }
    return null; // Unknown fee → show nothing, never a fake value.
  }

  @override
  Widget build(BuildContext context) {
    final cover = _coverSource;
    final logo = _logoSource;
    final storeIcon = merchant.type == 'restaurant'
        ? Icons.restaurant_rounded
        : Icons.storefront_rounded;
    final etaLabel = _etaLabel(context);
    final feeLabel = _feeLabel(context);

    return AnimatedScale(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      scale: highlightPulse ? 1.015 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: merchant.isOpen
                    ? [
                        const Color(0xFF1B3E72).withValues(alpha: 0.88),
                        const Color(0xFF122E55).withValues(alpha: 0.88),
                      ]
                    : [
                        const Color(0xFF2B3346).withValues(alpha: 0.92),
                        const Color(0xFF1E2434).withValues(alpha: 0.92),
                      ],
              ),
              border: Border.all(
                color: highlightPulse
                    ? Theme.of(context).colorScheme.secondary
                    : merchant.isOpen
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.10),
                width: highlightPulse ? 1.8 : 1,
              ),
              boxShadow: highlightPulse
                  ? [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : const [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Large cover ----
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  child: AspectRatio(
                    aspectRatio: 2.7,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cover != null)
                          CachedAppImage(
                            imageUrl: cover,
                            cacheIdentity: 'store_cover_${merchant.id}',
                            fit: BoxFit.cover,
                            errorWidget: (context, error, stackTrace) =>
                                _CoverPlaceholder(icon: storeIcon),
                          )
                        else
                          _CoverPlaceholder(icon: storeIcon),
                        // Legibility scrim.
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black38],
                            ),
                          ),
                        ),
                        // Favorite (top-start).
                        if (onToggleFavorite != null)
                          PositionedDirectional(
                            top: 8,
                            start: 8,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.34),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: onToggleFavorite,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    size: 18,
                                    color: isFavorite
                                        ? Colors.redAccent
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Verified + offer badges (top-end).
                        PositionedDirectional(
                          top: 8,
                          end: 8,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (merchant.hasActiveOffer)
                                _CoverBadge(
                                  icon: Icons.local_offer_rounded,
                                  label: context.lt(ar: 'عرض', en: 'Offer'),
                                  color: const Color(0xFFE0752D),
                                ),
                              if (merchant.isVerified) ...[
                                if (merchant.hasActiveOffer)
                                  const SizedBox(width: 6),
                                _CoverBadge(
                                  icon: Icons.verified_rounded,
                                  label: context.lt(
                                    ar: 'موثّق',
                                    en: 'Verified',
                                  ),
                                  color: const Color(0xFF2E7CD6),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ---- Body: logo + name + desc + meta ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        textDirection: TextDirection.rtl,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StoreLogo(
                            imageUrl: logo,
                            fallbackIcon: storeIcon,
                            merchantId: merchant.id,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  merchant.name,
                                  textDirection: TextDirection.rtl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                if (merchant.description?.trim().isNotEmpty ==
                                    true) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    merchant.description!.trim(),
                                    textDirection: TextDirection.rtl,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        textDirection: TextDirection.rtl,
                        children: [
                          _StatusPill(
                            label: _statusLabel(context),
                            isOpen: merchant.isOpen,
                          ),
                          _RatingChip(
                            avgRating: merchant.avgMerchantRating,
                            ratingCount: merchant.ratingCount,
                          ),
                          if (etaLabel != null)
                            _MetaChip(
                              icon: Icons.schedule_rounded,
                              text: etaLabel,
                              maxTextWidth: 118,
                            ),
                          if (feeLabel != null)
                            _MetaChip(
                              icon: Icons.local_shipping_rounded,
                              text: feeLabel,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Maslaki-branded placeholder for a missing store cover.
class _CoverPlaceholder extends StatelessWidget {
  final IconData icon;
  const _CoverPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1C355F), Color(0xFF122A4C)],
        ),
      ),
      child: Center(
        child: Icon(icon, size: 40, color: Colors.white.withValues(alpha: 0.5)),
      ),
    );
  }
}

/// Circular store logo with a Maslaki placeholder when no distinct logo exists.
class _StoreLogo extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;
  final int merchantId;

  const _StoreLogo({
    required this.imageUrl,
    required this.fallbackIcon,
    required this.merchantId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null
          ? CachedAppImage(
              imageUrl: imageUrl!,
              cacheIdentity: 'store_logo_$merchantId',
              fit: BoxFit.cover,
              errorWidget: (context, error, stackTrace) =>
                  Icon(fallbackIcon, color: Colors.white70),
            )
          : Icon(fallbackIcon, color: Colors.white70),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool isOpen;
  const _StatusPill({required this.label, required this.isOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: isOpen
            ? Colors.green.withValues(alpha: 0.20)
            : Colors.red.withValues(alpha: 0.20),
        border: Border.all(
          color: isOpen
              ? Colors.green.withValues(alpha: 0.45)
              : Colors.red.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Real rating with count, or "متجر جديد" when there are no reviews yet.
class _RatingChip extends StatelessWidget {
  final double? avgRating;
  final int ratingCount;
  const _RatingChip({required this.avgRating, required this.ratingCount});

  @override
  Widget build(BuildContext context) {
    if (ratingCount <= 0 || avgRating == null) {
      return _MetaChip(
        icon: Icons.fiber_new_rounded,
        text: context.lt(ar: 'متجر جديد', en: 'New store'),
      );
    }
    final label = context.lt(
      ar: '${avgRating!.toStringAsFixed(1)} ($ratingCount تقييم)',
      en: '${avgRating!.toStringAsFixed(1)} ($ratingCount reviews)',
    );
    return _MetaChip(icon: Icons.star_rounded, text: label, maxTextWidth: 130);
  }
}

/// Small pill used for verified/offer badges on the cover.
class _CoverBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _CoverBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.92),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final double maxTextWidth;

  const _MetaChip({
    required this.icon,
    required this.text,
    this.maxTextWidth = 110,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxTextWidth),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackofficeFilters extends StatelessWidget {
  final String? selectedType;
  final void Function(String? value) onSelectType;

  const _BackofficeFilters({
    required this.selectedType,
    required this.onSelectType,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text(l10n.commonAll),
            selected: selectedType == null,
            onSelected: (_) => onSelectType(null),
          ),
          ChoiceChip(
            label: Text(l10n.merchantListTypeRestaurant),
            selected: selectedType == 'restaurant',
            onSelected: (_) => onSelectType('restaurant'),
          ),
          ChoiceChip(
            label: Text(l10n.merchantListTypeMarket),
            selected: selectedType == 'market',
            onSelected: (_) => onSelectType('market'),
          ),
        ],
      ),
    );
  }
}

class _PromoItem {
  final String title;
  final String subtitle;
  final IconData icon;

  const _PromoItem({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
