import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../state/admin_controller.dart';
import 'monitoring_operations_list_screen.dart';
import 'monitoring_taxi_rides_screen.dart';

/// لوحة المتابعة الموحدة (المرحلة 3). تعرض البطاقات التشغيلية حسب صلاحيات
/// الموظف فقط (يحسمها الخادم) بعدّادات فورية حقيقية. الفرض في الخادم؛ هذه
/// الصفحة عرض فقط.
final commandCenterOverviewProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      return ref.read(adminApiProvider).monitoringOverview();
    });

class CommandCenterScreen extends ConsumerWidget {
  const CommandCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(commandCenterOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'لوحة المتابعة', en: 'Command center')),
        actions: [
          IconButton(
            tooltip: context.lt(ar: 'تحديث', en: 'Refresh'),
            onPressed: () => ref.invalidate(commandCenterOverviewProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          onRetry: () => ref.invalidate(commandCenterOverviewProvider),
        ),
        data: (data) {
          final cards = (data['cards'] as List?) ?? const [];
          if (cards.isEmpty) {
            return MaslakiEmptyState(
              icon: Icons.dashboard_customize_outlined,
              title: context.lt(
                ar: 'لا توجد بطاقات متاحة',
                en: 'No cards available',
              ),
              body: context.lt(
                ar: 'لا تملك صلاحية لعرض أي بطاقة متابعة حالياً.',
                en: 'You do not have permission to view any monitoring card yet.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(commandCenterOverviewProvider),
            child: ListView(
              padding: const EdgeInsets.all(MaslakiSpacing.md),
              children: [
                for (final raw in cards)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MaslakiSpacing.md),
                    child: _MonitoringCard(
                      card: Map<String, dynamic>.from(raw as Map),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MonitoringCard extends StatelessWidget {
  const _MonitoringCard({required this.card});

  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    final title = '${card['title'] ?? card['key'] ?? ''}';
    final available = card['available'] == true;
    final counters = card['counters'] is Map
        ? Map<String, dynamic>.from(card['counters'] as Map)
        : null;
    final key = '${card['key'] ?? ''}';
    final detailPath = card['detailPath'];
    final detailsPage = _detailsPageForKey(key);

    return MaslakiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (detailsPage != null && detailPath != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => detailsPage));
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(context.lt(ar: 'التفاصيل', en: 'Details')),
                ),
            ],
          ),
          const SizedBox(height: MaslakiSpacing.sm),
          if (!available)
            Text(
              context.lt(
                ar: 'قيد الربط — ستتوفر العدّادات قريباً.',
                en: 'Wiring in progress — counters coming soon.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            )
          else if (counters == null)
            Text(
              context.lt(
                ar: 'تعذّر تحميل العدّادات حالياً.',
                en: 'Counters unavailable right now.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: MaslakiSpacing.sm,
              runSpacing: MaslakiSpacing.sm,
              children: [
                for (final entry in counters.entries)
                  _CounterChip(
                    label: _counterLabel(context, entry.key),
                    value: '${entry.value}',
                    highlight:
                        _isAlertCounter(entry.key) &&
                        (int.tryParse('${entry.value}') ?? 0) > 0,
                  ),
              ],
            ),
          const SizedBox(height: MaslakiSpacing.sm),
          Text(
            _formatUpdatedAt(context, card['updatedAt']),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget? _detailsPageForKey(String key) {
    switch (key) {
      case 'taxi':
        return const MonitoringTaxiRidesScreen();
      case 'orders':
        return const MonitoringOperationsListScreen(
          mode: MonitoringOperationsMode.orders,
        );
      case 'delivery':
        return const MonitoringOperationsListScreen(
          mode: MonitoringOperationsMode.delivery,
        );
      default:
        return null;
    }
  }

  bool _isAlertCounter(String key) {
    return key == 'openEmergencies' ||
        key == 'cancelledToday' ||
        key == 'needsAttention';
  }

  String _counterLabel(BuildContext context, String key) {
    switch (key) {
      case 'active':
        return context.lt(ar: 'النشطة', en: 'Active');
      case 'searching':
        return context.lt(ar: 'قيد البحث', en: 'Searching');
      case 'cancelledToday':
        return context.lt(ar: 'ملغاة اليوم', en: 'Cancelled today');
      case 'completedToday':
        return context.lt(ar: 'مكتملة اليوم', en: 'Completed today');
      case 'openEmergencies':
        return context.lt(ar: 'طوارئ مفتوحة', en: 'Open emergencies');
      default:
        return key;
    }
  }

  String _formatUpdatedAt(BuildContext context, dynamic value) {
    final label = context.lt(ar: 'آخر تحديث', en: 'Updated');
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) return label;
    final local = parsed.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$label: $hh:$mm';
  }
}

class _CounterChip extends StatelessWidget {
  const _CounterChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = highlight
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final fg = highlight ? scheme.onErrorContainer : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 40),
          const SizedBox(height: MaslakiSpacing.sm),
          Text(
            context.lt(
              ar: 'تعذّر تحميل لوحة المتابعة.',
              en: 'Unable to load the command center.',
            ),
          ),
          const SizedBox(height: MaslakiSpacing.sm),
          FilledButton(
            onPressed: onRetry,
            child: Text(context.lt(ar: 'إعادة المحاولة', en: 'Retry')),
          ),
        ],
      ),
    );
  }
}
