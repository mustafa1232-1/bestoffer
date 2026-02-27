import 'package:flutter/material.dart';

import '../../auth/ui/merchants_list_screen.dart';

class CustomerStyleHubScreen extends StatelessWidget {
  const CustomerStyleHubScreen({super.key});

  void _open(BuildContext context, _StyleTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialType: 'market',
          initialSearchQuery: topic.query,
          overrideTitle: topic.title,
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
        appBar: AppBar(title: const Text('سوق الأزياء - نسائي ورجالي')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
          children: [
            _HeaderCard(),
            const SizedBox(height: 12),
            const _SectionTitle('قسم النساء'),
            const SizedBox(height: 8),
            _TopicGrid(
              topics: _womenTopics,
              onTap: (topic) => _open(context, topic),
            ),
            const SizedBox(height: 14),
            const _SectionTitle('قسم الرجال'),
            const SizedBox(height: 8),
            _TopicGrid(
              topics: _menTopics,
              onTap: (topic) => _open(context, topic),
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
          colors: [Color(0xFF2A4A8D), Color(0xFF1E3363)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'اختار حسب احتياجك',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          SizedBox(height: 6),
          Text(
            'ملابس، أحذية، شنط، عناية... قسم واضح وسريع حتى توصل للمطلوب بدون لف.',
          ),
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

class _TopicGrid extends StatelessWidget {
  final List<_StyleTopic> topics;
  final ValueChanged<_StyleTopic> onTap;

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

class _StyleTopic {
  final String title;
  final String subtitle;
  final String query;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  const _StyleTopic({
    required this.title,
    required this.subtitle,
    required this.query,
    required this.icon,
    required this.colorA,
    required this.colorB,
  });
}

const _womenTopics = <_StyleTopic>[
  _StyleTopic(
    title: 'ملابس نسائية',
    subtitle: 'فساتين وعبايات',
    query: 'ملابس نسائية فساتين عبايات',
    icon: Icons.checkroom_rounded,
    colorA: Color(0xFF7A3E8D),
    colorB: Color(0xFF4E2A66),
  ),
  _StyleTopic(
    title: 'أحذية نسائية',
    subtitle: 'كعب وسنيكرز',
    query: 'أحذية نسائية كعب',
    icon: Icons.shopping_bag_rounded,
    colorA: Color(0xFF6A517F),
    colorB: Color(0xFF3F3353),
  ),
  _StyleTopic(
    title: 'شنط وإكسسوارات',
    subtitle: 'حقائب وساعات',
    query: 'شنط نسائية اكسسوار',
    icon: Icons.shopping_bag_outlined,
    colorA: Color(0xFF8E5D3F),
    colorB: Color(0xFF5A3A26),
  ),
  _StyleTopic(
    title: 'عناية وتجميل',
    subtitle: 'عطور ومكياج',
    query: 'مكياج عناية عطور نسائية',
    icon: Icons.auto_awesome_rounded,
    colorA: Color(0xFF4E6E95),
    colorB: Color(0xFF314A69),
  ),
];

const _menTopics = <_StyleTopic>[
  _StyleTopic(
    title: 'ملابس رجالية',
    subtitle: 'كاجوال ورسمي',
    query: 'ملابس رجالية دشاديش',
    icon: Icons.checkroom_rounded,
    colorA: Color(0xFF1F4F81),
    colorB: Color(0xFF183A62),
  ),
  _StyleTopic(
    title: 'أحذية رجالية',
    subtitle: 'رسمي ورياضي',
    query: 'أحذية رجالية رياضي',
    icon: Icons.hiking_rounded,
    colorA: Color(0xFF2F6C70),
    colorB: Color(0xFF1D4A4D),
  ),
  _StyleTopic(
    title: 'عطور رجالية',
    subtitle: 'روائح يومية',
    query: 'عطور رجالية',
    icon: Icons.water_drop_rounded,
    colorA: Color(0xFF5A6786),
    colorB: Color(0xFF35415A),
  ),
  _StyleTopic(
    title: 'مستلزمات رياضية',
    subtitle: 'ألبسة وتجهيزات',
    query: 'ملابس رياضية رجالية',
    icon: Icons.sports_gymnastics_rounded,
    colorA: Color(0xFF3D6E51),
    colorB: Color(0xFF274836),
  ),
];
