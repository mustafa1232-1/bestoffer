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
                      Text('نموذج التسعير: ${leadPricing.pricingModel}'),
                    if (leadPricing != null)
                      Text('الوحدة: ${leadPricing.pricingUnit}'),
                    if (offering.estimatedDurationMinutes != null)
                      Text(
                        'المدة التقديرية: ${offering.estimatedDurationMinutes} دقيقة',
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
            if (offering.media.isNotEmpty) ...[
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
                  itemCount: offering.media.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final media = offering.media[index];
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
