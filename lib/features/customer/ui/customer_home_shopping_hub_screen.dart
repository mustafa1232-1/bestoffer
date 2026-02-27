import 'package:flutter/material.dart';

import '../../auth/ui/merchants_list_screen.dart';

class CustomerHomeShoppingHubScreen extends StatelessWidget {
  const CustomerHomeShoppingHubScreen({super.key});

  void _open(
    BuildContext context, {
    required String title,
    required String query,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialType: 'market',
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
        appBar: AppBar(title: const Text('قسم التسوق المنزلي')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
          children: [
            _HeaderCard(),
            const SizedBox(height: 12),
            _TopicGrid(
              topics: _homeTopics,
              onTap: (topic) =>
                  _open(context, title: topic.title, query: topic.query),
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
          colors: [Color(0xFF2B5D7D), Color(0xFF1D3F58)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'احتياجات البيت كلها هنا',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          SizedBox(height: 6),
          Text('أسواق، خضار وفواكه، لحوم، تنظيف، مكتبات، هدايا، ورد.'),
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(topic.icon, size: 24),
                  const Spacer(),
                  Text(
                    topic.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    topic.subtitle,
                    maxLines: 1,
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
  final String query;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  const _HomeTopic({
    required this.title,
    required this.subtitle,
    required this.query,
    required this.icon,
    required this.colorA,
    required this.colorB,
  });
}

const _homeTopics = <_HomeTopic>[
  _HomeTopic(
    title: 'أسواق ومواد تنظيف',
    subtitle: 'تسوق يومي',
    query: 'أسواق مواد تنظيف',
    icon: Icons.storefront_rounded,
    colorA: Color(0xFF2B6387),
    colorB: Color(0xFF1D4460),
  ),
  _HomeTopic(
    title: 'خضار وفواكه',
    subtitle: 'منتج طازج',
    query: 'خضار فواكه',
    icon: Icons.local_grocery_store_rounded,
    colorA: Color(0xFF2F7B5E),
    colorB: Color(0xFF20543F),
  ),
  _HomeTopic(
    title: 'لحوم ودواجن',
    subtitle: 'ملحمة ومجمدات',
    query: 'لحوم دواجن',
    icon: Icons.set_meal_rounded,
    colorA: Color(0xFF7A3C4B),
    colorB: Color(0xFF532734),
  ),
  _HomeTopic(
    title: 'مكتبات وهدايا وورد',
    subtitle: 'مناسبات وتغليف',
    query: 'مكتبة هدايا ورد',
    icon: Icons.card_giftcard_rounded,
    colorA: Color(0xFF745387),
    colorB: Color(0xFF4E365F),
  ),
  _HomeTopic(
    title: 'أدوات منزلية',
    subtitle: 'مطبخ وتنظيم',
    query: 'أدوات منزلية مطبخ',
    icon: Icons.home_work_rounded,
    colorA: Color(0xFF3F5E86),
    colorB: Color(0xFF263D5D),
  ),
  _HomeTopic(
    title: 'عناية شخصية',
    subtitle: 'عطور ومستلزمات',
    query: 'عناية شخصية عطور',
    icon: Icons.spa_rounded,
    colorA: Color(0xFF6A4E88),
    colorB: Color(0xFF473363),
  ),
];
