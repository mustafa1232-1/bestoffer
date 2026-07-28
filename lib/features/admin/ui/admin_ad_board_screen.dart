import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../models/ad_board_item_model.dart';
import '../state/admin_ad_board_controller.dart';
import '../state/admin_controller.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class AdminAdBoardScreen extends ConsumerStatefulWidget {
  const AdminAdBoardScreen({super.key});

  @override
  ConsumerState<AdminAdBoardScreen> createState() => _AdminAdBoardScreenState();
}

enum _AdTab { all, home, marketplace, categories, active, scheduled, expired }

class _AdminAdBoardScreenState extends ConsumerState<AdminAdBoardScreen> {
  _AdTab _tab = _AdTab.all;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(adminControllerProvider.notifier).bootstrap();
      await ref.read(adminAdBoardControllerProvider.notifier).bootstrap();
    });
  }

  String _placementChipLabel(AdBoardItemModel item) {
    switch (item.placement) {
      case 'MARKETPLACE_HOME':
        return 'السوق';
      case 'MARKETPLACE_CATEGORY':
        return 'تصنيف';
      case 'HOME_MAIN':
      default:
        return 'الرئيسية';
    }
  }

  String _tabLabel(_AdTab tab) {
    switch (tab) {
      case _AdTab.all:
        return 'الكل';
      case _AdTab.home:
        return 'الرئيسية العامة';
      case _AdTab.marketplace:
        return 'السوق';
      case _AdTab.categories:
        return 'التصنيفات';
      case _AdTab.active:
        return 'النشطة';
      case _AdTab.scheduled:
        return 'المجدولة';
      case _AdTab.expired:
        return 'المنتهية';
    }
  }

  List<AdBoardItemModel> _applyTab(List<AdBoardItemModel> items) {
    final now = DateTime.now();
    switch (_tab) {
      case _AdTab.all:
        return items;
      case _AdTab.home:
        return items.where((i) => i.placement == 'HOME_MAIN').toList();
      case _AdTab.marketplace:
        return items
            .where((i) => i.placement == 'MARKETPLACE_HOME')
            .toList();
      case _AdTab.categories:
        return items
            .where((i) => i.placement == 'MARKETPLACE_CATEGORY')
            .toList();
      case _AdTab.active:
        return items.where((i) => i.isLive(now)).toList();
      case _AdTab.scheduled:
        return items.where((i) => i.isScheduled(now)).toList();
      case _AdTab.expired:
        return items.where((i) => i.isExpired(now)).toList();
    }
  }

  Future<void> _confirmDelete(AdBoardItemModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.commonDelete),
        content: Text(
          'هل تريد حذف الإعلان "${item.title}"؟ لا يمكن التراجع.',
          textDirection: context.appTextDirection,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(adminAdBoardControllerProvider.notifier)
          .deleteItem(item.id);
    }
  }

  Future<void> _openSheet([AdBoardItemModel? item]) async {
    final merchants = ref.read(adminControllerProvider).managedMerchants;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AdBoardSheet(
        initial: item,
        merchants: merchants,
        onSubmit: (payload, imageFile) {
          if (item == null) {
            return ref
                .read(adminAdBoardControllerProvider.notifier)
                .createItem(payload, imageFile: imageFile);
          }
          return ref
              .read(adminAdBoardControllerProvider.notifier)
              .updateItem(item.id, payload, imageFile: imageFile);
        },
      ),
    );
  }

  String _mapMessage(String raw) {
    if (raw.startsWith('ad_board.validation_failed:')) {
      final fields = raw
          .substring('ad_board.validation_failed:'.length)
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map(_fieldLabel)
          .join('، ');
      return context.l10n.adminAdBoardReviewTheseFields(fields);
    }
    switch (raw) {
      case 'ad_board.load_failed':
        return context.l10n.adminAdBoardFailedToLoadTheAdBoard;
      case 'ad_board.create_success':
        return context.l10n.adminAdBoardAdItemCreated;
      case 'ad_board.create_failed':
        return context.l10n.adminAdBoardFailedToCreateTheAdItem;
      case 'ad_board.update_success':
        return context.l10n.adminAdBoardAdItemUpdated;
      case 'ad_board.update_failed':
        return context.l10n.adminAdBoardFailedToUpdateTheAdItem;
      case 'ad_board.delete_success':
        return context.l10n.adminAdBoardAdItemDeleted;
      case 'ad_board.delete_failed':
        return context.l10n.adminAdBoardFailedToDeleteTheAdItem;
      case 'ad_board.connection_failed':
        return context.l10n.adminAdBoardFailedToConnectToTheServer;
      default:
        return raw;
    }
  }

  String _fieldLabel(String raw) {
    switch (raw) {
      case 'title':
        return context.l10n.adminAdBoardTitle;
      case 'subtitle':
        return context.l10n.adminAdBoardSubtitle;
      case 'badgeLabel':
        return context.l10n.adminAdBoardBadgeLabel;
      case 'imageUrl':
        return context.l10n.adminAdBoardImageUrl;
      case 'ctaLabel':
        return context.l10n.adminAdBoardCtaLabel;
      case 'ctaTargetType':
        return context.l10n.adminAdBoardCtaType;
      case 'ctaTargetValue':
        return context.l10n.adminAdBoardCtaValue;
      case 'merchantId':
        return context.l10n.adminAdBoardLinkedMerchant;
      case 'targetId':
        return context.l10n.commonId;
      case 'targetRoute':
        return 'Route';
      case 'promoCode':
        return 'Promo Code';
      case 'category':
        return context.l10n.adminAdBoardOpenCategory;
      case 'externalLink':
        return context.l10n.adminAdBoardExternalUrl;
      case 'priority':
        return context.l10n.adminAdBoardPriority;
      case 'startsAt':
        return context.l10n.adminAdBoardStartDate;
      case 'endsAt':
        return context.l10n.adminAdBoardEndDate;
      default:
        return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminAdBoardControllerProvider);

    ref.listen<AdminAdBoardState>(adminAdBoardControllerProvider, (prev, next) {
      final message = next.error ?? next.success;
      final previous = prev?.error ?? prev?.success;
      if (message != null && message != previous && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mapMessage(message))));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.adminAdvancedToolsAdBoard),
        actions: [
          IconButton(
            tooltip: context.l10n.commonRefresh,
            onPressed: () =>
                ref.read(adminAdBoardControllerProvider.notifier).bootstrap(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: state.saving ? null : () => _openSheet(),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.l10n.adminAdBoardNewAd),
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(adminAdBoardControllerProvider.notifier).bootstrap(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.24),
                          Theme.of(
                            context,
                          ).colorScheme.secondary.withValues(alpha: 0.16),
                        ],
                      ),
                    ),
                    child: Text(
                      context.l10n.adminAdBoardIntroBanner,
                      textDirection: context.appTextDirection,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      children: _AdTab.values.map((tab) {
                        final selected = tab == _tab;
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text(_tabLabel(tab)),
                            selected: selected,
                            onSelected: (_) => setState(() => _tab = tab),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_applyTab(state.items).isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          context.l10n.adminAdBoardNoAdItemsYet,
                          textDirection: context.appTextDirection,
                        ),
                      ),
                    )
                  else
                    ..._applyTab(state.items).map(
                      (item) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          item.title,
                                          textDirection:
                                              context.appTextDirection,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.subtitle,
                                          textDirection:
                                              context.appTextDirection,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: item.isActive,
                                    onChanged: state.saving
                                        ? null
                                        : (value) {
                                            ref
                                                .read(
                                                  adminAdBoardControllerProvider
                                                      .notifier,
                                                )
                                                .updateItem(item.id, {
                                                  'isActive': value,
                                                });
                                          },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _Chip(label: _statusLabel(item)),
                                  _Chip(label: _placementChipLabel(item)),
                                  _Chip(
                                    label:
                                        '${context.l10n.adminAdBoardCta}: ${_ctaTypeLabel(item.ctaTargetType)}',
                                  ),
                                  _Chip(
                                    label:
                                        '${context.l10n.adminAdBoardPriority}: ${item.priority}',
                                  ),
                                  if ((item.category ?? '').trim().isNotEmpty)
                                    _Chip(label: 'قسم: ${item.category}'),
                                  if ((item.activityType ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    _Chip(label: 'نشاط: ${item.activityType}'),
                                  if ((item.merchantName ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    _Chip(
                                      label:
                                          '${context.l10n.commonMerchant}: ${item.merchantName}',
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _Chip(
                                    label:
                                        'مشاهدات: ${item.impressionCount}',
                                  ),
                                  _Chip(label: 'نقرات: ${item.clickCount}'),
                                  _Chip(
                                    label:
                                        'CTR: ${item.ctrPercent.toStringAsFixed(1)}%',
                                  ),
                                ],
                              ),
                              if (_scheduleLabel(item) != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _scheduleLabel(item)!,
                                  textDirection: context.appTextDirection,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if ((item.imageUrl ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: CachedAppImage(
                                    imageUrl: item.imageUrl!,
                                    height: 150,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: context.l10n.commonDelete,
                                    onPressed: state.saving
                                        ? null
                                        : () => _confirmDelete(item),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                  ),
                                  const Spacer(),
                                  FilledButton.icon(
                                    onPressed: state.saving
                                        ? null
                                        : () => _openSheet(item),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: Text(context.l10n.commonEdit),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  String _statusLabel(AdBoardItemModel item) {
    final now = DateTime.now();
    if (!item.isActive) return context.l10n.adminAdBoardDisabled;
    if (item.startsAt != null && item.startsAt!.isAfter(now)) {
      return context.l10n.adminAdBoardScheduled;
    }
    if (item.endsAt != null && item.endsAt!.isBefore(now)) {
      return context.l10n.adminAdBoardExpired;
    }
    return context.l10n.commonActive;
  }

  String _ctaTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'merchant':
        return context.l10n.adminAdBoardOpenMerchant;
      case 'category':
        return context.l10n.adminAdBoardOpenCategory;
      case 'product':
        return context.l10n.adminAdBoardOpenProduct;
      case 'taxi':
        return context.l10n.adminAdBoardOpenTaxi;
      case 'url':
        return context.l10n.adminAdBoardExternalUrl;
      case 'internal_campaign_page':
        return context.l10n.adminAdBoardInternalCampaignPage;
      case 'store_ad':
        return 'Store Ad';
      case 'promo_code':
        return 'Promo Code';
      case 'category_ad':
        return 'Category Ad';
      case 'external_link':
        return 'External Link';
      case 'internal_route':
        return 'Internal Route';
      default:
        return context.l10n.adminAdBoardNoAction;
    }
  }

  String? _scheduleLabel(AdBoardItemModel item) {
    final start = _fmt(item.startsAt);
    final end = _fmt(item.endsAt);
    if (start == null && end == null) return null;
    if (start != null && end != null) return '$start → $end';
    return start != null
        ? context.l10n.adminAdBoardStarts(start)
        : context.l10n.adminAdBoardEnds(end!);
  }

  String? _fmt(DateTime? value) {
    if (value == null) return null;
    return '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        textDirection: context.appTextDirection,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

typedef _AdBoardSubmit =
    Future<void> Function(
      Map<String, dynamic> payload,
      LocalImageFile? imageFile,
    );

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        textDirection: context.appTextDirection,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }
}

/// Live phone-sized preview of the ad as customers will see it on mobile.
class _AdMobilePreview extends StatelessWidget {
  final String titleAr;
  final String subtitleAr;
  final String ctaLabel;
  final String badgeLabel;
  final String imageUrl;
  final LocalImageFile? localImage;

  const _AdMobilePreview({
    required this.titleAr,
    required this.subtitleAr,
    required this.ctaLabel,
    required this.badgeLabel,
    required this.imageUrl,
    required this.localImage,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white24, width: 6),
          color: Colors.black,
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 2.6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl.isNotEmpty)
                CachedAppImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const ColoredBox(
                    color: Color(0xFF1A2E59),
                  ),
                )
              else
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF1A2E59), Color(0xFF142D51)],
                    ),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black26, Colors.black87],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (badgeLabel.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Colors.white24,
                        ),
                        child: Text(
                          badgeLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      titleAr.isEmpty ? 'عنوان الإعلان' : titleAr,
                      textDirection: TextDirection.rtl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitleAr.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitleAr,
                        textDirection: TextDirection.rtl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (ctaLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: Colors.white,
                          ),
                          child: Text(
                            ctaLabel,
                            style: const TextStyle(
                              color: Color(0xFF142D51),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductOption {
  final int id;
  final String name;

  const _ProductOption({required this.id, required this.name});

  factory _ProductOption.fromJson(Map<String, dynamic> json) {
    return _ProductOption(
      id: int.tryParse('${json['id'] ?? ''}') ?? 0,
      name: '${json['name'] ?? ''}'.trim(),
    );
  }
}

class _AdCategoryTarget {
  final String labelAr;
  final String labelEn;
  final String? category;
  final String? activityType;

  const _AdCategoryTarget({
    required this.labelAr,
    required this.labelEn,
    required this.category,
    required this.activityType,
  });

  String label(BuildContext context) =>
      context.lt(ar: labelAr, en: labelEn);
}

class _AdBoardSheet extends ConsumerStatefulWidget {
  final AdBoardItemModel? initial;
  final List<dynamic> merchants;
  final _AdBoardSubmit onSubmit;

  const _AdBoardSheet({
    this.initial,
    required this.merchants,
    required this.onSubmit,
  });

  @override
  ConsumerState<_AdBoardSheet> createState() => _AdBoardSheetState();
}

class _AdBoardSheetState extends ConsumerState<_AdBoardSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _badgeCtrl;
  late final TextEditingController _imageUrlCtrl;
  late final TextEditingController _ctaLabelCtrl;
  late final TextEditingController _ctaValueCtrl;
  late final TextEditingController _targetIdCtrl;
  late final TextEditingController _targetRouteCtrl;
  late final TextEditingController _promoCodeCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _externalLinkCtrl;
  late final TextEditingController _priorityCtrl;
  // Placement / bilingual / category-targeting / mobile image.
  late final TextEditingController _titleArCtrl;
  late final TextEditingController _titleEnCtrl;
  late final TextEditingController _subtitleArCtrl;
  late final TextEditingController _subtitleEnCtrl;
  late final TextEditingController _ctaLabelArCtrl;
  late final TextEditingController _ctaLabelEnCtrl;
  late final TextEditingController _mobileImageUrlCtrl;
  late final TextEditingController _activityTypeCtrl;

  static const List<String> _placements = <String>[
    'HOME_MAIN',
    'MARKETPLACE_HOME',
    'MARKETPLACE_CATEGORY',
  ];
  static const List<_AdCategoryTarget> _categoryTargets =
      <_AdCategoryTarget>[
    _AdCategoryTarget(
      labelAr: 'عام لكل صفحات الأقسام',
      labelEn: 'All category pages',
      category: null,
      activityType: null,
    ),
    _AdCategoryTarget(
      labelAr: 'الألبسة - عام',
      labelEn: 'Fashion - all',
      category: null,
      activityType: 'fashion_clothing',
    ),
    _AdCategoryTarget(
      labelAr: 'الألبسة - رجالي',
      labelEn: 'Fashion - men',
      category: 'men',
      activityType: 'fashion_clothing',
    ),
    _AdCategoryTarget(
      labelAr: 'الألبسة - نسائي',
      labelEn: 'Fashion - women',
      category: 'women',
      activityType: 'fashion_clothing',
    ),
    _AdCategoryTarget(
      labelAr: 'المطاعم',
      labelEn: 'Restaurants',
      category: null,
      activityType: 'restaurant',
    ),
    _AdCategoryTarget(
      labelAr: 'حلويات ومخابز',
      labelEn: 'Sweets & bakery',
      category: null,
      activityType: 'sweets_bakery',
    ),
    _AdCategoryTarget(
      labelAr: 'قهوة ومشروبات',
      labelEn: 'Coffee & drinks',
      category: null,
      activityType: 'coffee_drinks',
    ),
    _AdCategoryTarget(
      labelAr: 'ماركت وأسواق يومية',
      labelEn: 'Daily markets',
      category: null,
      activityType: 'supermarket',
    ),
    _AdCategoryTarget(
      labelAr: 'خضار وفواكه',
      labelEn: 'Fruits & vegetables',
      category: null,
      activityType: 'fruits_vegetables',
    ),
    _AdCategoryTarget(
      labelAr: 'مستلزمات المنزل',
      labelEn: 'Home & kitchen',
      category: null,
      activityType: 'home_kitchen',
    ),
    _AdCategoryTarget(
      labelAr: 'الإلكترونيات والموبايلات',
      labelEn: 'Electronics & mobile',
      category: null,
      activityType: 'electronics_mobile',
    ),
    _AdCategoryTarget(
      labelAr: 'الكهربائيات والإنارة',
      labelEn: 'Electrical & lighting',
      category: null,
      activityType: 'electrical_lighting',
    ),
    _AdCategoryTarget(
      labelAr: 'الصيدليات',
      labelEn: 'Pharmacies',
      category: null,
      activityType: 'pharmacy',
    ),
    _AdCategoryTarget(
      labelAr: 'الدخان والأراكيل',
      labelEn: 'Tobacco & hookah',
      category: null,
      activityType: 'smoking_supplies',
    ),
  ];
  String _placement = 'HOME_MAIN';
  _AdCategoryTarget? _selectedCategoryTarget;

  bool _saving = false;
  bool _isActive = true;
  bool _loadingProducts = false;
  LocalImageFile? _imageFile;
  String _ctaType = 'none';
  int? _merchantId;
  int? _selectedProductId;
  DateTime? _startsAt;
  DateTime? _endsAt;
  List<_ProductOption> _products = const [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _titleCtrl = TextEditingController(text: initial?.title ?? '');
    _subtitleCtrl = TextEditingController(text: initial?.subtitle ?? '');
    _badgeCtrl = TextEditingController(text: initial?.badgeLabel ?? '');
    _imageUrlCtrl = TextEditingController(text: initial?.imageUrl ?? '');
    _ctaLabelCtrl = TextEditingController(text: initial?.ctaLabel ?? '');
    _ctaValueCtrl = TextEditingController(text: initial?.ctaTargetValue ?? '');
    _targetIdCtrl = TextEditingController(
      text: initial?.targetId?.toString() ?? '',
    );
    _targetRouteCtrl = TextEditingController(text: initial?.targetRoute ?? '');
    _promoCodeCtrl = TextEditingController(text: initial?.promoCode ?? '');
    _categoryCtrl = TextEditingController(text: initial?.category ?? '');
    _externalLinkCtrl = TextEditingController(
      text: initial?.externalLink ?? '',
    );
    _priorityCtrl = TextEditingController(text: '${initial?.priority ?? 100}');
    _titleArCtrl = TextEditingController(text: initial?.titleAr ?? '');
    _titleEnCtrl = TextEditingController(text: initial?.titleEn ?? '');
    _subtitleArCtrl = TextEditingController(text: initial?.subtitleAr ?? '');
    _subtitleEnCtrl = TextEditingController(text: initial?.subtitleEn ?? '');
    _ctaLabelArCtrl = TextEditingController(text: initial?.ctaLabelAr ?? '');
    _ctaLabelEnCtrl = TextEditingController(text: initial?.ctaLabelEn ?? '');
    _mobileImageUrlCtrl = TextEditingController(
      text: initial?.mobileImageUrl ?? '',
    );
    _activityTypeCtrl = TextEditingController(text: initial?.activityType ?? '');
    _placement = _placements.contains(initial?.placement)
        ? initial!.placement
        : 'HOME_MAIN';
    _selectedCategoryTarget = _findCategoryTarget(
      category: initial?.category,
      activityType: initial?.activityType,
    );
    _ctaType = (initial?.type ?? initial?.ctaTargetType ?? 'none').trim();
    _merchantId = initial?.merchantId;
    _selectedProductId = int.tryParse(initial?.ctaTargetValue ?? '');
    _isActive = initial?.isActive ?? true;
    _startsAt = initial?.startsAt;
    _endsAt = initial?.endsAt;
    // Live mobile preview: rebuild when any preview-relevant field changes.
    for (final c in <TextEditingController>[
      _titleCtrl,
      _subtitleCtrl,
      _badgeCtrl,
      _imageUrlCtrl,
      _titleArCtrl,
      _subtitleArCtrl,
      _ctaLabelCtrl,
      _ctaLabelArCtrl,
      _mobileImageUrlCtrl,
    ]) {
      c.addListener(_onPreviewFieldChanged);
    }
    if (_merchantId != null) {
      Future.microtask(() => _loadProducts(_merchantId!));
    }
  }

  void _onPreviewFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _badgeCtrl.dispose();
    _imageUrlCtrl.dispose();
    _ctaLabelCtrl.dispose();
    _ctaValueCtrl.dispose();
    _targetIdCtrl.dispose();
    _targetRouteCtrl.dispose();
    _promoCodeCtrl.dispose();
    _categoryCtrl.dispose();
    _externalLinkCtrl.dispose();
    _priorityCtrl.dispose();
    _titleArCtrl.dispose();
    _titleEnCtrl.dispose();
    _subtitleArCtrl.dispose();
    _subtitleEnCtrl.dispose();
    _ctaLabelArCtrl.dispose();
    _ctaLabelEnCtrl.dispose();
    _mobileImageUrlCtrl.dispose();
    _activityTypeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts(int merchantId) async {
    setState(() => _loadingProducts = true);
    try {
      final raw = await ref
          .read(adminApiProvider)
          .adBoardMerchantProducts(merchantId);
      final items = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(_ProductOption.fromJson)
          .where((e) => e.id > 0 && e.name.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _products = items;
        _selectedProductId ??= items.isNotEmpty ? items.first.id : null;
      });
    } finally {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  _AdCategoryTarget? _findCategoryTarget({
    String? category,
    String? activityType,
  }) {
    final normalizedCategory = (category ?? '').trim().toLowerCase();
    final normalizedActivity = (activityType ?? '').trim().toLowerCase();
    for (final target in _categoryTargets) {
      final targetCategory = (target.category ?? '').trim().toLowerCase();
      final targetActivity = (target.activityType ?? '').trim().toLowerCase();
      if (targetCategory == normalizedCategory &&
          targetActivity == normalizedActivity) {
        return target;
      }
    }
    return null;
  }

  void _applyCategoryTarget(_AdCategoryTarget? target) {
    setState(() {
      _selectedCategoryTarget = target;
      if (target == null) return;
      _categoryCtrl.text = target.category ?? '';
      _activityTypeCtrl.text = target.activityType ?? '';
    });
  }

  String _placementLabel(String placement) {
    switch (placement) {
      case 'MARKETPLACE_HOME':
        return context.lt(ar: 'واجهة السوق', en: 'Marketplace home');
      case 'MARKETPLACE_CATEGORY':
        return context.lt(ar: 'صفحة تصنيف', en: 'Category page');
      case 'HOME_MAIN':
      default:
        return context.lt(ar: 'الرئيسية العامة', en: 'Home (general)');
    }
  }

  Future<void> _pickImage() async {
    final file = await pickImageFromDevice();
    if (file != null && mounted) setState(() => _imageFile = file);
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart
        ? (_startsAt ?? DateTime.now())
        : (_endsAt ?? DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
      locale: Locale(Localizations.localeOf(context).languageCode),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startsAt = DateTime(selected.year, selected.month, selected.day);
      } else {
        _endsAt = DateTime(
          selected.year,
          selected.month,
          selected.day,
          23,
          59,
          59,
        );
      }
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_ctaType == 'product' &&
        (_merchantId == null || _selectedProductId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.adminAdBoardChooseMerchantAndProductFirst,
            textDirection: context.appTextDirection,
          ),
        ),
      );
      return;
    }
    if (_startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.adminAdBoardEndDateAfterStart,
            textDirection: context.appTextDirection,
          ),
        ),
      );
      return;
    }
    if (_ctaType == 'external_link') {
      final link = _externalLinkCtrl.text.trim();
      final parsed = Uri.tryParse(link);
      if (link.isEmpty ||
          parsed == null ||
          !parsed.hasScheme ||
          parsed.scheme.toLowerCase() != 'https') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('External link must be https URL')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'subtitle': _subtitleCtrl.text.trim(),
        'badgeLabel': _badgeCtrl.text.trim().isEmpty
            ? null
            : _badgeCtrl.text.trim(),
        'imageUrl': _imageUrlCtrl.text.trim().isEmpty
            ? null
            : _imageUrlCtrl.text.trim(),
        'ctaLabel': _ctaLabelCtrl.text.trim().isEmpty
            ? null
            : _ctaLabelCtrl.text.trim(),
        'ctaTargetType': _ctaType,
        'ctaTargetValue': _ctaType == 'product'
            ? '${_selectedProductId!}'
            : (_ctaValueCtrl.text.trim().isEmpty
                  ? null
                  : _ctaValueCtrl.text.trim()),
        'targetId': int.tryParse(_targetIdCtrl.text.trim()),
        'targetRoute': _targetRouteCtrl.text.trim().isEmpty
            ? null
            : _targetRouteCtrl.text.trim(),
        'promoCode': _promoCodeCtrl.text.trim().isEmpty
            ? null
            : _promoCodeCtrl.text.trim(),
        'category': _categoryCtrl.text.trim().isEmpty
            ? null
            : _categoryCtrl.text.trim(),
        'externalLink': _externalLinkCtrl.text.trim().isEmpty
            ? null
            : _externalLinkCtrl.text.trim(),
        'merchantId': _merchantId,
        'priority': int.tryParse(_priorityCtrl.text.trim()) ?? 100,
        'isActive': _isActive,
        'startsAt': _startsAt?.toIso8601String(),
        'endsAt': _endsAt?.toIso8601String(),
        'placement': _placement,
        'titleAr': _emptyToNull(_titleArCtrl.text),
        'titleEn': _emptyToNull(_titleEnCtrl.text),
        'subtitleAr': _emptyToNull(_subtitleArCtrl.text),
        'subtitleEn': _emptyToNull(_subtitleEnCtrl.text),
        'ctaLabelAr': _emptyToNull(_ctaLabelArCtrl.text),
        'ctaLabelEn': _emptyToNull(_ctaLabelEnCtrl.text),
        'mobileImageUrl': _emptyToNull(_mobileImageUrlCtrl.text),
        // Category targeting only meaningful for MARKETPLACE_CATEGORY; sent as
        // null otherwise so an ad can act as the general fallback.
        'activityType': _placement == 'MARKETPLACE_CATEGORY'
            ? _emptyToNull(_activityTypeCtrl.text)
            : null,
      }..removeWhere((_, value) => value == null);

      await widget.onSubmit(payload, _imageFile);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final merchants = [
      DropdownMenuItem<int?>(
        value: null,
        child: Text(context.l10n.adminAdBoardGeneralAdWithoutMerchant),
      ),
      ...widget.merchants.map((merchant) {
        final id = int.tryParse('${merchant.id ?? ''}');
        final name = '${merchant.name ?? ''}'.trim();
        return DropdownMenuItem<int?>(value: id, child: Text(name));
      }),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          12,
          14,
          14 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                widget.initial == null
                    ? context.l10n.adminAdBoardCreateAd
                    : context.l10n.adminAdBoardEditAd,
                textDirection: context.appTextDirection,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: context.l10n.adminAdBoardTitle,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.l10n.adminAdBoardRequiredField
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _subtitleCtrl,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.l10n.adminAdBoardSubtitle,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.l10n.adminAdBoardRequiredField
                    : null,
              ),
              const SizedBox(height: 12),
              // ---- Placement ----
              DropdownButtonFormField<String>(
                initialValue: _placement,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.lt(ar: 'مكان الإعلان', en: 'Placement'),
                ),
                items: _placements
                    .map(
                      (p) => DropdownMenuItem<String>(
                        value: p,
                        child: Text(_placementLabel(p)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() {
                  _placement = value ?? 'HOME_MAIN';
                  if (_placement == 'MARKETPLACE_CATEGORY' &&
                      _selectedCategoryTarget == null &&
                      _categoryCtrl.text.trim().isEmpty &&
                      _activityTypeCtrl.text.trim().isEmpty) {
                    _selectedCategoryTarget = _categoryTargets.first;
                  }
                }),
              ),
              // ---- Category targeting (MARKETPLACE_CATEGORY only) ----
              if (_placement == 'MARKETPLACE_CATEGORY') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<_AdCategoryTarget?>(
                  initialValue: _selectedCategoryTarget,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.lt(
                      ar: 'القسم الذي يظهر فيه الإعلان',
                      en: 'Ad section',
                    ),
                    helperText: context.lt(
                      ar: 'اختر الصفحة المحددة، وسيظهر الإعلان هناك فقط. العام يظهر كاحتياط لكل صفحات الأقسام.',
                      en: 'Choose the exact page. General acts as fallback for category pages.',
                    ),
                  ),
                  items: _categoryTargets
                      .map(
                        (target) => DropdownMenuItem<_AdCategoryTarget?>(
                          value: target,
                          child: Text(target.label(context)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _applyCategoryTarget,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _categoryCtrl,
                  decoration: InputDecoration(
                    labelText: context.lt(
                      ar: 'مفتاح القسم الفرعي (اختياري)',
                      en: 'Category key',
                    ),
                    helperText: context.lt(
                      ar: 'مثال: men أو women. يملأ تلقائياً عند اختيار قسم من القائمة.',
                      en: 'Example: men or women. Filled automatically from the section list.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _activityTypeCtrl,
                  decoration: InputDecoration(
                    labelText: context.lt(
                      ar: 'نوع النشاط (اختياري)',
                      en: 'Activity type (optional)',
                    ),
                    helperText: context.lt(
                      ar: 'مثال: fashion_clothing أو electronics_mobile.',
                      en: 'Example: fashion_clothing or electronics_mobile.',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // ---- Bilingual overrides ----
              _SectionLabel(
                text: context.lt(
                  ar: 'نصوص ثنائية اللغة (اختياري)',
                  en: 'Bilingual text (optional)',
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _titleArCtrl,
                      decoration: const InputDecoration(labelText: 'العنوان (ع)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _titleEnCtrl,
                      decoration: const InputDecoration(labelText: 'Title (EN)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _subtitleArCtrl,
                      decoration: const InputDecoration(labelText: 'الوصف (ع)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _subtitleEnCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Subtitle (EN)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ctaLabelArCtrl,
                      decoration: const InputDecoration(labelText: 'زر CTA (ع)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _ctaLabelEnCtrl,
                      decoration: const InputDecoration(labelText: 'CTA (EN)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _mobileImageUrlCtrl,
                decoration: InputDecoration(
                  labelText: context.lt(
                    ar: 'رابط صورة الموبايل (اختياري)',
                    en: 'Mobile image URL (optional)',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ---- Live mobile preview ----
              _SectionLabel(
                text: context.lt(ar: 'معاينة الموبايل', en: 'Mobile preview'),
              ),
              const SizedBox(height: 6),
              _AdMobilePreview(
                titleAr: _titleArCtrl.text.trim().isNotEmpty
                    ? _titleArCtrl.text.trim()
                    : _titleCtrl.text.trim(),
                subtitleAr: _subtitleArCtrl.text.trim().isNotEmpty
                    ? _subtitleArCtrl.text.trim()
                    : _subtitleCtrl.text.trim(),
                ctaLabel: _ctaLabelArCtrl.text.trim().isNotEmpty
                    ? _ctaLabelArCtrl.text.trim()
                    : _ctaLabelCtrl.text.trim(),
                badgeLabel: _badgeCtrl.text.trim(),
                imageUrl: _mobileImageUrlCtrl.text.trim().isNotEmpty
                    ? _mobileImageUrlCtrl.text.trim()
                    : _imageUrlCtrl.text.trim(),
                localImage: _imageFile,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _merchantId,
                items: merchants,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.adminAdBoardLinkedMerchant,
                ),
                onChanged: (value) async {
                  setState(() {
                    _merchantId = value;
                    _products = const [];
                    _selectedProductId = null;
                    if (_ctaType == 'product' && _merchantId == null) {
                      _ctaType = 'none';
                    }
                  });
                  if (value != null) {
                    await _loadProducts(value);
                  }
                },
              ),
              if (_merchantId != null && _loadingProducts)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_merchantId != null && _products.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: _selectedProductId,
                  items: _products
                      .map(
                        (item) => DropdownMenuItem<int?>(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(growable: false),
                  decoration: InputDecoration(
                    labelText: context.l10n.adminAdBoardLinkedProduct,
                  ),
                  onChanged: (value) =>
                      setState(() => _selectedProductId = value),
                ),
              ],
              const SizedBox(height: 8),
              _ImageField(
                title: context.l10n.adminAdBoardAdImage,
                selectedFile: _imageFile,
                existingImageUrl: widget.initial?.imageUrl,
                onPick: _pickImage,
                onClear:
                    (_imageFile != null ||
                        (widget.initial?.imageUrl ?? '').isNotEmpty)
                    ? () {
                        setState(() {
                          _imageFile = null;
                          _imageUrlCtrl.clear();
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _imageUrlCtrl,
                decoration: InputDecoration(
                  labelText: context.l10n.adminAdBoardOrImageUrl,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _badgeCtrl,
                decoration: InputDecoration(
                  labelText: context.l10n.adminAdBoardBadgeLabel,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _priorityCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.adminAdBoardPriority,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _ctaType,
                decoration: InputDecoration(
                  labelText: context.l10n.adminAdBoardCtaDestination,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'none',
                    child: Text(context.l10n.adminAdBoardNoAction),
                  ),
                  DropdownMenuItem(
                    value: 'merchant',
                    child: Text(context.l10n.adminAdBoardOpenMerchant),
                  ),
                  DropdownMenuItem(
                    value: 'category',
                    child: Text(context.l10n.adminAdBoardOpenCategory),
                  ),
                  DropdownMenuItem(
                    value: 'product',
                    child: Text(context.l10n.adminAdBoardOpenProduct),
                  ),
                  DropdownMenuItem(
                    value: 'taxi',
                    child: Text(context.l10n.adminAdBoardOpenTaxi),
                  ),
                  DropdownMenuItem(
                    value: 'url',
                    child: Text(context.l10n.adminAdBoardExternalUrl),
                  ),
                  DropdownMenuItem(
                    value: 'internal_campaign_page',
                    child: Text(context.l10n.adminAdBoardInternalCampaignPage),
                  ),
                  const DropdownMenuItem(
                    value: 'store_ad',
                    child: Text('Store Ad'),
                  ),
                  const DropdownMenuItem(
                    value: 'promo_code',
                    child: Text('Promo Code'),
                  ),
                  const DropdownMenuItem(
                    value: 'category_ad',
                    child: Text('Category Ad'),
                  ),
                  const DropdownMenuItem(
                    value: 'external_link',
                    child: Text('External Link'),
                  ),
                  const DropdownMenuItem(
                    value: 'internal_route',
                    child: Text('Internal Route'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _ctaType = value ?? 'none'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _ctaLabelCtrl,
                decoration: InputDecoration(
                  labelText: context.l10n.adminAdBoardCtaLabel,
                ),
              ),
              if (_ctaType != 'product') ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ctaValueCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.adminAdBoardCtaValue,
                    helperText: _ctaType == 'internal_campaign_page'
                        ? context.l10n.adminAdBoardCampaignPageHelper
                        : null,
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if ((_ctaType == 'url' || _ctaType == 'category') &&
                        text.isEmpty) {
                      return context.l10n.adminAdBoardRequiredField;
                    }
                    return null;
                  },
                ),
              ],
              if (_ctaType == 'store_ad' || _ctaType == 'promo_code') ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _targetIdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target ID (optional)',
                  ),
                ),
              ],
              if (_ctaType == 'promo_code') ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _promoCodeCtrl,
                  decoration: const InputDecoration(labelText: 'Promo Code'),
                  validator: (value) {
                    if (_ctaType != 'promo_code') return null;
                    if ((value ?? '').trim().isEmpty) {
                      return context.l10n.adminAdBoardRequiredField;
                    }
                    return null;
                  },
                ),
              ],
              if (_ctaType == 'category_ad' || _ctaType == 'promo_code') ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _categoryCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Category (shopping/taxi/cars/...)',
                  ),
                ),
              ],
              if (_ctaType == 'internal_route') ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _targetRouteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Internal Route',
                  ),
                  validator: (value) {
                    if (_ctaType != 'internal_route') return null;
                    if ((value ?? '').trim().isEmpty) {
                      return context.l10n.adminAdBoardRequiredField;
                    }
                    return null;
                  },
                ),
              ],
              if (_ctaType == 'external_link') ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _externalLinkCtrl,
                  decoration: const InputDecoration(
                    labelText: 'External Link (https)',
                  ),
                  validator: (value) {
                    if (_ctaType != 'external_link') return null;
                    final text = (value ?? '').trim();
                    final parsed = Uri.tryParse(text);
                    if (text.isEmpty ||
                        parsed == null ||
                        !parsed.hasScheme ||
                        parsed.scheme.toLowerCase() != 'https') {
                      return context.l10n.adminAdBoardRequiredField;
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(true),
                      icon: const Icon(Icons.event_available_rounded),
                      label: Text(
                        _startsAt == null
                            ? context.l10n.adminAdBoardStartDate
                            : _fmt(_startsAt!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(false),
                      icon: const Icon(Icons.event_busy_rounded),
                      label: Text(
                        _endsAt == null
                            ? context.l10n.adminAdBoardEndDate
                            : _fmt(_endsAt!),
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.adminAdBoardActiveAndVisible),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _saving
                      ? context.l10n.adminAdBoardSaving
                      : context.l10n.adminAdBoardSaveAd,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
}

class _ImageField extends StatelessWidget {
  final String title;
  final LocalImageFile? selectedFile;
  final String? existingImageUrl;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _ImageField({
    required this.title,
    required this.selectedFile,
    required this.existingImageUrl,
    required this.onPick,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    Widget preview;
    if (selectedFile?.hasBytes == true) {
      preview = Image.memory(selectedFile!.bytes!, fit: BoxFit.cover);
    } else if ((existingImageUrl ?? '').trim().isNotEmpty) {
      preview = CachedAppImage(imageUrl: existingImageUrl!, fit: BoxFit.cover);
    } else {
      preview = Center(
        child: Text(
          context.l10n.adminAdBoardNoImageSelected,
          textDirection: context.appTextDirection,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textDirection: context.appTextDirection,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          height: 140,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.28),
            ),
          ),
          child: preview,
        ),
        Row(
          children: [
            if (onClear != null)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(context.l10n.adminAdBoardRemoveImage),
              ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(context.l10n.adminAdBoardPickFromDevice),
            ),
          ],
        ),
      ],
    );
  }
}
