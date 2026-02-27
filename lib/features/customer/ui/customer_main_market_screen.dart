import 'package:flutter/material.dart';

import '../../auth/ui/merchants_list_screen.dart';
import 'customer_cars_hub_screen.dart';
import 'customer_electronics_hub_screen.dart';
import 'customer_food_hub_screen.dart';
import 'customer_home_shopping_hub_screen.dart';
import 'customer_style_hub_screen.dart';

class CustomerMainMarketScreen extends StatelessWidget {
  const CustomerMainMarketScreen({super.key});

  void _openHub(BuildContext context, _MainHubCard card) {
    switch (card.id) {
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
      default:
        return;
    }
  }

  void _openSearch(
    BuildContext context, {
    required String title,
    required String query,
    String? type,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialType: type,
          initialSearchQuery: query,
          overrideTitle: title,
          compactCustomerMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('السوق الرئيسي')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
          children: [
            _HeaderCard(),
            const SizedBox(height: 12),
            const _SectionTitle('الأقسام الرئيسية'),
            const SizedBox(height: 8),
            ListView.separated(
              itemCount: _mainHubs.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final card = _mainHubs[index];
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
                          textDirection: TextDirection.rtl,
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
            const _SectionTitle('دخول سريع للتصنيفات'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickQueries
                  .map(
                    (item) => ActionChip(
                      avatar: Icon(item.icon, size: 16),
                      label: Text(item.title),
                      onPressed: () => _openSearch(
                        context,
                        title: item.title,
                        query: item.query,
                        type: item.type,
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
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'كل السوق بين إيدك',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          SizedBox(height: 6),
          Text('إذا تحب تتصفح كل الخيارات بدون فلترة، هذا مكانك.'),
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
  final String query;
  final String? type;
  final IconData icon;

  const _QuickQuery({
    required this.title,
    required this.query,
    required this.type,
    required this.icon,
  });
}

const _mainHubs = <_MainHubCard>[
  _MainHubCard(
    id: 'style',
    title: 'سوق الأزياء',
    subtitle: 'نسائي ورجالي',
    icon: Icons.style_rounded,
    colorA: Color(0xFF7A3E8D),
    colorB: Color(0xFF4E2A66),
  ),
  _MainHubCard(
    id: 'food',
    title: 'الطعام والمشروبات',
    subtitle: 'مطاعم وحلويات',
    icon: Icons.restaurant_rounded,
    colorA: Color(0xFF245D90),
    colorB: Color(0xFF183E66),
  ),
  _MainHubCard(
    id: 'home',
    title: 'التسوق المنزلي',
    subtitle: 'أسواق واحتياجات البيت',
    icon: Icons.home_filled,
    colorA: Color(0xFF2B6480),
    colorB: Color(0xFF1D435A),
  ),
  _MainHubCard(
    id: 'electronics',
    title: 'تجهيزات كهربائية',
    subtitle: 'أجهزة وقطع كهرباء',
    icon: Icons.electrical_services_rounded,
    colorA: Color(0xFF355D90),
    colorB: Color(0xFF223C62),
  ),
  _MainHubCard(
    id: 'cars',
    title: 'سوق السيارات',
    subtitle: 'بحث حسب الشركة والموديل والسنة',
    icon: Icons.directions_car_rounded,
    colorA: Color(0xFF2E5D86),
    colorB: Color(0xFF1D3E5D),
  ),
];

const _quickQueries = <_QuickQuery>[
  _QuickQuery(
    title: 'مطاعم',
    query: 'مطاعم',
    type: 'restaurant',
    icon: Icons.restaurant_rounded,
  ),
  _QuickQuery(
    title: 'حلويات ومعجنات',
    query: 'حلويات معجنات',
    type: 'restaurant',
    icon: Icons.cake_rounded,
  ),
  _QuickQuery(
    title: 'قهوة ومشروبات',
    query: 'قهوة مشروبات',
    type: 'restaurant',
    icon: Icons.local_cafe_rounded,
  ),
  _QuickQuery(
    title: 'أسواق ومواد تنظيف',
    query: 'أسواق مواد تنظيف',
    type: 'market',
    icon: Icons.storefront_rounded,
  ),
  _QuickQuery(
    title: 'خضار وفواكه',
    query: 'خضار فواكه',
    type: 'market',
    icon: Icons.local_grocery_store_rounded,
  ),
  _QuickQuery(
    title: 'لحوم ودواجن',
    query: 'لحوم دواجن',
    type: 'market',
    icon: Icons.set_meal_rounded,
  ),
  _QuickQuery(
    title: 'مكتبات وهدايا وورد',
    query: 'مكتبة هدايا ورد',
    type: 'market',
    icon: Icons.card_giftcard_rounded,
  ),
  _QuickQuery(
    title: 'تجهيزات كهربائية',
    query: 'تجهيزات كهربائية',
    type: 'market',
    icon: Icons.electrical_services_rounded,
  ),
  _QuickQuery(
    title: 'سوق السيارات',
    query: 'سيارات جديد مستعمل',
    type: 'market',
    icon: Icons.directions_car_rounded,
  ),
];
