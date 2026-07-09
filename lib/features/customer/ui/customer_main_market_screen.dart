import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../../behavior/data/behavior_api.dart';
import '../../auth/ui/merchants_list_screen.dart';
import 'customer_cars_hub_screen.dart';
import 'customer_electronics_hub_screen.dart';
import 'customer_food_hub_screen.dart';
import 'customer_global_product_search_screen.dart';
import 'customer_home_shopping_hub_screen.dart';
import 'fashion_market_screen.dart';

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
          MaterialPageRoute(builder: (_) => const FashionMarketScreen()),
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
              strictCategoryMode: true,
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
          // Quick categories are strict single-activity pages.
          strictCategoryMode: initialActivityType != null,
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
        accent: AppColors.brandNavy, // soft indigo — the general "all stores"
      ),
      _MainHubCard(
        id: 'style',
        title: l10n.customerDiscoveryHubStyleTitle,
        subtitle: l10n.customerDiscoveryHubStyleSubtitle,
        icon: Icons.style_rounded,
        accent: const Color(0xFF9C6BA8), // light lavender
      ),
      _MainHubCard(
        id: 'food',
        title: l10n.customerDiscoveryHubFoodTitle,
        subtitle: l10n.customerDiscoveryHubFoodSubtitle,
        icon: Icons.restaurant_rounded,
        accent: AppColors.brandGold, // honey gold
      ),
      _MainHubCard(
        id: 'home',
        title: l10n.customerDiscoveryHubHomeTitle,
        subtitle: l10n.customerDiscoveryHubHomeSubtitle,
        icon: Icons.home_filled,
        accent: const Color(0xFF5E8E72), // soft sage green
      ),
      _MainHubCard(
        id: 'electronics',
        title: l10n.customerDiscoveryHubElectronicsTitle,
        subtitle: l10n.customerDiscoveryHubElectronicsSubtitle,
        icon: Icons.electrical_services_rounded,
        accent: const Color(0xFF3E6BA0), // cool indigo/blue
      ),
      _MainHubCard(
        id: 'pharmacy',
        title: l10n.customerDiscoveryHubPharmacyTitle,
        subtitle: l10n.customerDiscoveryHubPharmacySubtitle,
        icon: Icons.local_hospital_rounded,
        accent: const Color(0xFF3E9488), // controlled medical mint/teal
      ),
      _MainHubCard(
        id: 'cars',
        title: l10n.customerDiscoveryHubCarsTitle,
        subtitle: l10n.customerDiscoveryHubCarsSubtitle,
        icon: Icons.directions_car_rounded,
        accent: const Color(0xFF4A6B8A), // steel blue
      ),
    ];
  }

  List<_QuickQuery> _localizedQuickQueries(BuildContext context) {
    final l10n = context.l10n;
    return <_QuickQuery>[
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryRestaurantsTitle,
        type: 'restaurant',
        activityType: 'restaurant',
        icon: Icons.restaurant_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryDessertsTitle,
        type: 'restaurant',
        activityType: 'sweets_bakery',
        icon: Icons.cake_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryCoffeeDrinksTitle,
        type: 'restaurant',
        activityType: 'coffee_drinks',
        icon: Icons.local_cafe_rounded,
      ),
      _QuickQuery(
        title: context.lt(ar: 'الملابس والأزياء', en: 'Fashion & Clothing'),
        type: 'market',
        activityType: 'fashion_clothing',
        icon: Icons.checkroom_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryMarketsCleaningTitle,
        type: 'market',
        activityType: 'supermarket',
        icon: Icons.storefront_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryFruitVegetablesTitle,
        type: 'market',
        activityType: 'fruits_vegetables',
        icon: Icons.local_grocery_store_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryMeatPoultryTitle,
        type: 'market',
        activityType: 'meat_poultry',
        icon: Icons.set_meal_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryStationeryGiftsTitle,
        type: 'market',
        activityType: 'stationery_office',
        icon: Icons.card_giftcard_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryCategoryElectricalSuppliesTitle,
        type: 'market',
        activityType: 'electrical_lighting',
        icon: Icons.electrical_services_rounded,
      ),
      _QuickQuery(
        title: l10n.customerDiscoveryHubPharmacyTitle,
        type: 'market',
        activityType: 'pharmacy',
        icon: Icons.local_hospital_rounded,
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
                return _MainHubTile(card: card, onTap: () => _openHub(context, card));
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

  /// Soft, on-theme accent used for the icon badge + border on the light card.
  final Color accent;

  const _MainHubCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });
}

/// Light, premium Maslaki market card: warm cream surface, soft indigo text,
/// gentle per-category accent badge and subtle elevation. Replaces the previous
/// dark teal/purple blocks for a consistent Maslaki identity.
class _MainHubTile extends StatelessWidget {
  final _MainHubCard card;
  final VoidCallback onTap;

  const _MainHubTile({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFFBF7EF);
    const ink = AppColors.brandNavy;
    final accent = card.accent;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: MaslakiCard(
        radius: 20,
        elevated: true,
        backgroundColor: cream,
        borderColor: accent.withValues(alpha: 0.24),
        padding: const EdgeInsets.symmetric(
          horizontal: MaslakiSpacing.md,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    accent.withValues(alpha: 0.20),
                    accent.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(color: accent.withValues(alpha: 0.32)),
              ),
              child: Icon(card.icon, size: 26, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    card.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink.withValues(alpha: 0.60),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 15,
              color: accent.withValues(alpha: 0.85),
            ),
          ],
        ),
      ),
    );
  }
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
