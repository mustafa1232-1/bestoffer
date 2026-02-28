import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_user_drawer.dart';
import '../../assistant/ui/assistant_chat_screen.dart';
import '../../auth/state/auth_controller.dart';
import '../../auth/ui/merchants_list_screen.dart';
import '../../behavior/data/behavior_api.dart';
import '../models/customer_home_prefs.dart';
import '../state/customer_home_prefs_controller.dart';
import 'customer_cars_hub_screen.dart';
import 'customer_electronics_hub_screen.dart';
import 'customer_food_hub_screen.dart';
import 'customer_home_shopping_hub_screen.dart';
import 'customer_main_market_screen.dart';
import 'customer_personalization_dialog.dart';
import 'customer_style_hub_screen.dart';
import '../../merchants/state/merchants_controller.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../../orders/state/cart_controller.dart';
import '../../orders/ui/cart_screen.dart';
import '../../orders/ui/customer_orders_screen.dart';
import '../../orders/ui/delivery_addresses_screen.dart';
import '../../../pages/map_page.dart';

class CustomerDiscoveryScreen extends ConsumerStatefulWidget {
  const CustomerDiscoveryScreen({super.key});

  @override
  ConsumerState<CustomerDiscoveryScreen> createState() =>
      _CustomerDiscoveryScreenState();
}

class _CustomerDiscoveryScreenState
    extends ConsumerState<CustomerDiscoveryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final PageController _adController = PageController(viewportFraction: 0.92);
  Timer? _adTimer;

  String _searchQuery = '';
  int _adPage = 0;
  bool _didCheckPersonalization = false;

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

    Future.microtask(() async {
      await ref.read(merchantsControllerProvider.notifier).load();
      await _bootstrapPersonalizationIfNeeded();
    });

    _adTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_adController.hasClients) return;
      _adPage = (_adPage + 1) % _adBanners.length;
      _adController.animateToPage(
        _adPage,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
      setState(() {});
    });
  }

  @override
  void dispose() {
    _adTimer?.cancel();
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

  Future<void> _openAddresses() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DeliveryAddressesScreen(selectOnTap: true),
      ),
    );
  }

  Future<void> _openAssistant() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AssistantChatScreen()));
  }

  Future<void> _openMapPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MapPage()));
  }

  Future<void> _openDiscoveryHub(_DiscoveryHub hub) async {
    await _trackBehaviorEvent(
      eventName: 'discovery.hub_open',
      category: 'discovery',
      action: 'open_hub',
      metadata: {'hubId': hub.id, 'hubTitle': hub.title},
    );
    if (!mounted) return;

    switch (hub.id) {
      case 'style':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerStyleHubScreen()),
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
    unawaited(
      _trackBehaviorEvent(
        eventName: 'discovery.category_open',
        category: 'discovery',
        action: 'open_category',
        metadata: {
          'categoryTitle': category.title,
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
          overrideTitle: category.title,
          compactCustomerMode: true,
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
          overrideTitle: title ?? (cleanQuery.isEmpty ? 'المتاجر' : cleanQuery),
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
      final bucket = '${hub.title} ${hub.subtitle} ${hub.tags.join(' ')}'
          .toLowerCase();
      if (bucket.contains(query)) {
        _openDiscoveryHub(hub);
        return;
      }
    }

    for (final category in _categories) {
      final bucket =
          '${category.title} ${category.seedQuery} ${category.tags.join(' ')}'
              .toLowerCase();
      if (bucket.contains(query)) {
        _openCategory(category);
        return;
      }
    }

    _openSearchResult(query: text, title: 'نتائج "$text"');
  }

  List<_DiscoveryHub> _orderedDiscoveryHubs(CustomerHomePrefs prefs) {
    final regularHubs = _discoveryHubs
        .where((hub) => hub.id != 'main_market')
        .toList(growable: false);
    final mainMarket = _discoveryHubs.firstWhere(
      (hub) => hub.id == 'main_market',
    );

    if (!prefs.completed) {
      return [...regularHubs, mainMarket];
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

    return [...visible, mainMarket];
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
    if (first.isEmpty) return 'مرحبًا';
    return 'مرحبًا ($first)';
  }

  _TimeGreeting _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) {
      return const _TimeGreeting(
        title: 'صباح الخير',
        tagline: 'يومك بدأ، والسوق بانتظارك لكل احتياجاتك.',
      );
    }
    if (hour >= 11 && hour < 14) {
      return const _TimeGreeting(
        title: 'ظهر الخير',
        tagline: 'وقت مناسب ترتب مشترياتك وتختار الأفضل بسهولة.',
      );
    }
    if (hour >= 14 && hour < 17) {
      return const _TimeGreeting(
        title: 'عصر الخير',
        tagline: 'جدد يومك بعروض متنوعة من المطاعم والأسواق والخدمات.',
      );
    }
    if (hour >= 17 && hour < 19) {
      return const _TimeGreeting(
        title: 'مغرب الخير',
        tagline: 'اختياراتك كلها هنا، من البيت للسيارة وبكل سرعة.',
      );
    }
    return const _TimeGreeting(
      title: 'مساء الخير',
      tagline: 'اختم يومك واطلب اللي تحتاجه من سوق متكامل بلمسة واحدة.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final userId = auth.user?.id;
    final merchantsState = ref.watch(merchantsControllerProvider);
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

    final drawerItems = <AppUserDrawerItem>[
      AppUserDrawerItem(
        icon: Icons.receipt_long_rounded,
        label: 'طلباتي',
        onTap: (_) => _openOrders(),
      ),
      AppUserDrawerItem(
        icon: Icons.shopping_cart_outlined,
        label: 'السلة',
        onTap: (_) => _openCart(),
      ),
      AppUserDrawerItem(
        icon: Icons.location_on_outlined,
        label: 'عناوين التوصيل',
        onTap: (_) => _openAddresses(),
      ),
      AppUserDrawerItem(
        icon: Icons.smart_toy_outlined,
        label: 'المساعد الذكي',
        onTap: (_) => _openAssistant(),
      ),
      AppUserDrawerItem(
        icon: Icons.map_outlined,
        label: 'الخريطة',
        onTap: (_) => _openMapPage(),
      ),
      AppUserDrawerItem(
        icon: Icons.refresh_rounded,
        label: 'تحديث البيانات',
        onTap: (_) => ref.read(merchantsControllerProvider.notifier).load(),
      ),
      if (userId != null)
        AppUserDrawerItem(
          icon: Icons.tune_rounded,
          label: 'إعادة تخصيص الواجهة',
          onTap: (_) async {
            Navigator.of(context).pop();
            await ref
                .read(customerHomePrefsProvider.notifier)
                .reset(userId: userId);
            if (!mounted) return;
            await _showPersonalizationDialog(userId);
          },
        ),
    ];

    return Scaffold(
      drawer: AppUserDrawer(
        title: 'BestOffer | بسماية',
        subtitle: 'تجربة تسوق حديثة داخل مدينة بسماية',
        items: drawerItems,
      ),
      appBar: AppBar(
        title: Text(_appBarGreeting(userFullName)),
        actions: [
          IconButton(
            tooltip: 'المساعد',
            onPressed: _openAssistant,
            icon: const Icon(Icons.smart_toy_outlined),
          ),
          IconButton(
            tooltip: 'الطلبات',
            onPressed: _openOrders,
            icon: const Icon(Icons.receipt_long_rounded),
          ),
          Stack(
            children: [
              IconButton(
                tooltip: 'السلة',
                onPressed: _openCart,
                icon: const Icon(Icons.shopping_bag_outlined),
              ),
              if (cartItems > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$cartItems',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const NotificationsBellButton(),
        ],
      ),
      body: merchantsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorView(
          onRetry: () => ref.read(merchantsControllerProvider.notifier).load(),
        ),
        data: (merchants) {
          final openCount = merchants.where((m) => m.isOpen).length;
          final offersCount = merchants
              .where((m) => m.hasDiscountOffer || m.hasFreeDeliveryOffer)
              .length;
          final restaurantsCount = merchants
              .where((m) => m.type == 'restaurant')
              .length;
          final marketsCount = merchants
              .where((m) => m.type == 'market')
              .length;

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(merchantsControllerProvider.notifier).load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              children: [
                _HeroWelcomeCard(greeting: timeGreeting),
                const SizedBox(height: 10),
                _TaxiServiceSpotlightCard(onTap: _openMapPage),
                const SizedBox(height: 10),
                _FuturePulsePanel(
                  openCount: openCount,
                  offersCount: offersCount,
                  restaurantsCount: restaurantsCount,
                  marketsCount: marketsCount,
                ),
                const SizedBox(height: 10),
                _AdsCarousel(controller: _adController, page: _adPage),
                const SizedBox(height: 12),
                _SearchPanel(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onSubmit: _onSubmitSearch,
                ),
                const SizedBox(height: 14),
                Text(
                  'التصنيفات الرئيسية',
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                ListView.separated(
                  itemCount: personalizedHubs.length,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemBuilder: (context, index) {
                    final hub = personalizedHubs[index];
                    return _DiscoveryHubCard(
                      hub: hub,
                      index: index,
                      onTap: () => _openDiscoveryHub(hub),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TimeGreeting {
  final String title;
  final String tagline;

  const _TimeGreeting({required this.title, required this.tagline});
}

class _HeroWelcomeCard extends StatefulWidget {
  final _TimeGreeting greeting;

  const _HeroWelcomeCard({required this.greeting});

  @override
  State<_HeroWelcomeCard> createState() => _HeroWelcomeCardState();
}

class _HeroWelcomeCardState extends State<_HeroWelcomeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final pulse = 0.90 + (_controller.value * 0.10);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${widget.greeting.title} 👋',
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.greeting.tagline,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'مع ',
                      textDirection: TextDirection.rtl,
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
                            colors: [Color(0xFFFFD166), Color(0xFFFF7F50)],
                          ).createShader(bounds);
                        },
                        child: const Text(
                          'BestOffer',
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
                      'كل عرض يفيدك، وطلبك بسرعة يجيك',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Transform.scale(
                      scale: pulse,
                      child: const Icon(
                        Icons.local_fire_department_rounded,
                        color: Color(0xFFFF8C42),
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FuturePulsePanel extends StatelessWidget {
  final int openCount;
  final int offersCount;
  final int restaurantsCount;
  final int marketsCount;

  const _FuturePulsePanel({
    required this.openCount,
    required this.offersCount,
    required this.restaurantsCount,
    required this.marketsCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1F4D7E), Color(0xFF173657)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'نبض السوق الآن',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              _FuturePulseItem(
                icon: Icons.storefront_rounded,
                label: 'متاجر مفتوحة',
                value: '$openCount',
              ),
              _FuturePulseItem(
                icon: Icons.local_offer_rounded,
                label: 'عروض فعالة',
                value: '$offersCount',
              ),
              _FuturePulseItem(
                icon: Icons.restaurant_rounded,
                label: 'مطاعم',
                value: '$restaurantsCount',
              ),
              _FuturePulseItem(
                icon: Icons.shopping_basket_rounded,
                label: 'أسواق',
                value: '$marketsCount',
              ),
            ],
          ),
        ],
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

class _TaxiServiceSpotlightCardState extends State<_TaxiServiceSpotlightCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1D4F82), Color(0xFF144066)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final pulse = 1 + (0.08 * _controller.value);
              return Transform.scale(
                scale: pulse,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3CC6FF).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.local_taxi_rounded,
                    color: Color(0xFF5CD7FF),
                    size: 30,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'تكسي BestOffer',
                  textDirection: TextDirection.rtl,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'حدد نقطة الانطلاق والوصول، واختر سعرك، والكباتن القريبين يرسلون عروضهم فورًا.',
                  textDirection: TextDirection.rtl,
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
                  label: const Text('اطلب تكسي الآن'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF59CEFF),
                    foregroundColor: const Color(0xFF06263A),
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

class _FuturePulseItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _FuturePulseItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  label,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
                Text(
                  value,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
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

  const _AdsCarousel({required this.controller, required this.page});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 112,
          child: PageView.builder(
            controller: controller,
            itemCount: _adBanners.length,
            itemBuilder: (context, index) {
              final banner = _adBanners[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [banner.colorA, banner.colorB],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(banner.icon, size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                banner.title,
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                banner.subtitle,
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.86),
                                  fontWeight: FontWeight.w600,
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
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_adBanners.length, (index) {
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

  const _SearchPanel({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textDirection: TextDirection.rtl,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            hintText: 'ابحث عن مطعم، سوق، أو منتج',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              onPressed: onSubmit,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
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

class _DiscoveryHubCardState extends State<_DiscoveryHubCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 1800 + (widget.index * 120)),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final lift = math.sin(t * math.pi * 2) * 2.0;
        final glow = 0.14 + (math.sin(t * math.pi * 2).abs() * 0.20);
        return Transform.translate(
          offset: Offset(0, -lift),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [widget.hub.colorA, widget.hub.colorB],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: widget.hub.colorA.withValues(alpha: 0.34),
                    blurRadius: 18,
                    spreadRadius: 0.8,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: glow * 0.28),
                    blurRadius: 20,
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: SizedBox(
                height: 112,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
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
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              widget.hub.title,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.hub.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.rtl,
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
          ),
        );
      },
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

class _CategoryCardState extends State<_CategoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 1800 + (widget.index * 120)),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final lift = math.sin(t * math.pi * 2) * 2.0;
        final glow = 0.14 + (math.sin(t * math.pi * 2).abs() * 0.20);
        return Transform.translate(
          offset: Offset(0, -lift),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [widget.category.colorA, widget.category.colorB],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: widget.category.colorA.withValues(alpha: 0.34),
                    blurRadius: 18,
                    spreadRadius: 0.8,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: glow * 0.28),
                    blurRadius: 20,
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
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
                      widget.category.title,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.category.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
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
          ),
        );
      },
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
            const Text(
              'تعذر تحميل الواجهة',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'تحقق من الاتصال ثم أعد المحاولة.',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryHub {
  final String id;
  final String title;
  final String subtitle;
  final List<String> tags;
  final IconData icon;
  final Color colorA;
  final Color colorB;
  final _CategoryMotion motion;

  const _DiscoveryHub({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.motion,
  });
}

class _DiscoveryCategory {
  final String title;
  final String subtitle;
  final String type;
  final String seedQuery;
  final List<String> tags;
  final IconData icon;
  final Color colorA;
  final Color colorB;
  final _CategoryMotion motion;

  const _DiscoveryCategory({
    required this.title,
    required this.subtitle,
    required this.type,
    required this.seedQuery,
    required this.tags,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.motion,
  });
}

class _AdBanner {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  const _AdBanner({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colorA,
    required this.colorB,
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

const _adBanners = <_AdBanner>[
  _AdBanner(
    title: 'عروض اليوم في بسماية',
    subtitle: 'خصومات حقيقية وتوصيل أسرع لنفس الحي',
    icon: Icons.local_offer_rounded,
    colorA: Color(0xFF1C4B88),
    colorB: Color(0xFF143766),
  ),
  _AdBanner(
    title: 'متاجر موثوقة ومجربة',
    subtitle: 'تقييمات واضحة وخدمة يومية ثابتة',
    icon: Icons.verified_user_rounded,
    colorA: Color(0xFF2B5A8B),
    colorB: Color(0xFF1F3E67),
  ),
  _AdBanner(
    title: 'طلبك يوصل للباب',
    subtitle: 'تتبع حي من لحظة التأكيد وحتى الاستلام',
    icon: Icons.delivery_dining_rounded,
    colorA: Color(0xFF235D7E),
    colorB: Color(0xFF1B4569),
  ),
];

const _discoveryHubs = <_DiscoveryHub>[
  _DiscoveryHub(
    id: 'style',
    title: 'سوق الأزياء',
    subtitle: 'نسائي ورجالي وأحذية وشنط',
    tags: ['أزياء', 'نسائي', 'رجالي', 'شنط', 'أحذية', 'عناية'],
    icon: Icons.style_rounded,
    colorA: Color(0xFF7A3F8B),
    colorB: Color(0xFF4A2B64),
    motion: _CategoryMotion.gift,
  ),
  _DiscoveryHub(
    id: 'food',
    title: 'الطعام والمشروبات',
    subtitle: 'مطاعم وحلويات ومعجنات وقهوة',
    tags: ['مطاعم', 'حلويات', 'معجنات', 'قهوة', 'مشروبات'],
    icon: Icons.restaurant_menu_rounded,
    colorA: Color(0xFF234E8A),
    colorB: Color(0xFF163A66),
    motion: _CategoryMotion.forkKnife,
  ),
  _DiscoveryHub(
    id: 'home',
    title: 'التسوق المنزلي',
    subtitle: 'أسواق ولحوم وخضار وتنظيف ومكتبات وهدايا',
    tags: [
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
    ],
    icon: Icons.home_work_rounded,
    colorA: Color(0xFF2B5C7E),
    colorB: Color(0xFF1D4160),
    motion: _CategoryMotion.bag,
  ),
  _DiscoveryHub(
    id: 'electronics',
    title: 'التجهيزات الكهربائية',
    subtitle: 'أجهزة وملحقات وكهربائيات منزلية',
    tags: ['كهربائيات', 'أجهزة', 'ملحقات', 'هواتف'],
    icon: Icons.electrical_services_rounded,
    colorA: Color(0xFF31508C),
    colorB: Color(0xFF1D2F57),
    motion: _CategoryMotion.bolt,
  ),
  _DiscoveryHub(
    id: 'cars',
    title: 'سوق السيارات',
    subtitle: 'جديد ومستعمل حسب الشركة والموديل والسنة',
    tags: ['سيارات', 'مركبات', 'جديد', 'مستعمل', 'موديل', 'سنة الصنع'],
    icon: Icons.directions_car_rounded,
    colorA: Color(0xFF2E5D86),
    colorB: Color(0xFF1D3E5D),
    motion: _CategoryMotion.car,
  ),
  _DiscoveryHub(
    id: 'main_market',
    title: 'السوق الرئيسي',
    subtitle: 'كل الأقسام في مكان واحد',
    tags: ['السوق', 'كل الأقسام', 'الكل'],
    icon: Icons.storefront_rounded,
    colorA: Color(0xFF275A84),
    colorB: Color(0xFF1A3E5F),
    motion: _CategoryMotion.coffee,
  ),
];

const _categories = <_DiscoveryCategory>[
  _DiscoveryCategory(
    title: 'مطاعم',
    subtitle: 'وجبات يومية ومطابخ متنوعة',
    type: 'restaurant',
    seedQuery: '',
    tags: ['برغر', 'مشاوي', 'رز', 'عشاء'],
    icon: Icons.restaurant_menu_rounded,
    colorA: Color(0xFF234E8A),
    colorB: Color(0xFF163A66),
    motion: _CategoryMotion.forkKnife,
  ),
  _DiscoveryCategory(
    title: 'أزياء نسائية',
    subtitle: 'ملابس، شنط، عناية وتجميل',
    type: 'market',
    seedQuery: 'نسائي',
    tags: ['نسائي', 'فساتين', 'عبايات', 'شنط', 'مكياج'],
    icon: Icons.style_rounded,
    colorA: Color(0xFF7A3F8B),
    colorB: Color(0xFF4A2B64),
    motion: _CategoryMotion.gift,
  ),
  _DiscoveryCategory(
    title: 'أزياء رجالية',
    subtitle: 'ملابس، أحذية، عطور رجالية',
    type: 'market',
    seedQuery: 'رجالي',
    tags: ['رجالي', 'أحذية', 'دشاديش', 'عطور'],
    icon: Icons.checkroom_rounded,
    colorA: Color(0xFF2A5D8C),
    colorB: Color(0xFF1A3D63),
    motion: _CategoryMotion.bag,
  ),
  _DiscoveryCategory(
    title: 'حلويات ومعجنات',
    subtitle: 'كيك، بقلاوة، ومعجنات طازجة',
    type: 'restaurant',
    seedQuery: 'حلويات',
    tags: ['كيك', 'بقلاوة', 'دونات', 'كرواسون'],
    icon: Icons.bakery_dining_rounded,
    colorA: Color(0xFF6A3E8C),
    colorB: Color(0xFF4B2B66),
    motion: _CategoryMotion.cake,
  ),
  _DiscoveryCategory(
    title: 'أسواق ومواد تنظيف',
    subtitle: 'مواد غذائية ومنزلية وتنظيف بمكان واحد',
    type: 'market',
    seedQuery: 'سوق',
    tags: ['سوبرماركت', 'مواد تنظيف', 'بقالة'],
    icon: Icons.store_mall_directory_rounded,
    colorA: Color(0xFF2B5C7E),
    colorB: Color(0xFF1D4160),
    motion: _CategoryMotion.bag,
  ),
  _DiscoveryCategory(
    title: 'خضار وفواكه',
    subtitle: 'منتجات يومية طازجة',
    type: 'market',
    seedQuery: 'خضار',
    tags: ['فواكه', 'خضار', 'طازج'],
    icon: Icons.local_grocery_store_rounded,
    colorA: Color(0xFF2F7C60),
    colorB: Color(0xFF1F5843),
    motion: _CategoryMotion.leaf,
  ),
  _DiscoveryCategory(
    title: 'لحوم ودواجن',
    subtitle: 'ملحمة ودجاج ومجمدات',
    type: 'market',
    seedQuery: 'لحوم',
    tags: ['ملحمة', 'دجاج', 'لحم'],
    icon: Icons.set_meal_rounded,
    colorA: Color(0xFF7A3B4A),
    colorB: Color(0xFF522733),
    motion: _CategoryMotion.meat,
  ),
  _DiscoveryCategory(
    title: 'قهوة ومشروبات',
    subtitle: 'قهوة باردة وساخنة وعصائر',
    type: 'restaurant',
    seedQuery: 'قهوة',
    tags: ['قهوة', 'عصير', 'مشروب'],
    icon: Icons.local_cafe_rounded,
    colorA: Color(0xFF7A5A2F),
    colorB: Color(0xFF5A411F),
    motion: _CategoryMotion.coffee,
  ),
  _DiscoveryCategory(
    title: 'تجهيزات كهربائية',
    subtitle: 'أجهزة وقطع كهرباء منزلية',
    type: 'market',
    seedQuery: 'كهربائيات',
    tags: ['أجهزة', 'كهرباء', 'مفاتيح'],
    icon: Icons.electrical_services_rounded,
    colorA: Color(0xFF31508C),
    colorB: Color(0xFF1D2F57),
    motion: _CategoryMotion.bolt,
  ),
  _DiscoveryCategory(
    title: 'أدوات منزلية',
    subtitle: 'مستلزمات المطبخ والبيت',
    type: 'market',
    seedQuery: 'منزلية',
    tags: ['مطبخ', 'تنظيم', 'منزل'],
    icon: Icons.home_work_rounded,
    colorA: Color(0xFF3F5E86),
    colorB: Color(0xFF263D5D),
    motion: _CategoryMotion.bag,
  ),
  _DiscoveryCategory(
    title: 'عناية شخصية',
    subtitle: 'مستلزمات يومية وعطور',
    type: 'market',
    seedQuery: 'عناية',
    tags: ['عناية', 'شامبو', 'عطور'],
    icon: Icons.spa_rounded,
    colorA: Color(0xFF6A4E88),
    colorB: Color(0xFF473363),
    motion: _CategoryMotion.leaf,
  ),
  _DiscoveryCategory(
    title: 'مكتبات وهدايا',
    subtitle: 'قرطاسية، تغليف، وهدايا',
    type: 'market',
    seedQuery: 'هدايا',
    tags: ['قرطاسية', 'هدايا', 'ورود'],
    icon: Icons.card_giftcard_rounded,
    colorA: Color(0xFF6A507C),
    colorB: Color(0xFF443254),
    motion: _CategoryMotion.gift,
  ),
];
