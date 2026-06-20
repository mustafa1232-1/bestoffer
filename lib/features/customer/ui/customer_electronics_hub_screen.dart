import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../../auth/ui/merchants_list_screen.dart';

class CustomerElectronicsHubScreen extends StatelessWidget {
  const CustomerElectronicsHubScreen({super.key});

  void _open(BuildContext context, _ElectronicsTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          // Strict isolation by real activity category — never market+keyword.
          initialActivityType: topic.activityType,
          initialSearchQuery: topic.searchQuery,
          overrideTitle: topic.title,
          compactCustomerMode: true,
          strictCategoryMode: true,
          applyInitialSearchQuery: topic.searchQuery.trim().isNotEmpty,
        ),
      ),
    );
  }

  List<_ElectronicsTopic> _topics(BuildContext context) {
    final l10n = context.l10n;
    return [
      _ElectronicsTopic(
        title: l10n.customerElectronicsHubHomeAppliancesTitle,
        subtitle: l10n.customerElectronicsHubHomeAppliancesSubtitle,
        searchQuery: 'كهربائيات',
        searchTerms: [
          'كهربائيات',
          'كهرباء',
          'أجهزة',
          'electrical',
          'electronics',
          'appliance',
        ],
        icon: Icons.electrical_services_rounded,
        colorA: const Color(0xFF365F94),
        colorB: const Color(0xFF244066),
        activityType: 'electrical_lighting',
      ),
      _ElectronicsTopic(
        title: l10n.customerElectronicsHubSmallAppliancesTitle,
        subtitle: l10n.customerElectronicsHubSmallAppliancesSubtitle,
        searchQuery: 'أجهزة',
        searchTerms: [
          'أجهزة',
          'صغيرة',
          'خلاط',
          'غلاية',
          'machine',
          'appliance',
        ],
        icon: Icons.kitchen_rounded,
        colorA: const Color(0xFF4F6D95),
        colorB: const Color(0xFF33475F),
        activityType: 'home_kitchen',
      ),
      _ElectronicsTopic(
        title: l10n.customerElectronicsHubAccessoriesTitle,
        subtitle: l10n.customerElectronicsHubAccessoriesSubtitle,
        searchQuery: 'اكسسوارات كهرباء',
        searchTerms: [
          'اكسسوارات كهرباء',
          'مفاتيح',
          'أسلاك',
          'قابس',
          'adapter',
          'cable',
          'switch',
        ],
        icon: Icons.settings_input_hdmi_rounded,
        colorA: const Color(0xFF3A6B78),
        colorB: const Color(0xFF254751),
        activityType: 'electronics_mobile',
      ),
      _ElectronicsTopic(
        title: l10n.customerElectronicsHubPhonesTitle,
        subtitle: l10n.customerElectronicsHubPhonesSubtitle,
        searchQuery: 'هواتف',
        searchTerms: [
          'هواتف',
          'موبايل',
          'تقنيات',
          'هاتف',
          'phone',
          'mobile',
          'tech',
          'laptop',
        ],
        icon: Icons.devices_other_rounded,
        colorA: const Color(0xFF5F5F9A),
        colorB: const Color(0xFF3D3D66),
        activityType: 'electronics_mobile',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customerElectronicsHubTitle),
        actions: const [AppBarQuickActions()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          _HeaderCard(
            title: l10n.customerElectronicsHubHeaderTitle,
            subtitle: l10n.customerElectronicsHubHeaderSubtitle,
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
          colors: [Color(0xFF34558E), Color(0xFF22375F)],
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
  final List<_ElectronicsTopic> topics;
  final ValueChanged<_ElectronicsTopic> onTap;

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

class _ElectronicsTopic {
  final String title;
  final String subtitle;
  final String searchQuery;
  final List<String> searchTerms;
  final IconData icon;
  final Color colorA;
  final Color colorB;

  /// Strict store activity this topic isolates to.
  final String activityType;

  const _ElectronicsTopic({
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
