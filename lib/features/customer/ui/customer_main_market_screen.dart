import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../../behavior/data/behavior_api.dart';
import '../../auth/ui/merchants_list_screen.dart';
import 'customer_cars_hub_screen.dart';
import 'customer_electronics_hub_screen.dart';
import 'customer_food_hub_screen.dart';
import 'customer_global_product_search_screen.dart';
import 'customer_home_shopping_hub_screen.dart';
import 'customer_style_hub_screen.dart';

class CustomerMainMarketScreen extends ConsumerStatefulWidget {
  const CustomerMainMarketScreen({super.key});

  @override
  ConsumerState<CustomerMainMarketScreen> createState() =>
      _CustomerMainMarketScreenState();
}

class _CustomerMainMarketScreenState
    extends ConsumerState<CustomerMainMarketScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(behaviorApiProvider)
          .trackEvent(
            eventName: 'shopping.main_market_open',
            category: 'shopping',
            action: 'open_main_market',
            metadata: const {
              'route': 'main_market',
              'screenLabel': 'كل السوق',
              'recentTitle': 'كنت تتصفح كل السوق',
              'recentSubtitle': 'اضغط للعودة إلى كل السوق',
            },
          );
    });
  }

  void _openHub(BuildContext context, _MainHubCard card) {
    switch (card.id) {
      case 'all_stores':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MerchantsListScreen(
              overrideTitle: context.l10n.customerDiscoveryMerchants,
              compactCustomerMode: true,
            ),
          ),
        );
        return;
      case 'style':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerStyleHubScreen()),
        );
        return;
      case 'food':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerFoodHubScreen()),
        );
        return;
      case 'home':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CustomerHomeShoppingHubScreen(),
          ),
        );
        return;
      case 'electronics':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CustomerElectronicsHubScreen(),
          ),
        );
        return;
      case 'cars':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerCarsHubScreen()),
        );
        return;
      case 'pharmacy':
        Navigator.of(context).push(
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
      default:
        return;
    }
  }

  void _openCategory(
    BuildContext context, {
    required String title,
    String? type,
    String? initialActivityType,
    String initialSearchQuery = '',
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialType: type,
          initialActivityType: initialActivityType,
          initialSearchQuery: initialSearchQuery,
          overrideTitle: title,
          compactCustomerMode: true,
          applyInitialSearchQuery: initialSearchQuery.trim().isNotEmpty,
        ),
      ),
    );
  }

  List<_MainHubCard> _localizedMainHubs(BuildContext context) {
    final l10n = context.l10n;
    return <_MainHubCard>[
      _MainHubCard(
        id: 'all_stores',
        title: l10n.customerDiscoveryMerchants,
        subtitle: l10n.customerMainMarketHeroSubtitle,
        icon: Icons.store_mall_directory_rounded,
        colorA: const Color(0xFF2A6E83),
        colorB: const Color(0xFF1A4453),
      ),
      _MainHubCard(
        id: 'style',
        title: l10n.customerDiscoveryHubStyleTitle,
        subtitle: l10n.customerDiscoveryHubStyleSubtitle,
        icon: Icons.style_rounded,
        colorA: const Color(0xFF7A3E8D),
        colorB: const Color(0xFF4E2A66),
      ),
      _MainHubCard(
        id: 'food',
        title: l10n.customerDiscoveryHubFoodTitle,
        subtitle: l10n.customerDiscoveryHubFoodSubtitle,
        icon: Icons.restaurant_rounded,
        colorA: const Color(0xFF245D90),
        colorB: const Color(0xFF183E66),
      ),
      _MainHubCard(
        id: 'home',
        title: l10n.customerDiscoveryHubHomeTitle,
        subtitle: l10n.customerDiscoveryHubHomeSubtitle,
        icon: Icons.home_filled,
        colorA: const Color(0xFF2B6480),
        colorB: const Color(0xFF1D435A),
      ),
      _MainHubCard(
        id: 'electronics',
        title: l10n.customerDiscoveryHubElectronicsTitle,
        subtitle: l10n.customerDiscoveryHubElectronicsSubtitle,
        icon: Icons.electrical_services_rounded,
        colorA: const Color(0xFF355D90),
        colorB: const Color(0xFF223C62),
      ),
      _MainHubCard(
        id: 'pharmacy',
        title: l10n.customerDiscoveryHubPharmacyTitle,
        subtitle: l10n.customerDiscoveryHubPharmacySubtitle,
        icon: Icons.local_hospital_rounded,
        colorA: const Color(0xFF216C79),
        colorB: const Color(0xFF16444D),
      ),
      _MainHubCard(
        id: 'cars',
        title: l10n.customerDiscoveryHubCarsTitle,
        subtitle: l10n.customerDiscoveryHubCarsSubtitle,
        icon: Icons.directions_car_rounded,
        colorA: const Color(0xFF2E5D86),
        colorB: const Color(0xFF1D3E5D),
      ),
    ];
  }

  List<_QuickQuery> _localizedQuickQueries(BuildContext context) {
    final l10n = context.l10n;
    return <_QuickQuery>[
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryRestaurantsTitle,
        type: 'restaurant',
        icon: Icons.restaurant_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryDessertsTitle,
        type: 'restaurant',
        icon: Icons.cake_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryCoffeeDrinksTitle,
        type: 'restaurant',
        icon: Icons.local_cafe_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryMarketsCleaningTitle,
        type: 'market',
        icon: Icons.storefront_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryFruitVegetablesTitle,
        type: 'market',
        icon: Icons.local_grocery_store_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryMeatPoultryTitle,
        type: 'market',
        icon: Icons.set_meal_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryStationeryGiftsTitle,
        type: 'market',
        icon: Icons.card_giftcard_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryElectricalSuppliesTitle,
        type: 'market',
        icon: Icons.electrical_services_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryHubPharmacyTitle,
        type: 'market',
        activityType: 'pharmacy',
        icon: Icons.local_hospital_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryHubCarsTitle,
        type: 'market',
        icon: Icons.directions_car_rounded,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final mainHubs = _localizedMainHubs(context);
    final quickQueries = _localizedQuickQueries(context);
    return Directionality(
      textDirection: context.appTextDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.customerMainMarketTitle),
          actions: const [AppBarQuickActions()],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
          children: [
            const _HeaderCard(),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomerGlobalProductSearchScreen(),
                ),
              ),
              icon: const Icon(Icons.travel_explore_rounded),
              label: const Text('بحث عام داخل كل المتاجر'),
            ),
            const SizedBox(height: 12),
            _SectionTitle(context.l10n.customerMainMarketMainHubs),
            const SizedBox(height: 8),
            ListView.separated(
              itemCount: mainHubs.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final card = mainHubs[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openHub(context, card),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [card.colorA, card.colorB],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    child: SizedBox(
                      height: 100,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          textDirection: context.appTextDirection,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                              child: Icon(card.icon, size: 24),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    card.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    card.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.88,
                                      ),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (_, _) => const SizedBox(height: 10),
            ),
            const SizedBox(height: 14),
            _SectionTitle(context.l10n.customerMainMarketQuickCategoryAccess),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: quickQueries
                  .map(
                    (item) => ActionChip(
                      avatar: Icon(item.icon, size: 16),
                      label: Text(item.title),
                      onPressed: () => _openCategory(
                        context,
                        title: item.title,
                        type: item.type,
                        initialActivityType: item.activityType,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF284D86), Color(0xFF1C355F)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            context.l10n.customerMainMarketHeroTitle,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 6),
          Text(context.l10n.customerMainMarketHeroSubtitle),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class _MainHubCard {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  const _MainHubCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colorA,
    required this.colorB,
  });
}

class _QuickQuery {
  final String title;
  final String? type;
  final String? activityType;
  final IconData icon;

  const _QuickQuery({
    required this.title,
    required this.type,
    this.activityType,
    required this.icon,
  });
}
