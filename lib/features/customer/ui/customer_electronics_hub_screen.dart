import 'package:flutter/material.dart';

import '../../auth/ui/merchants_list_screen.dart';

class CustomerElectronicsHubScreen extends StatelessWidget {
  const CustomerElectronicsHubScreen({super.key});

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
        appBar: AppBar(title: const Text('قسم التجهيزات الكهربائية')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
          children: [
            _HeaderCard(),
            const SizedBox(height: 12),
            _TopicGrid(
              topics: _electronicsTopics,
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
          colors: [Color(0xFF34558E), Color(0xFF22375F)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'قسم الكهرباء والتجهيزات',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          SizedBox(height: 6),
          Text('أجهزة منزلية، قطع كهرباء، إكسسوارات وتقنيات يومية.'),
        ],
      ),
    );
  }
}

class _TopicGrid extends StatelessWidget {
  final List<_ElectronicsTopic> topics;
  final ValueChanged<_ElectronicsTopic> onTap;

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

class _ElectronicsTopic {
  final String title;
  final String subtitle;
  final String query;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  const _ElectronicsTopic({
    required this.title,
    required this.subtitle,
    required this.query,
    required this.icon,
    required this.colorA,
    required this.colorB,
  });
}

const _electronicsTopics = <_ElectronicsTopic>[
  _ElectronicsTopic(
    title: 'تجهيزات كهربائية',
    subtitle: 'أساسيات المنزل',
    query: 'تجهيزات كهربائية',
    icon: Icons.electrical_services_rounded,
    colorA: Color(0xFF365F94),
    colorB: Color(0xFF244066),
  ),
  _ElectronicsTopic(
    title: 'أجهزة صغيرة',
    subtitle: 'استعمال يومي',
    query: 'أجهزة كهربائية منزلية',
    icon: Icons.kitchen_rounded,
    colorA: Color(0xFF4F6D95),
    colorB: Color(0xFF33475F),
  ),
  _ElectronicsTopic(
    title: 'إكسسوارات كهرباء',
    subtitle: 'مفاتيح وأسلاك',
    query: 'أسلاك مفاتيح كهرباء',
    icon: Icons.settings_input_hdmi_rounded,
    colorA: Color(0xFF3A6B78),
    colorB: Color(0xFF254751),
  ),
  _ElectronicsTopic(
    title: 'تقنيات وهواتف',
    subtitle: 'ملحقات وتقنيات',
    query: 'هواتف ملحقات تقنية',
    icon: Icons.devices_other_rounded,
    colorA: Color(0xFF5F5F9A),
    colorB: Color(0xFF3D3D66),
  ),
];
