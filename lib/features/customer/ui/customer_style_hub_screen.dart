import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../../auth/ui/merchants_list_screen.dart';

class CustomerStyleHubScreen extends StatelessWidget {
  const CustomerStyleHubScreen({super.key});

  void _open(BuildContext context, _StyleTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialType: 'market',
          initialSearchQuery: topic.searchQuery,
          requiredAnyKeywords: topic.searchTerms,
          overrideTitle: topic.title,
          compactCustomerMode: true,
          applyInitialSearchQuery: true,
        ),
      ),
    );
  }

  List<_StyleTopic> _womenTopics(BuildContext context) {
    final l10n = context.l10n;
    return [
      _StyleTopic(
        title: l10n.customerStyleHubWomenClothingTitle,
        subtitle: l10n.customerStyleHubWomenClothingSubtitle,
        searchQuery: 'نسائي',
        searchTerms: [
          'نسائي',
          'نساء',
          'فساتين',
          'عبايات',
          'حجاب',
          'women',
          'ladies',
        ],
        icon: Icons.checkroom_rounded,
        colorA: const Color(0xFF7A3E8D),
        colorB: const Color(0xFF4E2A66),
      ),
      _StyleTopic(
        title: l10n.customerStyleHubWomenShoesTitle,
        subtitle: l10n.customerStyleHubWomenShoesSubtitle,
        searchQuery: 'أحذية نسائية',
        searchTerms: [
          'أحذية نسائية',
          'كعب',
          'سنيكرز',
          'women shoes',
          'heels',
          'sneakers',
        ],
        icon: Icons.shopping_bag_rounded,
        colorA: const Color(0xFF6A517F),
        colorB: const Color(0xFF3F3353),
      ),
      _StyleTopic(
        title: l10n.customerStyleHubBagsTitle,
        subtitle: l10n.customerStyleHubBagsSubtitle,
        searchQuery: 'شنط',
        searchTerms: [
          'شنط',
          'حقائب',
          'اكسسوارات',
          'ساعات',
          'bags',
          'accessories',
          'watch',
        ],
        icon: Icons.shopping_bag_outlined,
        colorA: const Color(0xFF8E5D3F),
        colorB: const Color(0xFF5A3A26),
      ),
      _StyleTopic(
        title: l10n.customerStyleHubBeautyTitle,
        subtitle: l10n.customerStyleHubBeautySubtitle,
        searchQuery: 'تجميل',
        searchTerms: [
          'تجميل',
          'مكياج',
          'عناية',
          'عطور',
          'beauty',
          'makeup',
          'perfume',
          'skincare',
        ],
        icon: Icons.auto_awesome_rounded,
        colorA: const Color(0xFF4E6E95),
        colorB: const Color(0xFF314A69),
      ),
    ];
  }

  List<_StyleTopic> _menTopics(BuildContext context) {
    final l10n = context.l10n;
    return [
      _StyleTopic(
        title: l10n.customerStyleHubMenClothingTitle,
        subtitle: l10n.customerStyleHubMenClothingSubtitle,
        searchQuery: 'رجالي',
        searchTerms: ['رجالي', 'رجال', 'بدلات', 'قمصان', 'men', 'mens'],
        icon: Icons.checkroom_rounded,
        colorA: const Color(0xFF1F4F81),
        colorB: const Color(0xFF183A62),
      ),
      _StyleTopic(
        title: l10n.customerStyleHubMenShoesTitle,
        subtitle: l10n.customerStyleHubMenShoesSubtitle,
        searchQuery: 'أحذية رجالية',
        searchTerms: [
          'أحذية رجالية',
          'رجالي',
          'men shoes',
          'formal shoes',
          'sport shoes',
        ],
        icon: Icons.hiking_rounded,
        colorA: const Color(0xFF2F6C70),
        colorB: const Color(0xFF1D4A4D),
      ),
      _StyleTopic(
        title: l10n.customerStyleHubMenFragranceTitle,
        subtitle: l10n.customerStyleHubMenFragranceSubtitle,
        searchQuery: 'عطور رجالية',
        searchTerms: [
          'عطور رجالية',
          'عطر رجالي',
          'perfume',
          'fragrance',
          'men perfume',
        ],
        icon: Icons.water_drop_rounded,
        colorA: const Color(0xFF5A6786),
        colorB: const Color(0xFF35415A),
      ),
      _StyleTopic(
        title: l10n.customerStyleHubSportsTitle,
        subtitle: l10n.customerStyleHubSportsSubtitle,
        searchQuery: 'رياضية',
        searchTerms: ['رياضية', 'رياضة', 'gym', 'sport', 'تمارين', 'fitness'],
        icon: Icons.sports_gymnastics_rounded,
        colorA: const Color(0xFF3D6E51),
        colorB: const Color(0xFF274836),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customerStyleHubTitle),
        actions: const [AppBarQuickActions()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          _HeaderCard(
            title: l10n.customerStyleHubHeaderTitle,
            subtitle: l10n.customerStyleHubHeaderSubtitle,
          ),
          const SizedBox(height: 12),
          _SectionTitle(title: l10n.customerStyleHubWomenSection),
          const SizedBox(height: 8),
          _TopicGrid(
            topics: _womenTopics(context),
            onTap: (topic) => _open(context, topic),
          ),
          const SizedBox(height: 14),
          _SectionTitle(title: l10n.customerStyleHubMenSection),
          const SizedBox(height: 8),
          _TopicGrid(
            topics: _menTopics(context),
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
          colors: [Color(0xFF2A4A8D), Color(0xFF1E3363)],
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

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class _TopicGrid extends StatelessWidget {
  final List<_StyleTopic> topics;
  final ValueChanged<_StyleTopic> onTap;

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
          borderRadius: BorderRadius.circular(15),
          onTap: () => onTap(topic),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
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

class _StyleTopic {
  final String title;
  final String subtitle;
  final String searchQuery;
  final List<String> searchTerms;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  const _StyleTopic({
    required this.title,
    required this.subtitle,
    required this.searchQuery,
    required this.searchTerms,
    required this.icon,
    required this.colorA,
    required this.colorB,
  });
}
