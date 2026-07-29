import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../../auth/ui/merchants_list_screen.dart';

/// Dedicated "Home Furniture" section. Each card isolates to a real store
/// activity so stores registered under it (and only it) appear, with no keyword
/// search that could wrongly exclude a store.
///   مفروشات        -> furnishings      (existing)
///   أثاث منزلي      -> home_furniture   (added in migration 187)
///   مطابخ وديكورات  -> kitchens_decor   (added in migration 187)
class CustomerHomeFurnitureHubScreen extends StatelessWidget {
  const CustomerHomeFurnitureHubScreen({super.key});

  void _open(BuildContext context, _FurnitureTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          // Strict isolation by real activity category — no market+keyword.
          initialActivityType: topic.activityType,
          overrideTitle: topic.title,
          compactCustomerMode: true,
          strictCategoryMode: true,
          showCategoryIntelligence: false,
        ),
      ),
    );
  }

  List<_FurnitureTopic> _topics(BuildContext context) {
    return [
      _FurnitureTopic(
        title: context.lt(ar: 'مفروشات', en: 'Furnishings'),
        subtitle: context.lt(
          ar: 'كنب وأسرّة وسجاد وستائر',
          en: 'Sofas, beds, carpets & curtains',
        ),
        icon: Icons.weekend_rounded,
        colorA: const Color(0xFF7A5E3B),
        colorB: const Color(0xFF52401F),
        activityType: 'furnishings',
      ),
      _FurnitureTopic(
        title: context.lt(ar: 'أثاث منزلي', en: 'Home Furniture'),
        subtitle: context.lt(
          ar: 'أثاث غرف الجلوس والنوم والطعام',
          en: 'Living room, bedroom & dining furniture',
        ),
        icon: Icons.chair_rounded,
        colorA: const Color(0xFF6E5A86),
        colorB: const Color(0xFF463A5C),
        activityType: 'home_furniture',
      ),
      _FurnitureTopic(
        title: context.lt(ar: 'مطابخ وديكورات', en: 'Kitchens & Decor'),
        subtitle: context.lt(
          ar: 'مطابخ وإكسسوارات وإنارة وديكور',
          en: 'Kitchens, accessories, lighting & decor',
        ),
        icon: Icons.kitchen_rounded,
        colorA: const Color(0xFF3A6B78),
        colorB: const Color(0xFF254751),
        activityType: 'kitchens_decor',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'الأثاث المنزلي', en: 'Home Furniture')),
        actions: const [AppBarQuickActions()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          _HeaderCard(
            title: context.lt(
              ar: 'كل ما يخص أثاث المنزل في مكان واحد',
              en: 'Everything for your home furniture in one place',
            ),
            subtitle: context.lt(
              ar: 'مفروشات، أثاث منزلي، ومطابخ وديكورات.',
              en: 'Furnishings, home furniture, kitchens & decor.',
            ),
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
          colors: [Color(0xFF5B4A32), Color(0xFF3A2F1F)],
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
  final List<_FurnitureTopic> topics;
  final ValueChanged<_FurnitureTopic> onTap;

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

class _FurnitureTopic {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color colorA;
  final Color colorB;
  final String activityType;

  const _FurnitureTopic({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.activityType,
  });
}
