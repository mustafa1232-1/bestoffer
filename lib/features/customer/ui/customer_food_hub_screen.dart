import 'package:flutter/material.dart';

import '../../auth/ui/merchants_list_screen.dart';

class CustomerFoodHubScreen extends StatelessWidget {
  const CustomerFoodHubScreen({super.key});

  void _open(
    BuildContext context, {
    required String title,
    required String query,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialType: 'restaurant',
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
        appBar: AppBar(title: const Text('قسم الطعام والمشروبات')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
          children: [
            _HeaderCard(),
            const SizedBox(height: 12),
            _TopicGrid(
              topics: _foodTopics,
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
          colors: [Color(0xFF265B92), Color(0xFF1A3E69)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'كل خيارات الأكل بمكان واحد',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          SizedBox(height: 6),
          Text('مطاعم، حلويات، معجنات، قهوة ومشروبات.'),
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

class _FoodTopic {
  final String title;
  final String subtitle;
  final String query;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  const _FoodTopic({
    required this.title,
    required this.subtitle,
    required this.query,
    required this.icon,
    required this.colorA,
    required this.colorB,
  });
}

const _foodTopics = <_FoodTopic>[
  _FoodTopic(
    title: 'مطاعم',
    subtitle: 'وجبات يومية',
    query: 'مطاعم',
    icon: Icons.restaurant_rounded,
    colorA: Color(0xFF23588A),
    colorB: Color(0xFF183D65),
  ),
  _FoodTopic(
    title: 'حلويات',
    subtitle: 'كيك وبقلاوة',
    query: 'حلويات',
    icon: Icons.cake_rounded,
    colorA: Color(0xFF7A3E8E),
    colorB: Color(0xFF4C2A65),
  ),
  _FoodTopic(
    title: 'معجنات',
    subtitle: 'طازج يوميًا',
    query: 'معجنات',
    icon: Icons.bakery_dining_rounded,
    colorA: Color(0xFF99623A),
    colorB: Color(0xFF6A4427),
  ),
  _FoodTopic(
    title: 'قهوة ومشروبات',
    subtitle: 'ساخن وبارد',
    query: 'قهوة مشروبات',
    icon: Icons.local_cafe_rounded,
    colorA: Color(0xFF556F8A),
    colorB: Color(0xFF36485C),
  ),
];
