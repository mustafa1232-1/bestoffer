import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../auth/ui/merchants_list_screen.dart';

/// Fashion Market (سوق الأزياء) landing.
///
/// Shows ONLY the two top-level choices first — نسائي / رجالي — instead of the
/// old deep subcategory split. Selecting one opens the store list filtered by
/// that department (backend: activityType=fashion_clothing&department=men|women),
/// so the user sees stores immediately, scoped strictly to the chosen section.
class FashionMarketScreen extends StatelessWidget {
  const FashionMarketScreen({super.key});

  void _openDepartment(BuildContext context, String department, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialActivityType: 'fashion_clothing',
          initialDepartment: department,
          overrideTitle: title,
          compactCustomerMode: true,
          // Strict: only fashion stores of this department, no keyword fallback.
          strictCategoryMode: true,
          showCategoryIntelligence: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final womenTitle = context.lt(ar: 'نسائي', en: 'Women');
    final menTitle = context.lt(ar: 'رجالي', en: 'Men');
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'سوق الأزياء', en: 'Fashion Market')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                context.lt(
                  ar: 'اختر القسم لعرض المتاجر',
                  en: 'Choose a section to see its stores',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _DepartmentCard(
                  key: const Key('fashion_department_women'),
                  title: womenTitle,
                  icon: Icons.woman_rounded,
                  colorA: const Color(0xFF7A3E8D),
                  colorB: const Color(0xFF4E2A66),
                  onTap: () => _openDepartment(context, 'women', womenTitle),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _DepartmentCard(
                  key: const Key('fashion_department_men'),
                  title: menTitle,
                  icon: Icons.man_rounded,
                  colorA: const Color(0xFF20536B),
                  colorB: const Color(0xFF11313F),
                  onTap: () => _openDepartment(context, 'men', menTitle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  const _DepartmentCard({
    super.key,
    required this.title,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color colorA;
  final Color colorB;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colorA, colorB],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
