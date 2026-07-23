import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
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
        return 'حسب الساعات';
      case 'fixed_package':
      case 'fixed':
      case 'FIXED':
      case 'starting_from':
        return 'حسب الحجز';
      case 'per_visit':
      case 'PER_VISIT':
        return 'حسب الزيارة';
      case 'per_unit':
      case 'PER_UNIT':
        return 'حسب الكمية';
      case 'inspection_required':
      case 'custom_quote':
      case 'INSPECTION_REQUIRED':
        return 'بعد المعاينة';
      default:
        return value;
    }
  }

  String _pricingUnitLabel(String value) {
    switch (value) {
      case 'hour':
        return 'ساعة';
      case 'visit':
        return 'زيارة';
      case 'day':
        return 'يوم';
      case 'device':
        return 'جهاز';
      case 'room':
        return 'غرفة';
      case 'meter':
        return 'متر';
      case 'item':
        return 'قطعة';
      case 'package':
      case 'job':
        return 'حجز';
      default:
        return value;
    }
  }

  String _executionModeLabel(String value) {
    switch (value) {
      case 'home':
        return 'في المنزل';
      case 'provider_location':
        return 'عند مقدم الخدمة';
      case 'remote':
        return 'عن بعد';
      case 'both':
        return 'منزلي أو عند المقدم';
      default:
        return value;
    }
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
        .entryFor(AppSectionKeys.services, displayName: 'الخدمات');
    if (servicesSection.isBlocked) {
      return SectionUnavailableScreen(entry: servicesSection);
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _offering == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الخدمة')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تعذر تحميل الخدمة.\n${_error ?? ''}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _load,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final offering = _offering!;
    final provider = offering.provider;
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

    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الخدمة')),
      bottomNavigationBar: _privatePreview
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ServiceRequestCreateScreen(offering: offering),
                      ),
                    );
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(offering.bookingCta),
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
          children: [
            if (_privatePreview)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'هذه الخدمة غير منشورة للجمهور بعد، لكن تم تحميلها لك من مساحة مقدم الخدمة.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            if (_privatePreview) const SizedBox(height: 10),
            if (primaryMediaUrl != null) ...[
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 280),
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: Image.network(
                        primaryMediaUrl,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image_outlined, size: 42),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              offering.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
                  child: const Text('صفحة مقدم الخدمة'),
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
                            'التسعير',
                            _pricingModelLabel(leadPricing.pricingModel),
                          ),
                          _specChip(
                            'الوحدة',
                            _pricingUnitLabel(leadPricing.pricingUnit),
                          ),
                          _specChip(
                            'مكان التنفيذ',
                            _executionModeLabel(offering.executionMode),
                          ),
                          if (offering.estimatedDurationMinutes != null)
                            _specChip(
                              'المدة',
                              '${offering.estimatedDurationMinutes} دقيقة',
                            ),
                        ],
                      ),
                    if (offering.inspectionRequired || offering.customQuoteOnly)
                      const Text(
                        'الخدمة تتطلب معاينة/تسعير قبل الاتفاق النهائي.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
            ),
            if (galleryMedia.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'الصور',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
                      child: Image.network(
                        media.mediaUrl,
                        width: 160,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 160,
                          color: Colors.black12,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            if ((offering.description ?? '').trim().isNotEmpty) ...[
              const Text(
                'وصف الخدمة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(offering.description!),
              const SizedBox(height: 12),
            ],
            if ((offering.includesText ?? '').trim().isNotEmpty) ...[
              const Text(
                'يشمل السعر',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(offering.includesText!),
              const SizedBox(height: 12),
            ],
            if ((offering.excludesText ?? '').trim().isNotEmpty) ...[
              const Text(
                'لا يشمل السعر',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(offering.excludesText!),
              const SizedBox(height: 12),
            ],
            if (offering.activePromotions.isNotEmpty) ...[
              const Text(
                'العروض الفعالة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...offering.activePromotions.map(
                (promo) => Card(
                  color: Colors.orange.withValues(alpha: 0.12),
                  child: ListTile(
                    title: Text(promo.title),
                    subtitle: Text(promo.description ?? ''),
                    trailing: Text(
                      promo.discountType == 'percentage'
                          ? '${promo.discountValue?.toStringAsFixed(0) ?? '0'}%'
                          : promo.discountType,
                    ),
                  ),
                ),
              ),
            ],
            if (offering.reviews.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'آراء العملاء',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...offering.reviews
                  .take(6)
                  .map(
                    (review) => Card(
                      child: ListTile(
                        title: Text(review.customerFullName ?? 'عميل'),
                        subtitle: Text(review.comment ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber),
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
    );
  }
}
