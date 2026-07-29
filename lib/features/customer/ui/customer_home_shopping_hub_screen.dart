import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../../auth/ui/merchants_list_screen.dart';

class CustomerHomeShoppingHubScreen extends StatelessWidget {
  const CustomerHomeShoppingHubScreen({super.key});

  void _open(BuildContext context, _HomeTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          // Strict isolation by real activity category — never market+keyword.
          initialActivityType: topic.activityType,
          initialSearchQuery: topic.searchQuery,
          overrideTitle: topic.title,
          compactCustomerMode: true,
          strictCategoryMode: true,
          showCategoryIntelligence: false,
          applyInitialSearchQuery: topic.searchQuery.trim().isNotEmpty,
        ),
      ),
    );
  }

  List<_HomeTopic> _topics(BuildContext context) {
    final l10n = context.l10n;
    return [
      _HomeTopic(
        title: l10n.customerHomeShoppingHubGroceriesTitle,
        subtitle: l10n.customerHomeShoppingHubGroceriesSubtitle,
        searchQuery: '',
        searchTerms: [
          'سوق',
          'ماركت',
          'بقالة',
          'مواد تنظيف',
          'grocery',
          'supermarket',
          'market',
        ],
        icon: Icons.storefront_rounded,
        colorA: const Color(0xFF2B6387),
        colorB: const Color(0xFF1D4460),
        activityType: 'supermarket',
      ),
      _HomeTopic(
        title: l10n.customerHomeShoppingHubProduceTitle,
        subtitle: l10n.customerHomeShoppingHubProduceSubtitle,
        searchQuery: 'خضار',
        searchTerms: ['خضار', 'فواكه', 'فاكهة', 'ثمار', 'vegetable', 'fruit'],
        icon: Icons.local_grocery_store_rounded,
        colorA: const Color(0xFF2F7B5E),
        colorB: const Color(0xFF20543F),
        activityType: 'fruits_vegetables',
      ),
      _HomeTopic(
        title: l10n.customerHomeShoppingHubMeatTitle,
        subtitle: l10n.customerHomeShoppingHubMeatSubtitle,
        searchQuery: 'لحوم',
        searchTerms: ['لحوم', 'دواجن', 'ملحمة', 'فروج', 'meat', 'chicken'],
        icon: Icons.set_meal_rounded,
        colorA: const Color(0xFF7A3C4B),
        colorB: const Color(0xFF532734),
        activityType: 'meat_poultry',
      ),
      _HomeTopic(
        title: l10n.customerHomeShoppingHubGiftsTitle,
        subtitle: l10n.customerHomeShoppingHubGiftsSubtitle,
        searchQuery: 'هدايا',
        searchTerms: [
          'هدايا',
          'ورد',
          'مكتبة',
          'تغليف',
          'gift',
          'flower',
          'stationery',
        ],
        icon: Icons.card_giftcard_rounded,
        colorA: const Color(0xFF745387),
        colorB: const Color(0xFF4E365F),
        activityType: 'flowers_gifts',
      ),
      _HomeTopic(
        title: l10n.customerHomeShoppingHubHousewareTitle,
        subtitle: l10n.customerHomeShoppingHubHousewareSubtitle,
        searchQuery: 'منزلية',
        searchTerms: [
          'منزلية',
          'مطبخ',
          'تنظيم',
          'أدوات',
          'home',
          'kitchen',
          'houseware',
        ],
        icon: Icons.home_work_rounded,
        colorA: const Color(0xFF3F5E86),
        colorB: const Color(0xFF263D5D),
        activityType: 'home_kitchen',
      ),
      _HomeTopic(
        title: l10n.customerHomeShoppingHubPersonalCareTitle,
        subtitle: l10n.customerHomeShoppingHubPersonalCareSubtitle,
        searchQuery: 'عناية',
        searchTerms: [
          'عناية',
          'شخصية',
          'شامبو',
          'عطور',
          'care',
          'personal care',
          'hygiene',
          'perfume',
        ],
        icon: Icons.spa_rounded,
        colorA: const Color(0xFF6A4E88),
        colorB: const Color(0xFF473363),
        activityType: 'personal_care_beauty',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customerHomeShoppingHubTitle),
        actions: const [AppBarQuickActions()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          _HeaderCard(
            title: l10n.customerHomeShoppingHubHeaderTitle,
            subtitle: l10n.customerHomeShoppingHubHeaderSubtitle,
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
          colors: [Color(0xFF2B5D7D), Color(0xFF1D3F58)],
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
  final List<_HomeTopic> topics;
  final ValueChanged<_HomeTopic> onTap;

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

class _HomeTopic {
  final String title;
  final String subtitle;
  final String searchQuery;
  final List<String> searchTerms;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  /// Strict store activity this topic isolates to.
  final String activityType;

  const _HomeTopic({
    required this.title,
    required this.subtitle,
    required this.searchQuery,
    required this.searchTerms,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.activityType,
  });
}
