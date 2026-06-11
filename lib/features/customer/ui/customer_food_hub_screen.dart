import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../../auth/ui/merchants_list_screen.dart';

class CustomerFoodHubScreen extends StatelessWidget {
  const CustomerFoodHubScreen({super.key});

  void _open(BuildContext context, _FoodTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialType: 'restaurant',
          initialSearchQuery: topic.searchQuery,
          requiredAnyKeywords: topic.searchTerms,
          overrideTitle: topic.title,
          compactCustomerMode: true,
          applyInitialSearchQuery: true,
        ),
      ),
    );
  }

  List<_FoodTopic> _topics(BuildContext context) {
    final l10n = context.l10n;
    return [
      _FoodTopic(
        title: l10n.customerFoodHubRestaurantsTitle,
        subtitle: l10n.customerFoodHubRestaurantsSubtitle,
        searchQuery: '',
        searchTerms: ['مطاعم', 'مأكولات', 'restaurant', 'restaurants', 'food'],
        icon: Icons.restaurant_rounded,
        colorA: const Color(0xFF23588A),
        colorB: const Color(0xFF183D65),
      ),
      _FoodTopic(
        title: l10n.customerFoodHubDessertsTitle,
        subtitle: l10n.customerFoodHubDessertsSubtitle,
        searchQuery: 'حلويات',
        searchTerms: [
          'حلويات',
          'حلوى',
          'كيك',
          'بقلاوة',
          'كنافة',
          'dessert',
          'sweets',
          'cake',
        ],
        icon: Icons.cake_rounded,
        colorA: const Color(0xFF7A3E8E),
        colorB: const Color(0xFF4C2A65),
      ),
      _FoodTopic(
        title: l10n.customerFoodHubBakeryTitle,
        subtitle: l10n.customerFoodHubBakerySubtitle,
        searchQuery: 'معجنات',
        searchTerms: [
          'معجنات',
          'مخبوزات',
          'كرواسون',
          'مناقيش',
          'bakery',
          'pastry',
          'croissant',
        ],
        icon: Icons.bakery_dining_rounded,
        colorA: const Color(0xFF99623A),
        colorB: const Color(0xFF6A4427),
      ),
      _FoodTopic(
        title: l10n.customerFoodHubCoffeeTitle,
        subtitle: l10n.customerFoodHubCoffeeSubtitle,
        searchQuery: 'قهوة',
        searchTerms: [
          'قهوة',
          'كوفي',
          'مشروبات',
          'عصير',
          'coffee',
          'cafe',
          'drinks',
          'tea',
        ],
        icon: Icons.local_cafe_rounded,
        colorA: const Color(0xFF556F8A),
        colorB: const Color(0xFF36485C),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customerFoodHubTitle),
        actions: const [AppBarQuickActions()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          _HeaderCard(
            title: l10n.customerFoodHubHeaderTitle,
            subtitle: l10n.customerFoodHubHeaderSubtitle,
          ),
          const SizedBox(height: 12),
          _TopicGrid(
            topics: _topics(context),
            onTap: (topic) => _open(context, topic),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _HeaderCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final isLtr = Directionality.of(context) == TextDirection.ltr;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF265B92), Color(0xFF1A3E69)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: isLtr
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Text(
            title,
            textAlign: isLtr ? TextAlign.start : TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: isLtr ? TextAlign.start : TextAlign.end),
        ],
      ),
    );
  }
}

class _TopicGrid extends StatelessWidget {
  final List<_FoodTopic> topics;
  final ValueChanged<_FoodTopic> onTap;

  const _TopicGrid({required this.topics, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLtr = Directionality.of(context) == TextDirection.ltr;
    return GridView.builder(
      itemCount: topics.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.12,
      ),
      itemBuilder: (context, index) {
        final topic = topics[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onTap(topic),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [topic.colorA, topic.colorB],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: isLtr
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Icon(topic.icon, size: 24),
                  const Spacer(),
                  Text(
                    topic.title,
                    textAlign: isLtr ? TextAlign.start : TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    topic.subtitle,
                    textAlign: isLtr ? TextAlign.start : TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FoodTopic {
  final String title;
  final String subtitle;
  final String searchQuery;
  final List<String> searchTerms;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  const _FoodTopic({
    required this.title,
    required this.subtitle,
    required this.searchQuery,
    required this.searchTerms,
    required this.icon,
    required this.colorA,
    required this.colorB,
  });
}
