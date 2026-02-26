import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/pricing.dart';
import '../../../core/i18n/app_strings.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../assistant/ui/assistant_chat_screen.dart';
import '../../merchants/models/merchant_discovery_model.dart';
import '../../merchants/models/merchant_model.dart';
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
import '../state/auth_controller.dart';
import 'add_merchant_screen.dart';

class MerchantsListScreen extends ConsumerStatefulWidget {
  final String? initialType;
  final String initialSearchQuery;
  final String? overrideTitle;
  final bool compactCustomerMode;

  const MerchantsListScreen({
    super.key,
    this.initialType,
    this.initialSearchQuery = '',
    this.overrideTitle,
    this.compactCustomerMode = false,
  });

  @override
  ConsumerState<MerchantsListScreen> createState() =>
      _MerchantsListScreenState();
}

enum _CustomerMerchantSort { recommended, openFirst, offersFirst, alphabetical }

enum _DiscoveryMode { quick, savings, favorites, surprise }

class _MerchantsListScreenState extends ConsumerState<MerchantsListScreen> {
  static const _promoItems = <_PromoItem>[
    _PromoItem(
      title: 'عروض بسماية اليومية',
      subtitle: 'خصومات متجددة على المطاعم والمتاجر القريبة منك',
      icon: Icons.local_offer_rounded,
    ),
    _PromoItem(
      title: 'توصيل سريع داخل المجمع',
      subtitle: 'من المتجر إلى باب بيتك بأجور ثابتة وواضحة',
      icon: Icons.delivery_dining_rounded,
    ),
    _PromoItem(
      title: 'متاجر الحي بين يديك',
      subtitle: 'كل ما تحتاجه يوميًا من مكان واحد وبلمسة حديثة',
      icon: Icons.storefront_rounded,
    ),
  ];

  String? filterType;
  String searchQuery = '';
  bool openNowOnly = false;
  bool favoritesOnly = false;
  _CustomerMerchantSort sortBy = _CustomerMerchantSort.recommended;
  _DiscoveryMode? activeDiscoveryMode;
  bool surprisePicking = false;
  int? highlightedMerchantId;

  final searchCtrl = TextEditingController();
  final promoController = PageController(viewportFraction: 0.92);
  Timer? promoTimer;
  int promoPage = 0;

  @override
  void initState() {
    super.initState();
    filterType = widget.initialType;
    searchQuery = widget.initialSearchQuery.trim();
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
          .load(type: filterType);
      await ref.read(deliveryAddressControllerProvider.notifier).bootstrap();
      await _loadDiscoveryForType(auth: auth, type: filterType);
      if (!auth.isBackoffice &&
          !auth.isOwner &&
          !auth.isDelivery &&
          userId != null) {
        await ref
            .read(customerMerchantPrefsProvider.notifier)
            .bootstrap(userId: userId);
      }
    });
    promoTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !promoController.hasClients) return;
      promoPage = (promoPage + 1) % _promoItems.length;
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

  Future<void> _openAssistant() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AssistantChatScreen()));
  }

  Future<void> _refresh() {
    final auth = ref.read(authControllerProvider);
    return Future.wait([
      ref.read(merchantsControllerProvider.notifier).load(type: filterType),
      _loadDiscoveryForType(auth: auth, type: filterType, force: true),
    ]);
  }

  void _onChangeType(String? value) {
    if (filterType == value) return;
    setState(() => filterType = value);
    ref.read(merchantsControllerProvider.notifier).load(type: value);
    _loadDiscoveryForType(auth: ref.read(authControllerProvider), type: value);
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

  String _searchHintText() {
    final title = (widget.overrideTitle ?? '').trim();
    if (title.isNotEmpty) {
      return 'ابحث عن $title';
    }

    final currentType = filterType ?? widget.initialType;
    if (currentType == 'market') {
      return 'ابحث عن الأسواق';
    }
    return 'ابحث عن المطاعم';
  }

  List<MerchantModel> _applySearch(
    List<MerchantModel> list,
    Set<int> favoriteMerchantIds,
    Map<int, double> insightScoreByMerchantId,
  ) {
    final q = searchQuery.trim().toLowerCase();
    var filtered = q.isEmpty
        ? list
        : list.where((merchant) {
            final name = merchant.name.toLowerCase();
            final description = (merchant.description ?? '').toLowerCase();
            final phone = (merchant.phone ?? '').toLowerCase();
            return name.contains(q) ||
                description.contains(q) ||
                phone.contains(q);
          }).toList();

    if (openNowOnly) {
      filtered = filtered.where((merchant) => merchant.isOpen).toList();
    }
    if (favoritesOnly) {
      filtered = filtered
          .where((merchant) => favoriteMerchantIds.contains(merchant.id))
          .toList();
    }
    return _sortMerchants(
      filtered,
      favoriteMerchantIds,
      insightScoreByMerchantId,
    );
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

  String _greetingByHour(int hour) {
    if (hour < 6) return 'ليلة هادئة';
    if (hour < 12) return 'صباح نشيط';
    if (hour < 17) return 'ظهيرة سريعة';
    if (hour < 22) return 'مساء حيوي';
    return 'ليل بسماية';
  }

  ({String label, Color color, double score}) _cityPulse({
    required int hour,
    required int openCount,
    required int offersCount,
    required int totalCount,
  }) {
    final openRatio = totalCount <= 0 ? 0.0 : openCount / totalCount;
    final offerRatio = totalCount <= 0 ? 0.0 : offersCount / totalCount;
    final hourBias = (hour >= 12 && hour <= 23) ? 0.22 : 0.12;
    final score = (openRatio * 0.58 + offerRatio * 0.30 + hourBias).clamp(
      0.05,
      1.0,
    );
    if (score >= 0.72) {
      return (
        label: 'ذروة الطلب',
        color: const Color(0xFF2DD881),
        score: score,
      );
    }
    if (score >= 0.42) {
      return (
        label: 'نشاط متوسط',
        color: const Color(0xFFF9C74F),
        score: score,
      );
    }
    return (label: 'نشاط هادئ', color: const Color(0xFF56CFE1), score: score);
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
        const SnackBar(content: Text('لا توجد متاجر متاحة حالياً')),
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
    switch (value) {
      case 'budget':
        return 'اقتصادي';
      case 'balanced':
        return 'متوازن';
      case 'premium':
        return 'مرتفع';
      default:
        return 'جديد';
    }
  }

  String _priceSensitivityText(String value) {
    switch (value) {
      case 'high':
        return 'حساسية سعر عالية';
      case 'low':
        return 'يركز على الجودة';
      default:
        return 'تفضيل متوازن';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final merchants = ref.watch(merchantsControllerProvider);
    final discovery = ref.watch(merchantDiscoveryControllerProvider);
    final cart = ref.watch(cartControllerProvider);
    final prefs = ref.watch(customerMerchantPrefsProvider);
    final strings = ref.watch(appStringsProvider);
    final showCustomerActions =
        !auth.isBackoffice && !auth.isOwner && !auth.isDelivery;
    final showRichDiscovery =
        showCustomerActions && !widget.compactCustomerMode;
    final lockTypeSelection =
        widget.compactCustomerMode && widget.initialType != null;
    final showSecondaryFilters = showCustomerActions && !lockTypeSelection;
    final drawerItems = <AppUserDrawerItem>[
      AppUserDrawerItem(
        icon: Icons.home_outlined,
        label: strings.t('drawerHome'),
      ),
      AppUserDrawerItem(
        icon: Icons.refresh_rounded,
        label: strings.t('drawerRefresh'),
        onTap: (_) => _refresh(),
      ),
      if (showCustomerActions)
        AppUserDrawerItem(
          icon: Icons.receipt_long_rounded,
          label: strings.t('myOrders'),
          onTap: (_) async => _openOrders(),
        ),
      if (showCustomerActions)
        AppUserDrawerItem(
          icon: Icons.shopping_cart_outlined,
          label: strings.t('drawerCart'),
          onTap: (_) async => _openCart(),
        ),
      if (showCustomerActions)
        AppUserDrawerItem(
          icon: Icons.location_on_outlined,
          label: 'عناوين التوصيل',
          onTap: (_) async => _openAddresses(),
        ),
      if (showCustomerActions)
        AppUserDrawerItem(
          icon: Icons.smart_toy_outlined,
          label: 'المساعد الذكي',
          onTap: (_) async => _openAssistant(),
        ),
      if (auth.isAdmin)
        AppUserDrawerItem(
          icon: Icons.add_business_rounded,
          label: strings.t('drawerCreateMerchant'),
          onTap: (_) async {
            final created = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const AddMerchantScreen()),
            );
            if (created == true) {
              await _refresh();
            }
          },
        ),
    ];

    return Scaffold(
      drawer: AppUserDrawer(
        title: strings.t('drawerWorkspace'),
        subtitle: strings.t('drawerMerchantsSub'),
        items: drawerItems,
      ),
      appBar: AppBar(
        title: Text(
          widget.overrideTitle ??
              (showCustomerActions
                  ? strings.t('customerHomeTitle')
                  : strings.t('backofficeMerchantsTitle')),
        ),
        actions: [
          if (showCustomerActions)
            IconButton(
              tooltip: strings.t('myOrders'),
              onPressed: _openOrders,
              icon: const Icon(Icons.receipt_long),
            ),
          if (showCustomerActions)
            IconButton(
              tooltip: 'المساعد الذكي',
              onPressed: _openAssistant,
              icon: const Icon(Icons.smart_toy_outlined),
            ),
          if (showCustomerActions)
            IconButton(
              tooltip: 'عناوين التوصيل',
              onPressed: _openAddresses,
              icon: const Icon(Icons.location_on_outlined),
            ),
          if (showCustomerActions)
            _CartButton(totalItems: cart.totalItems, onPressed: _openCart),
          if (showCustomerActions) const NotificationsBellButton(),
        ],
      ),
      floatingActionButton: auth.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const AddMerchantScreen()),
                );
                if (created == true) {
                  await _refresh();
                }
              },
              label: const Text('إنشاء متجر'),
              icon: const Icon(Icons.add_business_rounded),
            )
          : showRichDiscovery
          ? FloatingActionButton.small(
              onPressed: _openAssistant,
              tooltip: 'المساعد الذكي',
              child: const Icon(Icons.smart_toy_outlined),
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
                    greeting: _greetingByHour(DateTime.now().hour),
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
                TextField(
                  controller: searchCtrl,
                  textDirection: TextDirection.rtl,
                  onChanged: (value) => setState(() => searchQuery = value),
                  decoration: InputDecoration(
                    hintText: _searchHintText(),
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
                ],
                if (showRichDiscovery) const SizedBox(height: 14),
                if (showRichDiscovery)
                  _PromoCarousel(
                    controller: promoController,
                    promoItems: _promoItems,
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
                      const _MiniSectionHeader(
                        title: 'الأسرع توصيلًا',
                        subtitle: 'ترتيب حسب سرعة التوصيل الفعلية',
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
                      const _MiniSectionHeader(
                        title: 'الأعلى تقييمًا',
                        subtitle: 'أفضل جودة خدمة وطعم حسب التقييمات',
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
                      const _MiniSectionHeader(
                        title: 'أفضل قيمة مقابل السعر',
                        subtitle: 'السعر مع الجودة معًا',
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
                      const _MiniSectionHeader(
                        title: 'عروض اليوم',
                        subtitle: 'خصومات وتوصيل مجاني متاح الآن',
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
                      const _MiniSectionHeader(
                        title: 'الأكثر طلبًا',
                        subtitle: 'الأكثر نشاطًا من الزبائن اليوميين',
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
                      const _MiniSectionHeader(
                        title: 'أعد طلبك السابق',
                        subtitle: 'عودة سريعة للمتاجر التي طلبت منها',
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
                  title: 'متاجر بسماية',
                  subtitle:
                      '${filtered.length} متجر متاح • ${filtered.where((m) => m.isOpen).length} مفتوح الآن',
                ),
                const SizedBox(height: 8),
                if (showRichDiscovery && storyMerchants.isNotEmpty) ...[
                  _MiniSectionHeader(
                    title: 'حالات سريعة',
                    subtitle: 'ادخل مباشرة على المتاجر النشطة',
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
                    title: 'مقترح لك',
                    subtitle: 'أفضل خيارات حسب التوفر والعروض',
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
                    title: 'شوهد مؤخراً',
                    subtitle: 'عودة سريعة للمتاجر التي زرتها',
                    trailing: TextButton(
                      onPressed: userId == null
                          ? null
                          : () => ref
                                .read(customerMerchantPrefsProvider.notifier)
                                .clearRecent(userId: userId),
                      child: const Text('مسح'),
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
                if (filtered.isEmpty)
                  const _EmptySearchState()
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
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
                    children: const [
                      SizedBox(height: 180),
                      Center(child: Text('لا توجد متاجر')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: merchants.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final merchant = merchants[index];
                      final typeLabel = merchant.type == 'restaurant'
                          ? 'مطعم'
                          : 'سوق';
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
                          trailing: Text(merchant.isOpen ? 'مفتوح' : 'مغلق'),
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
                    label: 'العناوين',
                    onTap: onOpenAddresses,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.receipt_long_outlined,
                    label: 'طلباتي',
                    onTap: onOpenOrders,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.shopping_cart_outlined,
                    label: 'السلة',
                    onTap: onOpenCart,
                  ),
                ),
              ],
            ),
            if (showOpenNowToggle) ...[
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('عرض المتاجر المفتوحة الآن فقط'),
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
                  label: 'المتاجر',
                  value: '$totalMerchants',
                ),
                _PulseChip(
                  icon: Icons.lock_open_rounded,
                  label: 'مفتوح الآن',
                  value: '$openMerchants',
                ),
                _PulseChip(
                  icon: Icons.local_offer_rounded,
                  label: 'عروض',
                  value: '$offersCount',
                ),
                _PulseChip(
                  icon: Icons.favorite_rounded,
                  label: 'مفضلة',
                  value: '$favoritesCount',
                ),
                _PulseChip(
                  icon: Icons.history_rounded,
                  label: 'شوهد مؤخراً',
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
                  ? Image.network(
                      widget.merchant.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
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
                const Expanded(
                  child: Text(
                    'مزاجي الآن',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontWeight: FontWeight.w700),
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
                  label: 'مستعجل',
                  onTap: onSelectMode,
                ),
                _DiscoveryModeChip(
                  mode: _DiscoveryMode.savings,
                  activeMode: activeMode,
                  icon: Icons.savings_rounded,
                  label: 'توفير',
                  onTap: onSelectMode,
                ),
                _DiscoveryModeChip(
                  mode: _DiscoveryMode.favorites,
                  activeMode: activeMode,
                  icon: Icons.favorite_rounded,
                  label: 'المفضلة',
                  onTap: onSelectMode,
                ),
                _DiscoveryModeChip(
                  mode: _DiscoveryMode.surprise,
                  activeMode: activeMode,
                  icon: Icons.casino_rounded,
                  label: 'فاجئني',
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
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

    if (!widget.animated || selected) {
      return chip;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = 1 + (_controller.value * 0.035);
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                const Icon(Icons.tune_rounded, size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'تخصيص عرض المتاجر',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DropdownButton<_CustomerMerchantSort>(
                  value: sortBy,
                  onChanged: (value) {
                    if (value == null) return;
                    onChangeSort(value);
                  },
                  items: const [
                    DropdownMenuItem(
                      value: _CustomerMerchantSort.recommended,
                      child: Text('المقترحة'),
                    ),
                    DropdownMenuItem(
                      value: _CustomerMerchantSort.openFirst,
                      child: Text('المفتوحة أولاً'),
                    ),
                    DropdownMenuItem(
                      value: _CustomerMerchantSort.offersFirst,
                      child: Text('الأفضل بالعروض'),
                    ),
                    DropdownMenuItem(
                      value: _CustomerMerchantSort.alphabetical,
                      child: Text('أبجدياً'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                FilterChip(
                  selected: favoritesOnly,
                  onSelected: onToggleFavoritesOnly,
                  label: const Text('المفضلة فقط'),
                  avatar: const Icon(Icons.favorite_rounded, size: 16),
                ),
              ],
            ),
          ],
        ),
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
                'جارٍ بناء ترتيب المتاجر الذكي لهذا التصنيف...',
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
              label: const Text('إعادة'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'تعذر تحميل ترتيب المتاجر الذكي، أعد المحاولة.',
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
              const Text(
                'لوحة الذكاء داخل التصنيف',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'الترتيب يعتمد على السرعة والتقييم والسعر والعروض بدون معيار القرب.',
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
                label: 'المتاجر',
                value: '$merchantCount',
              ),
              _MetricPill(
                icon: Icons.shopping_cart_checkout_rounded,
                label: 'طلباتك',
                value: '${profile.ordersCountInCategory120d}',
              ),
              _MetricPill(
                icon: Icons.account_balance_wallet_outlined,
                label: 'قدرتك الشرائية',
                value: spendingBandText,
              ),
              _MetricPill(
                icon: Icons.price_check_rounded,
                label: 'تفضيل السعر',
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
                          ? Image.network(
                              merchant.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
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
                              merchant.isOpen ? 'مفتوح' : 'مغلق',
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
          tooltip: 'السلة',
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
            tooltip: 'إدارة العناوين',
            onPressed: () => onOpenAddresses(),
            icon: const Icon(Icons.edit_location_alt_outlined),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'مدينة بسماية',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.90),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                if (addressState.loading)
                  const Text(
                    'جاري تحميل العناوين...',
                    textDirection: TextDirection.rtl,
                  )
                else if (selected == null && listItems.isEmpty)
                  InkWell(
                    onTap: () => onOpenAddresses(selectMode: true),
                    child: Text(
                      'أضف عنوان توصيل للبدء',
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
                        hint: const Text('اختر عنوان التوصيل'),
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
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _CategoryPill(
            label: 'الكل',
            icon: Icons.grid_view_rounded,
            selected: selectedType == null,
            onTap: () => onSelectType(null),
          ),
          const SizedBox(width: 8),
          _CategoryPill(
            label: 'مطاعم',
            icon: Icons.restaurant_menu_rounded,
            selected: selectedType == 'restaurant',
            onTap: () => onSelectType('restaurant'),
          ),
          const SizedBox(width: 8),
          _CategoryPill(
            label: 'أسواق',
            icon: Icons.storefront_rounded,
            selected: selectedType == 'market',
            onTap: () => onSelectType('market'),
          ),
        ],
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

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, size: 34),
            const SizedBox(height: 8),
            const Text(
              'لا توجد نتائج مطابقة',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'جرّب البحث باسم مختلف أو اختر قسمًا آخر',
              textDirection: TextDirection.rtl,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.76)),
            ),
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

  @override
  Widget build(BuildContext context) {
    final typeLabel = merchant.type == 'restaurant' ? 'مطعم' : 'متجر';
    final hasOffers =
        merchant.hasDiscountOffer || merchant.hasFreeDeliveryOffer;
    final deliveryLabel = merchant.hasFreeDeliveryOffer
        ? 'توصيل مجاني'
        : formatIqd(deliveryFeeIqd);
    final etaLabel = merchant.isOpen ? '25 - 40 دقيقة' : 'خارج الدوام';
    final statusLabel = merchant.isOpen ? 'مفتوح الآن' : 'مغلق الآن';

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
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 66,
                        height: 66,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(
                                  width: 66,
                                  height: 66,
                                  child: merchant.imageUrl?.isNotEmpty == true
                                      ? Image.network(
                                          merchant.imageUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (
                                                context,
                                                error,
                                                stackTrace,
                                              ) => Container(
                                                color: Colors.white.withValues(
                                                  alpha: 0.10,
                                                ),
                                                alignment: Alignment.center,
                                                child: Icon(
                                                  merchant.type == 'restaurant'
                                                      ? Icons.restaurant_rounded
                                                      : Icons
                                                            .storefront_rounded,
                                                ),
                                              ),
                                        )
                                      : Container(
                                          color: Colors.white.withValues(
                                            alpha: 0.10,
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            merchant.type == 'restaurant'
                                                ? Icons.restaurant_rounded
                                                : Icons.storefront_rounded,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            if (onToggleFavorite != null)
                              Positioned(
                                left: 2,
                                top: 2,
                                child: Material(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: onToggleFavorite,
                                    child: Padding(
                                      padding: const EdgeInsets.all(5),
                                      child: Icon(
                                        isFavorite
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        size: 16,
                                        color: isFavorite
                                            ? Colors.redAccent
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              merchant.name,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              merchant.description?.trim().isNotEmpty == true
                                  ? merchant.description!
                                  : 'متجر من قلب بسماية',
                              textDirection: TextDirection.rtl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                            ),
                            if (hasOffers) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                alignment: WrapAlignment.end,
                                children: [
                                  if (merchant.hasDiscountOffer)
                                    const _MetaChip(
                                      icon: Icons.local_offer_rounded,
                                      text: 'عروض خصم',
                                    ),
                                  if (merchant.hasFreeDeliveryOffer)
                                    const _MetaChip(
                                      icon: Icons.local_shipping_rounded,
                                      text: 'توصيل مجاني',
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      textDirection: TextDirection.rtl,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: merchant.isOpen
                                ? Colors.green.withValues(alpha: 0.20)
                                : Colors.red.withValues(alpha: 0.20),
                            border: Border.all(
                              color: merchant.isOpen
                                  ? Colors.green.withValues(alpha: 0.45)
                                  : Colors.red.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            statusLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _MetaChip(
                          icon: Icons.category_rounded,
                          text: typeLabel,
                        ),
                        _MetaChip(
                          icon: Icons.local_shipping_rounded,
                          text: deliveryLabel,
                        ),
                        _MetaChip(
                          icon: Icons.schedule_rounded,
                          text: etaLabel,
                          maxTextWidth: 118,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('الكل'),
            selected: selectedType == null,
            onSelected: (_) => onSelectType(null),
          ),
          ChoiceChip(
            label: const Text('مطاعم'),
            selected: selectedType == 'restaurant',
            onSelected: (_) => onSelectType('restaurant'),
          ),
          ChoiceChip(
            label: const Text('أسواق'),
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
