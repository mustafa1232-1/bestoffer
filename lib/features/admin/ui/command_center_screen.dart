import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../state/admin_controller.dart';
import 'admin_notification_center_screen.dart';
import 'admin_support_tickets_screen.dart';
import 'monitoring_operations_list_screen.dart';
import 'monitoring_taxi_rides_screen.dart';

/// لوحة المتابعة الموحدة (المرحلة 3، إعادة تصميم المرحلة 2).
///
/// تعرض تقريراً مفهوماً لأي شخص: أولاً "تنبيهات تحتاج تدخّلاً" مجمّعة من كل
/// الأقسام ومرتّبة حسب الخطورة، ثم بطاقة لكل قسم بحالة صحية ووصف واضح وأرقام
/// مشروحة. البطاقات تظهر حسب صلاحيات الموظف (يحسمها الخادم). عرض فقط.
final commandCenterOverviewProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      return ref.read(adminApiProvider).monitoringOverview();
    });

// ===== مستويات الخطورة =====
enum _Sev { critical, warning, watch, info, good }

class _SevColors {
  const _SevColors(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

_SevColors _sevColors(BuildContext context, _Sev sev) {
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (sev) {
    case _Sev.critical:
      return _SevColors(scheme.errorContainer, scheme.onErrorContainer);
    case _Sev.warning:
      return _SevColors(
        dark ? const Color(0x33F59E0B) : const Color(0x1AF59E0B),
        dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
      );
    case _Sev.good:
      return _SevColors(
        dark ? const Color(0x3322C55E) : const Color(0x1A22C55E),
        dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
      );
    case _Sev.watch:
      return _SevColors(
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      );
    case _Sev.info:
      return _SevColors(scheme.surfaceContainerHighest, scheme.onSurface);
  }
}

// ===== وصف كل عدّاد بلغة مفهومة =====
class _MetricMeta {
  const _MetricMeta({
    required this.severity,
    required this.isAlert,
    required this.priority,
    required this.labelAr,
    required this.labelEn,
    required this.descAr,
    required this.descEn,
  });

  final _Sev severity;
  final bool isAlert; // يحتاج تدخّلاً حين تكون قيمته > 0
  final int priority; // الأصغر = أعلى أولوية في قائمة التنبيهات
  final String labelAr;
  final String labelEn;
  final String descAr;
  final String descEn;
}

const Map<String, _MetricMeta> _metricCatalog = {
  'openEmergencies': _MetricMeta(
    severity: _Sev.critical,
    isAlert: true,
    priority: 0,
    labelAr: 'طوارئ مفتوحة',
    labelEn: 'Open emergencies',
    descAr: 'رحلات فُعّل فيها زر الطوارئ — تدخّل فوري.',
    descEn: 'Rides where the emergency button was triggered — act now.',
  ),
  'pendingNoDriver': _MetricMeta(
    severity: _Sev.critical,
    isAlert: true,
    priority: 1,
    labelAr: 'طلبات بلا دلفري',
    labelEn: 'Orders with no courier',
    descAr: 'طلبات جاهزة لكن لا يوجد سائق لاستلامها.',
    descEn: 'Ready orders that no courier has picked up.',
  ),
  'needsAttention': _MetricMeta(
    severity: _Sev.warning,
    isAlert: true,
    priority: 2,
    labelAr: 'تحتاج تدخّلاً',
    labelEn: 'Needs attention',
    descAr: 'حالات متعثّرة تحتاج مراجعة يدوية.',
    descEn: 'Stuck cases that need a manual review.',
  ),
  'delayed': _MetricMeta(
    severity: _Sev.warning,
    isAlert: true,
    priority: 3,
    labelAr: 'متأخّرة',
    labelEn: 'Delayed',
    descAr: 'تجاوزت الوقت المتوقّع للإنجاز.',
    descEn: 'Past the expected completion time.',
  ),
  'openTickets': _MetricMeta(
    severity: _Sev.warning,
    isAlert: true,
    priority: 4,
    labelAr: 'شكاوى مفتوحة',
    labelEn: 'Open tickets',
    descAr: 'تذاكر/شكاوى مرتبطة لم تُحلّ بعد.',
    descEn: 'Linked complaints not resolved yet.',
  ),
  'active': _MetricMeta(
    severity: _Sev.info,
    isAlert: false,
    priority: 20,
    labelAr: 'نشطة الآن',
    labelEn: 'Active now',
    descAr: 'عمليات جارية حالياً.',
    descEn: 'Operations currently in progress.',
  ),
  'searching': _MetricMeta(
    severity: _Sev.info,
    isAlert: false,
    priority: 21,
    labelAr: 'قيد البحث عن كابتن',
    labelEn: 'Searching',
    descAr: 'رحلات تبحث عن كابتن الآن.',
    descEn: 'Rides looking for a captain right now.',
  ),
  'available': _MetricMeta(
    severity: _Sev.info,
    isAlert: false,
    priority: 22,
    labelAr: 'دلفري متاحون',
    labelEn: 'Couriers available',
    descAr: 'سائقون متصلون وجاهزون للاستلام.',
    descEn: 'Drivers online and ready to pick up.',
  ),
  'onlineFresh': _MetricMeta(
    severity: _Sev.info,
    isAlert: false,
    priority: 23,
    labelAr: 'متصلون حديثاً',
    labelEn: 'Freshly online',
    descAr: 'سائقون حدّثوا موقعهم خلال دقائق.',
    descEn: 'Drivers who updated location within minutes.',
  ),
  'deliveriesToday': _MetricMeta(
    severity: _Sev.info,
    isAlert: false,
    priority: 24,
    labelAr: 'توصيلات اليوم',
    labelEn: 'Deliveries today',
    descAr: 'إجمالي التوصيلات المنجزة اليوم.',
    descEn: 'Total deliveries completed today.',
  ),
  'cancelledToday': _MetricMeta(
    severity: _Sev.watch,
    isAlert: false,
    priority: 30,
    labelAr: 'ملغاة اليوم',
    labelEn: 'Cancelled today',
    descAr: 'عمليات أُلغيت اليوم — للمتابعة.',
    descEn: 'Operations cancelled today — worth watching.',
  ),
  'completedToday': _MetricMeta(
    severity: _Sev.good,
    isAlert: false,
    priority: 40,
    labelAr: 'مكتملة اليوم',
    labelEn: 'Completed today',
    descAr: 'عمليات أُنجزت بنجاح اليوم.',
    descEn: 'Operations completed successfully today.',
  ),
  'acknowledged': _MetricMeta(
    severity: _Sev.good,
    isAlert: false,
    priority: 41,
    labelAr: 'تمت معالجتها',
    labelEn: 'Acknowledged',
    descAr: 'تنبيهات جرى التعامل معها.',
    descEn: 'Alerts that were handled.',
  ),
};

_MetricMeta _metaFor(String key) {
  return _metricCatalog[key] ??
      _MetricMeta(
        severity: _Sev.info,
        isAlert: false,
        priority: 50,
        labelAr: key,
        labelEn: key,
        descAr: '',
        descEn: '',
      );
}

// ===== وصف كل قسم =====
class _SectionMeta {
  const _SectionMeta(this.icon, this.descAr, this.descEn);
  final IconData icon;
  final String descAr;
  final String descEn;
}

const Map<String, _SectionMeta> _sectionCatalog = {
  'taxi': _SectionMeta(
    Icons.local_taxi_rounded,
    'حالة رحلات التكسي المباشرة اليوم.',
    'Live taxi rides status today.',
  ),
  'orders': _SectionMeta(
    Icons.shopping_bag_rounded,
    'طلبات المتاجر وحالتها اليوم.',
    'Store orders and their status today.',
  ),
  'delivery': _SectionMeta(
    Icons.delivery_dining_rounded,
    'السائقون والتوصيلات الجارية.',
    'Couriers and deliveries in progress.',
  ),
  'services': _SectionMeta(
    Icons.handyman_rounded,
    'طلبات الخدمات المنزلية والمهنية.',
    'Home and professional service requests.',
  ),
  'real_estate': _SectionMeta(
    Icons.apartment_rounded,
    'إعلانات العقارات وحالتها.',
    'Real-estate listings and their status.',
  ),
  'cars': _SectionMeta(
    Icons.directions_car_rounded,
    'إعلانات السيارات وحالتها.',
    'Car listings and their status.',
  ),
  'jobs': _SectionMeta(
    Icons.work_rounded,
    'الوظائف والتقديمات عليها.',
    'Jobs and their applications.',
  ),
  'community': _SectionMeta(
    Icons.groups_rounded,
    'نشاط المجتمع والمستخدمون.',
    'Community activity and users.',
  ),
  'tickets': _SectionMeta(
    Icons.support_agent_rounded,
    'الشكاوى وتذاكر الدعم.',
    'Complaints and support tickets.',
  ),
  'ops_alerts': _SectionMeta(
    Icons.notifications_active_rounded,
    'التنبيهات التشغيلية العامة.',
    'General operational alerts.',
  ),
};

// عنصر تنبيه مجمّع للعرض في الأعلى.
class _Alert {
  const _Alert({
    required this.sectionKey,
    required this.sectionTitle,
    required this.count,
    required this.meta,
  });
  final String sectionKey;
  final String sectionTitle;
  final int count;
  final _MetricMeta meta;
}

int _toInt(dynamic value) => int.tryParse('${value ?? ''}') ?? 0;

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
          final cards = ((data['cards'] as List?) ?? const [])
              .whereType<Map>()
              .map((raw) => Map<String, dynamic>.from(raw))
              .toList(growable: false);
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

          final alerts = _collectAlerts(cards);
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(commandCenterOverviewProvider),
            child: ListView(
              padding: const EdgeInsets.all(MaslakiSpacing.md),
              children: [
                _AlertsBanner(alerts: alerts),
                const SizedBox(height: MaslakiSpacing.md),
                _SectionsHeader(count: cards.length),
                const SizedBox(height: MaslakiSpacing.sm),
                for (final card in cards)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MaslakiSpacing.md),
                    child: _MonitoringCard(card: card),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<_Alert> _collectAlerts(List<Map<String, dynamic>> cards) {
    final alerts = <_Alert>[];
    for (final card in cards) {
      if (card['available'] != true) continue;
      final counters = card['counters'];
      if (counters is! Map) continue;
      final title = '${card['title'] ?? card['key'] ?? ''}';
      final key = '${card['key'] ?? ''}';
      counters.forEach((counterKey, value) {
        final meta = _metaFor('$counterKey');
        final count = _toInt(value);
        if (meta.isAlert && count > 0) {
          alerts.add(
            _Alert(
              sectionKey: key,
              sectionTitle: title,
              count: count,
              meta: meta,
            ),
          );
        }
      });
    }
    alerts.sort((a, b) {
      final byPriority = a.meta.priority.compareTo(b.meta.priority);
      if (byPriority != 0) return byPriority;
      return b.count.compareTo(a.count);
    });
    return alerts;
  }
}

class _SectionsHeader extends StatelessWidget {
  const _SectionsHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.grid_view_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          context.lt(ar: 'تفاصيل الأقسام', en: 'Sections'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '($count)',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ===== بطاقة التنبيهات المجمّعة في الأعلى =====
class _AlertsBanner extends StatelessWidget {
  const _AlertsBanner({required this.alerts});
  final List<_Alert> alerts;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      final good = _sevColors(context, _Sev.good);
      return Container(
        padding: const EdgeInsets.all(MaslakiSpacing.md),
        decoration: BoxDecoration(
          color: good.bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: good.fg),
            const SizedBox(width: MaslakiSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.lt(
                      ar: 'كل شيء تحت السيطرة',
                      en: 'Everything is under control',
                    ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: good.fg,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    context.lt(
                      ar: 'لا يوجد ما يحتاج تدخّلاً الآن.',
                      en: 'Nothing needs intervention right now.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: good.fg,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final criticalCount = alerts
        .where((a) => a.meta.severity == _Sev.critical)
        .fold<int>(0, (sum, a) => sum + a.count);
    final totalCount = alerts.fold<int>(0, (sum, a) => sum + a.count);
    final headSev = alerts.first.meta.severity;
    final headColors = _sevColors(context, headSev);

    return Container(
      decoration: BoxDecoration(
        color: headColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: headColors.fg.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(MaslakiSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.priority_high_rounded, color: headColors.fg),
              const SizedBox(width: MaslakiSpacing.sm),
              Expanded(
                child: Text(
                  context.lt(
                    ar: 'تنبيهات تحتاج تدخّلاً',
                    en: 'Alerts needing intervention',
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: headColors.fg,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _CountBadge(text: '$totalCount', colors: headColors),
            ],
          ),
          if (criticalCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              context.lt(
                ar: 'منها $criticalCount حالة حرِجة تتطلّب تدخّلاً فورياً.',
                en: '$criticalCount of them are critical and need immediate action.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: headColors.fg,
              ),
            ),
          ],
          const SizedBox(height: MaslakiSpacing.sm),
          for (final alert in alerts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AlertRow(alert: alert),
            ),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});
  final _Alert alert;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final colors = _sevColors(context, alert.meta.severity);
    final scheme = Theme.of(context).colorScheme;
    final label = isArabic ? alert.meta.labelAr : alert.meta.labelEn;
    final desc = isArabic ? alert.meta.descAr : alert.meta.descEn;
    final detailsPage = _detailsPageForKey(alert.sectionKey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${alert.count}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.fg,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alert.sectionTitle} — $label',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (desc.isNotEmpty)
                  Text(
                    desc,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (detailsPage != null)
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => detailsPage)),
              child: Text(context.lt(ar: 'معالجة', en: 'Handle')),
            ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.text, required this.colors});
  final String text;
  final _SevColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.fg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: colors.bg,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ===== بطاقة قسم =====
class _MonitoringCard extends StatelessWidget {
  const _MonitoringCard({required this.card});

  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final title = '${card['title'] ?? card['key'] ?? ''}';
    final available = card['available'] == true;
    final key = '${card['key'] ?? ''}';
    final detailPath = card['detailPath'];
    final detailsPage = _detailsPageForKey(key);
    final section = _sectionCatalog[key];
    final counters = card['counters'] is Map
        ? Map<String, dynamic>.from(card['counters'] as Map)
        : null;

    // فرز العدّادات: التي تحتاج تدخّلاً أولاً ثم البقية حسب الأولوية.
    final entries = (counters?.entries.toList() ?? [])
      ..sort((a, b) => _metaFor(a.key).priority.compareTo(_metaFor(b.key).priority));
    final alertEntries = entries
        .where((e) => _metaFor(e.key).isAlert && _toInt(e.value) > 0)
        .toList(growable: false);
    final normalEntries = entries
        .where((e) => !(_metaFor(e.key).isAlert && _toInt(e.value) > 0))
        .toList(growable: false);

    final health = _healthFor(alertEntries);

    return MaslakiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (section != null) ...[
                Icon(
                  section.icon,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (section != null)
                      Text(
                        isArabic ? section.descAr : section.descEn,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (available && counters != null) _HealthPill(health: health),
            ],
          ),
          const SizedBox(height: MaslakiSpacing.sm),
          if (!available)
            _MutedNote(
              context.lt(
                ar: 'قيد الربط — ستتوفّر الأرقام قريباً.',
                en: 'Wiring in progress — numbers coming soon.',
              ),
            )
          else if (counters == null)
            _MutedNote(
              context.lt(
                ar: 'تعذّر تحميل الأرقام حالياً.',
                en: 'Numbers unavailable right now.',
              ),
            )
          else ...[
            if (alertEntries.isNotEmpty) ...[
              _GroupLabel(
                context.lt(ar: 'يحتاج تدخّلاً', en: 'Needs intervention'),
              ),
              for (final entry in alertEntries)
                _MetricRow(counterKey: entry.key, value: _toInt(entry.value)),
              const SizedBox(height: MaslakiSpacing.sm),
            ],
            if (normalEntries.isNotEmpty) ...[
              _GroupLabel(context.lt(ar: 'الوضع العام', en: 'General status')),
              for (final entry in normalEntries)
                _MetricRow(counterKey: entry.key, value: _toInt(entry.value)),
            ],
          ],
          const SizedBox(height: MaslakiSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatUpdatedAt(context, card['updatedAt']),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (detailsPage != null && detailPath != null)
                TextButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => detailsPage)),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(context.lt(ar: 'التفاصيل', en: 'Details')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  _Sev _healthFor(List<MapEntry<String, dynamic>> alertEntries) {
    var hasWarning = false;
    for (final entry in alertEntries) {
      final sev = _metaFor(entry.key).severity;
      if (sev == _Sev.critical) return _Sev.critical;
      if (sev == _Sev.warning) hasWarning = true;
    }
    return hasWarning ? _Sev.warning : _Sev.good;
  }
}

class _HealthPill extends StatelessWidget {
  const _HealthPill({required this.health});
  final _Sev health;

  @override
  Widget build(BuildContext context) {
    final colors = _sevColors(context, health);
    final String label;
    final IconData icon;
    switch (health) {
      case _Sev.critical:
        label = context.lt(ar: 'حرِج', en: 'Critical');
        icon = Icons.error_rounded;
        break;
      case _Sev.warning:
        label = context.lt(ar: 'يحتاج انتباه', en: 'Attention');
        icon = Icons.warning_amber_rounded;
        break;
      default:
        label = context.lt(ar: 'سليم', en: 'Healthy');
        icon = Icons.check_circle_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.fg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.counterKey, required this.value});
  final String counterKey;
  final int value;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final meta = _metaFor(counterKey);
    // العدّادات الصفرية غير التنبيهية تبقى بلون محايد حتى لا تُشتّت الانتباه.
    final sev = (meta.isAlert && value == 0) ? _Sev.info : meta.severity;
    final colors = _sevColors(context, sev);
    final scheme = Theme.of(context).colorScheme;
    final label = isArabic ? meta.labelAr : meta.labelEn;
    final desc = isArabic ? meta.descAr : meta.descEn;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$value',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.fg,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (desc.isNotEmpty)
                  Text(
                    desc,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MutedNote extends StatelessWidget {
  const _MutedNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
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
    case 'services':
      return const MonitoringOperationsListScreen(
        mode: MonitoringOperationsMode.services,
      );
    case 'real_estate':
      return const MonitoringOperationsListScreen(
        mode: MonitoringOperationsMode.realEstate,
      );
    case 'cars':
      return const MonitoringOperationsListScreen(
        mode: MonitoringOperationsMode.cars,
      );
    case 'jobs':
      return const MonitoringOperationsListScreen(
        mode: MonitoringOperationsMode.jobs,
      );
    case 'community':
      return const MonitoringOperationsListScreen(
        mode: MonitoringOperationsMode.community,
      );
    case 'tickets':
      return const AdminSupportTicketsScreen();
    case 'ops_alerts':
      return const AdminNotificationCenterScreen();
    default:
      return null;
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
