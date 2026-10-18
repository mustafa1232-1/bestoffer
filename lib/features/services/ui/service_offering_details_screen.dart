import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/media/cached_app_video_loader.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../auth/presentation/login_screen.dart';
import '../../auth/state/auth_controller.dart';
import '../../behavior/data/behavior_api.dart';
import '../data/services_api.dart';
import '../models/service_models.dart';
import 'service_provider_profile_screen.dart';
import 'service_request_create_screen.dart';

class ServiceOfferingDetailsScreen extends ConsumerStatefulWidget {
  final int offeringId;

  const ServiceOfferingDetailsScreen({super.key, required this.offeringId});

  @override
  ConsumerState<ServiceOfferingDetailsScreen> createState() =>
      _ServiceOfferingDetailsScreenState();
}

class _ServiceOfferingDetailsScreenState
    extends ConsumerState<ServiceOfferingDetailsScreen> {
  bool _loading = true;
  bool _privatePreview = false;
  String? _error;
  ServiceOfferingModel? _offering;

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  String _t({required String ar, required String en}) => _isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _privatePreview = false;
    });
    try {
      final raw = await ref
          .read(servicesApiProvider)
          .getPublicOffering(widget.offeringId);
      final offering = ServiceOfferingModel.fromJson(raw);
      await ref
          .read(behaviorApiProvider)
          .trackEvent(
            eventName: 'services.offering_open',
            category: 'services',
            action: 'open_offering',
            entityType: 'service_offering',
            entityId: offering.id,
            metadata: {
              'offeringName': offering.name,
              'providerName': offering.provider.businessName,
              'route': 'services',
              'screenLabel': offering.name,
              'recentTitle': 'كنت تشاهد خدمة: ${offering.name}',
              'recentSubtitle': 'اضغط للعودة إلى ${offering.name}',
            },
          );
      if (!mounted) return;
      setState(() {
        _offering = offering;
        _loading = false;
        _privatePreview = false;
      });
    } catch (e) {
      final auth = ref.read(authControllerProvider);
      if (e is DioException &&
          e.response?.statusCode == 404 &&
          (auth.isServiceProvider || auth.isBackoffice || auth.isSuperAdmin)) {
        try {
          final workspaceRaw = await ref
              .read(servicesApiProvider)
              .getProviderWorkspace();
          final workspace = ServiceProviderWorkspaceModel.fromJson(
            workspaceRaw,
          );
          ServiceOfferingModel? privateOffering;
          for (final offering in workspace.provider.offerings) {
            if (offering.id == widget.offeringId) {
              privateOffering = offering;
              break;
            }
          }
          if (privateOffering != null) {
            if (!mounted) return;
            setState(() {
              _offering = privateOffering;
              _loading = false;
              _privatePreview = true;
              _error = null;
            });
            return;
          }
        } catch (_) {
          // Fall through to the regular error state below.
        }
      }
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _pricingModelLabel(String value) {
    switch (value) {
      case 'per_hour':
      case 'hourly':
      case 'HOURLY':
        return _t(ar: 'حسب الساعات', en: 'Hourly');
      case 'fixed_package':
      case 'fixed':
      case 'FIXED':
      case 'starting_from':
        return _t(ar: 'حسب الحجز', en: 'Fixed booking');
      case 'per_visit':
      case 'PER_VISIT':
        return _t(ar: 'حسب الزيارة', en: 'Per visit');
      case 'per_unit':
      case 'PER_UNIT':
        return _t(ar: 'حسب الكمية', en: 'Per unit');
      case 'inspection_required':
      case 'custom_quote':
      case 'INSPECTION_REQUIRED':
        return _t(ar: 'بعد المعاينة', en: 'After inspection');
      default:
        return value;
    }
  }

  String _executionModeLabel(String value) {
    switch (value) {
      case 'home':
        return _t(ar: 'في المنزل', en: 'At home');
      case 'provider_location':
        return _t(ar: 'عند مقدم الخدمة', en: 'At provider location');
      case 'remote':
        return _t(ar: 'عن بعد', en: 'Remote');
      case 'both':
        return _t(ar: 'منزلي أو عند المقدم', en: 'Home or provider location');
      default:
        return value;
    }
  }

  String _money(double value) {
    final digits = value.round().toString();
    return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  String _promotionValue(ServicePromotionModel promotion) {
    switch (promotion.discountType.trim().toUpperCase()) {
      case 'PERCENTAGE':
        return '${promotion.discountValue?.toStringAsFixed(0) ?? '0'}%';
      case 'FIXED_AMOUNT':
        return '${_money(promotion.discountValue ?? 0)} د.ع';
      case 'SPECIAL_UNIT_PRICE':
        return '${_money(promotion.specialPrice ?? 0)} د.ع';
      default:
        return promotion.discountType;
    }
  }

  Future<void> _startBooking(ServiceOfferingModel offering) async {
    var auth = ref.read(authControllerProvider);
    if (!auth.isAuthed || auth.isGuest) {
      final loggedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(popOnSuccess: true),
        ),
      );
      if (!mounted || loggedIn != true) return;
      auth = ref.read(authControllerProvider);
      if (!auth.isAuthed || auth.isGuest) return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceRequestCreateScreen(offering: offering),
      ),
    );
  }

  Widget _specChip(String label, String value) {
    return Chip(
      label: Text('$label: $value'),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final servicesSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(
          AppSectionKeys.services,
          displayName: _t(ar: 'الخدمات', en: 'Services'),
        );
    if (servicesSection.isBlocked) {
      return SectionUnavailableScreen(entry: servicesSection);
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _offering == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_t(ar: 'تفاصيل الخدمة', en: 'Service details')),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_t(ar: 'تعذر تحميل الخدمة.', en: 'Unable to load service.')}\n${_error ?? ''}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _load,
                  child: Text(_t(ar: 'إعادة المحاولة', en: 'Retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final offering = _offering!;
    final provider = offering.provider;
    final primaryMedia = offering.media.isEmpty ? null : offering.media.first;
    final primaryMediaUrl = offering.primaryMediaUrl;
    final galleryMedia = offering.media.length > 1
        ? offering.media.skip(1).toList()
        : const <ServiceMediaModel>[];
    ServicePricingOptionModel? leadPricing;
    if (offering.pricingOptions.isNotEmpty) {
      leadPricing = offering.pricingOptions.firstWhere(
        (item) => item.isDefault,
        orElse: () => offering.pricingOptions.first,
      );
    }
    final basePrice = offering.baseUnitPrice;
    final discountedPrice = offering.discountedUnitPrice;

    return Scaffold(
      appBar: AppBar(
        title: Text(_t(ar: 'تفاصيل الخدمة', en: 'Service details')),
      ),
      bottomNavigationBar: _privatePreview
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => _startBooking(offering),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(offering.bookingCta),
                ),
              ),
            ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
            children: [
              if (_privatePreview)
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _t(
                        ar: 'هذه الخدمة غير منشورة للجمهور بعد، لكن تم تحميلها لك من مساحة مقدم الخدمة.',
                        en: 'This service is not public yet, but it was loaded from the provider workspace.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              if (_privatePreview) const SizedBox(height: 10),
              if (primaryMediaUrl != null) ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final height = (constraints.maxWidth * 0.68).clamp(
                      240.0,
                      390.0,
                    );
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: double.infinity,
                        height: height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _ServiceMediaSurface(
                              media: primaryMedia!,
                              fit: BoxFit.cover,
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.72),
                                  ],
                                ),
                              ),
                            ),
                            PositionedDirectional(
                              start: 16,
                              end: 16,
                              bottom: 16,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    offering.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    provider.businessName ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
              ] else ...[
                Container(
                  height: 180,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.65),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.home_repair_service_outlined, size: 42),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          ar: 'صورة الخدمة غير متوفرة',
                          en: 'Service image unavailable',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                offering.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      provider.businessName ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ServiceProviderProfileScreen(
                            providerId: provider.id,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      _t(ar: 'صفحة مقدم الخدمة', en: 'Provider profile'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (discountedPrice != null && basePrice != null) ...[
                        Text(
                          '${_money(basePrice)} د.ع',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                decoration: TextDecoration.lineThrough,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_money(discountedPrice)} د.ع${leadPricing == null ? '' : ' ${leadPricing.unitDisplayText()}'}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ] else
                        Text(
                          offering.displayPriceText,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      const SizedBox(height: 6),
                      if (leadPricing != null)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _specChip(
                              _t(ar: 'التسعير', en: 'Pricing'),
                              _pricingModelLabel(leadPricing.pricingModel),
                            ),
                            _specChip(
                              _t(ar: 'الوحدة', en: 'Unit'),
                              leadPricing.unitDisplayText(),
                            ),
                            _specChip(
                              _t(ar: 'مكان التنفيذ', en: 'Execution'),
                              _executionModeLabel(offering.executionMode),
                            ),
                            if (offering.estimatedDurationMinutes != null)
                              _specChip(
                                _t(ar: 'المدة', en: 'Duration'),
                                _t(
                                  ar: '${offering.estimatedDurationMinutes} دقيقة',
                                  en: '${offering.estimatedDurationMinutes} minutes',
                                ),
                              ),
                          ],
                        ),
                      if (offering.inspectionRequired ||
                          offering.customQuoteOnly)
                        Text(
                          _t(
                            ar: 'الخدمة تتطلب معاينة/تسعير قبل الاتفاق النهائي.',
                            en: 'This service requires inspection or quote before final confirmation.',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ),
              ),
              if (galleryMedia.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _t(ar: 'صور وفيديو الخدمة', en: 'Service media'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: galleryMedia.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final media = galleryMedia[index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 160,
                          height: 120,
                          child: _ServiceMediaSurface(
                            media: media,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if ((offering.description ?? '').trim().isNotEmpty) ...[
                Text(
                  _t(ar: 'وصف الخدمة', en: 'Service description'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(offering.description!),
                const SizedBox(height: 12),
              ],
              if ((offering.includesText ?? '').trim().isNotEmpty) ...[
                Text(
                  _t(ar: 'يشمل السعر', en: 'Included'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(offering.includesText!),
                const SizedBox(height: 12),
              ],
              if ((offering.excludesText ?? '').trim().isNotEmpty) ...[
                Text(
                  _t(ar: 'لا يشمل السعر', en: 'Not included'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(offering.excludesText!),
                const SizedBox(height: 12),
              ],
              if (offering.activePromotions.isNotEmpty) ...[
                Text(
                  _t(ar: 'العروض الفعالة', en: 'Active offers'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ...offering.activePromotions.map(
                  (promo) => Card(
                    color: Colors.orange.withValues(alpha: 0.12),
                    child: ListTile(
                      title: Text(promo.title),
                      subtitle: Text(promo.description ?? ''),
                      trailing: Text(_promotionValue(promo)),
                    ),
                  ),
                ),
              ],
              if (offering.reviews.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _t(ar: 'آراء العملاء', en: 'Customer reviews'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ...offering.reviews
                    .take(6)
                    .map(
                      (review) => Card(
                        child: ListTile(
                          title: Text(
                            review.customerFullName ??
                                _t(ar: 'عميل', en: 'Customer'),
                          ),
                          subtitle: Text(review.comment ?? ''),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Colors.amber,
                              ),
                              Text('${review.rating}'),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceMediaSurface extends StatelessWidget {
  final ServiceMediaModel media;
  final BoxFit fit;

  const _ServiceMediaSurface({required this.media, required this.fit});

  @override
  Widget build(BuildContext context) {
    if (media.mediaKind.trim().toLowerCase() == 'video') {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedAppVideoLoader(
            videoUrl: media.mediaUrl,
            fit: fit,
            muted: true,
            loop: true,
          ),
          const Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: Colors.white,
              size: 42,
            ),
          ),
        ],
      );
    }
    return Image.network(
      media.mediaUrl,
      fit: fit,
      alignment: Alignment.center,
      errorBuilder: (_, _, _) => Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, size: 42),
      ),
    );
  }
}
