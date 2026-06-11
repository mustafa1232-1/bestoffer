import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/assistant/ui/assistant_chat_screen.dart';
import '../../features/auth/state/auth_controller.dart';
import '../../features/auth/ui/merchants_list_screen.dart';
import '../../features/coupons/ui/customer_coupons_hub_screen.dart';
import '../../features/customer/ui/customer_account_hub_screen.dart';
import '../../features/customer/ui/customer_cars_hub_screen.dart';
import '../../features/customer/ui/customer_discovery_screen.dart';
import '../../features/customer/ui/customer_electronics_hub_screen.dart';
import '../../features/customer/ui/customer_food_hub_screen.dart';
import '../../features/customer/ui/customer_home_shopping_hub_screen.dart';
import '../../features/customer/ui/customer_main_market_screen.dart';
import '../../features/customer/ui/customer_style_hub_screen.dart';
import '../../features/jobs/ui/jobs_hub_screen.dart';
import '../../features/orders/ui/delivery_addresses_screen.dart';
import '../../features/orders/ui/favorite_products_screen.dart';
import '../../features/real_estate/ui/real_estate_marketplace_screen.dart';
import '../../features/services/ui/services_marketplace_screen.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../../features/taxi/ui/taxi_customer_tools_screen.dart';
import '../../pages/map_page.dart';
import '../i18n/app_localizations_context.dart';
import '../i18n/locale_text.dart';
import 'maslaki_brand_mark.dart';
import 'maslaki_wordmark.dart';

class MaslakiDrawerEntry {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  const MaslakiDrawerEntry({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class MaslakiDrawerSection {
  final String title;
  final List<MaslakiDrawerEntry> entries;

  const MaslakiDrawerSection({required this.title, required this.entries});
}

class MaslakiUserDrawer extends ConsumerWidget {
  final bool embedded;
  final List<MaslakiDrawerSection> extraSections;

  const MaslakiUserDrawer({
    super.key,
    this.embedded = false,
    this.extraSections = const [],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final profileName = (auth.user?.fullName ?? '').trim();
    final phone = (auth.user?.phone ?? '').trim();
    final safeName = profileName.isEmpty ? context.l10n.appName : profileName;
    final avatarLabel = safeName.characters.first;

    Future<void> open(Widget page) async {
      if (!embedded) {
        Navigator.of(context).pop();
      }
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }

    final sections = <MaslakiDrawerSection>[
      ...extraSections,
      MaslakiDrawerSection(
        title: context.lt(ar: 'الخدمات', en: 'Services'),
        entries: [
          MaslakiDrawerEntry(
            icon: Icons.storefront_rounded,
            label: context.lt(ar: 'كل السوق', en: 'All market'),
            onTap: () => open(const CustomerMainMarketScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.restaurant_menu_rounded,
            label: context.lt(ar: 'المطاعم', en: 'Restaurants'),
            onTap: () => open(const CustomerFoodHubScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.checkroom_rounded,
            label: context.lt(ar: 'الأزياء', en: 'Style'),
            onTap: () => open(const CustomerStyleHubScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.chair_alt_rounded,
            label: context.lt(ar: 'سوق المنزل', en: 'Home market'),
            onTap: () => open(const CustomerHomeShoppingHubScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.electrical_services_rounded,
            label: context.lt(ar: 'الكهربائيات', en: 'Electronics'),
            onTap: () => open(const CustomerElectronicsHubScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.shopping_basket_rounded,
            label: context.lt(ar: 'التسوق العام', en: 'Shopping'),
            onTap: () => open(
              const CustomerDiscoveryScreen(
                mode: CustomerDiscoveryMode.shoppingOnly,
                initialType: 'market',
              ),
            ),
          ),
          MaslakiDrawerEntry(
            icon: Icons.local_pharmacy_outlined,
            label: context.lt(ar: 'الصيدلية', en: 'Pharmacy'),
            onTap: () => open(
              MerchantsListScreen(
                initialType: 'market',
                initialActivityType: 'pharmacy',
                overrideTitle: context.lt(ar: 'الصيدليات', en: 'Pharmacies'),
                compactCustomerMode: true,
              ),
            ),
          ),
          MaslakiDrawerEntry(
            icon: Icons.local_taxi_rounded,
            label: context.lt(ar: 'التكسي', en: 'Taxi'),
            onTap: () => open(const MapPage()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.handyman_rounded,
            label: context.lt(ar: 'الخدمات', en: 'Services'),
            onTap: () => open(const ServicesMarketplaceScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.work_outline_rounded,
            label: context.lt(ar: 'الوظائف', en: 'Jobs'),
            onTap: () => open(const JobsHubScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.apartment_rounded,
            label: context.lt(ar: 'العقارات', en: 'Real estate'),
            onTap: () => open(const RealEstateMarketplaceScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.directions_car_filled_rounded,
            label: context.lt(ar: 'السيارات', en: 'Cars'),
            onTap: () => open(const CustomerCarsHubScreen()),
          ),
        ],
      ),
      MaslakiDrawerSection(
        title: context.lt(ar: 'الأدوات', en: 'Tools'),
        entries: [
          MaslakiDrawerEntry(
            icon: Icons.place_outlined,
            label: context.lt(ar: 'العناوين', en: 'Addresses'),
            onTap: () => open(const DeliveryAddressesScreen(selectOnTap: true)),
          ),
          MaslakiDrawerEntry(
            icon: Icons.bookmark_border_rounded,
            label: context.l10n.taxiSavedPlacesTitle,
            onTap: () => open(const TaxiCustomerToolsScreen(initialTab: 0)),
          ),
          MaslakiDrawerEntry(
            icon: Icons.route_outlined,
            label: context.l10n.taxiFavoriteTripsTitle,
            onTap: () => open(const TaxiCustomerToolsScreen(initialTab: 1)),
          ),
          MaslakiDrawerEntry(
            icon: Icons.discount_outlined,
            label: context.lt(ar: 'الكوبونات', en: 'Coupons'),
            onTap: () => open(const CustomerCouponsHubScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.favorite_border_rounded,
            label: context.lt(ar: 'المفضلة', en: 'Favorites'),
            onTap: () => open(const FavoriteProductsScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.auto_awesome_rounded,
            label: context.lt(ar: 'المساعد الذكي', en: 'Assistant'),
            onTap: () => open(const AssistantChatScreen()),
          ),
        ],
      ),
      MaslakiDrawerSection(
        title: context.lt(ar: 'الحساب', en: 'Account'),
        entries: [
          MaslakiDrawerEntry(
            icon: Icons.person_outline_rounded,
            label: context.lt(ar: 'حسابي', en: 'My account'),
            onTap: () => open(const CustomerAccountHubScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.settings_outlined,
            label: context.l10n.commonSettings,
            onTap: () => open(const SettingsScreen()),
          ),
          MaslakiDrawerEntry(
            icon: Icons.logout_rounded,
            label: context.lt(ar: 'تسجيل الخروج', en: 'Log out'),
            onTap: () async {
              if (!embedded) {
                Navigator.of(context).pop();
              }
              await ref.read(authControllerProvider.notifier).logout();
            },
          ),
        ],
      ),
    ];

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            context.maslakiTokens.backgroundPrimary,
            context.maslakiTokens.surfacePrimary,
            context.maslakiTokens.backgroundSecondary,
          ],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            MaslakiCard(
              padding: const EdgeInsets.all(MaslakiSpacing.lg),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  context.maslakiTokens.cardElevated,
                  context.maslakiTokens.surfacePrimary,
                ],
              ),
              child: Row(
                textDirection: context.appTextDirection,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.maslakiTokens.primaryAccent,
                      ),
                    ),
                    child: CircleAvatar(
                      backgroundColor: context.maslakiTokens.surfaceSecondary,
                      child: Text(
                        avatarLabel,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: MaslakiSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MaslakiWordmark(arabicSize: 22),
                            SizedBox(width: 8),
                            MaslakiBrandMark(size: 28, borderRadius: 8),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          safeName,
                          textDirection: context.appTextDirection,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            phone,
                            textDirection: TextDirection.ltr,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          context.l10n.customerHomeDrawerSubtitle,
                          textDirection: context.appTextDirection,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: context.maslakiTokens.textMuted,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MaslakiSpacing.lg),
            for (var i = 0; i < sections.length; i++) ...[
              _MaslakiDrawerSection(section: sections[i]),
              if (i != sections.length - 1)
                const SizedBox(height: MaslakiSpacing.lg),
            ],
          ],
        ),
      ),
    );

    if (embedded) return panel;
    return Drawer(
      width: MediaQuery.sizeOf(context).width.clamp(300.0, 372.0),
      child: panel,
    );
  }
}

class MaslakiUserDrawerButton extends StatelessWidget {
  final Color? color;
  final String? tooltip;
  final bool openStartDrawer;

  const MaslakiUserDrawerButton({
    super.key,
    this.color,
    this.tooltip,
    this.openStartDrawer = false,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => IconButton(
        tooltip: tooltip ?? 'Open navigation menu',
        onPressed: () {
          if (openStartDrawer) {
            Scaffold.of(context).openDrawer();
            return;
          }
          Scaffold.of(context).openEndDrawer();
        },
        icon: Icon(Icons.menu_rounded, color: color),
      ),
    );
  }
}

class _MaslakiDrawerSection extends StatelessWidget {
  final MaslakiDrawerSection section;

  const _MaslakiDrawerSection({required this.section});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 8, end: 6),
          child: Text(
            section.title,
            textDirection: context.appTextDirection,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: context.maslakiTokens.primaryAccent,
            ),
          ),
        ),
        MaslakiCard(
          padding: const EdgeInsets.symmetric(
            horizontal: MaslakiSpacing.sm,
            vertical: MaslakiSpacing.xs,
          ),
          elevated: false,
          child: Column(
            children: [
              for (var i = 0; i < section.entries.length; i++) ...[
                _MaslakiDrawerTile(entry: section.entries[i]),
                if (i != section.entries.length - 1)
                  Divider(
                    height: 1,
                    color: context.maslakiTokens.borderSubtle.withValues(
                      alpha: 0.55,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MaslakiDrawerTile extends StatelessWidget {
  final MaslakiDrawerEntry entry;

  const _MaslakiDrawerTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onTap: entry.onTap,
      leading: Icon(
        Icons.chevron_left_rounded,
        color: context.maslakiTokens.textMuted,
      ),
      title: Text(
        entry.label,
        textDirection: context.appTextDirection,
        textAlign: TextAlign.end,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      trailing: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: context.maslakiTokens.primaryAccent.withValues(alpha: 0.12),
          border: Border.all(color: context.maslakiTokens.borderSubtle),
        ),
        child: Icon(entry.icon, color: context.maslakiTokens.primaryAccent),
      ),
    );
  }
}
