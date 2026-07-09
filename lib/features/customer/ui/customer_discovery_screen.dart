import 'dart:async';
import 'dart:math' as math;

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../../core/widgets/maslaki_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import '../../auth/ui/merchants_list_screen.dart';
import '../../behavior/data/behavior_api.dart';
import '../models/customer_home_prefs.dart';
import '../models/customer_ad_board_item.dart';
import '../state/customer_ad_board_controller.dart';
import '../state/customer_home_prefs_controller.dart';
import 'customer_cars_hub_screen.dart';
import 'ad_campaign_details_screen.dart';
import 'customer_electronics_hub_screen.dart';
import 'customer_food_hub_screen.dart';
import 'customer_home_shopping_hub_screen.dart';
import 'customer_main_market_screen.dart';
import 'customer_personalization_dialog.dart';
import 'fashion_market_screen.dart';
import '../../merchants/state/merchants_controller.dart';
import '../../orders/state/cart_controller.dart';
import '../../orders/ui/cart_screen.dart';
import '../../orders/ui/customer_orders_screen.dart';
import '../../../pages/map_page.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

enum CustomerDiscoveryMode { full, shoppingOnly }

class CustomerDiscoveryScreen extends ConsumerStatefulWidget {
  final CustomerDiscoveryMode mode;
  final String? initialType;
  final String initialSearchQuery;
  final String? initialTitle;

  const CustomerDiscoveryScreen({
    super.key,
    this.mode = CustomerDiscoveryMode.full,
    this.initialType,
    this.initialSearchQuery = '',
    this.initialTitle,
  });

  @override
  ConsumerState<CustomerDiscoveryScreen> createState() =>
      _CustomerDiscoveryScreenState();
}

const List<(Color, Color)> _splashGradientPairs = [
  (Color(0xFF0D1B2A), Color(0xFF11243A)),
  (Color(0xFF11243A), Color(0xFF14263D)),
  (Color(0xFF162A42), Color(0xFF0D1B2A)),
  (Color(0xFF14263D), Color(0xFF162A42)),
  (Color(0xFF11243A), Color(0xFF0D1B2A)),
];

(Color, Color) _splashPairForSeed(String seed) {
  final safeSeed = seed.trim();
  final idx = safeSeed.isEmpty
      ? 0
      : safeSeed.hashCode.abs() % _splashGradientPairs.length;
  return _splashGradientPairs[idx];
}

class _CustomerDiscoveryScreenState
    extends ConsumerState<CustomerDiscoveryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final PageController _adController = PageController(viewportFraction: 0.92);

  String _searchQuery = '';
  int _adPage = 0;
  int _adItemsCount = _defaultAdBanners.length;
  bool _didCheckPersonalization = false;
  bool _didApplyInitialShoppingIntent = false;

  bool get _isShoppingOnly => widget.mode == CustomerDiscoveryMode.shoppingOnly;

  bool get _isEnglish => context.isEnglishLocale;

  Future<void> _trackBehaviorEvent({
    required String eventName,
    String? category,
    String? action,
    Map<String, dynamic>? metadata,
  }) async {
    await ref
        .read(behaviorApiProvider)
        .trackEvent(
          eventName: eventName,
          category: category,
          action: action,
          metadata: metadata,
        );
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final next = _searchCtrl.text.trim();
      if (next == _searchQuery) return;
      setState(() => _searchQuery = next);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapDiscoveryData());
    });
  }

  Future<void> _bootstrapDiscoveryData() async {
    final merchantsState = ref.read(merchantsControllerProvider);
    final needsMerchantsLoad =
        !merchantsState.hasValue ||
        (merchantsState.valueOrNull?.isEmpty ?? true);
    if (needsMerchantsLoad) {
      await ref.read(merchantsControllerProvider.notifier).load();
    }
    if (!mounted) return;
    if (!_isShoppingOnly) {
      final adBoardState = ref.read(customerAdBoardControllerProvider);
      final needsAdBoardLoad =
          !adBoardState.hasValue || (adBoardState.valueOrNull?.isEmpty ?? true);
      if (needsAdBoardLoad) {
        unawaited(ref.read(customerAdBoardControllerProvider.notifier).load());
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrapPersonalizationIfNeeded());
      _applyInitialShoppingIntentIfNeeded();
    });
  }

  void _applyInitialShoppingIntentIfNeeded() {
    if (_didApplyInitialShoppingIntent) return;

    final cleanType = widget.initialType?.trim();
    final cleanTitle = widget.initialTitle?.trim();
    final cleanQuery = widget.initialSearchQuery.trim();
    final hasIntent =
        (cleanType != null && cleanType.isNotEmpty) ||
        cleanQuery.isNotEmpty ||
        (cleanTitle != null && cleanTitle.isNotEmpty);
    if (!hasIntent) return;

    _didApplyInitialShoppingIntent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openSearchResult(
        type: cleanType == null || cleanType.isEmpty ? null : cleanType,
        query: cleanQuery,
        title: cleanTitle == null || cleanTitle.isEmpty ? null : cleanTitle,
      );
    });
  }

  @override
  void dispose() {
    _adController.dispose();
    _searchFocus.dispose();
    _searchCtrl.dispose();
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

  Future<void> _openMapPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MapPage()));
  }

  Future<void> _openDiscoveryHub(_DiscoveryHub hub) async {
    if (_isShoppingOnly && hub.id == 'cars') {
      return;
    }
    await _trackBehaviorEvent(
      eventName: 'discovery.hub_open',
      category: 'discovery',
      action: 'open_hub',
      metadata: {'hubId': hub.id, 'hubTitle': hub.titleFor(context)},
    );
    if (!mounted) return;

    switch (hub.id) {
      case 'style':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FashionMarketScreen()),
        );
        return;
      case 'food':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerFoodHubScreen()),
        );
        return;
      case 'home':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CustomerHomeShoppingHubScreen(),
          ),
        );
        return;
      case 'electronics':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CustomerElectronicsHubScreen(),
          ),
        );
        return;
      case 'cars':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerCarsHubScreen()),
        );
        return;
      case 'pharmacy':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MerchantsListScreen(
              initialType: 'market',
              initialActivityType: 'pharmacy',
              overrideTitle: context.l10n.customerDiscoveryHubPharmacyTitle,
              compactCustomerMode: true,
            ),
          ),
        );
        return;
      case 'main_market':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerMainMarketScreen()),
        );
        return;
    }
  }

  Future<void> _bootstrapPersonalizationIfNeeded() async {
    if (_didCheckPersonalization) return;
    _didCheckPersonalization = true;

    final auth = ref.read(authControllerProvider);
    if (auth.isBackoffice || auth.isOwner || auth.isDelivery) return;
    final userId = auth.user?.id;
    if (userId == null) return;

    await ref
        .read(customerHomePrefsProvider.notifier)
        .bootstrap(userId: userId);
    if (!mounted) return;

    final prefs =
        ref.read(customerHomePrefsProvider).valueOrNull ??
        CustomerHomePrefs.empty;
    if (prefs.completed) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showPersonalizationDialog(userId);
    });
  }

  Future<void> _showPersonalizationDialog(int userId) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return CustomerPersonalizationDialog(
          onSubmit:
              ({
                required audience,
                required priority,
                required interests,
              }) async {
                await ref
                    .read(customerHomePrefsProvider.notifier)
                    .completeOnboarding(
                      userId: userId,
                      audience: audience,
                      priority: priority,
                      interests: interests,
                    );
              },
        );
      },
    );
  }

  void _openCategory(_DiscoveryCategory category) {
    final localizedTitle = category.titleFor(context);
    unawaited(
      _trackBehaviorEvent(
        eventName: 'discovery.category_open',
        category: 'discovery',
        action: 'open_category',
        metadata: {
          'categoryTitle': localizedTitle,
          'merchantType': category.type,
          'seedQuery': category.seedQuery,
        },
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialType: category.type,
          initialSearchQuery: category.seedQuery,
          overrideTitle: localizedTitle,
          compactCustomerMode: true,
          applyInitialSearchQuery: false,
        ),
      ),
    );
  }

  void _openSearchResult({String? type, required String query, String? title}) {
    final cleanQuery = query.trim();
    unawaited(
      _trackBehaviorEvent(
        eventName: 'discovery.search_open_result',
        category: 'discovery',
        action: 'search',
        metadata: {
          'searchQuery': cleanQuery,
          'merchantType': type,
          'title': title,
        },
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialType: type,
          initialSearchQuery: cleanQuery,
          overrideTitle:
              title ??
              (cleanQuery.isEmpty
                  ? context.l10n.customerDiscoveryMerchants
                  : cleanQuery),
          compactCustomerMode: true,
        ),
      ),
    );
  }

  void _onSubmitSearch() {
    final text = _searchQuery.trim();
    if (text.isEmpty) return;
    unawaited(
      _trackBehaviorEvent(
        eventName: 'discovery.search_submit',
        category: 'discovery',
        action: 'search_submit',
        metadata: {'searchQuery': text},
      ),
    );
    final query = text.toLowerCase();

    for (final hub in _discoveryHubs) {
      if (_isShoppingOnly && hub.id == 'cars') continue;
      if (hub.searchBucket.contains(query)) {
        _openDiscoveryHub(hub);
        return;
      }
    }

    for (final category in _categories) {
      if (category.searchBucket.contains(query)) {
        _openCategory(category);
        return;
      }
    }

    _openSearchResult(
      query: text,
      title: context.l10n.customerDiscoveryResultsFor(text),
    );
  }

  Future<void> _openAdBanner(_DisplayAdBanner banner) async {
    if (_isShoppingOnly && banner.ctaTargetType == 'taxi') {
      return;
    }

    unawaited(
      _trackBehaviorEvent(
        eventName: 'discovery.ad_click',
        category: 'ads',
        action: 'click',
        metadata: {
          'adTitle': banner.title,
          'ctaType': banner.ctaTargetType,
          'merchantId': banner.merchantId,
          'merchantName': banner.merchantName,
          'ctaValue': banner.ctaTargetValue,
        },
      ),
    );

    if (banner.ctaTargetType == 'internal_campaign_page') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AdCampaignDetailsScreen(
            title: banner.title,
            subtitle: banner.subtitle,
            badgeLabel: banner.badgeLabel,
            imageUrl: banner.imageUrl,
            merchantName: banner.merchantName,
            ctaLabel: banner.ctaLabel,
            onPrimaryAction: () => _openInternalCampaignAction(banner),
          ),
        ),
      );
      return;
    }

    await _openStandardAdAction(banner);
  }

  Future<void> _openStandardAdAction(_DisplayAdBanner banner) async {
    switch (banner.ctaTargetType) {
      case 'merchant':
        final query = (banner.merchantName ?? banner.ctaTargetValue ?? '')
            .trim();
        if (query.isNotEmpty) {
          _openSearchResult(
            type: banner.merchantType,
            query: query,
            title: banner.merchantName ?? banner.title,
          );
        }
        return;
      case 'category':
        final value = (banner.ctaTargetValue ?? '').trim();
        if (value.isNotEmpty) {
          _openSearchResult(type: value, query: '', title: banner.title);
        }
        return;
      case 'product':
        final query = (banner.merchantName ?? '').trim();
        if (query.isNotEmpty) {
          _openSearchResult(
            type: banner.merchantType,
            query: query,
            title: banner.merchantName ?? banner.title,
          );
        }
        return;
      case 'taxi':
        await _openMapPage();
        return;
      case 'url':
        final raw = (banner.ctaTargetValue ?? '').trim();
        final uri = Uri.tryParse(raw);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.commonOpenLinkFailed)),
        );
        return;
      default:
        if ((banner.merchantName ?? '').trim().isNotEmpty) {
          _openSearchResult(
            type: banner.merchantType,
            query: banner.merchantName!,
            title: banner.title,
          );
        }
        return;
    }
  }

  Future<void> _openInternalCampaignAction(_DisplayAdBanner banner) async {
    if ((banner.merchantName ?? '').trim().isNotEmpty) {
      _openSearchResult(
        type: banner.merchantType,
        query: banner.merchantName!,
        title: banner.merchantName ?? banner.title,
      );
      return;
    }
    final raw = (banner.ctaTargetValue ?? '').trim();
    if (raw.isEmpty) return;
    if (raw.toLowerCase() == 'taxi') {
      await _openMapPage();
      return;
    }
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    _openSearchResult(query: '', type: raw, title: banner.title);
  }

  List<_DisplayAdBanner> _buildDisplayAdBanners(
    List<CustomerAdBoardItem>? items,
  ) {
    if (items == null || items.isEmpty) {
      return _defaultAdBanners
          .map((b) {
            final title = b.titleFor(context);
            final pair = _splashPairForSeed(title);
            return _DisplayAdBanner(
              title: title,
              subtitle: b.subtitleFor(context),
              icon: b.icon,
              colorA: pair.$1,
              colorB: pair.$2,
            );
          })
          .toList(growable: false);
    }

    return items
        .map((item) {
          final icon = _iconForAdTarget(item.ctaTargetType, item.merchantType);
          final colors = _colorsForAd(item.priority, item.merchantType);
          return _DisplayAdBanner(
            title: item.title,
            subtitle: item.subtitle,
            imageUrl: item.imageUrl,
            badgeLabel: item.badgeLabel,
            ctaLabel: item.ctaLabel,
            ctaTargetType: item.ctaTargetType,
            ctaTargetValue: item.ctaTargetValue,
            merchantId: item.merchantId,
            merchantName: item.merchantName,
            merchantType: item.merchantType,
            icon: icon,
            colorA: colors.$1,
            colorB: colors.$2,
          );
        })
        .toList(growable: false);
  }

  Widget _buildQuickStatActions({
    required int openCount,
    required int offersCount,
    required int restaurantsCount,
    required int marketsCount,
  }) {
    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: !_isEnglish,
        children: [
          _DiscoveryQuickStatCard(
            icon: Icons.storefront_outlined,
            title: context.l10n.customerDiscoveryOpenNow,
            subtitle: context.l10n.customerDiscoveryOpenStores,
            value: '$openCount',
            onTap: () => _openSearchResult(
              query: 'مفتوح الآن',
              title: context.l10n.customerDiscoveryOpenMerchants,
            ),
          ),
          const SizedBox(width: 8),
          _DiscoveryQuickStatCard(
            icon: Icons.local_offer_outlined,
            title: context.l10n.customerDiscoveryOffers,
            subtitle: context.l10n.customerDiscoveryCurrentDiscounts,
            value: '$offersCount',
            onTap: () => _openSearchResult(
              query: 'عروض',
              title: context.l10n.customerDiscoveryTodayOffers,
            ),
          ),
          const SizedBox(width: 8),
          _DiscoveryQuickStatCard(
            icon: Icons.restaurant_outlined,
            title: context.l10n.customerDiscoveryRestaurants,
            subtitle: context.l10n.customerDiscoveryAllInOnePlace,
            value: '$restaurantsCount',
            onTap: () => _openSearchResult(
              type: 'restaurant',
              query: '',
              title: context.l10n.customerDiscoveryRestaurants,
            ),
          ),
          const SizedBox(width: 8),
          _DiscoveryQuickStatCard(
            icon: Icons.shopping_cart_outlined,
            title: context.l10n.customerDiscoveryStores,
            subtitle: context.l10n.customerDiscoverySupermarketsAndMore,
            value: '$marketsCount',
            onTap: () => _openSearchResult(
              type: 'market',
              query: '',
              title: context.l10n.customerDiscoveryStores,
            ),
          ),
          if (!_isShoppingOnly) ...[
            const SizedBox(width: 8),
            _DiscoveryQuickStatCard(
              icon: Icons.local_taxi_outlined,
              title: context.l10n.customerDiscoveryTaxi,
              subtitle: context.l10n.customerDiscoveryQuickRequest,
              value: '',
              onTap: () => unawaited(_openMapPage()),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForAdTarget(String ctaType, String? merchantType) {
    switch (ctaType) {
      case 'taxi':
        return Icons.local_taxi_rounded;
      case 'url':
        return Icons.open_in_new_rounded;
      case 'internal_campaign_page':
        return Icons.auto_awesome_rounded;
      case 'category':
        return Icons.category_rounded;
      case 'product':
        return Icons.inventory_2_rounded;
      case 'merchant':
        if (merchantType == 'restaurant') return Icons.restaurant_rounded;
        return Icons.storefront_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  (Color, Color) _colorsForAd(int priority, String? merchantType) {
    if (merchantType == 'restaurant') {
      return (const Color(0xFF14263D), const Color(0xFF11243A));
    }
    if (merchantType == 'market') {
      return (const Color(0xFF11243A), const Color(0xFF162A42));
    }
    if (priority < 20) {
      return (const Color(0xFF162A42), const Color(0xFF11243A));
    }
    return (const Color(0xFF0D1B2A), const Color(0xFF11243A));
  }

  List<_DiscoveryHub> _orderedDiscoveryHubs(CustomerHomePrefs prefs) {
    final regularHubs = _discoveryHubs
        .where((hub) => hub.id != 'main_market')
        .toList(growable: false);
    final mainMarket = _discoveryHubs.firstWhere(
      (hub) => hub.id == 'main_market',
    );

    if (!prefs.completed) {
      final defaults = <_DiscoveryHub>[...regularHubs];
      final pharmacyIndex = defaults.indexWhere((hub) => hub.id == 'pharmacy');
      if (pharmacyIndex > 0) {
        final pharmacyHub = defaults.removeAt(pharmacyIndex);
        defaults.insert(0, pharmacyHub);
      }
      return [mainMarket, ...defaults];
    }

    final scored = regularHubs
        .map(
          (hub) => MapEntry<String, int>(
            hub.id,
            _hubScore(
              hubId: hub.id,
              audience: prefs.audience,
              priority: prefs.priority,
              interests: prefs.interests,
            ),
          ),
        )
        .toList();

    final preferredIds = scored.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final visible = preferredIds
        .map((entry) => regularHubs.firstWhere((hub) => hub.id == entry.key))
        .toList();

    if (visible.isEmpty) {
      visible.addAll(regularHubs);
    }

    final carsHub = regularHubs.firstWhere((hub) => hub.id == 'cars');
    if (!visible.any((hub) => hub.id == 'cars')) {
      visible.add(carsHub);
    }

    final pharmacyHub = regularHubs.firstWhere((hub) => hub.id == 'pharmacy');
    visible.removeWhere((hub) => hub.id == 'pharmacy');
    visible.insert(0, pharmacyHub);

    return [mainMarket, ...visible];
  }

  int _hubScore({
    required String hubId,
    required String audience,
    required String priority,
    required List<String> interests,
  }) {
    final interestSet = interests.toSet();
    var score = 0;

    bool hasAny(Iterable<String> keys) =>
        keys.any((key) => interestSet.contains(key));

    if (hubId == 'style' &&
        hasAny(const [
          'women_fashion',
          'men_fashion',
          'shoes',
          'bags',
          'beauty',
        ])) {
      score += 180;
    }
    if (hubId == 'food' && hasAny(const ['restaurants', 'sweets', 'coffee'])) {
      score += 180;
    }
    if (hubId == 'home' &&
        hasAny(const ['markets', 'home', 'kids', 'gifts', 'sports'])) {
      score += 180;
    }
    if (hubId == 'electronics' && interestSet.contains('electronics')) {
      score += 180;
    }
    if (hubId == 'cars' && interestSet.contains('cars')) {
      score += 180;
    }

    switch (audience) {
      case 'women':
      case 'men':
        if (hubId == 'style') score += 85;
        break;
      case 'family':
        if (hubId == 'food') score += 55;
        if (hubId == 'home') score += 75;
        break;
      default:
        break;
    }

    switch (priority) {
      case 'speed':
        if (hubId == 'food') score += 35;
        if (hubId == 'home') score += 20;
        break;
      case 'price':
      case 'offers':
        if (hubId == 'home') score += 35;
        if (hubId == 'style') score += 20;
        break;
      case 'rating':
        if (hubId == 'food') score += 30;
        if (hubId == 'style') score += 20;
        if (hubId == 'electronics') score += 20;
        if (hubId == 'cars') score += 30;
        break;
      default:
        break;
    }

    return score;
  }

  String _firstName(String? fullName) {
    if (fullName == null) return '';
    final clean = fullName.trim();
    if (clean.isEmpty) return '';
    return clean.split(RegExp(r'\s+')).first;
  }

  String _appBarGreeting(String? fullName) {
    final first = _firstName(fullName);
    if (first.isEmpty) return context.l10n.customerHomeWelcome;
    return context.l10n.customerHomeHiName(first);
  }

  _TimeGreeting _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) {
      return const _TimeGreeting(
        titleAr: 'صباح الخير',
        titleEn: 'Good morning',
        taglineAr: 'كلشي حاضر، اطلب اللي يعجبك وخله يوصلك.',
        taglineEn:
            'Everything is ready. Order what you like and have it delivered.',
      );
    }
    if (hour >= 11 && hour < 14) {
      return const _TimeGreeting(
        titleAr: 'هلا بالظهر',
        titleEn: 'Good afternoon',
        taglineAr: 'إذا جوعان أو محتاج شي، طلبك ينطلب هسه.',
        taglineEn:
            'If you are hungry or need something, your order can start right now.',
      );
    }
    if (hour >= 14 && hour < 17) {
      return const _TimeGreeting(
        titleAr: 'عصر الخير',
        titleEn: 'Good afternoon',
        taglineAr: 'العروض شغالة، وطلبك يوصل بدون لفة.',
        taglineEn:
            'Offers are live, and your order arrives without extra delay.',
      );
    }
    if (hour >= 17 && hour < 19) {
      return const _TimeGreeting(
        titleAr: 'مساء الخير',
        titleEn: 'Good evening',
        taglineAr: 'خذ راحتك، واختار اللي تحتاجه لليلية.',
        taglineEn: 'Take your time and pick what you need for the evening.',
      );
    }
    return const _TimeGreeting(
      titleAr: 'هلا بالليل',
      titleEn: 'Late night',
      taglineAr: 'إذا تحتاج طلب متأخر، بعدنا وياك.',
      taglineEn: 'If you need a late order, we are still with you.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final shoppingSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.shopping, displayName: 'التسوق');
    if (shoppingSection.isBlocked) {
      return SectionUnavailableScreen(entry: shoppingSection);
    }
    final merchantsState = ref.watch(merchantsControllerProvider);
    final adBoardState = ref.watch(customerAdBoardControllerProvider);
    final userFullName = ref.watch(
      authControllerProvider.select((state) => state.user?.fullName),
    );
    final cartItems = ref.watch(
      cartControllerProvider.select((v) => v.totalItems),
    );
    final timeGreeting = _timeGreeting();
    final homePrefs =
        ref.watch(customerHomePrefsProvider).valueOrNull ??
        CustomerHomePrefs.empty;
    final personalizedHubs = _orderedDiscoveryHubs(homePrefs);
    final visibleHubs = _isShoppingOnly
        ? personalizedHubs
              .where((hub) => hub.id != 'cars')
              .toList(growable: false)
        : personalizedHubs;
    final bodyContent = merchantsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _ErrorView(
        onRetry: () =>
            ref.read(merchantsControllerProvider.notifier).load(force: true),
      ),
      data: (merchants) {
        final displayAds = _isShoppingOnly
            ? const <_DisplayAdBanner>[]
            : _buildDisplayAdBanners(adBoardState.valueOrNull);
        if (!_isShoppingOnly && _adItemsCount != displayAds.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _adItemsCount = displayAds.isEmpty ? 1 : displayAds.length;
              if (_adPage >= _adItemsCount) _adPage = 0;
            });
          });
        }
        final openCount = merchants.where((m) => m.isOpen).length;
        final offersCount = merchants
            .where((m) => m.hasDiscountOffer || m.hasFreeDeliveryOffer)
            .length;
        final restaurantsCount = merchants
            .where((m) => m.type == 'restaurant')
            .length;
        final marketsCount = merchants.where((m) => m.type == 'market').length;

        return RefreshIndicator(
          onRefresh: () async {
            await ref
                .read(merchantsControllerProvider.notifier)
                .load(force: true);
            if (!_isShoppingOnly) {
              await ref
                  .read(customerAdBoardControllerProvider.notifier)
                  .load(force: true);
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            children: [
              _HeroWelcomeCard(greeting: timeGreeting),
              if (!_isShoppingOnly) ...[
                const SizedBox(height: 10),
                _AdsCarousel(
                  controller: _adController,
                  page: _adPage,
                  banners: displayAds,
                  onTapBanner: _openAdBanner,
                ),
              ],
              const SizedBox(height: 12),
              _SearchPanel(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onSubmit: _onSubmitSearch,
                onQuickSearch: (value) {
                  _searchCtrl.text = value;
                  _searchCtrl.selection = TextSelection.collapsed(
                    offset: _searchCtrl.text.length,
                  );
                  _onSubmitSearch();
                },
              ),
              const SizedBox(height: 14),
              Text(
                context.l10n.customerDiscoveryMainCategories,
                textDirection: context.appTextDirection,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              ListView.separated(
                itemCount: visibleHubs.length,
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  final hub = visibleHubs[index];
                  return _DiscoveryHubCard(
                    hub: hub,
                    index: index,
                    onTap: () => _openDiscoveryHub(hub),
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(height: 10),
              ),
              if (!_isShoppingOnly) ...[
                const SizedBox(height: 12),
                _TaxiServiceSpotlightCard(onTap: _openMapPage),
              ],
              const SizedBox(height: 12),
              _IntentLauncherStrip(
                onTaxi: _openMapPage,
                showTaxi: !_isShoppingOnly,
                onOffers: () => _openSearchResult(
                  query: context.l10n.customerDiscoverySearchQueryOffers,
                  title: context.l10n.customerDiscoveryTodayOffers,
                ),
                onTopRated: () => _openSearchResult(
                  query: context.l10n.customerDiscoverySearchQueryTopRated,
                  title: context.l10n.customerDiscoveryTopRated,
                ),
                onReorder: _openOrders,
              ),
              const SizedBox(height: 12),
              _buildQuickStatActions(
                openCount: openCount,
                offersCount: offersCount,
                restaurantsCount: restaurantsCount,
                marketsCount: marketsCount,
              ),
            ],
          ),
        );
      },
    );

    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      endDrawer: const MaslakiUserDrawer(),
      appBar: MaslakiTopBar(
        title: _appBarGreeting(userFullName),
        subtitle: _isShoppingOnly
            ? context.lt(
                ar: 'تصفح الفئات والمتاجر والمنتجات بدون تشتيت.',
                en: 'Browse categories, stores, and products without clutter.',
              )
            : context.l10n.customerDiscoveryMarketSubtitle,
        leading: canPop
            ? IconButton(
                tooltip: context.l10n.commonBack,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : const MaslakiUserDrawerButton(),
        actions: [
          if (canPop) const MaslakiUserDrawerButton(),
          IconButton(
            tooltip: context.l10n.customerDiscoveryOrders,
            onPressed: _openOrders,
            icon: const Icon(Icons.receipt_long_rounded),
          ),
          if (!_isShoppingOnly)
            IconButton(
              tooltip: context.l10n.customerDiscoveryTaxi,
              onPressed: _openMapPage,
              icon: const Icon(Icons.local_taxi_outlined),
            ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: context.l10n.customerDiscoveryCart,
                onPressed: _openCart,
                icon: const Icon(Icons.shopping_bag_outlined),
              ),
              if (cartItems > 0)
                PositionedDirectional(
                  top: 7,
                  end: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.maslakiTokens.primaryAccent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$cartItems',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.maslakiTokens.backgroundPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: bodyContent,
    );
  }
}

class _TimeGreeting {
  final String titleAr;
  final String titleEn;
  final String taglineAr;
  final String taglineEn;

  const _TimeGreeting({
    required this.titleAr,
    required this.titleEn,
    required this.taglineAr,
    required this.taglineEn,
  });

  String titleFor(BuildContext context) {
    final l10n = context.l10n;
    return switch (taglineEn) {
      'Everything is ready. Order what you like and have it delivered.' =>
        l10n.customerDiscoveryGreetingMorningTitle,
      'If you are hungry or need something, your order can start right now.' =>
        l10n.customerDiscoveryGreetingNoonTitle,
      'Offers are live, and your order arrives without extra delay.' =>
        l10n.customerDiscoveryGreetingAfternoonTitle,
      'Take your time and pick what you need for the evening.' =>
        l10n.customerDiscoveryGreetingEveningTitle,
      'If you need a late order, we are still with you.' =>
        l10n.customerDiscoveryGreetingNightTitle,
      _ => titleEn,
    };
  }

  String taglineFor(BuildContext context) {
    final l10n = context.l10n;
    return switch (taglineEn) {
      'Everything is ready. Order what you like and have it delivered.' =>
        l10n.customerDiscoveryGreetingMorningTagline,
      'If you are hungry or need something, your order can start right now.' =>
        l10n.customerDiscoveryGreetingNoonTagline,
      'Offers are live, and your order arrives without extra delay.' =>
        l10n.customerDiscoveryGreetingAfternoonTagline,
      'Take your time and pick what you need for the evening.' =>
        l10n.customerDiscoveryGreetingEveningTagline,
      'If you need a late order, we are still with you.' =>
        l10n.customerDiscoveryGreetingNightTagline,
      _ => taglineEn,
    };
  }
}

class _HeroWelcomeCard extends StatefulWidget {
  final _TimeGreeting greeting;

  const _HeroWelcomeCard({required this.greeting});

  @override
  State<_HeroWelcomeCard> createState() => _HeroWelcomeCardState();
}

class _HeroWelcomeCardState extends State<_HeroWelcomeCard> {
  @override
  Widget build(BuildContext context) {
    const pulse = 1.0;
    const halo = 0.12;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF14263D), Color(0xFF0D1B2A)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: halo),
              blurRadius: 22,
              spreadRadius: 0.4,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -22,
              left: -12,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: -18,
              right: -8,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: context.isEnglishLocale
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Text(
                    widget.greeting.titleFor(context),
                    textDirection: context.appTextDirection,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.greeting.taglineFor(context),
                    textDirection: context.appTextDirection,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: context.isEnglishLocale
                        ? WrapAlignment.start
                        : WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        context.l10n.customerDiscoveryHeroWith,
                        textDirection: context.appTextDirection,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Transform.scale(
                        scale: pulse,
                        child: ShaderMask(
                          shaderCallback: (bounds) {
                            return const LinearGradient(
                              colors: [Color(0xFFE6C98A), Color(0xFFD4AF37)],
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'Maslaki',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        context.l10n.customerDiscoveryHeroCloserTagline,
                        textDirection: context.appTextDirection,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Transform.scale(
                        scale: pulse,
                        child: Icon(
                          Icons.local_fire_department_rounded,
                          color: scheme.primary,
                          size: 19,
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
  }
}

class _DiscoveryQuickStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onTap;

  const _DiscoveryQuickStatCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textDirection = context.appTextDirection;
    final crossAxisAlignment = context.isEnglishLocale
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;
    final rowAlignment = context.isEnglishLocale
        ? MainAxisAlignment.start
        : MainAxisAlignment.end;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          width: 168,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                scheme.primary.withValues(alpha: 0.2),
                scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ],
            ),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
          ),
          child: Row(
            textDirection: textDirection,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: scheme.primary.withValues(alpha: 0.18),
                child: Icon(icon, size: 17, color: scheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: crossAxisAlignment,
                  children: [
                    Row(
                      mainAxisAlignment: rowAlignment,
                      textDirection: textDirection,
                      children: [
                        if (value.isNotEmpty) ...[
                          Text(
                            value,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            title,
                            textDirection: textDirection,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: context.isEnglishLocale
                                ? TextAlign.start
                                : TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      textDirection: textDirection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaxiServiceSpotlightCard extends StatefulWidget {
  final VoidCallback onTap;

  const _TaxiServiceSpotlightCard({required this.onTap});

  @override
  State<_TaxiServiceSpotlightCard> createState() =>
      _TaxiServiceSpotlightCardState();
}

class _TaxiServiceSpotlightCardState extends State<_TaxiServiceSpotlightCard> {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    const wave = 0.35;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF14263D), Color(0xFF0D1B2A)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        textDirection: context.appTextDirection,
        children: [
          SizedBox(
            width: 74,
            height: 74,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.92 + (0.12 * wave),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.local_taxi_rounded,
                      color: scheme.primary,
                      size: 30,
                    ),
                  ),
                ),
                Positioned(
                  top: 8 + (34 * wave),
                  right: 4,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: context.isEnglishLocale
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text(
                  context.l10n.customerDiscoveryTaxiSpotlightTitle,
                  textDirection: context.appTextDirection,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.customerDiscoveryTaxiSpotlightBody,
                  textDirection: context.appTextDirection,
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: widget.onTap,
                  icon: const Icon(Icons.navigation_rounded),
                  label: Text(
                    context.l10n.customerDiscoveryTaxiSpotlightAction,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: const Color(0xFF0D1B2A),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdsCarousel extends StatelessWidget {
  final PageController controller;
  final int page;
  final List<_DisplayAdBanner> banners;
  final Future<void> Function(_DisplayAdBanner banner) onTapBanner;

  const _AdsCarousel({
    required this.controller,
    required this.page,
    required this.banners,
    required this.onTapBanner,
  });

  @override
  Widget build(BuildContext context) {
    if (banners.isEmpty) {
      return const SizedBox.shrink();
    }

    final textDirection = context.appTextDirection;
    final crossAxisAlignment = context.isEnglishLocale
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;
    final ctaArrow = context.isEnglishLocale
        ? Icons.arrow_forward_rounded
        : Icons.arrow_back_rounded;

    return Column(
      children: [
        SizedBox(
          height: 112,
          child: PageView.builder(
            controller: controller,
            itemCount: banners.length,
            itemBuilder: (context, index) {
              final banner = banners[index];
              final pair = _splashPairForSeed(
                '${banner.title}:${banner.ctaTargetType}:${banner.merchantType ?? ''}',
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onTapBanner(banner),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: pair.$1.withValues(alpha: 0.16),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                                colors: [pair.$1, pair.$2],
                              ),
                            ),
                          ),
                        ),
                        if ((banner.imageUrl ?? '').trim().isNotEmpty)
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: CachedAppImage(
                                imageUrl: banner.imageUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (context, error, stackTrace) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.12),
                                  Colors.black.withValues(alpha: 0.46),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            textDirection: textDirection,
                            children: [
                              Icon(banner.icon, size: 26),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: crossAxisAlignment,
                                  children: [
                                    if ((banner.badgeLabel ?? '')
                                        .trim()
                                        .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            color: Colors.black.withValues(
                                              alpha: 0.22,
                                            ),
                                          ),
                                          child: Text(
                                            banner.badgeLabel!,
                                            textDirection: textDirection,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    Text(
                                      banner.title,
                                      textDirection: textDirection,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      banner.subtitle,
                                      textDirection: textDirection,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.86,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(ctaArrow, size: 22),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(banners.length, (index) {
            final active = index == page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white.withValues(alpha: 0.28),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SearchPanel extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final ValueChanged<String> onQuickSearch;

  const _SearchPanel({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onQuickSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: controller,
              focusNode: focusNode,
              textDirection: context.appTextDirection,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: context.l10n.customerDiscoverySearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  onPressed: onSubmit,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                reverse: !context.isEnglishLocale,
                children: [
                  _quickChip(
                    icon: Icons.local_offer_rounded,
                    label: context.l10n.customerDiscoveryTodayOffers,
                    onTap: () => onQuickSearch('عروض اليوم'),
                  ),
                  _quickChip(
                    icon: Icons.flash_on_rounded,
                    label: context.l10n.customerDiscoveryFastestDelivery,
                    onTap: () => onQuickSearch('الأسرع توصيلًا'),
                  ),
                  _quickChip(
                    icon: Icons.star_rounded,
                    label: context.l10n.customerDiscoveryTopRated,
                    onTap: () => onQuickSearch('الأعلى تقييمًا'),
                  ),
                  _quickChip(
                    icon: Icons.currency_exchange_rounded,
                    label: context.l10n.customerDiscoveryBestPrice,
                    onTap: () => onQuickSearch('أفضل سعر'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: Colors.white.withValues(alpha: 0.10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntentLauncherStrip extends StatefulWidget {
  final VoidCallback onTaxi;
  final bool showTaxi;
  final VoidCallback onOffers;
  final VoidCallback onTopRated;
  final VoidCallback onReorder;

  const _IntentLauncherStrip({
    required this.onTaxi,
    this.showTaxi = true,
    required this.onOffers,
    required this.onTopRated,
    required this.onReorder,
  });

  @override
  State<_IntentLauncherStrip> createState() => _IntentLauncherStripState();
}

class _IntentLauncherStripState extends State<_IntentLauncherStrip> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: !context.isEnglishLocale,
        children: [
          if (widget.showTaxi)
            _intentButton(
              icon: Icons.local_taxi_rounded,
              label: context.l10n.customerDiscoveryRequestTaxi,
              color: const Color(0xFF56D7FF),
              glow: 0.08,
              onTap: widget.onTaxi,
            ),
          _intentButton(
            icon: Icons.local_offer_rounded,
            label: context.l10n.customerDiscoveryTodayOffers,
            color: const Color(0xFFFFBA68),
            glow: 0.08,
            onTap: widget.onOffers,
          ),
          _intentButton(
            icon: Icons.verified_rounded,
            label: context.l10n.customerDiscoveryTopRated,
            color: const Color(0xFF7BFFCE),
            glow: 0.08,
            onTap: widget.onTopRated,
          ),
          _intentButton(
            icon: Icons.history_toggle_off_rounded,
            label: context.l10n.customerDiscoveryReorder,
            color: const Color(0xFFCEB6FF),
            glow: 0.08,
            onTap: widget.onReorder,
          ),
        ],
      ),
    );
  }

  Widget _intentButton({
    required IconData icon,
    required String label,
    required Color color,
    required double glow,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.30),
                color.withValues(alpha: 0.10),
              ],
            ),
            border: Border.all(color: color.withValues(alpha: 0.65)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: glow),
                blurRadius: 14,
                spreadRadius: 0.2,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveryHubCard extends StatefulWidget {
  final _DiscoveryHub hub;
  final int index;
  final VoidCallback onTap;

  const _DiscoveryHubCard({
    required this.hub,
    required this.index,
    required this.onTap,
  });

  @override
  State<_DiscoveryHubCard> createState() => _DiscoveryHubCardState();
}

class _DiscoveryHubCardState extends State<_DiscoveryHubCard> {
  @override
  Widget build(BuildContext context) {
    final pair = _splashPairForSeed(widget.hub.id);
    final textDirection = context.appTextDirection;
    final crossAxisAlignment = context.isEnglishLocale
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;
    const t = 0.35;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: widget.onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [pair.$1, pair.$2],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: pair.$1.withValues(alpha: 0.18),
              blurRadius: 10,
              spreadRadius: 0,
            ),
          ],
        ),
        child: SizedBox(
          height: 112,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              textDirection: textDirection,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  child: Icon(widget.hub.icon, size: 28),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: crossAxisAlignment,
                    children: [
                      Text(
                        widget.hub.titleFor(context),
                        textDirection: textDirection,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.hub.subtitleFor(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: textDirection,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.90),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 82,
                  height: 82,
                  child: _CategoryShowcaseGlyph(
                    motion: widget.hub.motion,
                    progress: t,
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

class _CategoryCard extends StatefulWidget {
  final _DiscoveryCategory category;
  final int index;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.index,
    required this.onTap,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  @override
  Widget build(BuildContext context) {
    final pair = _splashPairForSeed(
      '${widget.category.titleEn}:${widget.category.type}',
    );
    final textDirection = context.appTextDirection;
    final crossAxisAlignment = context.isEnglishLocale
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;
    const t = 0.35;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: widget.onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [pair.$1, pair.$2],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: pair.$1.withValues(alpha: 0.18),
              blurRadius: 10,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: crossAxisAlignment,
            children: [
              Row(
                textDirection: textDirection,
                children: [
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                    child: Icon(widget.category.icon, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Center(
                  child: _CategoryShowcaseGlyph(
                    motion: widget.category.motion,
                    progress: t,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.category.titleFor(context),
                textDirection: textDirection,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.category.subtitleFor(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: textDirection,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w600,
                  fontSize: 12.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryShowcaseGlyph extends StatelessWidget {
  final _CategoryMotion motion;
  final double progress;

  const _CategoryShowcaseGlyph({required this.motion, required this.progress});

  @override
  Widget build(BuildContext context) {
    final pulse = 0.94 + (math.sin(progress * math.pi * 2).abs() * 0.13);
    switch (motion) {
      case _CategoryMotion.forkKnife:
        return CustomPaint(
          size: const Size.square(94),
          painter: _ForkKnifePlatePainter(progress: progress),
        );
      case _CategoryMotion.meat:
        return CustomPaint(
          size: const Size.square(94),
          painter: _MeatBoardPainter(progress: progress),
        );
      case _CategoryMotion.cake:
        return Transform.rotate(
          angle: math.sin(progress * math.pi * 2) * 0.11,
          child: Transform.scale(
            scale: pulse,
            child: const Icon(Icons.cake_rounded, size: 52),
          ),
        );
      case _CategoryMotion.bag:
        return Transform.translate(
          offset: Offset(0, -3 * math.sin(progress * math.pi * 2)),
          child: const Icon(Icons.shopping_basket_rounded, size: 52),
        );
      case _CategoryMotion.bolt:
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
            Opacity(
              opacity: 0.55 + (math.sin(progress * math.pi * 2).abs() * 0.45),
              child: const Icon(Icons.bolt_rounded, size: 44),
            ),
          ],
        );
      case _CategoryMotion.leaf:
        return Transform.rotate(
          angle: math.sin(progress * math.pi * 2) * 0.12,
          child: const Icon(Icons.eco_rounded, size: 50),
        );
      case _CategoryMotion.gift:
        return Transform.scale(
          scale: pulse,
          child: const Icon(Icons.redeem_rounded, size: 50),
        );
      case _CategoryMotion.coffee:
        return Transform.translate(
          offset: Offset(0, -2 * math.sin(progress * math.pi * 2)),
          child: const Icon(Icons.local_cafe_rounded, size: 50),
        );
      case _CategoryMotion.car:
        return Transform.translate(
          offset: Offset(math.sin(progress * math.pi * 2) * 6, 0),
          child: const Icon(Icons.directions_car_rounded, size: 52),
        );
    }
  }
}

class _ForkKnifePlatePainter extends CustomPainter {
  final double progress;

  const _ForkKnifePlatePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final plateR = size.width * 0.26;
    final wave = math.sin(progress * math.pi * 2);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(center, plateR + 9, ringPaint);

    final platePaint = Paint()..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawCircle(center, plateR, platePaint);

    final foodPaint = Paint()..color = const Color(0xFFFFB26B);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, 1),
        width: plateR * 1.35,
        height: plateR * 0.75,
      ),
      foodPaint,
    );

    final forkX = center.dx + 22;
    final forkTop = center.dy - 24 + (wave * 2);
    final forkPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(forkX, forkTop),
      Offset(forkX, center.dy + 25),
      forkPaint,
    );
    for (var i = -2; i <= 2; i += 2) {
      canvas.drawLine(
        Offset(forkX + i.toDouble(), forkTop),
        Offset(forkX + i.toDouble(), forkTop + 10),
        forkPaint,
      );
    }

    final knifeX = center.dx - 22;
    final knifeTipY = center.dy - 22 + (wave * 5);
    final knifePath = Path()
      ..moveTo(knifeX, center.dy + 24)
      ..lineTo(knifeX + 4, center.dy + 24)
      ..lineTo(knifeX + 3, knifeTipY)
      ..lineTo(knifeX + 1.6, knifeTipY - 5)
      ..lineTo(knifeX - 0.3, knifeTipY)
      ..close();
    final knifePaint = Paint()..color = Colors.white.withValues(alpha: 0.95);
    canvas.drawPath(knifePath, knifePaint);

    final sparkPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4 + (wave.abs() * 0.3));
    canvas.drawCircle(
      Offset(center.dx - 6, center.dy - 9),
      1.8 + (wave.abs() * 0.8),
      sparkPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ForkKnifePlatePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _MeatBoardPainter extends CustomPainter {
  final double progress;

  const _MeatBoardPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final wave = math.sin(progress * math.pi * 2);

    final board = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(0, 4),
        width: size.width * 0.68,
        height: size.height * 0.44,
      ),
      const Radius.circular(12),
    );
    final boardPaint = Paint()..color = const Color(0xFF8A5B40);
    canvas.drawRRect(board, boardPaint);

    final meatPaint = Paint()..color = const Color(0xFFE36B6B);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-4, 4),
        width: size.width * 0.34,
        height: size.height * 0.20,
      ),
      meatPaint,
    );
    final fatPaint = Paint()..color = const Color(0xFFF9D3D3);
    canvas.drawCircle(center.translate(-7, 3), 5.5, fatPaint);

    final knifePath = Path()
      ..moveTo(center.dx + 10, center.dy - 18 + (wave * 4))
      ..lineTo(center.dx + 38, center.dy - 3 + (wave * 4))
      ..lineTo(center.dx + 33, center.dy + 3 + (wave * 4))
      ..lineTo(center.dx + 6, center.dy - 11 + (wave * 4))
      ..close();
    final knifePaint = Paint()..color = Colors.white.withValues(alpha: 0.94);
    canvas.drawPath(knifePath, knifePaint);

    final handlePaint = Paint()..color = const Color(0xFF2E2E33);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx + 41, center.dy + 1 + (wave * 4)),
          width: 14,
          height: 6,
        ),
        const Radius.circular(4),
      ),
      handlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MeatBoardPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 36),
            const SizedBox(height: 10),
            Text(
              context.l10n.customerDiscoveryLoadFailedTitle,
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.customerDiscoveryLoadFailedBody,
              textDirection: context.appTextDirection,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryHub {
  final String id;
  final String titleAr;
  final String titleEn;
  final String subtitleAr;
  final String subtitleEn;
  final List<String> searchTerms;
  final IconData icon;
  final Color colorA;
  final Color colorB;
  final _CategoryMotion motion;

  const _DiscoveryHub({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.subtitleAr,
    required this.subtitleEn,
    required this.searchTerms,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.motion,
  });

  String titleFor(BuildContext context) {
    final l10n = context.l10n;
    return switch (id) {
      'style' => l10n.customerDiscoveryHubStyleTitle,
      'food' => l10n.customerDiscoveryHubFoodTitle,
      'home' => l10n.customerDiscoveryHubHomeTitle,
      'electronics' => l10n.customerDiscoveryHubElectronicsTitle,
      'cars' => l10n.customerDiscoveryHubCarsTitle,
      'pharmacy' => l10n.customerDiscoveryHubPharmacyTitle,
      'main_market' => l10n.customerDiscoveryHubMainMarketTitle,
      _ => titleEn,
    };
  }

  String subtitleFor(BuildContext context) {
    final l10n = context.l10n;
    return switch (id) {
      'style' => l10n.customerDiscoveryHubStyleSubtitle,
      'food' => l10n.customerDiscoveryHubFoodSubtitle,
      'home' => l10n.customerDiscoveryHubHomeSubtitle,
      'electronics' => l10n.customerDiscoveryHubElectronicsSubtitle,
      'cars' => l10n.customerDiscoveryHubCarsSubtitle,
      'pharmacy' => l10n.customerDiscoveryHubPharmacySubtitle,
      'main_market' => l10n.customerDiscoveryHubMainMarketSubtitle,
      _ => subtitleEn,
    };
  }

  String get searchBucket =>
      '$titleAr $titleEn $subtitleAr $subtitleEn ${searchTerms.join(' ')}'
          .toLowerCase();
}

class _DiscoveryCategory {
  final String titleAr;
  final String titleEn;
  final String subtitleAr;
  final String subtitleEn;
  final String type;
  final String seedQuery;
  final List<String> searchTerms;
  final IconData icon;
  final Color colorA;
  final Color colorB;
  final _CategoryMotion motion;

  const _DiscoveryCategory({
    required this.titleAr,
    required this.titleEn,
    required this.subtitleAr,
    required this.subtitleEn,
    required this.type,
    required this.seedQuery,
    required this.searchTerms,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.motion,
  });

  String titleFor(BuildContext context) {
    final l10n = context.l10n;
    return switch (titleEn) {
      'Restaurants' => l10n.customerDiscoveryCategoryRestaurantsTitle,
      'Women fashion' => l10n.customerDiscoveryCategoryWomenFashionTitle,
      'Men fashion' => l10n.customerDiscoveryCategoryMenFashionTitle,
      'Desserts and pastries' => l10n.customerDiscoveryCategoryDessertsTitle,
      'Markets and cleaning' =>
        l10n.customerDiscoveryCategoryMarketsCleaningTitle,
      'Fruit and vegetables' =>
        l10n.customerDiscoveryCategoryFruitVegetablesTitle,
      'Meat and poultry' => l10n.customerDiscoveryCategoryMeatPoultryTitle,
      'Coffee and drinks' => l10n.customerDiscoveryCategoryCoffeeDrinksTitle,
      'Electrical supplies' =>
        l10n.customerDiscoveryCategoryElectricalSuppliesTitle,
      'Home essentials' => l10n.customerDiscoveryCategoryHomeEssentialsTitle,
      'Personal care' => l10n.customerDiscoveryCategoryPersonalCareTitle,
      'Stationery and gifts' =>
        l10n.customerDiscoveryCategoryStationeryGiftsTitle,
      _ => titleEn,
    };
  }

  String subtitleFor(BuildContext context) {
    final l10n = context.l10n;
    return switch (titleEn) {
      'Restaurants' => l10n.customerDiscoveryCategoryRestaurantsSubtitle,
      'Women fashion' => l10n.customerDiscoveryCategoryWomenFashionSubtitle,
      'Men fashion' => l10n.customerDiscoveryCategoryMenFashionSubtitle,
      'Desserts and pastries' => l10n.customerDiscoveryCategoryDessertsSubtitle,
      'Markets and cleaning' =>
        l10n.customerDiscoveryCategoryMarketsCleaningSubtitle,
      'Fruit and vegetables' =>
        l10n.customerDiscoveryCategoryFruitVegetablesSubtitle,
      'Meat and poultry' => l10n.customerDiscoveryCategoryMeatPoultrySubtitle,
      'Coffee and drinks' => l10n.customerDiscoveryCategoryCoffeeDrinksSubtitle,
      'Electrical supplies' =>
        l10n.customerDiscoveryCategoryElectricalSuppliesSubtitle,
      'Home essentials' => l10n.customerDiscoveryCategoryHomeEssentialsSubtitle,
      'Personal care' => l10n.customerDiscoveryCategoryPersonalCareSubtitle,
      'Stationery and gifts' =>
        l10n.customerDiscoveryCategoryStationeryGiftsSubtitle,
      _ => subtitleEn,
    };
  }

  String get searchBucket =>
      '$titleAr $titleEn $subtitleAr $subtitleEn $seedQuery ${searchTerms.join(' ')}'
          .toLowerCase();
}

class _StaticAdBanner {
  final String titleAr;
  final String titleEn;
  final String subtitleAr;
  final String subtitleEn;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  const _StaticAdBanner({
    required this.titleAr,
    required this.titleEn,
    required this.subtitleAr,
    required this.subtitleEn,
    required this.icon,
    required this.colorA,
    required this.colorB,
  });

  String titleFor(BuildContext context) {
    final l10n = context.l10n;
    return switch (titleEn) {
      'Maslaki brings the offer to you' =>
        l10n.customerDiscoveryBannerOfferTitle,
      'A complete market in one place' =>
        l10n.customerDiscoveryBannerUnifiedMarketTitle,
      'Maslaki Taxi all day long' => l10n.customerDiscoveryBannerTaxiTitle,
      _ => titleEn,
    };
  }

  String subtitleFor(BuildContext context) {
    final l10n = context.l10n;
    return switch (titleEn) {
      'Maslaki brings the offer to you' =>
        l10n.customerDiscoveryBannerOfferSubtitle,
      'A complete market in one place' =>
        l10n.customerDiscoveryBannerUnifiedMarketSubtitle,
      'Maslaki Taxi all day long' => l10n.customerDiscoveryBannerTaxiSubtitle,
      _ => subtitleEn,
    };
  }
}

class _DisplayAdBanner {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String? badgeLabel;
  final String? ctaLabel;
  final String ctaTargetType;
  final String? ctaTargetValue;
  final int? merchantId;
  final String? merchantName;
  final String? merchantType;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  const _DisplayAdBanner({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colorA,
    required this.colorB,
    this.imageUrl,
    this.badgeLabel,
    this.ctaLabel,
    this.ctaTargetType = 'none',
    this.ctaTargetValue,
    this.merchantId,
    this.merchantName,
    this.merchantType,
  });
}

enum _CategoryMotion {
  forkKnife,
  meat,
  cake,
  bag,
  bolt,
  leaf,
  gift,
  coffee,
  car,
}

const _defaultAdBanners = <_StaticAdBanner>[
  _StaticAdBanner(
    titleAr: 'مسلكي وياك.. العرض يلكاك',
    titleEn: 'Maslaki brings the offer to you',
    subtitleAr: 'خصومات يومية حقيقية من متاجر ومطاعم بسماية',
    subtitleEn: 'Real daily offers from Basmaya stores and restaurants',
    icon: Icons.local_offer_rounded,
    colorA: Color(0xFF1C4B88),
    colorB: Color(0xFF143766),
  ),
  _StaticAdBanner(
    titleAr: 'سوق متكامل بلمسة واحدة',
    titleEn: 'A complete market in one place',
    subtitleAr: 'مطاعم، تسوق منزلي، سيارات، وتكسي داخل تطبيق واحد',
    subtitleEn: 'Restaurants, home shopping, cars, and taxi in one app',
    icon: Icons.verified_user_rounded,
    colorA: Color(0xFF2B5A8B),
    colorB: Color(0xFF1F3E67),
  ),
  _StaticAdBanner(
    titleAr: 'تكسي مسلكي على مدار اليوم',
    titleEn: 'Maslaki Taxi all day long',
    subtitleAr: 'حدد سعر الرحلة والكباتن يرسلون عروضهم فورًا',
    subtitleEn: 'Set your ride price and captains respond instantly',
    icon: Icons.local_taxi_rounded,
    colorA: Color(0xFF235D7E),
    colorB: Color(0xFF1B4569),
  ),
];

const _discoveryHubs = <_DiscoveryHub>[
  _DiscoveryHub(
    id: 'style',
    titleAr: 'سوق الأزياء',
    titleEn: 'Fashion market',
    subtitleAr: 'نسائي ورجالي وأحذية وشنط',
    subtitleEn: 'Women, men, shoes, and bags',
    searchTerms: [
      'أزياء',
      'نسائي',
      'رجالي',
      'شنط',
      'أحذية',
      'عناية',
      'fashion',
      'women',
      'men',
      'bags',
      'shoes',
      'beauty',
    ],
    icon: Icons.style_rounded,
    colorA: Color(0xFF7A3F8B),
    colorB: Color(0xFF4A2B64),
    motion: _CategoryMotion.gift,
  ),
  _DiscoveryHub(
    id: 'food',
    titleAr: 'الطعام والمشروبات',
    titleEn: 'Food and drinks',
    subtitleAr: 'مطاعم وحلويات ومعجنات وقهوة',
    subtitleEn: 'Restaurants, desserts, pastries, and coffee',
    searchTerms: [
      'مطاعم',
      'حلويات',
      'معجنات',
      'قهوة',
      'مشروبات',
      'food',
      'restaurant',
      'desserts',
      'pastries',
      'coffee',
      'drinks',
    ],
    icon: Icons.restaurant_menu_rounded,
    colorA: Color(0xFF234E8A),
    colorB: Color(0xFF163A66),
    motion: _CategoryMotion.forkKnife,
  ),
  _DiscoveryHub(
    id: 'home',
    titleAr: 'التسوق المنزلي',
    titleEn: 'Home shopping',
    subtitleAr: 'أسواق ولحوم وخضار وتنظيف ومكتبات وهدايا',
    subtitleEn: 'Markets, meats, produce, cleaning, stationery, and gifts',
    searchTerms: [
      'أسواق',
      'تنظيف',
      'لحوم',
      'دواجن',
      'خضار',
      'فواكه',
      'مكتبة',
      'هدايا',
      'ورد',
      'منزل',
      'market',
      'groceries',
      'cleaning',
      'meat',
      'vegetables',
      'fruit',
      'stationery',
      'gifts',
      'home',
    ],
    icon: Icons.home_work_rounded,
    colorA: Color(0xFF2B5C7E),
    colorB: Color(0xFF1D4160),
    motion: _CategoryMotion.bag,
  ),
  _DiscoveryHub(
    id: 'electronics',
    titleAr: 'التجهيزات الكهربائية',
    titleEn: 'Electrical essentials',
    subtitleAr: 'أجهزة وملحقات وكهربائيات منزلية',
    subtitleEn: 'Devices, accessories, and home electrical items',
    searchTerms: [
      'كهربائيات',
      'أجهزة',
      'ملحقات',
      'هواتف',
      'electronics',
      'devices',
      'accessories',
      'electrical',
      'phones',
    ],
    icon: Icons.electrical_services_rounded,
    colorA: Color(0xFF31508C),
    colorB: Color(0xFF1D2F57),
    motion: _CategoryMotion.bolt,
  ),
  _DiscoveryHub(
    id: 'cars',
    titleAr: 'سوق السيارات',
    titleEn: 'Cars market',
    subtitleAr: 'جديد ومستعمل حسب الشركة والموديل والسنة',
    subtitleEn: 'New and used by make, model, and year',
    searchTerms: [
      'سيارات',
      'مركبات',
      'جديد',
      'مستعمل',
      'موديل',
      'سنة الصنع',
      'cars',
      'vehicles',
      'new',
      'used',
      'model',
      'year',
    ],
    icon: Icons.directions_car_rounded,
    colorA: Color(0xFF2E5D86),
    colorB: Color(0xFF1D3E5D),
    motion: _CategoryMotion.car,
  ),
  _DiscoveryHub(
    id: 'pharmacy',
    titleAr: 'الصيدليات',
    titleEn: 'Pharmacies',
    subtitleAr: 'وصفات ومكملات وأجهزة ومستلزمات طبية',
    subtitleEn: 'Prescriptions, supplements, and medical supplies',
    searchTerms: [
      'صيدلية',
      'دواء',
      'وصفة',
      'فيتامين',
      'مستلزمات طبية',
      'pharmacy',
      'medicine',
      'prescription',
      'vitamin',
      'medical',
    ],
    icon: Icons.local_hospital_rounded,
    colorA: Color(0xFF2A6F97),
    colorB: Color(0xFF174E70),
    motion: _CategoryMotion.leaf,
  ),
  _DiscoveryHub(
    id: 'main_market',
    titleAr: 'السوق الرئيسي',
    titleEn: 'Main market',
    subtitleAr: 'كل الأقسام في مكان واحد',
    subtitleEn: 'All categories in one place',
    searchTerms: [
      'السوق',
      'كل الأقسام',
      'الكل',
      'market',
      'all categories',
      'everything',
    ],
    icon: Icons.storefront_rounded,
    colorA: Color(0xFF275A84),
    colorB: Color(0xFF1A3E5F),
    motion: _CategoryMotion.coffee,
  ),
];

const _categories = <_DiscoveryCategory>[
  _DiscoveryCategory(
    titleAr: 'مطاعم',
    titleEn: 'Restaurants',
    subtitleAr: 'وجبات يومية ومطابخ متنوعة',
    subtitleEn: 'Daily meals and a variety of cuisines',
    type: 'restaurant',
    seedQuery: '',
    searchTerms: [
      'برغر',
      'مشاوي',
      'رز',
      'عشاء',
      'burger',
      'grill',
      'rice',
      'dinner',
    ],
    icon: Icons.restaurant_menu_rounded,
    colorA: Color(0xFF234E8A),
    colorB: Color(0xFF163A66),
    motion: _CategoryMotion.forkKnife,
  ),
  _DiscoveryCategory(
    titleAr: 'أزياء نسائية',
    titleEn: 'Women fashion',
    subtitleAr: 'ملابس، شنط، عناية وتجميل',
    subtitleEn: 'Clothing, bags, care, and beauty',
    type: 'market',
    seedQuery: 'نسائي',
    searchTerms: [
      'نسائي',
      'فساتين',
      'عبايات',
      'شنط',
      'مكياج',
      'women',
      'dresses',
      'abayas',
      'bags',
      'makeup',
    ],
    icon: Icons.style_rounded,
    colorA: Color(0xFF7A3F8B),
    colorB: Color(0xFF4A2B64),
    motion: _CategoryMotion.gift,
  ),
  _DiscoveryCategory(
    titleAr: 'أزياء رجالية',
    titleEn: 'Men fashion',
    subtitleAr: 'ملابس، أحذية، عطور رجالية',
    subtitleEn: 'Clothing, shoes, and men fragrances',
    type: 'market',
    seedQuery: 'رجالي',
    searchTerms: [
      'رجالي',
      'أحذية',
      'دشاديش',
      'عطور',
      'men',
      'shoes',
      'dishdasha',
      'fragrance',
    ],
    icon: Icons.checkroom_rounded,
    colorA: Color(0xFF2A5D8C),
    colorB: Color(0xFF1A3D63),
    motion: _CategoryMotion.bag,
  ),
  _DiscoveryCategory(
    titleAr: 'حلويات ومعجنات',
    titleEn: 'Desserts and pastries',
    subtitleAr: 'كيك، بقلاوة، ومعجنات طازجة',
    subtitleEn: 'Cake, baklava, and fresh pastries',
    type: 'restaurant',
    seedQuery: 'حلويات',
    searchTerms: [
      'كيك',
      'بقلاوة',
      'دونات',
      'كرواسون',
      'cake',
      'baklava',
      'donuts',
      'croissant',
    ],
    icon: Icons.bakery_dining_rounded,
    colorA: Color(0xFF6A3E8C),
    colorB: Color(0xFF4B2B66),
    motion: _CategoryMotion.cake,
  ),
  _DiscoveryCategory(
    titleAr: 'أسواق ومواد تنظيف',
    titleEn: 'Markets and cleaning',
    subtitleAr: 'مواد غذائية ومنزلية وتنظيف بمكان واحد',
    subtitleEn: 'Groceries, home goods, and cleaning in one place',
    type: 'market',
    seedQuery: 'سوق',
    searchTerms: [
      'سوبرماركت',
      'مواد تنظيف',
      'بقالة',
      'supermarket',
      'cleaning',
      'groceries',
    ],
    icon: Icons.store_mall_directory_rounded,
    colorA: Color(0xFF2B5C7E),
    colorB: Color(0xFF1D4160),
    motion: _CategoryMotion.bag,
  ),
  _DiscoveryCategory(
    titleAr: 'خضار وفواكه',
    titleEn: 'Fruit and vegetables',
    subtitleAr: 'منتجات يومية طازجة',
    subtitleEn: 'Fresh daily produce',
    type: 'market',
    seedQuery: 'خضار',
    searchTerms: ['فواكه', 'خضار', 'طازج', 'fruit', 'vegetables', 'fresh'],
    icon: Icons.local_grocery_store_rounded,
    colorA: Color(0xFF2F7C60),
    colorB: Color(0xFF1F5843),
    motion: _CategoryMotion.leaf,
  ),
  _DiscoveryCategory(
    titleAr: 'لحوم ودواجن',
    titleEn: 'Meat and poultry',
    subtitleAr: 'ملحمة ودجاج ومجمدات',
    subtitleEn: 'Butcher, chicken, and frozen items',
    type: 'market',
    seedQuery: 'لحوم',
    searchTerms: ['ملحمة', 'دجاج', 'لحم', 'butcher', 'chicken', 'meat'],
    icon: Icons.set_meal_rounded,
    colorA: Color(0xFF7A3B4A),
    colorB: Color(0xFF522733),
    motion: _CategoryMotion.meat,
  ),
  _DiscoveryCategory(
    titleAr: 'قهوة ومشروبات',
    titleEn: 'Coffee and drinks',
    subtitleAr: 'قهوة باردة وساخنة وعصائر',
    subtitleEn: 'Hot and cold coffee with juices',
    type: 'restaurant',
    seedQuery: 'قهوة',
    searchTerms: ['قهوة', 'عصير', 'مشروب', 'coffee', 'juice', 'drink'],
    icon: Icons.local_cafe_rounded,
    colorA: Color(0xFF7A5A2F),
    colorB: Color(0xFF5A411F),
    motion: _CategoryMotion.coffee,
  ),
  _DiscoveryCategory(
    titleAr: 'تجهيزات كهربائية',
    titleEn: 'Electrical supplies',
    subtitleAr: 'أجهزة وقطع كهرباء منزلية',
    subtitleEn: 'Devices and home electrical parts',
    type: 'market',
    seedQuery: 'كهربائيات',
    searchTerms: [
      'أجهزة',
      'كهرباء',
      'مفاتيح',
      'devices',
      'electric',
      'switches',
    ],
    icon: Icons.electrical_services_rounded,
    colorA: Color(0xFF31508C),
    colorB: Color(0xFF1D2F57),
    motion: _CategoryMotion.bolt,
  ),
  _DiscoveryCategory(
    titleAr: 'أدوات منزلية',
    titleEn: 'Home essentials',
    subtitleAr: 'مستلزمات المطبخ والبيت',
    subtitleEn: 'Kitchen and home essentials',
    type: 'market',
    seedQuery: 'منزلية',
    searchTerms: ['مطبخ', 'تنظيم', 'منزل', 'kitchen', 'organizing', 'home'],
    icon: Icons.home_work_rounded,
    colorA: Color(0xFF3F5E86),
    colorB: Color(0xFF263D5D),
    motion: _CategoryMotion.bag,
  ),
  _DiscoveryCategory(
    titleAr: 'عناية شخصية',
    titleEn: 'Personal care',
    subtitleAr: 'مستلزمات يومية وعطور',
    subtitleEn: 'Daily essentials and fragrances',
    type: 'market',
    seedQuery: 'عناية',
    searchTerms: ['عناية', 'شامبو', 'عطور', 'care', 'shampoo', 'fragrance'],
    icon: Icons.spa_rounded,
    colorA: Color(0xFF6A4E88),
    colorB: Color(0xFF473363),
    motion: _CategoryMotion.leaf,
  ),
  _DiscoveryCategory(
    titleAr: 'مكتبات وهدايا',
    titleEn: 'Stationery and gifts',
    subtitleAr: 'قرطاسية، تغليف، وهدايا',
    subtitleEn: 'Stationery, wrapping, and gifts',
    type: 'market',
    seedQuery: 'هدايا',
    searchTerms: ['قرطاسية', 'هدايا', 'ورود', 'stationery', 'gifts', 'flowers'],
    icon: Icons.card_giftcard_rounded,
    colorA: Color(0xFF6A507C),
    colorB: Color(0xFF443254),
    motion: _CategoryMotion.gift,
  ),
];
