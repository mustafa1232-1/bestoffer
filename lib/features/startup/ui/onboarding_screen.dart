import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/notifications/push_notification_service.dart';
import '../../../core/widgets/maslaki_brand_mark.dart';
import '../../../core/widgets/maslaki_wordmark.dart';
import 'package:core_maps/core_maps.dart';

class MaslakiOnboardingScreen extends ConsumerStatefulWidget {
  final Future<void> Function() onStartNow;

  const MaslakiOnboardingScreen({super.key, required this.onStartNow});

  @override
  ConsumerState<MaslakiOnboardingScreen> createState() =>
      _MaslakiOnboardingScreenState();
}

class _MaslakiOnboardingScreenState
    extends ConsumerState<MaslakiOnboardingScreen> {
  final PageController _pageController = PageController();
  int _pageIndex = 0;
  bool _submitting = false;
  bool _loadingLocationPermission = false;
  bool _loadingNotificationPermission = false;
  bool _locationGranted = false;
  bool _notificationsGranted = false;
  bool _locationServiceEnabled = true;
  bool _locationPermanentlyDenied = false;
  bool _notificationsPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadPermissionStatus);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<_OnboardingServiceTileData> _serviceCatalog(BuildContext context) => [
    _OnboardingServiceTileData(
      title: context.l10n.onboardingRestaurantsTitle,
      icon: Icons.restaurant_menu_rounded,
      accent: const Color(0xFFFFA23B),
      kind: _OnboardingSlideKind.restaurants,
    ),
    _OnboardingServiceTileData(
      title: context.l10n.customerHomeShoppingHubTitle,
      icon: Icons.shopping_bag_rounded,
      accent: const Color(0xFF4AB8FF),
      kind: _OnboardingSlideKind.shopping,
    ),
    _OnboardingServiceTileData(
      title: context.l10n.customerDiscoveryHubPharmacyTitle,
      icon: Icons.local_pharmacy_rounded,
      accent: const Color(0xFF78D6B4),
    ),
    _OnboardingServiceTileData(
      title: context.l10n.deliveryAppTitle,
      icon: Icons.local_shipping_rounded,
      accent: const Color(0xFFE6C98A),
    ),
    _OnboardingServiceTileData(
      title: context.l10n.onboardingTaxiTitle,
      icon: Icons.local_taxi_rounded,
      accent: const Color(0xFFFFD23B),
      kind: _OnboardingSlideKind.taxi,
    ),
    _OnboardingServiceTileData(
      title: context.l10n.jobsHubPlatformTitle,
      icon: Icons.work_outline_rounded,
      accent: const Color(0xFF71DF89),
      kind: _OnboardingSlideKind.jobs,
    ),
    _OnboardingServiceTileData(
      title: context.l10n.socialExploreHeroTitle,
      icon: Icons.groups_rounded,
      accent: const Color(0xFFC88BFF),
      kind: _OnboardingSlideKind.community,
    ),
  ];

  List<_OnboardingSlide> _slides(BuildContext context) => [
    _OnboardingSlide(
      kind: _OnboardingSlideKind.restaurants,
      title: context.l10n.onboardingRestaurantsTitle,
      description: context.l10n.onboardingRestaurantsDescription,
      accent: const Color(0xFFFFA23B),
      icon: Icons.restaurant_menu_rounded,
      visual: const _FoodVisual(),
    ),
    _OnboardingSlide(
      kind: _OnboardingSlideKind.shopping,
      title: context.l10n.onboardingShoppingTitle,
      description: context.l10n.onboardingShoppingDescription,
      accent: const Color(0xFF4AB8FF),
      icon: Icons.shopping_bag_rounded,
      visual: const _ShoppingVisual(),
    ),
    _OnboardingSlide(
      kind: _OnboardingSlideKind.taxi,
      title: context.l10n.onboardingTaxiTitle,
      description: context.l10n.onboardingTaxiDescription,
      accent: const Color(0xFFFFD23B),
      icon: Icons.local_taxi_rounded,
      visual: const _YellowTaxiVisual(),
    ),
    _OnboardingSlide(
      kind: _OnboardingSlideKind.jobs,
      title: context.l10n.onboardingJobsTitle,
      description: context.l10n.onboardingJobsDescription,
      accent: const Color(0xFF71DF89),
      icon: Icons.work_outline_rounded,
      visual: const _JobsVisual(),
    ),
    _OnboardingSlide(
      kind: _OnboardingSlideKind.community,
      title: context.l10n.onboardingCommunityTitle,
      description: context.l10n.onboardingCommunityDescription,
      accent: const Color(0xFFC88BFF),
      icon: Icons.groups_rounded,
      visual: const _CommunityVisual(),
    ),
    _OnboardingSlide(
      kind: _OnboardingSlideKind.permissions,
      title: context.l10n.onboardingPermissionsTitle,
      description: context.l10n.onboardingPermissionsDescription,
      accent: const Color(0xFF43D6FF),
      icon: Icons.verified_user_rounded,
      visual: const _PermissionsVisual(),
      permissionsStep: true,
    ),
  ];

  Future<void> _loadPermissionStatus() async {
    final locationStatus = await ref
        .read(locationPermissionServiceProvider)
        .getStatus();
    final notificationStatus = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _locationServiceEnabled = locationStatus.serviceEnabled;
      _locationGranted = locationStatus.isGranted;
      _locationPermanentlyDenied = locationStatus.isPermanentlyDenied;
      _notificationsGranted =
          notificationStatus.isGranted || notificationStatus.isLimited;
      _notificationsPermanentlyDenied = notificationStatus.isPermanentlyDenied;
    });
  }

  Future<void> _requestLocationPermission() async {
    if (_loadingLocationPermission) return;
    setState(() => _loadingLocationPermission = true);
    try {
      final service = ref.read(locationPermissionServiceProvider);
      final current = await service.getStatus();
      if (!current.serviceEnabled) {
        await service.openLocationSettings();
      }
      final next = await service.requestPermission();
      if (next.isPermanentlyDenied) {
        await openAppSettings();
      }
    } finally {
      if (mounted) {
        setState(() => _loadingLocationPermission = false);
      }
      await _loadPermissionStatus();
    }
  }

  Future<void> _requestNotificationsPermission() async {
    if (_loadingNotificationPermission) return;
    setState(() => _loadingNotificationPermission = true);
    try {
      final status = await Permission.notification.status;
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        await ref.read(localNotificationsProvider).requestPermissionsIfNeeded();
        await ref.read(pushNotificationsProvider).requestPermissionIfNeeded();
        await Permission.notification.request();
      }
    } finally {
      if (mounted) {
        setState(() => _loadingNotificationPermission = false);
      }
      await _loadPermissionStatus();
    }
  }

  Future<void> _nextOrFinish(List<_OnboardingSlide> slides) async {
    if (_submitting) return;
    if (_pageIndex < slides.length - 1) {
      await _goToPage(_pageIndex + 1);
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onStartNow();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _skip() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onStartNow();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _goToPage(int index) async {
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildSlideCard(
    BuildContext context,
    _OnboardingSlide slide,
    List<_OnboardingServiceTileData> services,
    int slideIndex,
    int slideCount,
  ) {
    final tokens = context.maslakiTokens;
    final isWide = MediaQuery.sizeOf(context).width >= 760;

    final visualPanel = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: isWide ? 320 : 360,
        minHeight: 250,
        maxHeight: 330,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    slide.accent.withValues(alpha: 0.28),
                    slide.accent.withValues(alpha: 0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: _OnboardingMetaPill(
              icon: slide.icon,
              label: '${slideIndex + 1} / $slideCount',
              color: slide.accent,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: slide.visual,
              ),
            ),
          ),
        ],
      ),
    );

    final contentPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const _OnboardingBrandChip(),
            _OnboardingMetaPill(
              icon: slide.icon,
              label: '${slideIndex + 1} / $slideCount',
              color: slide.accent,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          slide.title,
          textAlign: TextAlign.start,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          slide.description,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: tokens.textSecondary,
            height: 1.55,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 18),
        _OnboardingServicesPanel(
          services: services,
          activeKind: slide.kind == _OnboardingSlideKind.permissions
              ? null
              : slide.kind,
        ),
        if (slide.permissionsStep) ...[
          const SizedBox(height: 18),
          _PermissionConsentPanel(
            locationGranted: _locationGranted,
            locationServiceEnabled: _locationServiceEnabled,
            locationPermanentlyDenied: _locationPermanentlyDenied,
            notificationsGranted: _notificationsGranted,
            notificationsPermanentlyDenied: _notificationsPermanentlyDenied,
            loadingLocationPermission: _loadingLocationPermission,
            loadingNotificationPermission: _loadingNotificationPermission,
            onRequestLocation: _requestLocationPermission,
            onRequestNotifications: _requestNotificationsPermission,
          ),
        ],
      ],
    );

    return MaslakiCard(
      radius: 30,
      padding: const EdgeInsets.all(18),
      backgroundColor: tokens.cardPrimary.withValues(alpha: 0.74),
      borderColor: Colors.white.withValues(alpha: 0.10),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          slide.accent.withValues(alpha: 0.16),
          tokens.cardPrimary.withValues(alpha: 0.92),
          tokens.cardElevated.withValues(alpha: 0.94),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 5, child: contentPanel),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: visualPanel),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      visualPanel,
                      const SizedBox(height: 12),
                      contentPanel,
                    ],
                  ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides(context);
    final isLast = _pageIndex == slides.length - 1;
    final current = slides[_pageIndex];
    final l10n = context.l10n;
    final tokens = context.maslakiTokens;
    final services = _serviceCatalog(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tokens.backgroundPrimary,
                  tokens.backgroundSecondary,
                  tokens.backgroundTertiary,
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.85, -0.90),
                    radius: 1.0,
                    colors: [
                      current.accent.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(child: _OnboardingHeaderBrand()),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: _submitting ? null : _skip,
                        icon: const Icon(Icons.chevron_right_rounded),
                        label: Text(l10n.onboardingSkip),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: slides.length,
                    onPageChanged: (value) =>
                        setState(() => _pageIndex = value),
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: _buildSlideCard(
                        context,
                        slides[index],
                        services,
                        index,
                        slides.length,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  child: MaslakiCard(
                    radius: 24,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    backgroundColor: tokens.cardPrimary.withValues(alpha: 0.68),
                    borderColor: Colors.white.withValues(alpha: 0.08),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            slides.length,
                            (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: _pageIndex == index ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: _pageIndex == index
                                    ? current.accent
                                    : Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            if (_pageIndex > 0) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _submitting
                                      ? null
                                      : () => _goToPage(_pageIndex - 1),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  label: Text(l10n.commonBack),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: tokens.textPrimary,
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.16,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              flex: _pageIndex > 0 ? 2 : 1,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: current.accent,
                                  foregroundColor: const Color(0xFF08132D),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onPressed: _submitting
                                    ? null
                                    : () => _nextOrFinish(slides),
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        isLast
                                            ? Icons.check_circle_rounded
                                            : Icons.arrow_forward_rounded,
                                      ),
                                label: Text(
                                  isLast
                                      ? l10n.onboardingStartNow
                                      : l10n.commonNext,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

enum _OnboardingSlideKind {
  restaurants,
  shopping,
  taxi,
  jobs,
  community,
  permissions,
}

class _OnboardingSlide {
  final _OnboardingSlideKind kind;
  final String title;
  final String description;
  final Color accent;
  final IconData icon;
  final Widget visual;
  final bool permissionsStep;

  const _OnboardingSlide({
    required this.kind,
    required this.title,
    required this.description,
    required this.accent,
    required this.icon,
    required this.visual,
    this.permissionsStep = false,
  });
}

class _OnboardingServiceTileData {
  final String title;
  final IconData icon;
  final Color accent;
  final _OnboardingSlideKind? kind;

  const _OnboardingServiceTileData({
    required this.title,
    required this.icon,
    required this.accent,
    this.kind,
  });
}

class _OnboardingHeaderBrand extends StatelessWidget {
  const _OnboardingHeaderBrand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        MaslakiBrandMark(size: 42, borderRadius: 14),
        SizedBox(width: 12),
        Expanded(
          child: MaslakiWordmark(
            arabicSize: 24,
            latinSize: 9.5,
            latinLetterSpacing: 3.6,
            showLatin: true,
          ),
        ),
      ],
    );
  }
}

class _OnboardingBrandChip extends StatelessWidget {
  const _OnboardingBrandChip();

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: tokens.primaryAccent.withValues(alpha: 0.12),
        border: Border.all(color: tokens.primaryAccent.withValues(alpha: 0.22)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MaslakiBrandMark(size: 24, borderRadius: 8, showGlow: false),
            SizedBox(width: 8),
            MaslakiWordmark(
              arabicSize: 16,
              latinSize: 7,
              latinLetterSpacing: 2.8,
              showLatin: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _OnboardingMetaPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingServicesPanel extends StatelessWidget {
  final List<_OnboardingServiceTileData> services;
  final _OnboardingSlideKind? activeKind;

  const _OnboardingServicesPanel({
    required this.services,
    required this.activeKind,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.splashTagline,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.onboardingBrand,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: services
                  .map(
                    (service) => _OnboardingServiceTile(
                      data: service,
                      active: activeKind != null && service.kind == activeKind,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingServiceTile extends StatelessWidget {
  final _OnboardingServiceTileData data;
  final bool active;

  const _OnboardingServiceTile({required this.data, required this.active});

  @override
  Widget build(BuildContext context) {
    final background = active
        ? data.accent.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.04);
    final border = active
        ? data.accent.withValues(alpha: 0.36)
        : Colors.white.withValues(alpha: 0.10);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: background,
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: data.accent.withValues(alpha: active ? 0.24 : 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(data.icon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodVisual extends StatelessWidget {
  const _FoodVisual();

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      'assets/lottie/onboarding_food.json',
      fit: BoxFit.contain,
      repeat: true,
    );
  }
}

class _CommunityVisual extends StatelessWidget {
  const _CommunityVisual();

  @override
  Widget build(BuildContext context) {
    return const _AnimatedCommunityVisual();
  }
}

class _PermissionsVisual extends StatelessWidget {
  const _PermissionsVisual();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.18), Colors.transparent],
        ),
      ),
      child: const Icon(
        Icons.verified_user_rounded,
        size: 112,
        color: Colors.white,
      ),
    );
  }
}

class _PermissionConsentPanel extends StatelessWidget {
  final bool locationGranted;
  final bool locationServiceEnabled;
  final bool locationPermanentlyDenied;
  final bool notificationsGranted;
  final bool notificationsPermanentlyDenied;
  final bool loadingLocationPermission;
  final bool loadingNotificationPermission;
  final Future<void> Function() onRequestLocation;
  final Future<void> Function() onRequestNotifications;

  const _PermissionConsentPanel({
    required this.locationGranted,
    required this.locationServiceEnabled,
    required this.locationPermanentlyDenied,
    required this.notificationsGranted,
    required this.notificationsPermanentlyDenied,
    required this.loadingLocationPermission,
    required this.loadingNotificationPermission,
    required this.onRequestLocation,
    required this.onRequestNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        _PermissionTile(
          icon: Icons.my_location_rounded,
          title: l10n.onboardingPermissionsLocationTitle,
          description: l10n.onboardingPermissionsLocationDescription,
          granted: locationGranted,
          warning: !locationServiceEnabled || locationPermanentlyDenied,
          actionLabel: locationPermanentlyDenied
              ? l10n.commonSettings
              : l10n.onboardingPermissionsAllowLocation,
          loading: loadingLocationPermission,
          onTap: onRequestLocation,
        ),
        const SizedBox(height: 12),
        _PermissionTile(
          icon: Icons.notifications_active_outlined,
          title: l10n.onboardingPermissionsNotificationsTitle,
          description: l10n.onboardingPermissionsNotificationsDescription,
          granted: notificationsGranted,
          warning: notificationsPermanentlyDenied,
          actionLabel: notificationsPermanentlyDenied
              ? l10n.commonSettings
              : l10n.onboardingPermissionsAllowNotifications,
          loading: loadingNotificationPermission,
          onTap: onRequestNotifications,
        ),
      ],
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final bool warning;
  final String actionLabel;
  final bool loading;
  final Future<void> Function() onTap;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.warning,
    required this.actionLabel,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = granted
        ? const Color(0xFF71DF89)
        : (warning ? const Color(0xFFFFA23B) : const Color(0xFF43D6FF));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(
                  granted
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  color: accentColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                height: 1.4,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: loading ? null : () => onTap(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: accentColor.withValues(alpha: 0.82)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedCommunityVisual extends StatefulWidget {
  const _AnimatedCommunityVisual();

  @override
  State<_AnimatedCommunityVisual> createState() =>
      _AnimatedCommunityVisualState();
}

class _AnimatedCommunityVisualState extends State<_AnimatedCommunityVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _CommunityPainter(progress: _controller.value),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _CommunityPainter extends CustomPainter {
  final double progress;

  const _CommunityPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final pulse = (math.sin(progress * math.pi * 2) + 1) / 2;

    final hubRadius = size.width * 0.14;
    final hubGlowPaint = Paint()
      ..color = const Color(0xFFC98CFF).withValues(alpha: 0.18 + pulse * 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, hubRadius * 1.35, hubGlowPaint);

    final hubPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF2D2FF).withValues(alpha: 0.95),
          const Color(0xFFA965FF).withValues(alpha: 0.92),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: hubRadius));
    canvas.drawCircle(center, hubRadius, hubPaint);

    final nodes = <_CommunityNode>[
      _CommunityNode(
        offset: Offset(-size.width * 0.26, -size.height * 0.12),
        icon: Icons.chat_bubble_rounded,
        color: const Color(0xFF4AB8FF),
      ),
      _CommunityNode(
        offset: Offset(size.width * 0.24, -size.height * 0.10),
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFFFFD34B),
      ),
      _CommunityNode(
        offset: Offset(-size.width * 0.18, size.height * 0.22),
        icon: Icons.groups_rounded,
        color: const Color(0xFF6FE08C),
      ),
      _CommunityNode(
        offset: Offset(size.width * 0.20, size.height * 0.24),
        icon: Icons.home_rounded,
        color: const Color(0xFFFF6EAA),
      ),
    ];

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final nodeCenter = center + node.offset;
      final delay = (i * 0.18) % 1.0;
      final wave = (math.sin((progress - delay) * math.pi * 2) + 1) / 2;

      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Colors.white.withValues(alpha: 0.22 + wave * 0.24);
      canvas.drawLine(center, nodeCenter, linePaint);

      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = node.color.withValues(alpha: 0.22 + wave * 0.40);
      canvas.drawCircle(nodeCenter, 17 + wave * 5, ringPaint);

      final nodePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            node.color.withValues(alpha: 0.95),
            node.color.withValues(alpha: 0.70),
          ],
        ).createShader(Rect.fromCircle(center: nodeCenter, radius: 16));
      canvas.drawCircle(nodeCenter, 16, nodePaint);

      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: String.fromCharCode(node.icon.codePoint),
          style: TextStyle(
            fontSize: 16,
            fontFamily: node.icon.fontFamily,
            package: node.icon.fontPackage,
            color: Colors.white,
          ),
        ),
      )..layout();
      textPainter.paint(
        canvas,
        nodeCenter - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CommunityPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _CommunityNode {
  final Offset offset;
  final IconData icon;
  final Color color;

  const _CommunityNode({
    required this.offset,
    required this.icon,
    required this.color,
  });
}

class _ShoppingVisual extends StatefulWidget {
  const _ShoppingVisual();

  @override
  State<_ShoppingVisual> createState() => _ShoppingVisualState();
}

class _ShoppingVisualState extends State<_ShoppingVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return CustomPaint(
          painter: _ShoppingPainter(progress: t),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _ShoppingPainter extends CustomPainter {
  final double progress;

  const _ShoppingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final bagRect = Rect.fromCenter(
      center: center.translate(0, 8),
      width: size.width * 0.42,
      height: size.height * 0.38,
    );
    final bagPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF4AB8FF), Color(0xFF2B7BFF)],
      ).createShader(bagRect);
    final handlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.92);

    final handleTop = bagRect.top + 10;
    final handleLeft = bagRect.left + bagRect.width * 0.25;
    final handleRight = bagRect.right - bagRect.width * 0.25;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bagRect, const Radius.circular(26)),
      bagPaint,
    );
    canvas.drawArc(
      Rect.fromLTRB(handleLeft, handleTop - 20, handleRight, handleTop + 30),
      math.pi,
      math.pi,
      false,
      handlePaint,
    );

    final orbPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final y = lerpDouble(size.height * 0.82, size.height * 0.20, progress)!;
    for (var i = 0; i < 3; i++) {
      final x = lerpDouble(bagRect.left + 18, bagRect.right - 18, (i + 1) / 4)!;
      canvas.drawCircle(
        Offset(x, y + i * 8),
        6,
        orbPaint..color = Colors.white.withValues(alpha: 0.85 - i * 0.2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShoppingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _YellowTaxiVisual extends StatefulWidget {
  const _YellowTaxiVisual();

  @override
  State<_YellowTaxiVisual> createState() => _YellowTaxiVisualState();
}

class _YellowTaxiVisualState extends State<_YellowTaxiVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _TaxiPainter(progress: _controller.value),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _TaxiPainter extends CustomPainter {
  final double progress;

  const _TaxiPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final mapPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.20);
    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.24)
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.10,
        size.width * 0.52,
        size.height * 0.28,
      )
      ..quadraticBezierTo(
        size.width * 0.76,
        size.height * 0.50,
        size.width * 0.90,
        size.height * 0.40,
      );
    canvas.drawPath(path, mapPaint);

    final altPath = Path()
      ..moveTo(size.width * 0.14, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.36,
        size.height * 0.52,
        size.width * 0.62,
        size.height * 0.68,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.78,
        size.width * 0.90,
        size.height * 0.64,
      );
    canvas.drawPath(altPath, mapPaint);

    final t = Curves.easeInOut.transform(progress);
    final x = lerpDouble(size.width * 0.18, size.width * 0.82, t)!;
    final y = lerpDouble(size.height * 0.68, size.height * 0.34, t)!;
    final wobble = math.sin(progress * math.pi * 4) * 2.4;
    final taxiCenter = Offset(x, y + wobble);

    final carRect = Rect.fromCenter(
      center: taxiCenter,
      width: size.width * 0.24,
      height: size.height * 0.10,
    );
    final carPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFDF47), Color(0xFFF2A600)],
      ).createShader(carRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(carRect, const Radius.circular(10)),
      carPaint,
    );

    final topRect = Rect.fromCenter(
      center: taxiCenter.translate(0, -carRect.height * 0.38),
      width: carRect.width * 0.55,
      height: carRect.height * 0.58,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(topRect, const Radius.circular(8)),
      Paint()..color = const Color(0xFFFFC928),
    );

    final wheelPaint = Paint()..color = const Color(0xFF1A1E2E);
    canvas.drawCircle(
      taxiCenter.translate(-carRect.width * 0.28, carRect.height * 0.42),
      7,
      wheelPaint,
    );
    canvas.drawCircle(
      taxiCenter.translate(carRect.width * 0.28, carRect.height * 0.42),
      7,
      wheelPaint,
    );

    final trailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD84C).withValues(alpha: 0.38);
    canvas.drawLine(
      taxiCenter.translate(-carRect.width * 0.75, 4),
      taxiCenter.translate(-carRect.width * 1.32, 4),
      trailPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TaxiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _JobsVisual extends StatefulWidget {
  const _JobsVisual();

  @override
  State<_JobsVisual> createState() => _JobsVisualState();
}

class _JobsVisualState extends State<_JobsVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _JobsPainter(progress: _controller.value),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _JobsPainter extends CustomPainter {
  final double progress;

  const _JobsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final lift = lerpDouble(0, 14, Curves.easeInOut.transform(progress))!;

    void drawCard({
      required double widthFactor,
      required double heightFactor,
      required double dx,
      required double dy,
      required Color color,
    }) {
      final rect = Rect.fromCenter(
        center: center.translate(dx, dy - lift),
        width: size.width * widthFactor,
        height: size.height * heightFactor,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(16)),
        Paint()..color = color,
      );
      final linePaint = Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.78);
      canvas.drawLine(
        rect.topLeft.translate(18, 18),
        rect.topLeft.translate(rect.width * 0.55, 18),
        linePaint,
      );
      canvas.drawLine(
        rect.topLeft.translate(18, 32),
        rect.topLeft.translate(rect.width * 0.70, 32),
        linePaint..color = Colors.white.withValues(alpha: 0.55),
      );
    }

    drawCard(
      widthFactor: 0.62,
      heightFactor: 0.30,
      dx: -36,
      dy: 30,
      color: const Color(0xFF2A7FFF).withValues(alpha: 0.74),
    );
    drawCard(
      widthFactor: 0.66,
      heightFactor: 0.32,
      dx: 0,
      dy: 0,
      color: const Color(0xFF56C2FF).withValues(alpha: 0.90),
    );
    drawCard(
      widthFactor: 0.62,
      heightFactor: 0.30,
      dx: 38,
      dy: 36,
      color: const Color(0xFF66DD97).withValues(alpha: 0.78),
    );

    final briefcaseRect = Rect.fromCenter(
      center: center.translate(0, -size.height * 0.22),
      width: size.width * 0.26,
      height: size.height * 0.11,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(briefcaseRect, const Radius.circular(10)),
      Paint()..color = const Color(0xFF6FE08C),
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: briefcaseRect.center.translate(0, -briefcaseRect.height * 0.40),
        width: briefcaseRect.width * 0.46,
        height: briefcaseRect.height * 0.78,
      ),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.84),
    );
  }

  @override
  bool shouldRepaint(covariant _JobsPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
