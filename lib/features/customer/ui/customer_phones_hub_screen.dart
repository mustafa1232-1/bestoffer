import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../../auth/ui/merchants_list_screen.dart';

/// Dedicated phones section. Phones span three real store activities
/// (`phones_technology`, `phone_maintenance`, `electronics_mobile`), and the
/// merchants list can only filter by one activity at a time, so we surface each
/// as a strict single-activity entry here. Every entry opens without a keyword
/// search so stores whose names don't contain "هواتف" (e.g. صيانة المحترف /
/// الضمان التقني للموبايلات) are never filtered out.
class CustomerPhonesHubScreen extends StatelessWidget {
  const CustomerPhonesHubScreen({super.key});

  void _open(BuildContext context, _PhonesTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          // Strict isolation by real activity category — no market+keyword.
          initialActivityType: topic.activityType,
          overrideTitle: topic.title,
          compactCustomerMode: true,
          strictCategoryMode: true,
        ),
      ),
    );
  }

  List<_PhonesTopic> _topics(BuildContext context) {
    return [
      _PhonesTopic(
        title: context.lt(ar: 'إلكترونيات وموبايل', en: 'Electronics & Mobile'),
        subtitle: context.lt(
          ar: 'هواتف وأجهزة وإلكترونيات وموبايلات',
          en: 'Phones, devices, electronics & mobiles',
        ),
        icon: Icons.smartphone_rounded,
        colorA: const Color(0xFF365F94),
        colorB: const Color(0xFF244066),
        activityType: 'electronics_mobile',
      ),
      _PhonesTopic(
        title: context.lt(ar: 'صيانة الهواتف', en: 'Phone Maintenance'),
        subtitle: context.lt(
          ar: 'صيانة الشاشات والبطاريات والبرمجة والضمان',
          en: 'Screen, battery, software repair & warranty',
        ),
        icon: Icons.build_rounded,
        colorA: const Color(0xFF3A6B78),
        colorB: const Color(0xFF254751),
        activityType: 'phone_maintenance',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.lt(ar: 'الهواتف والتكنولوجيا', en: 'Phones & Technology'),
        ),
        actions: const [AppBarQuickActions()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          _HeaderCard(
            title: context.lt(
              ar: 'كل ما يخص الهواتف في مكان واحد',
              en: 'Everything phones in one place',
            ),
            subtitle: context.lt(
              ar: 'بيع الهواتف والتقنيات، صيانة محترفة، وضمان تقني وملحقات.',
              en: 'Phone sales, professional maintenance, technical warranty & accessories.',
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
          colors: [Color(0xFF3D3D66), Color(0xFF25254A)],
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
  final List<_PhonesTopic> topics;
  final ValueChanged<_PhonesTopic> onTap;

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

class _PhonesTopic {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color colorA;
  final Color colorB;
  final String activityType;

  const _PhonesTopic({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.activityType,
  });
}
