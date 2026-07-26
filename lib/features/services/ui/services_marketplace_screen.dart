// ignore_for_file: deprecated_member_use, unnecessary_brace_in_string_interps

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/cached_app_image.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../behavior/data/behavior_api.dart';
import '../../auth/state/auth_controller.dart';
import '../models/service_models.dart';
import '../state/services_discovery_controller.dart';
import 'service_my_requests_screen.dart';
import 'service_offering_details_screen.dart';
import 'service_provider_onboarding_screen.dart';
import 'service_provider_shell.dart';
import 'service_provider_workspace_screen.dart';

class ServicesMarketplaceScreen extends ConsumerStatefulWidget {
  const ServicesMarketplaceScreen({super.key});

  @override
  ConsumerState<ServicesMarketplaceScreen> createState() =>
      _ServicesMarketplaceScreenState();
}

class _ServicesMarketplaceScreenState
    extends ConsumerState<ServicesMarketplaceScreen> {
  final _searchCtrl = TextEditingController();
  bool _didTrackMarketplaceOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trackMarketplaceOpen();
    });
  }

  Future<void> _trackMarketplaceOpen() async {
    if (!mounted || _didTrackMarketplaceOpen) {
      return;
    }
    _didTrackMarketplaceOpen = true;
    await ref
        .read(behaviorApiProvider)
        .trackEvent(
          eventName: 'services.marketplace_open',
          category: 'services',
          action: 'open_marketplace',
          metadata: const {
            'route': 'services',
            'screenLabel': 'الخدمات',
            'recentTitle': 'كنت تتصفح قسم الخدمات',
            'recentSubtitle': 'اضغط للعودة إلى الخدمات',
          },
        );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openOffering(ServiceOfferingModel offering) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceOfferingDetailsScreen(offeringId: offering.id),
      ),
    );
  }

  Future<void> _openMyRequests() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ServiceMyRequestsScreen()));
  }

  Future<void> _openProviderWorkspace() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const ServiceProviderShell(child: ServiceProviderWorkspaceScreen()),
      ),
    );
  }

  Future<void> _openProviderOnboarding() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ServiceProviderOnboardingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(servicesDiscoveryControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final servicesSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.services, displayName: 'الخدمات');
    final ctrl = ref.read(servicesDiscoveryControllerProvider.notifier);
    if (servicesSection.isBlocked &&
        !servicesSection.allowExistingActiveAccess) {
      return SectionUnavailableScreen(entry: servicesSection);
    }

    final roots = state.categories.where((item) => item.level == 1).toList();
    ServiceCategoryModel? selectedRoot;
    for (final item in roots) {
      if (item.id == state.categoryId) {
        selectedRoot = item;
        break;
      }
    }
    final subcategories =
        selectedRoot?.children ?? const <ServiceCategoryModel>[];

    final mainCategoryDropdown = DropdownButtonFormField<int?>(
      value: state.categoryId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'الفئة الرئيسية'),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('كل الفئات', overflow: TextOverflow.ellipsis),
        ),
        ...roots.map(
          (item) => DropdownMenuItem<int?>(
            value: item.id,
            child: Text(item.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: ctrl.setCategory,
    );

    final subcategoryDropdown = DropdownButtonFormField<int?>(
      value: state.subcategoryId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'الفئة الفرعية'),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('الكل', overflow: TextOverflow.ellipsis),
        ),
        ...subcategories.map(
          (item) => DropdownMenuItem<int?>(
            value: item.id,
            child: Text(item.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: state.categoryId == null ? null : ctrl.setSubcategory,
    );

    final sortDropdown = DropdownButtonFormField<String>(
      value: state.sort,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'الفرز'),
      items: const [
        DropdownMenuItem(value: 'newest', child: Text('الأحدث')),
        DropdownMenuItem(value: 'cheapest', child: Text('الأرخص')),
        DropdownMenuItem(value: 'rating_desc', child: Text('الأعلى تقييمًا')),
        DropdownMenuItem(
          value: 'fastest_response',
          child: Text('الأسرع استجابة'),
        ),
        DropdownMenuItem(
          value: 'most_completed',
          child: Text('الأكثر إنجازًا'),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        ctrl.setSort(value);
      },
    );

    return Scaffold(
      appBar: MaslakiTopBar(
        title: 'الخدمات',
        subtitle: 'قسم الخدمات',
        actions: [
          if (!auth.isServiceProvider)
            IconButton(
              tooltip: 'طلباتي',
              onPressed: _openMyRequests,
              icon: const Icon(Icons.receipt_long_rounded),
            ),
          if (auth.isServiceProvider)
            IconButton(
              tooltip: 'لوحة مقدم الخدمة',
              onPressed: _openProviderWorkspace,
              icon: const Icon(Icons.workspaces_rounded),
            ),
          if (auth.isServiceProvider)
            IconButton(
              tooltip: 'متابعة الحساب',
              onPressed: _openProviderOnboarding,
              icon: const Icon(Icons.verified_user_outlined),
            ),
          if (!auth.isServiceProvider && servicesSection.isOpen)
            IconButton(
              tooltip: 'كن مقدم خدمة',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ServiceProviderOnboardingScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
        ],
      ),
      body: servicesSection.isBlocked
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                MaslakiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MaslakiStatusPill(
                        label: servicesSection.badgeLabel ?? 'غير متاح',
                        icon: Icons.lock_outline_rounded,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        servicesSection.effectiveMessage,
                        textDirection: TextDirection.rtl,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'تم إيقاف التصفح والطلبات الجديدة حاليًا. ما زال بإمكانك متابعة الطلبات النشطة فقط.',
                        textDirection: TextDirection.rtl,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.end,
                        children: [
                          if (!auth.isServiceProvider)
                            MaslakiPrimaryButton(
                              onPressed: _openMyRequests,
                              icon: Icons.receipt_long_rounded,
                              label: 'عرض طلباتي النشطة',
                            ),
                          if (auth.isServiceProvider)
                            MaslakiOutlineButton(
                              onPressed: _openProviderWorkspace,
                              icon: Icons.workspaces_rounded,
                              label: 'لوحة مقدم الخدمة',
                            ),
                          if (auth.isServiceProvider)
                            MaslakiPrimaryButton(
                              onPressed: _openProviderOnboarding,
                              icon: Icons.verified_user_outlined,
                              label: 'متابعة الحساب',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Column(
                    children: [
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          if (!auth.isServiceProvider)
                            Expanded(
                              child: MaslakiOutlineButton(
                                onPressed: _openMyRequests,
                                icon: Icons.receipt_long_rounded,
                                label: 'طلباتي',
                              ),
                            ),
                          if (!auth.isServiceProvider &&
                              servicesSection.isOpen) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: MaslakiPrimaryButton(
                                onPressed: _openProviderOnboarding,
                                icon: Icons.person_add_alt_1_rounded,
                                label: 'صاحب خدمة',
                              ),
                            ),
                          ],
                          if (auth.isServiceProvider) ...[
                            Expanded(
                              child: MaslakiOutlineButton(
                                onPressed: _openProviderWorkspace,
                                icon: Icons.workspaces_rounded,
                                label: 'لوحة مقدم الخدمة',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: MaslakiPrimaryButton(
                                onPressed: _openProviderOnboarding,
                                icon: Icons.verified_user_outlined,
                                label: 'متابعة الحساب',
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      MaslakiSearchField(
                        controller: _searchCtrl,
                        hintText: 'ابحث عن خدمة أو مقدم خدمة',
                        onSubmitted: (value) {
                          ctrl.setQuery(value);
                          ctrl.search();
                        },
                        trailing: IconButton(
                          onPressed: () {
                            ctrl.setQuery(_searchCtrl.text);
                            ctrl.search();
                          },
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 760) {
                        return MaslakiCard(
                          child: Column(
                            children: [
                              mainCategoryDropdown,
                              const SizedBox(height: 10),
                              subcategoryDropdown,
                              const SizedBox(height: 10),
                              sortDropdown,
                            ],
                          ),
                        );
                      }
                      return MaslakiCard(
                        child: Row(
                          children: [
                            Expanded(child: mainCategoryDropdown),
                            const SizedBox(width: 10),
                            Expanded(child: subcategoryDropdown),
                            const SizedBox(width: 10),
                            Expanded(child: sortDropdown),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      MaslakiChip(
                        label: 'منزلية',
                        icon: Icons.home_repair_service_outlined,
                        selected: state.homeService == true,
                        onTap: ctrl.toggleHomeService,
                      ),
                      const SizedBox(width: 8),
                      MaslakiChip(
                        label: 'طوارئ',
                        icon: Icons.emergency_outlined,
                        selected: state.emergency == true,
                        onTap: ctrl.toggleEmergencyService,
                      ),
                      const SizedBox(width: 8),
                      MaslakiChip(
                        label: 'بعروض فقط',
                        icon: Icons.local_offer_outlined,
                        selected: state.offersOnly == true,
                        onTap: ctrl.toggleOffersOnly,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: ctrl.search,
                    child: Builder(
                      builder: (context) {
                        if (state.loading) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (state.error != null && state.offerings.isEmpty) {
                          return ListView(
                            children: [
                              const SizedBox(height: 120),
                              MaslakiEmptyState(
                                icon: Icons.error_outline_rounded,
                                title: 'تعذر تحميل النتائج',
                                body:
                                    state.error ??
                                    'حدث خلل أثناء تحميل الخدمات.',
                              ),
                            ],
                          );
                        }
                        if (state.offerings.isEmpty) {
                          return ListView(
                            children: const [
                              SizedBox(height: 120),
                              MaslakiEmptyState(
                                icon: Icons.search_off_rounded,
                                title: 'لا توجد نتائج مطابقة',
                                body: 'جرّب تعديل البحث أو الفلاتر الحالية.',
                              ),
                            ],
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                          itemCount: state.offerings.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final offering = state.offerings[index];
                            return _ServiceOfferingCard(
                              offering: offering,
                              onTap: () => _openOffering(offering),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ServiceOfferingCard extends StatelessWidget {
  final ServiceOfferingModel offering;
  final VoidCallback onTap;

  const _ServiceOfferingCard({required this.offering, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rating = offering.provider.ratingAvg ?? 0;
    final reviews = offering.provider.ratingCount ?? 0;
    final tokens = context.maslakiTokens;
    final location = [
      offering.provider.city,
      offering.provider.area,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' - ');
    final coverUrl = offering.primaryMediaUrl ?? offering.provider.logoUrl;

    return MaslakiCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if ((coverUrl ?? '').trim().isNotEmpty)
                        CachedAppImage(
                          imageUrl: coverUrl!,
                          fit: BoxFit.cover,
                          placeholder: (placeholderContext, placeholderChild) =>
                              Container(
                                color: const Color(0xFF102748),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.design_services_outlined,
                                ),
                              ),
                          errorWidget:
                              (errorContext, errorChild, errorProgress) =>
                                  Container(
                                    color: const Color(0xFF102748),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.image_not_supported_outlined,
                                    ),
                                  ),
                        )
                      else
                        Container(
                          color: const Color(0xFF102748),
                          alignment: Alignment.center,
                          child: const Icon(Icons.design_services_outlined),
                        ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.6),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (offering.hasActivePromotion)
                        const PositionedDirectional(
                          top: 10,
                          start: 10,
                          child: MaslakiStatusPill(
                            label: 'عرض',
                            icon: Icons.local_offer_outlined,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: Text(
                      offering.name,
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    offering.displayPriceText,
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: tokens.primaryAccent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                offering.provider.businessName ?? '',
                textDirection: TextDirection.rtl,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (location.isNotEmpty)
                    _metaChip(Icons.location_on_outlined, location),
                  _metaChip(Icons.star_rounded, '$rating (${reviews} تقييم)'),
                  if (offering.provider.hasEmergencyService)
                    _metaChip(Icons.emergency_rounded, 'طوارئ'),
                  if ((offering.provider.averageResponseMinutes ?? 0) > 0)
                    _metaChip(
                      Icons.timer_outlined,
                      'رد خلال ${offering.provider.averageResponseMinutes} دقيقة',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return MaslakiChip(label: text, icon: icon);
  }
}
