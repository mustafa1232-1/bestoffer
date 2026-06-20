import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:core_auth/core_auth.dart';
import 'package:core_design_system/core_design_system.dart';
import 'package:core_localization/core_localization.dart';
import 'package:core_maps/core_maps.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_notifications/core_notifications.dart';
import 'package:core_storage/core_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:social_core/social_core.dart';
import 'package:social_ui/social_ui.dart';

final _consentAcceptedProvider = StateProvider<bool>((_) => false);
final _selectedTabProvider = StateProvider<int>((_) => 0);
final _locationRefreshTickProvider = StateProvider<int>((_) => 0);
final _locationStatusProvider = FutureProvider<LocationPermissionStatus>((
  ref,
) async {
  ref.watch(_locationRefreshTickProvider);
  return ref.read(locationPermissionServiceProvider).getStatus();
});

enum _RuntimeFeatureDestination {
  stores,
  taxi,
  orders,
  feed,
  search,
  reels,
  inbox,
  notifications,
}

enum _RuntimeRideTimingMode { now, scheduled }

enum _RuntimeRideStep { timing, pickup, dropoff, summary }

enum _RuntimeChatAttachmentAction { image, video, file, location }

final _runtimeStoreSearchProvider = StateProvider<String>((_) => '');
final _runtimeStoreActivityFilterProvider = StateProvider<String>((_) => 'all');
final _runtimeSocialSearchQueryProvider = StateProvider<String>((_) => '');

final _runtimeMerchantsApiProvider = Provider<_RuntimeMerchantsApi>((ref) {
  return _RuntimeMerchantsApi(ref.watch(runtimeDioProvider));
});

final _runtimeTaxiApiProvider = Provider<_RuntimeTaxiApi>((ref) {
  return _RuntimeTaxiApi(ref.watch(runtimeDioProvider));
});

final _runtimeNotificationsApiProvider = Provider<_RuntimeNotificationsApi>((
  ref,
) {
  return _RuntimeNotificationsApi(ref.watch(runtimeDioProvider));
});

final _runtimeOrdersApiProvider = Provider<_RuntimeOrdersApi>((ref) {
  return _RuntimeOrdersApi(ref.watch(runtimeDioProvider));
});

final _runtimeSocialApiProvider = Provider<SocialApi>((ref) {
  return SocialApi(ref.watch(runtimeDioProvider));
});

final _runtimeCurrentRideProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isUser) return null;
  try {
    return await ref.read(_runtimeTaxiApiProvider).getCurrentRide();
  } catch (_) {
    return null;
  }
});

final _runtimeSocialExploreProvider = FutureProvider<SocialExplorePayload?>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isUser) return null;
  try {
    final response = await ref
        .read(_runtimeSocialApiProvider)
        .listExplore(limit: 12);
    return SocialExplorePayload.fromJson(response);
  } catch (_) {
    return null;
  }
});

final _runtimeSuggestedPeopleProvider =
    FutureProvider<List<SocialUserSearchResult>>((ref) async {
      final auth = ref.watch(authControllerProvider);
      if (auth.user == null || !auth.isUser) {
        return const <SocialUserSearchResult>[];
      }
      try {
        final response = await ref
            .read(_runtimeSocialApiProvider)
            .listSuggestedPeople(limit: 8);
        return List<dynamic>.from(
              response['users'] ??
                  response['items'] ??
                  response['suggestedPeople'] ??
                  const [],
            )
            .map(
              (item) => SocialUserSearchResult.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false);
      } catch (_) {
        return const <SocialUserSearchResult>[];
      }
    });

final _runtimeExploreReelsProvider = FutureProvider<List<SocialReelItem>>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isUser) {
    return const <SocialReelItem>[];
  }
  try {
    final response = await ref
        .read(_runtimeSocialApiProvider)
        .listExploreReels(limit: 12);
    return List<dynamic>.from(
          response['reels'] ??
              response['items'] ??
              response['posts'] ??
              const [],
        )
        .map(
          (item) =>
              SocialReelItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  } catch (_) {
    return const <SocialReelItem>[];
  }
});

final _runtimeSocialFeedProvider = FutureProvider<List<SocialPost>>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isUser) return const <SocialPost>[];
  try {
    final response = await ref
        .read(_runtimeSocialApiProvider)
        .listPosts(limit: 12);
    return List<dynamic>.from(
          response['posts'] ?? response['items'] ?? const [],
        )
        .map(
          (item) => SocialPost.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  } catch (_) {
    return const <SocialPost>[];
  }
});

final _runtimeSocialStoriesProvider = FutureProvider<List<SocialStoryGroup>>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isUser) {
    return const <SocialStoryGroup>[];
  }
  try {
    final response = await ref
        .read(_runtimeSocialApiProvider)
        .listStories(limitUsers: 20, maxPerUser: 5);
    return List<dynamic>.from(
          response['groups'] ?? response['items'] ?? const [],
        )
        .map(
          (item) =>
              SocialStoryGroup.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  } catch (_) {
    return const <SocialStoryGroup>[];
  }
});

final _runtimeSocialThreadsProvider = FutureProvider<List<SocialChatThread>>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isUser) {
    return const <SocialChatThread>[];
  }
  try {
    final response = await ref.read(_runtimeSocialApiProvider).listThreads();
    return List<dynamic>.from(
          response['threads'] ?? response['items'] ?? const [],
        )
        .map(
          (item) =>
              SocialChatThread.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  } catch (_) {
    return const <SocialChatThread>[];
  }
});

final _runtimeMySocialProfileProvider = FutureProvider<SocialUserProfile?>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  final user = auth.user;
  if (user == null || !auth.isUser) return null;
  try {
    final response = await ref
        .read(_runtimeSocialApiProvider)
        .getUserProfile(user.id);
    return SocialUserProfile.fromJson(response);
  } catch (_) {
    return null;
  }
});

final _runtimeTrendingHashtagsProvider = FutureProvider<List<SocialHashtag>>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isUser) return const <SocialHashtag>[];
  try {
    final response = await ref
        .read(_runtimeSocialApiProvider)
        .listTrendingHashtags(limit: 8);
    return List<dynamic>.from(
          response['hashtags'] ?? response['items'] ?? const [],
        )
        .map(
          (item) =>
              SocialHashtag.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  } catch (_) {
    return const <SocialHashtag>[];
  }
});

final _runtimeSocialSearchProvider = FutureProvider<SocialSearchResults?>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isUser) return null;
  final query = ref.watch(_runtimeSocialSearchQueryProvider).trim();
  if (query.isEmpty) return null;
  try {
    final response = await ref
        .read(_runtimeSocialApiProvider)
        .searchSocial(search: query, limit: 12);
    return SocialSearchResults.fromJson(response);
  } catch (_) {
    return null;
  }
});

final _runtimeNotificationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      final auth = ref.watch(authControllerProvider);
      if (auth.user == null || !auth.isUser) {
        return const <Map<String, dynamic>>[];
      }
      try {
        return await ref.read(_runtimeNotificationsApiProvider).list(limit: 20);
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    });

final _runtimeUnreadNotificationsCountProvider = FutureProvider<int>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isUser) return 0;
  try {
    return await ref.read(_runtimeNotificationsApiProvider).unreadCount();
  } catch (_) {
    return 0;
  }
});

final _runtimeOrdersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isUser) return const <Map<String, dynamic>>[];
  try {
    return await ref.read(_runtimeOrdersApiProvider).listMyOrders();
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
});

final _runtimeMerchantListProvider = FutureProvider<List<MerchantModel>>((
  ref,
) async {
  final search = ref.watch(_runtimeStoreSearchProvider);
  final activityFilter = ref.watch(_runtimeStoreActivityFilterProvider);
  try {
    return await ref
        .read(_runtimeMerchantsApiProvider)
        .list(
          search: search,
          activityType: activityFilter == 'all' ? null : activityFilter,
        );
  } catch (_) {
    return _fallbackRuntimeMerchants
        .where((merchant) {
          final matchesFilter =
              activityFilter == 'all' ||
              merchant.activityType == activityFilter ||
              merchant.type == activityFilter;
          final q = search.trim().toLowerCase();
          final matchesSearch =
              q.isEmpty ||
              merchant.name.toLowerCase().contains(q) ||
              (merchant.description ?? '').toLowerCase().contains(q);
          return matchesFilter && matchesSearch;
        })
        .toList(growable: false);
  }
});

String _runtimeText(
  BuildContext context, {
  required String ar,
  required String en,
}) {
  final code = Localizations.maybeLocaleOf(context)?.languageCode.toLowerCase();
  return code == 'ar' ? ar : en;
}

class _RuntimeFareEstimateRange {
  final int lowIqd;
  final int highIqd;
  final int suggestedIqd;

  const _RuntimeFareEstimateRange({
    required this.lowIqd,
    required this.highIqd,
    required this.suggestedIqd,
  });
}

int _roundUpToStep(int value, {int step = 500}) {
  if (value <= 0) return step;
  final remainder = value % step;
  if (remainder == 0) return value;
  return value + (step - remainder);
}

_RuntimeFareEstimateRange _estimateFareFromDistanceKm(double distanceKm) {
  const minimumFareIqd = 1500;
  const farePerKmIqd = 500;
  final rawEstimate = minimumFareIqd + (distanceKm * farePerKmIqd);
  final lowEstimate = _roundUpToStep(
    rawEstimate < minimumFareIqd ? minimumFareIqd : rawEstimate.round(),
  );
  final dynamicBuffer = (lowEstimate * 0.15).round();
  final highEstimate = _roundUpToStep(
    lowEstimate + (dynamicBuffer > 1000 ? dynamicBuffer : 1000),
  );
  return _RuntimeFareEstimateRange(
    lowIqd: lowEstimate,
    highIqd: highEstimate,
    suggestedIqd: lowEstimate,
  );
}

class _RuntimeCoordinate {
  final double latitude;
  final double longitude;

  const _RuntimeCoordinate({required this.latitude, required this.longitude});
}

const _runtimeFallbackPickup = _RuntimeCoordinate(
  latitude: 33.3152,
  longitude: 44.3661,
);

_RuntimeCoordinate _offsetCoordinateFromDistance(
  _RuntimeCoordinate origin,
  double distanceKm,
) {
  final safeDistanceKm = distanceKm <= 0 ? 0.5 : distanceKm;
  final latitudeDelta = safeDistanceKm / 111.0;
  final longitudeFactor = math.max(
    0.25,
    math.cos(origin.latitude * math.pi / 180).abs(),
  );
  final longitudeDelta = safeDistanceKm / (111.0 * longitudeFactor);
  return _RuntimeCoordinate(
    latitude: origin.latitude + (latitudeDelta * 0.58),
    longitude: origin.longitude + (longitudeDelta * 0.82),
  );
}

String _formatIqd(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final reverseIndex = raw.length - i;
    buffer.write(raw[i]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

void runAppUser() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [appSettingsStorageScopeProvider.overrideWithValue('user')],
      child: const MaslakiUserApp(),
    ),
  );
}

class MaslakiUserApp extends ConsumerStatefulWidget {
  final bool requireConsent;
  final bool skipBootstrap;
  final bool useNetworkAuth;

  const MaslakiUserApp({
    super.key,
    this.requireConsent = true,
    this.skipBootstrap = false,
    this.useNetworkAuth = true,
  });

  @override
  ConsumerState<MaslakiUserApp> createState() => _MaslakiUserAppState();
}

class _MaslakiUserAppState extends ConsumerState<MaslakiUserApp>
    with WidgetsBindingObserver {
  static const _consentAcceptedKey = 'user.consent_accepted';

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _bootstrapped = false;
  bool _roleMismatchLogoutQueued = false;
  ProviderSubscription<AuthState>? _authStateSub;
  StreamSubscription<RuntimeNotificationTapPayload>? _localTapSub;
  StreamSubscription<RuntimeNotificationTapPayload>? _pushTapSub;
  RuntimeNotificationTapPayload? _pendingNotificationTap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authStateSub = ref.listenManual<AuthState>(authControllerProvider, (
      previous,
      next,
    ) {
      unawaited(_handleAuthStateChanged(previous, next));
    });
    if (widget.skipBootstrap) {
      _bootstrapped = true;
      return;
    }
    Future.microtask(() async {
      final store = ref.read(appScopedPreferencesStoreProvider);
      final consentAccepted =
          await store.readBool(_consentAcceptedKey) ?? false;
      ref.read(_consentAcceptedProvider.notifier).state = consentAccepted;
      final localNotifications = ref.read(runtimeLocalNotificationsProvider);
      await localNotifications.initialize();
      _localTapSub = localNotifications.tapStream.listen(
        _handleRuntimeNotificationTap,
      );
      final pushNotifications = ref.read(runtimePushNotificationsProvider);
      await pushNotifications.initialize();
      _pushTapSub = pushNotifications.tapStream.listen(
        _handleRuntimeNotificationTap,
      );
      if (consentAccepted) {
        await pushNotifications.requestPermissionIfNeeded();
      }
      await ref.read(authControllerProvider.notifier).bootstrap();
      final auth = ref.read(authControllerProvider);
      if (auth.isAuthed && auth.isUser) {
        await pushNotifications.syncToken();
      }
      if (!mounted) return;
      setState(() {
        _bootstrapped = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _flushPendingNotificationTap();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authStateSub?.close();
    _localTapSub?.cancel();
    _pushTapSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final selectedTab = ref.read(_selectedTabProvider);
    switch (selectedTab) {
      case 0:
        ref.read(_locationRefreshTickProvider.notifier).state++;
        ref.invalidate(_runtimeSocialStoriesProvider);
        ref.invalidate(_runtimeSocialFeedProvider);
        break;
      case 1:
        ref.invalidate(_runtimeMerchantListProvider);
        ref.invalidate(_runtimeSocialExploreProvider);
        ref.invalidate(_runtimeSuggestedPeopleProvider);
        ref.invalidate(_runtimeTrendingHashtagsProvider);
        ref.invalidate(_runtimeSocialSearchProvider);
        break;
      case 2:
        ref.invalidate(_runtimeExploreReelsProvider);
        break;
      case 3:
        ref.invalidate(_runtimeSocialThreadsProvider);
        ref.invalidate(_runtimeUnreadNotificationsCountProvider);
        break;
      case 4:
        ref.invalidate(_runtimeMySocialProfileProvider);
        break;
    }
    final auth = ref.read(authControllerProvider);
    if (auth.isAuthed && auth.isUser) {
      unawaited(ref.read(runtimePushNotificationsProvider).syncToken());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushPendingNotificationTap();
    });
  }

  Future<void> _handleAuthStateChanged(
    AuthState? previous,
    AuthState next,
  ) async {
    if (widget.skipBootstrap) return;
    final pushNotifications = ref.read(runtimePushNotificationsProvider);
    if (next.isAuthed && next.isUser) {
      await pushNotifications.syncToken();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _flushPendingNotificationTap();
        });
      }
      return;
    }
    if (previous?.isAuthed == true && (!next.isAuthed || !next.isUser)) {
      await pushNotifications.unregisterCurrentToken();
    }
  }

  void _handleRuntimeNotificationTap(RuntimeNotificationTapPayload payload) {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed || !auth.isUser) {
      _pendingNotificationTap = payload;
      return;
    }
    final navigationContext = _navigatorKey.currentContext;
    if (navigationContext == null) {
      _pendingNotificationTap = payload;
      return;
    }
    _pendingNotificationTap = null;
    unawaited(
      _openRuntimeNotificationDetails(navigationContext, payload.toJson()),
    );
  }

  void _flushPendingNotificationTap() {
    final pending = _pendingNotificationTap;
    if (pending == null) return;
    _handleRuntimeNotificationTap(pending);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final consentAccepted =
        !widget.requireConsent || ref.watch(_consentAcceptedProvider);

    if (auth.isAuthed && !auth.isUser && !_roleMismatchLogoutQueued) {
      _roleMismatchLogoutQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref.read(authControllerProvider.notifier).logout();
        _roleMismatchLogoutQueued = false;
      });
    } else if (!auth.isAuthed || auth.isUser) {
      _roleMismatchLogoutQueued = false;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      onGenerateTitle: (context) => context.l10n.userAppWindowTitle,
      locale: settings.locale,
      supportedLocales: CoreAppLocalizations.supportedLocales,
      localizationsDelegates: CoreAppLocalizations.localizationsDelegates,
      theme: AppTheme.light(preset: settings.themePreset),
      darkTheme: AppTheme.dark(preset: settings.themePreset),
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return AppBackdrop(
          animationsEnabled: settings.animationsEnabled,
          weatherEffectsEnabled: settings.weatherEffectsEnabled,
          child: AppResponsiveShell(child: child),
        );
      },
      home: !_bootstrapped
          ? const _UserSplashScreen()
          : auth.isAuthed && auth.isUser
          ? const _UserRuntimeShell()
          : consentAccepted
          ? (widget.useNetworkAuth
                ? const _UserNetworkLoginScreen()
                : const _RoleLoginScreen(
                    scope: RuntimeAppScope.user,
                    role: AuthRoleScope.user,
                    loginKey: Key('user_login_button'),
                  ))
          : const _UserConsentScreen(),
    );
  }
}

class _UserSplashScreen extends StatelessWidget {
  const _UserSplashScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/branding/maslaki_official_logo.png',
                width: 88,
                height: 88,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.appName,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.userAppWindowTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                minHeight: 5,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserConsentScreen extends ConsumerWidget {
  const _UserConsentScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 20),
                _HeroPanel(
                  title: l10n.userConsentTitle,
                  subtitle: l10n.userConsentSubtitle,
                  icon: Icons.explore_rounded,
                ),
                const SizedBox(height: 20),
                _InfoCard(
                  icon: Icons.my_location_rounded,
                  title: l10n.locationPermissionTitle,
                  subtitle: l10n.locationPermissionDescription,
                ),
                const SizedBox(height: 14),
                _InfoCard(
                  icon: Icons.notifications_active_rounded,
                  title: l10n.notificationsPermissionTitle,
                  subtitle: l10n.notificationsPermissionDescription,
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.14,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.rocket_launch_rounded,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            l10n.startupHighlightsSubtitle,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  key: const Key('user_start_continue_button'),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final service = ref.read(locationPermissionServiceProvider);
                    final status = await service.getStatus();
                    switch (status.state) {
                      case AppLocationPermissionState.denied:
                      case AppLocationPermissionState.grantedApproximate:
                        await service.requestPermission();
                        break;
                      case AppLocationPermissionState.serviceDisabled:
                        await service.openLocationSettings();
                        break;
                      case AppLocationPermissionState.permanentlyDenied:
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.locationDeniedForeverMessage),
                          ),
                        );
                        break;
                      case AppLocationPermissionState.grantedPrecise:
                        break;
                    }
                    ref.read(_locationRefreshTickProvider.notifier).state++;
                    await ref
                        .read(runtimePushNotificationsProvider)
                        .requestPermissionIfNeeded();
                    ref.read(_consentAcceptedProvider.notifier).state = true;
                    await ref
                        .read(appScopedPreferencesStoreProvider)
                        .writeBool(
                          _MaslakiUserAppState._consentAcceptedKey,
                          true,
                        );
                  },
                  child: Text(l10n.continueToLoginLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleLoginScreen extends ConsumerWidget {
  final RuntimeAppScope scope;
  final AuthRoleScope role;
  final Key loginKey;

  const _RoleLoginScreen({
    required this.scope,
    required this.role,
    required this.loginKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.secondary,
                          ],
                        ),
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        color: theme.colorScheme.onPrimary,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.roleLoginTitle(scope),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.signInAsUserHint,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      key: loginKey,
                      onPressed: () async {
                        await ref
                            .read(authControllerProvider.notifier)
                            .login(role);
                      },
                      child: Text(l10n.loginButtonLabel(scope)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserNetworkLoginScreen extends ConsumerStatefulWidget {
  const _UserNetworkLoginScreen();

  @override
  ConsumerState<_UserNetworkLoginScreen> createState() =>
      _UserNetworkLoginScreenState();
}

class _UserNetworkLoginScreenState
    extends ConsumerState<_UserNetworkLoginScreen> {
  late final TextEditingController _phoneController;
  late final TextEditingController _pinController;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _pinController = TextEditingController();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.roleLoginTitle(RuntimeAppScope.user),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.runtimeAuthHint, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    TextField(
                      key: const Key('user_phone_field'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: l10n.runtimePhoneLabel,
                        prefixIcon: const Icon(Icons.phone_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('user_pin_field'),
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.runtimePinLabel,
                        prefixIcon: const Icon(Icons.lock_rounded),
                      ),
                    ),
                    if ((auth.error ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        auth.error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('user_login_button'),
                        onPressed: auth.loading
                            ? null
                            : () async {
                                await ref
                                    .read(authControllerProvider.notifier)
                                    .loginWithPhonePin(
                                      phone: _phoneController.text,
                                      pin: _pinController.text,
                                      expectedRole: AuthRoleScope.user,
                                    );
                              },
                        child: auth.loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(l10n.loginButtonLabel(RuntimeAppScope.user)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserRuntimeShell extends ConsumerWidget {
  const _UserRuntimeShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTab = ref.watch(_selectedTabProvider);
    final l10n = context.l10n;
    final pages = <Widget>[
      const _UserHomeTab(),
      const _UserDiscoverTab(),
      const _RuntimeSharedReelsFeedScreen(),
      const _UserInboxTab(),
      const _UserProfileTab(),
    ];
    final titles = <String>[
      l10n.homeLabel,
      l10n.exploreLabel,
      l10n.reelsHubTitle,
      _runtimeText(context, ar: 'الرسائل', en: 'Inbox'),
      l10n.profileLabel,
    ];

    return Scaffold(
      drawer: _UserAppDrawer(
        selectedTab: selectedTab,
        onSelectTab: (value) {
          ref.read(_selectedTabProvider.notifier).state = value;
        },
      ),
      appBar: AppBar(
        title: Text(titles[selectedTab]),
        actions: [
          IconButton(
            key: const Key('user_logout_button'),
            tooltip: l10n.commonLogout,
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey(selectedTab),
            child: pages[selectedTab],
          ),
        ),
      ),
      floatingActionButton: selectedTab == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                _openRuntimeFeaturePage(
                  context,
                  _RuntimeFeatureDestination.taxi,
                );
              },
              icon: const Icon(Icons.local_taxi_rounded),
              label: Text(l10n.requestTaxiTitle),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (value) {
          ref.read(_selectedTabProvider.notifier).state = value;
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_rounded),
            label: l10n.homeLabel,
          ),
          NavigationDestination(
            icon: const Icon(Icons.explore_rounded),
            label: l10n.exploreLabel,
          ),
          NavigationDestination(
            icon: const Icon(Icons.ondemand_video_rounded),
            label: l10n.reelsHubTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: _runtimeText(context, ar: 'الرسائل', en: 'Inbox'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_rounded),
            label: l10n.profileLabel,
          ),
        ],
      ),
    );
  }
}

class _UserHomeTab extends ConsumerWidget {
  const _UserHomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroPanel(
          title: l10n.homeGreeting,
          subtitle: l10n.homeSummary,
          icon: Icons.waving_hand_rounded,
        ),
        const SizedBox(height: 16),
        const _RuntimeStoriesSection(),
        const SizedBox(height: 16),
        _SectionTitle(
          title: _runtimeText(context, ar: 'منشورات لك', en: 'For you'),
        ),
        const SizedBox(height: 12),
        const _RuntimeFeedPreviewSection(),
        const SizedBox(height: 16),
        _LocationStatusCard(
          locationStatus: ref.watch(_locationStatusProvider),
          onRefresh: () {
            ref.read(_locationRefreshTickProvider.notifier).state++;
          },
        ),
        const SizedBox(height: 16),
        _SectionTitle(title: l10n.quickActionsTitle),
        const SizedBox(height: 12),
        const _QuickActionsGrid(),
        const SizedBox(height: 16),
        const _UserTabShortcuts(),
        const SizedBox(height: 16),
        _SectionTitle(title: l10n.startupHighlightsTitle),
        const SizedBox(height: 12),
        _InfoCard(
          icon: Icons.bolt_rounded,
          title: l10n.startupHighlightsTitle,
          subtitle: l10n.startupHighlightsSubtitle,
        ),
      ],
    );
  }
}

class _UserDiscoverTab extends StatelessWidget {
  const _UserDiscoverTab();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroPanel(
          title: l10n.exploreLabel,
          subtitle: l10n.homeSummary,
          icon: Icons.explore_rounded,
        ),
        const SizedBox(height: 16),
        _SectionTitle(title: l10n.storesFeaturedSectionTitle),
        const SizedBox(height: 12),
        const _RuntimeStoreHighlightsSection(limit: 2),
        const SizedBox(height: 16),
        const _RuntimeSocialPulseSection(),
        const SizedBox(height: 16),
        _InfoCard(
          icon: Icons.storefront_rounded,
          title: l10n.discoverStoresTitle,
          subtitle: l10n.discoverStoresSubtitle,
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () => _openRuntimeFeaturePage(
            context,
            _RuntimeFeatureDestination.stores,
          ),
          icon: const Icon(Icons.storefront_rounded),
          label: Text(l10n.runtimeOpenLabel),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          icon: Icons.dynamic_feed_rounded,
          title: _runtimeText(
            context,
            ar: 'الفيد الاجتماعي',
            en: 'Social feed',
          ),
          subtitle: _runtimeText(
            context,
            ar: 'منشورات وصور وفيديو من نفس نواة السوشل المشتركة.',
            en: 'Posts, photos, and video from the same shared social core.',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () =>
              _openRuntimeFeaturePage(context, _RuntimeFeatureDestination.feed),
          icon: const Icon(Icons.dynamic_feed_rounded),
          label: Text(l10n.runtimeOpenLabel),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          icon: Icons.search_rounded,
          title: _runtimeText(
            context,
            ar: 'البحث الاجتماعي',
            en: 'Social search',
          ),
          subtitle: _runtimeText(
            context,
            ar: 'ابحث عن الحسابات والوسوم والمحتوى من نفس محرك السوشل.',
            en: 'Search accounts, hashtags, and content from the same social engine.',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () => _openRuntimeFeaturePage(
            context,
            _RuntimeFeatureDestination.search,
          ),
          icon: const Icon(Icons.search_rounded),
          label: Text(l10n.runtimeOpenLabel),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          icon: Icons.local_taxi_rounded,
          title: l10n.requestTaxiTitle,
          subtitle: l10n.requestTaxiSubtitle,
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () =>
              _openRuntimeFeaturePage(context, _RuntimeFeatureDestination.taxi),
          icon: const Icon(Icons.local_taxi_rounded),
          label: Text(l10n.runtimeOpenLabel),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          icon: Icons.ondemand_video_rounded,
          title: l10n.watchReelsTitle,
          subtitle: l10n.watchReelsSubtitle,
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () => _openRuntimeFeaturePage(
            context,
            _RuntimeFeatureDestination.reels,
          ),
          icon: const Icon(Icons.ondemand_video_rounded),
          label: Text(l10n.runtimeOpenLabel),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          icon: Icons.location_on_outlined,
          title: l10n.locationCardTitle,
          subtitle: l10n.locationPermissionDescription,
        ),
      ],
    );
  }
}

class _RuntimeStoreHighlightsSection extends ConsumerWidget {
  final int limit;

  const _RuntimeStoreHighlightsSection({required this.limit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final merchants = ref.watch(_runtimeMerchantListProvider);
    return merchants.when(
      data: (items) {
        if (items.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.storesEmptyTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(l10n.storesEmptySubtitle),
                ],
              ),
            ),
          );
        }
        final visibleItems = items.take(limit).toList(growable: false);
        return Column(
          children: [
            for (var i = 0; i < visibleItems.length; i++) ...[
              _StorePreviewCard(merchant: visibleItems[i]),
              if (i != visibleItems.length - 1) const SizedBox(height: 12),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                onPressed: () => _openRuntimeFeaturePage(
                  context,
                  _RuntimeFeatureDestination.stores,
                ),
                icon: const Icon(Icons.storefront_rounded),
                label: Text(l10n.runtimeOpenLabel),
              ),
            ),
          ],
        );
      },
      error: (_, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.storesEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(l10n.storesEmptySubtitle),
            ],
          ),
        ),
      ),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _RuntimeSocialPulseSection extends ConsumerWidget {
  const _RuntimeSocialPulseSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final explore = ref.watch(_runtimeSocialExploreProvider);
    final suggested = ref.watch(_runtimeSuggestedPeopleProvider);
    final highlights = explore.maybeWhen(
      data: (payload) => payload == null
          ? const <SocialPost>[]
          : [
              ...payload.forYou,
              ...payload.popularPosts,
              ...payload.trendingBasmaya,
            ],
      orElse: () => const <SocialPost>[],
    );
    final visibleHighlights = highlights.take(2).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: _runtimeText(context, ar: 'نبض مسلكي', en: 'Maslaki pulse'),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _runtimeText(
                          context,
                          ar: 'محتوى اجتماعي مشترك من نفس نواة السوشل',
                          en: 'Shared social content from the same social core',
                        ),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _runtimeText(
                          context,
                          ar: 'الاقتراحات والريلز والمنشورات هنا أصبحت تُحمَّل من نفس الـ API والموديلات المستخدمة في السطح الرئيسي.',
                          en: 'Suggestions, reels, and post previews now come from the same API and models used by the main social surface.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        suggested.when(
          data: (items) {
            if (items.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    _runtimeText(
                      context,
                      ar: 'لا توجد حسابات مقترحة الآن.',
                      en: 'No suggested people right now.',
                    ),
                  ),
                ),
              );
            }
            final visibleItems = items.take(6).toList(growable: false);
            return SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, index) =>
                    SocialSuggestedPersonTile(item: visibleItems[index]),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemCount: visibleItems.length,
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                _runtimeText(
                  context,
                  ar: 'تعذر تحميل الحسابات المقترحة الآن.',
                  en: 'Unable to load suggested people right now.',
                ),
              ),
            ),
          ),
        ),
        if (visibleHighlights.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (var i = 0; i < visibleHighlights.length; i++) ...[
            SocialMediaCard(post: visibleHighlights[i]),
            if (i != visibleHighlights.length - 1) const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

// ignore: unused_element
class _RuntimeSuggestedPersonTile extends StatelessWidget {
  final SocialUserSearchResult item;

  const _RuntimeSuggestedPersonTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = item.user;
    return Container(
      width: 188,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: (user.imageUrl ?? '').trim().isNotEmpty
                ? NetworkImage(user.imageUrl!)
                : null,
            child: (user.imageUrl ?? '').trim().isEmpty
                ? Text(
                    user.fullName.trim().isEmpty
                        ? '?'
                        : user.fullName.trim()[0],
                    style: theme.textTheme.titleMedium,
                  )
                : null,
          ),
          const SizedBox(height: 10),
          Text(
            user.fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            user.username == null || user.username!.trim().isEmpty
                ? _runtimeText(
                    context,
                    ar: 'عضو في المجتمع',
                    en: 'Community member',
                  )
                : '@${user.username}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          Row(
            children: [
              if (user.isResidentVerified)
                Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              if (user.isPremiumCreator) ...[
                if (user.isResidentVerified) const SizedBox(width: 6),
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: theme.colorScheme.secondary,
                ),
              ],
              const Spacer(),
              Text(
                _runtimeText(context, ar: 'مقترح', en: 'Suggested'),
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _RuntimeSuggestedPersonRow extends StatelessWidget {
  final SocialUserSearchResult item;

  const _RuntimeSuggestedPersonRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = item.user;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: (user.imageUrl ?? '').trim().isNotEmpty
              ? NetworkImage(user.imageUrl!)
              : null,
          child: (user.imageUrl ?? '').trim().isEmpty
              ? Text(
                  user.fullName.trim().isEmpty ? '?' : user.fullName.trim()[0],
                  style: theme.textTheme.titleMedium,
                )
              : null,
        ),
        title: Text(
          user.fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          user.username == null || user.username!.trim().isEmpty
              ? _runtimeText(
                  context,
                  ar: 'عضو في المجتمع',
                  en: 'Community member',
                )
              : '@${user.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user.isResidentVerified)
              Icon(
                Icons.verified_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            if (user.isPremiumCreator) ...[
              if (user.isResidentVerified) const SizedBox(width: 6),
              Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _RuntimeSocialMediaCard extends StatelessWidget {
  final SocialPost post;

  const _RuntimeSocialMediaCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualUrl = resolveSocialPostPosterUrl(post);
    final mediaClass = normalizeSocialPostMediaClass(post);
    final isVideo = mediaClass == 'video' || mediaClass == 'reel';
    final chipLabel = switch (mediaClass) {
      'reel' => _runtimeText(context, ar: 'ريل', en: 'Reel'),
      'video' => _runtimeText(context, ar: 'فيديو', en: 'Video'),
      'image' => _runtimeText(context, ar: 'صورة', en: 'Image'),
      'merchant_review' => _runtimeText(
        context,
        ar: 'مراجعة متجر',
        en: 'Store review',
      ),
      _ => _runtimeText(context, ar: 'منشور', en: 'Post'),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if ((visualUrl ?? '').trim().isNotEmpty)
                  Image.network(
                    visualUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _RuntimeMediaFallback(),
                  )
                else
                  const _RuntimeMediaFallback(),
                if (isVideo)
                  const Align(
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                PositionedDirectional(
                  top: 12,
                  start: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        chipLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.author.fullName,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (post.caption.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    post.caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusChip(
                      icon: Icons.favorite_border_rounded,
                      label: '${post.likesCount}',
                    ),
                    _StatusChip(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: '${post.commentsCount}',
                    ),
                    if ((post.merchantName ?? '').trim().isNotEmpty)
                      _StatusChip(
                        icon: Icons.storefront_rounded,
                        label: post.merchantName!,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeMediaFallback extends StatelessWidget {
  const _RuntimeMediaFallback();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.8),
            theme.colorScheme.secondary.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.auto_awesome_rounded, size: 44, color: Colors.white),
      ),
    );
  }
}

class _RuntimeStoriesSection extends ConsumerWidget {
  const _RuntimeStoriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(_runtimeSocialStoriesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: _runtimeText(context, ar: 'الستوري', en: 'Stories'),
        ),
        const SizedBox(height: 12),
        stories.when(
          data: (items) {
            if (items.isEmpty) {
              return _InfoCard(
                icon: Icons.auto_stories_outlined,
                title: _runtimeText(
                  context,
                  ar: 'لا توجد ستوري الآن',
                  en: 'No stories right now',
                ),
                subtitle: _runtimeText(
                  context,
                  ar: 'ستظهر تحديثات الأصدقاء والمحيط هنا عندما تصبح متاحة.',
                  en: 'Friend and local updates will appear here when available.',
                ),
              );
            }
            final visibleItems = items.take(10).toList(growable: false);
            return SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: visibleItems.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, index) =>
                    SocialStoryGroupTile(group: visibleItems[index]),
              ),
            );
          },
          loading: () => const SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => _InfoCard(
            icon: Icons.error_outline_rounded,
            title: _runtimeText(
              context,
              ar: 'تعذر تحميل الستوري',
              en: 'Unable to load stories',
            ),
            subtitle: _runtimeText(
              context,
              ar: 'حدثت مشكلة أثناء تحميل الستوري المشتركة.',
              en: 'A problem occurred while loading shared stories.',
            ),
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _RuntimeStoryGroupTile extends StatelessWidget {
  final SocialStoryGroup group;

  const _RuntimeStoryGroupTile({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: group.hasUnviewed
                    ? [theme.colorScheme.primary, theme.colorScheme.secondary]
                    : [
                        theme.colorScheme.outlineVariant,
                        theme.colorScheme.outlineVariant,
                      ],
              ),
            ),
            child: CircleAvatar(
              backgroundImage: (group.author.imageUrl ?? '').trim().isNotEmpty
                  ? NetworkImage(group.author.imageUrl!)
                  : null,
              child: (group.author.imageUrl ?? '').trim().isEmpty
                  ? Text(
                      group.author.fullName.trim().isEmpty
                          ? '?'
                          : group.author.fullName.trim()[0],
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            group.author.fullName.trim().isEmpty
                ? group.author.username ?? '@user'
                : group.author.fullName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeFeedPreviewSection extends ConsumerWidget {
  const _RuntimeFeedPreviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(_runtimeSocialFeedProvider);
    return posts.when(
      data: (items) {
        if (items.isEmpty) {
          return _InfoCard(
            icon: Icons.dynamic_feed_outlined,
            title: _runtimeText(
              context,
              ar: 'لا توجد منشورات الآن',
              en: 'No posts right now',
            ),
            subtitle: _runtimeText(
              context,
              ar: 'سيظهر الفيد الاجتماعي هنا من نفس النواة المشتركة.',
              en: 'The shared social feed will appear here from the same core.',
            ),
          );
        }
        final visibleItems = items.take(3).toList(growable: false);
        return Column(
          children: [
            for (var i = 0; i < visibleItems.length; i++) ...[
              SocialMediaCard(post: visibleItems[i]),
              if (i != visibleItems.length - 1) const SizedBox(height: 12),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                onPressed: () => _openRuntimeFeaturePage(
                  context,
                  _RuntimeFeatureDestination.feed,
                ),
                icon: const Icon(Icons.dynamic_feed_rounded),
                label: Text(
                  _runtimeText(context, ar: 'فتح الفيد', en: 'Open feed'),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _InfoCard(
        icon: Icons.error_outline_rounded,
        title: _runtimeText(
          context,
          ar: 'تعذر تحميل الفيد',
          en: 'Unable to load feed',
        ),
        subtitle: _runtimeText(
          context,
          ar: 'حدثت مشكلة أثناء تحميل المعاينة الاجتماعية.',
          en: 'A problem occurred while loading the social preview.',
        ),
      ),
    );
  }
}

class _UserInboxTab extends ConsumerStatefulWidget {
  const _UserInboxTab();

  @override
  ConsumerState<_UserInboxTab> createState() => _UserInboxTabState();
}

class _UserInboxTabState extends ConsumerState<_UserInboxTab>
    with WidgetsBindingObserver {
  Timer? _pollTimer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || !_foreground) return;
      ref.invalidate(_runtimeSocialThreadsProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (_foreground) {
      ref.invalidate(_runtimeSocialThreadsProvider);
    }
  }

  Future<void> _openThread(SocialChatThread thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _RuntimeThreadScreen(thread: thread),
      ),
    );
    if (!mounted) return;
    ref.invalidate(_runtimeSocialThreadsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final threads = ref.watch(_runtimeSocialThreadsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_runtimeSocialThreadsProvider);
        await ref.read(_runtimeSocialThreadsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: _runtimeText(context, ar: 'الرسائل', en: 'Inbox'),
            subtitle: _runtimeText(
              context,
              ar: 'محادثاتك المباشرة والجماعية من نفس نواة السوشل المشتركة.',
              en: 'Your direct and group chats from the same shared social core.',
            ),
            icon: Icons.chat_bubble_outline_rounded,
          ),
          const SizedBox(height: 16),
          threads.when(
            data: (items) {
              if (items.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(Icons.forum_outlined, size: 52),
                        const SizedBox(height: 12),
                        Text(
                          _runtimeText(
                            context,
                            ar: 'لا توجد محادثات الآن.',
                            en: 'No chats available right now.',
                          ),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _runtimeText(
                            context,
                            ar: 'ابدأ محادثة من أي حساب أو منشور داخل السطح الاجتماعي.',
                            en: 'Start a chat from any profile or post inside the social surface.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _RuntimeThreadTile(
                      thread: items[i],
                      onTap: () => _openThread(items[i]),
                    ),
                    if (i != items.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  _runtimeText(
                    context,
                    ar: 'تعذر تحميل المحادثات.',
                    en: 'Unable to load chats.',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeThreadTile extends StatelessWidget {
  final SocialChatThread thread;
  final VoidCallback onTap;

  const _RuntimeThreadTile({required this.thread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = thread.lastMessage?.previewText.trim();
    final presenceColor = thread.presence.isOnline
        ? theme.colorScheme.tertiary
        : theme.colorScheme.outline;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.42,
          ),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage:
                      (thread.displayImageUrl ?? '').trim().isNotEmpty
                      ? NetworkImage(thread.displayImageUrl!)
                      : null,
                  child: (thread.displayImageUrl ?? '').trim().isEmpty
                      ? Text(
                          thread.displayTitle.isEmpty
                              ? '?'
                              : thread.displayTitle[0],
                        )
                      : null,
                ),
                PositionedDirectional(
                  end: -2,
                  bottom: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: presenceColor,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (thread.state.pinnedAt != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 8),
                          child: Icon(
                            Icons.push_pin_rounded,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview == null || preview.isEmpty
                        ? _runtimeText(
                            context,
                            ar: 'ابدأ المحادثة الآن',
                            en: 'Start the chat now',
                          )
                        : preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (thread.lastMessageAt != null)
                  Text(
                    _formatRuntimeDateTime(thread.lastMessageAt!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 8),
                if (thread.state.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: theme.colorScheme.primary,
                    ),
                    child: Text(
                      '${thread.state.unreadCount}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RuntimeThreadScreen extends ConsumerStatefulWidget {
  final SocialChatThread thread;

  const _RuntimeThreadScreen({required this.thread});

  @override
  ConsumerState<_RuntimeThreadScreen> createState() =>
      _RuntimeThreadScreenState();
}

class _RuntimeThreadScreenState extends ConsumerState<_RuntimeThreadScreen>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final SocialVoiceComposerController _voiceComposer;
  Timer? _pollTimer;
  Timer? _typingTimer;
  List<SocialChatMessage> _messages = const <SocialChatMessage>[];
  List<SocialScheduledChatMessage> _scheduledMessages =
      const <SocialScheduledChatMessage>[];
  final Set<int> _translationBusyMessageIds = <int>{};
  final Map<int, SocialChatMessageTranslation> _messageTranslations =
      <int, SocialChatMessageTranslation>{};
  LocalMediaFile? _attachmentDraft;
  SocialSharedEntity? _sharedEntityDraft;
  bool _loading = true;
  bool _sending = false;
  bool _foreground = true;
  bool _typingActive = false;
  double _voiceStartDy = 0;
  late String _threadThemeKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voiceComposer = SocialVoiceComposerController();
    _threadThemeKey = widget.thread.state.themeKey;
    _messageController.addListener(_handleComposerChanged);
    Future.microtask(() async {
      await _loadMessages();
      await _loadScheduledMessages(silent: true);
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_foreground) return;
      unawaited(_loadMessages(silent: true));
      unawaited(_loadScheduledMessages(silent: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _typingTimer?.cancel();
    _messageController.removeListener(_handleComposerChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _voiceComposer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!_foreground) {
      unawaited(_voiceComposer.handleAppPause());
      unawaited(_setTyping(false));
      return;
    }
    unawaited(_loadMessages(silent: true));
    unawaited(_loadScheduledMessages(silent: true));
  }

  void _handleComposerChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (mounted) setState(() {});
    if (hasText) {
      unawaited(_setTyping(true));
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        unawaited(_setTyping(false));
      });
    } else {
      unawaited(_setTyping(false));
    }
  }

  Future<void> _setTyping(bool typing) async {
    if (_typingActive == typing) return;
    _typingActive = typing;
    try {
      await ref
          .read(_runtimeSocialApiProvider)
          .emitThreadTyping(threadId: widget.thread.id, typing: typing);
    } catch (_) {
      // Best effort typing state.
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    try {
      final response = await ref
          .read(_runtimeSocialApiProvider)
          .listThreadMessages(widget.thread.id, limit: 50);
      final messages =
          List<dynamic>.from(
                response['messages'] ?? response['items'] ?? const [],
              )
              .map(
                (item) => SocialChatMessage.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(growable: false)
            ..sort(
              (a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(
                    b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                  ),
            );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        final threadRaw = response['thread'];
        if (threadRaw is Map) {
          _threadThemeKey = SocialChatThread.fromJson(
            Map<String, dynamic>.from(threadRaw),
          ).state.themeKey;
        }
        _loading = false;
      });
      unawaited(
        ref
            .read(_runtimeSocialApiProvider)
            .markThreadRead(threadId: widget.thread.id),
      );
      ref.invalidate(_runtimeSocialThreadsProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    } catch (_) {
      if (!mounted || silent) return;
      setState(() => _loading = false);
    }
  }

  String get _translationTargetLanguage =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'en'
      ? 'ar'
      : 'en';

  SocialThreadVisualTheme get _threadVisualTheme =>
      resolveSocialThreadTheme(Theme.of(context).colorScheme, _threadThemeKey);

  String _themeLabel(String key) {
    switch (key) {
      case 'sunset':
        return _runtimeText(context, ar: 'غروب', en: 'Sunset');
      case 'ocean':
        return _runtimeText(context, ar: 'محيط', en: 'Ocean');
      case 'forest':
        return _runtimeText(context, ar: 'غابة', en: 'Forest');
      case 'violet':
        return _runtimeText(context, ar: 'بنفسجي', en: 'Violet');
      default:
        return _runtimeText(context, ar: 'افتراضي', en: 'Default');
    }
  }

  Future<void> _toggleMessageTranslation(SocialChatMessage message) async {
    if (message.isDeleted || message.body.trim().isEmpty) return;
    if (_messageTranslations.containsKey(message.id)) {
      setState(() {
        _messageTranslations.remove(message.id);
      });
      return;
    }
    if (_translationBusyMessageIds.contains(message.id)) return;
    setState(() {
      _translationBusyMessageIds.add(message.id);
    });
    try {
      final response = await ref
          .read(_runtimeSocialApiProvider)
          .translateThreadMessage(
            threadId: widget.thread.id,
            messageId: message.id,
            targetLanguage: _translationTargetLanguage,
          );
      final raw = response['translation'];
      if (!mounted || raw is! Map) return;
      setState(() {
        _messageTranslations[message.id] =
            SocialChatMessageTranslation.fromJson(
              Map<String, dynamic>.from(raw),
            );
      });
    } catch (_) {
      if (!mounted) return;
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'تعذر ترجمة الرسالة الآن.',
          en: 'Unable to translate the message right now.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _translationBusyMessageIds.remove(message.id);
        });
      }
    }
  }

  Future<void> _openThemePicker() async {
    final selectedKey = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                _runtimeText(
                  sheetContext,
                  ar: 'ثيم المحادثة',
                  en: 'Chat theme',
                ),
              ),
            ),
            for (final key in socialThreadThemeKeys)
              ListTile(
                leading: Icon(
                  key == _threadThemeKey
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                ),
                title: Text(_themeLabel(key)),
                onTap: () => Navigator.of(sheetContext).pop(key),
              ),
          ],
        ),
      ),
    );
    if (selectedKey == null || selectedKey == _threadThemeKey) return;
    try {
      await ref
          .read(_runtimeSocialApiProvider)
          .setThreadTheme(threadId: widget.thread.id, themeKey: selectedKey);
      if (!mounted) return;
      setState(() {
        _threadThemeKey = selectedKey;
      });
      ref.invalidate(_runtimeSocialThreadsProvider);
    } catch (_) {
      if (!mounted) return;
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'تعذر تحديث ثيم المحادثة الآن.',
          en: 'Unable to update the chat theme right now.',
        ),
      );
    }
  }

  Future<void> _loadScheduledMessages({bool silent = false}) async {
    try {
      final response = await ref
          .read(_runtimeSocialApiProvider)
          .listScheduledThreadMessages(widget.thread.id);
      final items =
          List<dynamic>.from(
                response['items'] ?? response['scheduledMessages'] ?? const [],
              )
              .map(
                (item) => SocialScheduledChatMessage.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(growable: false);
      if (!mounted) return;
      setState(() => _scheduledMessages = items);
    } catch (_) {
      if (!silent) {
        _showRuntimeMessage(
          context,
          _runtimeText(
            context,
            ar: 'تعذر تحميل الرسائل المجدولة الآن.',
            en: 'Unable to load scheduled messages right now.',
          ),
        );
      }
    }
  }

  Future<void> _sendText() async {
    final body = _messageController.text.trim();
    final voiceDraft = _voiceComposer.state.draft;
    final attachmentFile = voiceDraft?.file ?? _attachmentDraft;
    final sharedDraft = _sharedEntityDraft;
    if ((body.isEmpty && attachmentFile == null && sharedDraft == null) ||
        _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(_runtimeSocialApiProvider)
          .sendThreadMessage(
            widget.thread.id,
            body,
            attachmentFile: attachmentFile,
            attachmentDurationMs: voiceDraft?.durationMs,
            sharedEntityType: sharedDraft?.type,
            sharedEntityId: sharedDraft?.id,
            sharedSnapshot: sharedDraft?.snapshot,
          );
      if (!mounted) return;
      _messageController.clear();
      _attachmentDraft = null;
      _sharedEntityDraft = null;
      if (voiceDraft != null) {
        await _voiceComposer.discardDraft();
      }
      await _loadMessages(silent: true);
    } catch (_) {
      if (!mounted) return;
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'تعذر إرسال الرسالة.',
          en: sharedDraft?.type == 'location'
              ? 'Unable to share the location right now.'
              : 'Failed to send the message.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendVoiceDraft(SocialVoiceRecordingDraft draft) async {
    await ref
        .read(_runtimeSocialApiProvider)
        .sendThreadMessage(
          widget.thread.id,
          '',
          attachmentFile: draft.file,
          attachmentDurationMs: draft.durationMs,
        );
    await _loadMessages(silent: true);
  }

  // ignore: unused_element
  Future<void> _shareCurrentLocation() async {
    if (_sending) return;
    final service = ref.read(locationPermissionServiceProvider);
    var status = await service.getStatus();
    if (!status.isGranted || !status.serviceEnabled) {
      status = await service.requestPermission();
    }
    if (!status.serviceEnabled || !status.isGranted) {
      if (!mounted) return;
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'يجب منح صلاحية الموقع لمشاركة موقعك الحالي.',
          en: 'Location permission is required to share your current location.',
        ),
      );
      return;
    }
    final position = await service.getCurrentPosition();
    if (position == null) {
      if (!mounted) return;
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'تعذر قراءة موقعك الحالي الآن.',
          en: 'Unable to read your current location right now.',
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final lat = position.latitude;
      final lng = position.longitude;
      await ref
          .read(_runtimeSocialApiProvider)
          .sendThreadMessage(
            widget.thread.id,
            '',
            sharedEntityType: 'location',
            sharedEntityId: DateTime.now().millisecondsSinceEpoch,
            sharedSnapshot: <String, dynamic>{
              'title': _runtimeText(
                context,
                ar: 'موقعي الحالي',
                en: 'My current location',
              ),
              'address': '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
              'latitude': lat,
              'longitude': lng,
            },
          );
      await _loadMessages(silent: true);
    } catch (_) {
      if (!mounted) return;
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'تعذر مشاركة الموقع الآن.',
          en: 'Unable to share the location right now.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<SocialSharedEntity?> _buildLocationDraftForComposer() async {
    final service = ref.read(locationPermissionServiceProvider);
    var status = await service.getStatus();
    if (!status.isGranted || !status.serviceEnabled) {
      status = await service.requestPermission();
    }
    if (!status.serviceEnabled || !status.isGranted) {
      if (!mounted) return null;
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'يجب منح صلاحية الموقع لمشاركة موقعك الحالي.',
          en: 'Location permission is required to share your current location.',
        ),
      );
      return null;
    }
    final position = await service.getCurrentPosition();
    if (position == null) {
      if (!mounted) return null;
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'تعذر قراءة موقعك الحالي الآن.',
          en: 'Unable to read your current location right now.',
        ),
      );
      return null;
    }
    final lat = position.latitude;
    final lng = position.longitude;
    return SocialSharedEntity(
      type: 'location',
      id: DateTime.now().millisecondsSinceEpoch,
      snapshot: <String, dynamic>{
        'title': _runtimeText(
          context,
          ar: 'موقعي الحالي',
          en: 'My current location',
        ),
        'address': '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
        'latitude': lat,
        'longitude': lng,
      },
    );
  }

  Future<LocalMediaFile?> _pickRuntimeAttachment(
    _RuntimeChatAttachmentAction action,
  ) async {
    final fileType = switch (action) {
      _RuntimeChatAttachmentAction.image => FileType.image,
      _RuntimeChatAttachmentAction.video => FileType.video,
      _RuntimeChatAttachmentAction.file => FileType.custom,
      _RuntimeChatAttachmentAction.location => FileType.any,
    };
    final allowedExtensions = switch (action) {
      _RuntimeChatAttachmentAction.file => const [
        'pdf',
        'txt',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'zip',
        'rar',
      ],
      _ => const <String>[],
    };
    final result = await FilePicker.platform.pickFiles(
      type: fileType,
      allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    if ((picked.path ?? '').isEmpty &&
        (picked.bytes == null || picked.bytes!.isEmpty)) {
      return null;
    }
    final extension = (picked.extension ?? '').trim().toLowerCase();
    String mime = picked.extension == null ? 'application/octet-stream' : '';
    if (fileType == FileType.image) {
      mime = 'image/${extension.isEmpty ? 'jpeg' : extension}';
    } else if (fileType == FileType.video) {
      mime = 'video/${extension.isEmpty ? 'mp4' : extension}';
    } else if (extension == 'pdf') {
      mime = 'application/pdf';
    } else if (extension == 'txt') {
      mime = 'text/plain';
    } else if (extension == 'doc') {
      mime = 'application/msword';
    } else if (extension == 'docx') {
      mime =
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    } else if (extension == 'xls') {
      mime = 'application/vnd.ms-excel';
    } else if (extension == 'xlsx') {
      mime =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    } else if (extension == 'zip') {
      mime = 'application/zip';
    } else if (extension == 'rar') {
      mime = 'application/vnd.rar';
    }
    return LocalMediaFile(
      name: picked.name,
      path: picked.path,
      bytes: picked.bytes,
      mimeType: mime,
    );
  }

  Future<void> _applyRuntimeAttachmentAction(
    _RuntimeChatAttachmentAction action,
  ) async {
    if (_sending) return;
    if (action == _RuntimeChatAttachmentAction.location) {
      final draft = await _buildLocationDraftForComposer();
      if (!mounted || draft == null) return;
      setState(() {
        _sharedEntityDraft = draft;
        _attachmentDraft = null;
      });
      return;
    }
    final file = await _pickRuntimeAttachment(action);
    if (!mounted || file == null) return;
    setState(() {
      _attachmentDraft = file;
      _sharedEntityDraft = null;
    });
  }

  Future<void> _openRuntimeAttachmentMenu() async {
    if (_sending) return;
    final action = await showModalBottomSheet<_RuntimeChatAttachmentAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(
                _runtimeText(sheetContext, ar: 'موقع', en: 'Location'),
              ),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_RuntimeChatAttachmentAction.location),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(_runtimeText(sheetContext, ar: 'ملف', en: 'File')),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_RuntimeChatAttachmentAction.file),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(_runtimeText(sheetContext, ar: 'صورة', en: 'Image')),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_RuntimeChatAttachmentAction.image),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(_runtimeText(sheetContext, ar: 'فيديو', en: 'Video')),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_RuntimeChatAttachmentAction.video),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    await _applyRuntimeAttachmentAction(action);
  }

  Future<void> _openRuntimeStickerGifMenu() async {
    if (_sending) return;
    final selectedText = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Text(
                    _runtimeText(
                      sheetContext,
                      ar: 'الملصقات و GIF',
                      en: 'Stickers & GIF',
                    ),
                    style: Theme.of(sheetContext).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: ['😀', '😍', '🔥', '👏', '👍', '💯']
                  .map(
                    (emoji) => InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.of(sheetContext).pop(emoji),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _showRuntimeMessage(
                  context,
                  _runtimeText(
                    context,
                    ar: 'ميزة GIF تحتاج إعداد Tenor.',
                    en: 'GIF requires Tenor configuration.',
                  ),
                );
              },
              icon: const Icon(Icons.gif_box_outlined),
              label: Text(
                _runtimeText(sheetContext, ar: 'فتح GIF', en: 'Open GIF'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || (selectedText ?? '').trim().isEmpty) return;
    final current = _messageController.text;
    final prefix = current.trim().isEmpty ? '' : '$current ';
    _messageController.value = TextEditingValue(
      text: '$prefix${selectedText!.trim()}',
      selection: TextSelection.collapsed(
        offset: '$prefix${selectedText.trim()}'.length,
      ),
    );
  }

  Future<void> _scheduleCurrentDraft() async {
    if (_sending) return;
    final body = _messageController.text.trim();
    final voiceDraft = _voiceComposer.state.draft;
    final attachmentFile = voiceDraft?.file ?? _attachmentDraft;
    if (body.isEmpty && attachmentFile == null) {
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'أضف نصًا أو مرفقًا قبل جدولة الرسالة.',
          en: 'Add text or an attachment before scheduling the message.',
        ),
      );
      return;
    }
    final scheduledFor = await pickSocialScheduledDateTime(context);
    if (!mounted || scheduledFor == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(_runtimeSocialApiProvider)
          .scheduleThreadMessage(
            widget.thread.id,
            body,
            scheduledFor: scheduledFor,
            attachmentFile: attachmentFile,
            attachmentDurationMs: voiceDraft?.durationMs,
          );
      _messageController.clear();
      _attachmentDraft = null;
      if (voiceDraft != null) {
        await _voiceComposer.discardDraft();
      }
      await _loadScheduledMessages(silent: true);
      if (!mounted) return;
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'تمت جدولة الرسالة بنجاح.',
          en: 'The message was scheduled successfully.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'تعذر جدولة الرسالة الآن.',
          en: 'Unable to schedule the message right now.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _cancelScheduledMessage(int scheduledMessageId) async {
    try {
      await ref
          .read(_runtimeSocialApiProvider)
          .cancelScheduledThreadMessage(
            threadId: widget.thread.id,
            scheduledMessageId: scheduledMessageId,
          );
      if (!mounted) return;
      setState(() {
        _scheduledMessages = _scheduledMessages
            .where((item) => item.id != scheduledMessageId)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      _showRuntimeMessage(
        context,
        _runtimeText(
          context,
          ar: 'تعذر إلغاء الرسالة المجدولة.',
          en: 'Unable to cancel the scheduled message.',
        ),
      );
    }
  }

  Future<void> _handleVoiceResult(
    SocialVoiceComposerResult result, {
    required String fallbackMessage,
  }) async {
    if (!mounted) return;
    switch (result.type) {
      case SocialVoiceComposerResultType.permissionDenied:
        _showRuntimeMessage(
          context,
          _runtimeText(
            context,
            ar: 'صلاحية المايكروفون مطلوبة لتسجيل رسالة صوتية.',
            en: 'Microphone permission is required to record a voice message.',
          ),
        );
        return;
      case SocialVoiceComposerResultType.tooShort:
      case SocialVoiceComposerResultType.failed:
        _showRuntimeMessage(context, fallbackMessage);
        return;
      default:
        return;
    }
  }

  Future<void> _startVoiceHold() async {
    HapticFeedback.mediumImpact();
    final result = await _voiceComposer.startHolding(
      draftKey: 'runtime_thread_${widget.thread.id}',
    );
    await _handleVoiceResult(
      result,
      fallbackMessage: _runtimeText(
        context,
        ar: 'تعذر تسجيل الرسالة الصوتية الآن.',
        en: 'Unable to record the voice message right now.',
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _releaseVoiceHold() async {
    final result = await _voiceComposer.releaseHoldToPreview();
    await _handleVoiceResult(
      result,
      fallbackMessage: _runtimeText(
        context,
        ar: 'تعذر تسجيل الرسالة الصوتية الآن.',
        en: 'Unable to record the voice message right now.',
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _stopLockedVoice() async {
    final result = await _voiceComposer.stopLockedRecordingToPreview();
    await _handleVoiceResult(
      result,
      fallbackMessage: _runtimeText(
        context,
        ar: 'تعذر تسجيل الرسالة الصوتية الآن.',
        en: 'Unable to record the voice message right now.',
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildMessageBubble(SocialChatMessage message) {
    final visualTheme = _threadVisualTheme;
    final isMine = message.isMine;
    final translation = _messageTranslations[message.id];
    final bubbleColor = isMine
        ? visualTheme.mineBubble
        : visualTheme.peerBubble;
    final textColor = isMine ? visualTheme.mineText : visualTheme.peerText;
    return Align(
      alignment: isMine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: GestureDetector(
          onLongPress: () => unawaited(_toggleMessageTranslation(message)),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMine && widget.thread.isGroup)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      message.sender.fullName,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (message.body.trim().isNotEmpty)
                  Text(message.body, style: TextStyle(color: textColor)),
                if (translation != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: visualTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: visualTheme.accent.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _runtimeText(
                            context,
                            ar: 'الترجمة',
                            en: 'Translation',
                          ),
                          style: TextStyle(
                            color: visualTheme.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          translation.translatedText,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (message.attachment != null) ...[
                  if (message.body.trim().isNotEmpty || translation != null)
                    const SizedBox(height: 10),
                  _RuntimeThreadAttachmentView(
                    attachment: message.attachment!,
                    textColor: textColor,
                  ),
                ],
                if (message.sharedEntity != null) ...[
                  if (message.body.trim().isNotEmpty ||
                      message.attachment != null ||
                      translation != null)
                    const SizedBox(height: 10),
                  _RuntimeThreadSharedEntityView(entity: message.sharedEntity!),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatRuntimeDateTime(
                        message.createdAt ?? DateTime.now(),
                      ),
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.72),
                        fontSize: 11.5,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 8),
                      Text(
                        message.readByPeer
                            ? _runtimeText(
                                context,
                                ar: 'تمت المشاهدة',
                                en: 'Seen',
                              )
                            : message.deliveredToPeer
                            ? _runtimeText(
                                context,
                                ar: 'تم التسليم',
                                en: 'Delivered',
                              )
                            : '...',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.72),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                if (_translationBusyMessageIds.contains(message.id))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _runtimeText(
                        context,
                        ar: 'جارٍ ترجمة الرسالة...',
                        en: 'Translating message...',
                      ),
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final voiceState = _voiceComposer.state;
    final hasComposerText = _messageController.text.trim().isNotEmpty;
    final showSendAction =
        hasComposerText ||
        _attachmentDraft != null ||
        _sharedEntityDraft != null ||
        voiceState.hasPreview;
    final visualTheme = _threadVisualTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.thread.displayTitle),
        actions: [
          IconButton(
            tooltip: _runtimeText(
              context,
              ar: 'ثيم المحادثة',
              en: 'Chat theme',
            ),
            onPressed: _openThemePicker,
            icon: const Icon(Icons.palette_outlined),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: visualTheme.backgroundGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                    ? Center(
                        child: Text(
                          _runtimeText(
                            context,
                            ar: 'لا توجد رسائل بعد. ابدأ المحادثة الآن.',
                            en: 'No messages yet. Start the conversation now.',
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (_, index) =>
                            _buildMessageBubble(_messages[index]),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (voiceState.isRecording)
                      SocialVoiceRecordingStatusCard(
                        duration: voiceState.duration,
                        locked: voiceState.isLocked,
                        title: _runtimeText(
                          context,
                          ar: 'تسجيل رسالة صوتية',
                          en: 'Record voice message',
                        ),
                        slideToLockLabel: _runtimeText(
                          context,
                          ar: 'اضغط مطولًا ثم اسحب للأعلى للقفل',
                          en: 'Hold to record, then slide up to lock',
                        ),
                        lockedLabel: _runtimeText(
                          context,
                          ar: 'التسجيل مقفل ويمكنك المتابعة بدون ضغط.',
                          en: 'Recording locked. You can continue hands-free.',
                        ),
                        cancelLabel: _runtimeText(
                          context,
                          ar: 'حذف',
                          en: 'Delete',
                        ),
                        stopLabel: _runtimeText(
                          context,
                          ar: 'إيقاف التسجيل',
                          en: 'Stop recording',
                        ),
                        onCancel: () async {
                          await _voiceComposer.cancelRecording();
                          if (mounted) setState(() {});
                        },
                        onStop: voiceState.isLocked
                            ? () => unawaited(_stopLockedVoice())
                            : null,
                      ),
                    if (voiceState.hasPreview && voiceState.draft != null)
                      SocialVoicePreviewCard(
                        draft: voiceState.draft!,
                        sending: voiceState.isSending,
                        title: _runtimeText(
                          context,
                          ar: 'معاينة الرسالة الصوتية',
                          en: 'Voice message preview',
                        ),
                        playLabel: _runtimeText(
                          context,
                          ar: 'تشغيل الرسالة الصوتية',
                          en: 'Play voice message',
                        ),
                        pauseLabel: _runtimeText(
                          context,
                          ar: 'إيقاف الرسالة الصوتية',
                          en: 'Pause voice message',
                        ),
                        deleteLabel: _runtimeText(
                          context,
                          ar: 'حذف',
                          en: 'Delete',
                        ),
                        sendLabel: _runtimeText(
                          context,
                          ar: 'إرسال الرسالة الصوتية',
                          en: 'Send voice message',
                        ),
                        onDelete: () async {
                          await _voiceComposer.discardDraft();
                          if (mounted) setState(() {});
                        },
                        onSend: () async {
                          final result = await _voiceComposer.sendDraft(
                            _sendVoiceDraft,
                          );
                          await _handleVoiceResult(
                            result,
                            fallbackMessage: _runtimeText(
                              context,
                              ar: 'تعذر إرسال الرسالة الصوتية.',
                              en: 'Unable to send the voice message.',
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                      ),
                    if (_scheduledMessages.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _runtimeText(
                                context,
                                ar: 'الرسائل المجدولة',
                                en: 'Scheduled messages',
                              ),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            for (final item in _scheduledMessages)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SocialScheduledMessageCard(
                                  item: item,
                                  title: _runtimeText(
                                    context,
                                    ar: 'رسالة مجدولة',
                                    en: 'Scheduled message',
                                  ),
                                  scheduledLabel: _runtimeText(
                                    context,
                                    ar: 'مجدولة',
                                    en: 'Scheduled',
                                  ),
                                  failedLabel: _runtimeText(
                                    context,
                                    ar: 'فشل الإرسال',
                                    en: 'Failed',
                                  ),
                                  processingLabel: _runtimeText(
                                    context,
                                    ar: 'جارٍ المعالجة',
                                    en: 'Processing',
                                  ),
                                  deleteLabel: _runtimeText(
                                    context,
                                    ar: 'إلغاء',
                                    en: 'Cancel',
                                  ),
                                  onDelete: () => unawaited(
                                    _cancelScheduledMessage(item.id),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (_attachmentDraft != null)
                      SocialAttachmentPreviewCard(
                        file: _attachmentDraft!,
                        onClear: () => setState(() => _attachmentDraft = null),
                      ),
                    if (_sharedEntityDraft != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.82),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_rounded),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _sharedEntityDraft!.address ??
                                      _sharedEntityDraft!.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    setState(() => _sharedEntityDraft = null),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: _runtimeText(
                                context,
                                ar: 'اكتب رسالتك...',
                                en: 'Write your message...',
                              ),
                              prefixIcon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          onPressed: _sending || voiceState.isRecording
                              ? null
                              : _openRuntimeStickerGifMenu,
                          icon: const Icon(
                            Icons.sentiment_satisfied_alt_rounded,
                          ),
                          tooltip: _runtimeText(
                            context,
                            ar: 'الملصقات و GIF',
                            en: 'Stickers & GIF',
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          onPressed: _sending || voiceState.isRecording
                              ? null
                              : _openRuntimeAttachmentMenu,
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          tooltip: _runtimeText(
                            context,
                            ar: 'مشاركة الموقع',
                            en: 'Add attachment',
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          onPressed: _sending || voiceState.isRecording
                              ? null
                              : _scheduleCurrentDraft,
                          icon: const Icon(Icons.schedule_send_rounded),
                          tooltip: _runtimeText(
                            context,
                            ar: 'جدولة الرسالة',
                            en: 'Schedule message',
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (!showSendAction)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPressStart: (details) async {
                              _voiceStartDy = details.globalPosition.dy;
                              await _startVoiceHold();
                            },
                            onLongPressMoveUpdate: (details) {
                              if (!_voiceComposer.state.isRecording ||
                                  _voiceComposer.state.isLocked) {
                                return;
                              }
                              final dy =
                                  _voiceStartDy - details.globalPosition.dy;
                              if (dy >= 64) {
                                _voiceComposer.lock();
                                if (mounted) setState(() {});
                              }
                            },
                            onLongPressEnd: (_) =>
                                unawaited(_releaseVoiceHold()),
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: voiceState.isRecording
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.errorContainer
                                    : Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                              ),
                              child: Icon(
                                voiceState.isRecording
                                    ? Icons.mic_rounded
                                    : Icons.mic_none_rounded,
                                color: voiceState.isRecording
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        const SizedBox(width: 10),
                        if (showSendAction)
                          FilledButton(
                            onPressed: _sending ? null : _sendText,
                            child: _sending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                          ),
                      ],
                    ),
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

class _RuntimeThreadAttachmentView extends StatelessWidget {
  final SocialChatAttachment attachment;
  final Color textColor;

  const _RuntimeThreadAttachmentView({
    required this.attachment,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final kind = attachment.kind.trim().toLowerCase();
    if (kind == 'audio') {
      return SocialAudioAttachmentBubble(
        attachment: attachment,
        textColor: textColor,
      );
    }
    if (kind == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          attachment.url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _RuntimeMediaFallback(),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black.withValues(alpha: 0.08),
        border: Border.all(color: textColor.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(
            kind == 'video'
                ? Icons.ondemand_video_rounded
                : Icons.attach_file_rounded,
            color: textColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              attachment.name?.trim().isNotEmpty == true
                  ? attachment.name!.trim()
                  : attachment.previewLabel,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeThreadSharedEntityView extends StatelessWidget {
  final SocialSharedEntity entity;

  const _RuntimeThreadSharedEntityView({required this.entity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocation = entity.type.trim().toLowerCase() == 'location';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black.withValues(alpha: 0.08),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
            ),
            child: Icon(
              isLocation ? Icons.location_on_rounded : Icons.article_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLocation
                      ? _runtimeText(
                          context,
                          ar: 'موقع مشترك',
                          en: 'Shared location',
                        )
                      : entity.previewLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isLocation ? (entity.address ?? entity.title) : entity.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatRuntimeDateTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _UserOrdersTab extends ConsumerWidget {
  const _UserOrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final currentRide = ref.watch(_runtimeCurrentRideProvider);
    final orders = ref.watch(_runtimeOrdersProvider);
    final unreadCount = ref.watch(_runtimeUnreadNotificationsCountProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroPanel(
          title: l10n.ordersLabel,
          subtitle: l10n.ordersEmptySubtitle,
          icon: Icons.receipt_long_rounded,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatusChip(
              icon: Icons.shopping_bag_outlined,
              label: l10n.discoverStoresTitle,
            ),
            _StatusChip(
              icon: Icons.local_taxi_outlined,
              label: l10n.requestTaxiTitle,
            ),
            _StatusChip(
              icon: Icons.notifications_active_outlined,
              label: unreadCount.maybeWhen(
                data: (value) => value > 0
                    ? '${l10n.notificationsLabel} ($value)'
                    : l10n.notificationsLabel,
                orElse: () => l10n.notificationsLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        orders.when(
          data: (items) {
            if (items.isEmpty) return const SizedBox.shrink();
            final previewOrders = items.take(3).toList(growable: false);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.ordersLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < previewOrders.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _RuntimeOrderTile(order: previewOrders[i]),
                    ],
                  ],
                ),
              ),
            );
          },
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        currentRide.when(
          data: (ride) {
            if (ride != null) {
              return _RuntimeCurrentRideCard(ride: ride);
            }
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inbox_rounded, size: 52),
                    const SizedBox(height: 12),
                    Text(
                      l10n.ordersEmptyTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.ordersEmptySubtitle, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        ref.read(_selectedTabProvider.notifier).state = 1;
                      },
                      icon: const Icon(Icons.explore_rounded),
                      label: Text(l10n.exploreLabel),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (_, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long_rounded, size: 48),
                  const SizedBox(height: 12),
                  Text(l10n.ordersEmptySubtitle, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UserProfileTab extends ConsumerWidget {
  const _UserProfileTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider);
    final socialProfile = ref.watch(_runtimeMySocialProfileProvider);
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        socialProfile.when(
          data: (profile) => profile == null
              ? const SizedBox.shrink()
              : SocialProfileSummaryCard(profile: profile),
          loading: () => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(minHeight: 3),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        _SectionTitle(title: l10n.profileSectionTitle),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.themeSectionTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  Localizations.localeOf(context).languageCode == 'ar'
                      ? 'تم اعتماد الهوية البصرية الرسمية لمسلكي.'
                      : 'Maslaki official visual identity is now fixed.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.languageSectionTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ChoiceChip(
                      label: Text(l10n.languageArabic),
                      selected: settings.locale.languageCode == 'ar',
                      onSelected: (_) {
                        ref
                            .read(appSettingsControllerProvider.notifier)
                            .setLocale(const Locale('ar'));
                      },
                    ),
                    ChoiceChip(
                      label: Text(l10n.languageEnglish),
                      selected: settings.locale.languageCode == 'en',
                      onSelected: (_) {
                        ref
                            .read(appSettingsControllerProvider.notifier)
                            .setLocale(const Locale('en'));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.animationsEnabled,
                  onChanged: (value) {
                    ref
                        .read(appSettingsControllerProvider.notifier)
                        .setAnimationsEnabled(value);
                  },
                  title: Text(l10n.animationsLabel),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.weatherEffectsEnabled,
                  onChanged: (value) {
                    ref
                        .read(appSettingsControllerProvider.notifier)
                        .setWeatherEffectsEnabled(value);
                  },
                  title: Text(l10n.ambientEffectsLabel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _RuntimeProfileOverviewCard extends StatelessWidget {
  final SocialUserProfile profile;

  const _RuntimeProfileOverviewCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: (profile.imageUrl ?? '').trim().isNotEmpty
                      ? NetworkImage(profile.imageUrl!)
                      : null,
                  child: (profile.imageUrl ?? '').trim().isEmpty
                      ? Text(
                          profile.fullName.trim().isEmpty
                              ? '?'
                              : profile.fullName.trim()[0],
                          style: theme.textTheme.titleLarge,
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.fullName,
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.username == null ||
                                profile.username!.trim().isEmpty
                            ? _runtimeText(
                                context,
                                ar: 'ملف اجتماعي مشترك',
                                en: 'Shared social profile',
                              )
                            : '@${profile.username}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (profile.isResidentVerified)
                  Icon(
                    Icons.verified_rounded,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
            if (profile.bio.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(profile.bio, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  icon: Icons.grid_view_rounded,
                  label: '${profile.stats.totalPosts}',
                ),
                _StatusChip(
                  icon: Icons.favorite_border_rounded,
                  label: '${profile.stats.likesReceived}',
                ),
                _StatusChip(
                  icon: Icons.people_alt_outlined,
                  label: '${profile.stats.connectionsCount}',
                ),
                if ((profile.localContext ?? '').trim().isNotEmpty)
                  _StatusChip(
                    icon: Icons.location_on_outlined,
                    label: profile.localContext!,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationStatusCard extends ConsumerWidget {
  final AsyncValue<LocationPermissionStatus> locationStatus;
  final VoidCallback onRefresh;

  const _LocationStatusCard({
    required this.locationStatus,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: locationStatus.when(
          data: (status) {
            final config = _permissionConfig(context, status.state);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: config.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(config.icon, color: config.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.locationCardTitle,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(config.message),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () =>
                          _handlePrimaryAction(context, ref, status.state),
                      icon: Icon(config.buttonIcon),
                      label: Text(config.buttonLabel),
                    ),
                    OutlinedButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(l10n.commonRefresh),
                    ),
                    if (status.state == AppLocationPermissionState.denied ||
                        status.state ==
                            AppLocationPermissionState.permanentlyDenied)
                      TextButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.chooseLocationManuallyLabel),
                            ),
                          );
                        },
                        icon: const Icon(Icons.place_rounded),
                        label: Text(l10n.chooseLocationManuallyLabel),
                      ),
                  ],
                ),
              ],
            );
          },
          error: (_, _) => ListTile(
            leading: const Icon(Icons.warning_amber_rounded),
            title: Text(l10n.locationCardTitle),
            subtitle: Text(l10n.locationDeniedMessage),
            trailing: IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          loading: () => const SizedBox(
            height: 84,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
  }

  Future<void> _handlePrimaryAction(
    BuildContext context,
    WidgetRef ref,
    AppLocationPermissionState state,
  ) async {
    final service = ref.read(locationPermissionServiceProvider);
    switch (state) {
      case AppLocationPermissionState.denied:
      case AppLocationPermissionState.grantedApproximate:
        await service.requestPermission();
        break;
      case AppLocationPermissionState.permanentlyDenied:
        await service.openAppSettings();
        break;
      case AppLocationPermissionState.serviceDisabled:
        await service.openLocationSettings();
        break;
      case AppLocationPermissionState.grantedPrecise:
        break;
    }
    onRefresh();
  }

  _PermissionConfig _permissionConfig(
    BuildContext context,
    AppLocationPermissionState state,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return switch (state) {
      AppLocationPermissionState.grantedPrecise => _PermissionConfig(
        icon: Icons.verified_rounded,
        color: Colors.tealAccent.shade400,
        message: l10n.locationPreciseGranted,
        buttonLabel: l10n.commonRefresh,
        buttonIcon: Icons.refresh_rounded,
      ),
      AppLocationPermissionState.grantedApproximate => _PermissionConfig(
        icon: Icons.my_location_rounded,
        color: theme.colorScheme.primary,
        message: l10n.locationApproximateGranted,
        buttonLabel: l10n.requestLocationLabel,
        buttonIcon: Icons.my_location_rounded,
      ),
      AppLocationPermissionState.denied => _PermissionConfig(
        icon: Icons.location_off_rounded,
        color: theme.colorScheme.error,
        message: l10n.locationDeniedMessage,
        buttonLabel: l10n.requestLocationLabel,
        buttonIcon: Icons.location_searching_rounded,
      ),
      AppLocationPermissionState.permanentlyDenied => _PermissionConfig(
        icon: Icons.settings_rounded,
        color: theme.colorScheme.error,
        message: l10n.locationDeniedForeverMessage,
        buttonLabel: l10n.commonOpenSettings,
        buttonIcon: Icons.settings_rounded,
      ),
      AppLocationPermissionState.serviceDisabled => _PermissionConfig(
        icon: Icons.location_disabled_rounded,
        color: theme.colorScheme.secondary,
        message: l10n.locationServiceDisabledMessage,
        buttonLabel: l10n.openLocationSettingsLabel,
        buttonIcon: Icons.map_rounded,
      ),
    };
  }
}

class _PermissionConfig {
  final IconData icon;
  final Color color;
  final String message;
  final String buttonLabel;
  final IconData buttonIcon;

  const _PermissionConfig({
    required this.icon,
    required this.color,
    required this.message,
    required this.buttonLabel,
    required this.buttonIcon,
  });
}

class _UserAppDrawer extends ConsumerWidget {
  final int selectedTab;
  final ValueChanged<int> onSelectTab;

  const _UserAppDrawer({required this.selectedTab, required this.onSelectTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locationStatus = ref.watch(_locationStatusProvider);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              child: _HeroPanel(
                title: l10n.appName,
                subtitle: l10n.userAppWindowTitle,
                icon: Icons.navigation_rounded,
              ),
            ),
            _DrawerTabTile(
              selected: selectedTab == 0,
              icon: Icons.home_rounded,
              title: l10n.homeLabel,
              onTap: () => _select(context, 0),
            ),
            _DrawerTabTile(
              selected: selectedTab == 1,
              icon: Icons.explore_rounded,
              title: l10n.exploreLabel,
              onTap: () => _select(context, 1),
            ),
            _DrawerTabTile(
              selected: selectedTab == 2,
              icon: Icons.ondemand_video_rounded,
              title: l10n.reelsHubTitle,
              onTap: () => _select(context, 2),
            ),
            _DrawerTabTile(
              selected: selectedTab == 3,
              icon: Icons.chat_bubble_outline_rounded,
              title: _runtimeText(context, ar: 'الرسائل', en: 'Inbox'),
              onTap: () => _select(context, 3),
            ),
            _DrawerTabTile(
              selected: selectedTab == 4,
              icon: Icons.person_rounded,
              title: l10n.profileLabel,
              onTap: () => _select(context, 4),
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.place_rounded),
              title: Text(l10n.locationCardTitle),
              subtitle: Text(
                locationStatus.when(
                  data: (value) => _drawerLocationLabel(l10n, value.state),
                  error: (_, _) => l10n.locationDeniedMessage,
                  loading: () => l10n.commonRefresh,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.chooseLocationManuallyLabel)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.color_lens_outlined),
              title: Text(l10n.themeSectionTitle),
              subtitle: Text(l10n.profileSectionTitle),
              onTap: () => _select(context, 4),
            ),
          ],
        ),
      ),
    );
  }

  void _select(BuildContext context, int index) {
    onSelectTab(index);
    Navigator.of(context).pop();
  }

  String _drawerLocationLabel(
    CoreAppLocalizations l10n,
    AppLocationPermissionState state,
  ) {
    return switch (state) {
      AppLocationPermissionState.grantedPrecise => l10n.locationPreciseGranted,
      AppLocationPermissionState.grantedApproximate =>
        l10n.locationApproximateGranted,
      AppLocationPermissionState.denied => l10n.locationDeniedMessage,
      AppLocationPermissionState.permanentlyDenied =>
        l10n.locationDeniedForeverMessage,
      AppLocationPermissionState.serviceDisabled =>
        l10n.locationServiceDisabledMessage,
    };
  }
}

class _DrawerTabTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerTabTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.12),
      leading: Icon(icon),
      title: Text(title),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

class _QuickActionsGrid extends ConsumerWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final items = [
      _QuickActionData(
        icon: Icons.dynamic_feed_rounded,
        title: _runtimeText(context, ar: 'الفيد', en: 'Feed'),
        subtitle: _runtimeText(
          context,
          ar: 'آخر منشورات السوشل المشتركة',
          en: 'Latest shared social posts',
        ),
        onTap: () =>
            _openRuntimeFeaturePage(context, _RuntimeFeatureDestination.feed),
      ),
      _QuickActionData(
        icon: Icons.search_rounded,
        title: _runtimeText(context, ar: 'بحث', en: 'Search'),
        subtitle: _runtimeText(
          context,
          ar: 'حسابات ووسوم ومحتوى',
          en: 'Accounts, hashtags, and content',
        ),
        onTap: () =>
            _openRuntimeFeaturePage(context, _RuntimeFeatureDestination.search),
      ),
      _QuickActionData(
        icon: Icons.chat_bubble_outline_rounded,
        title: _runtimeText(context, ar: 'الرسائل', en: 'Inbox'),
        subtitle: _runtimeText(
          context,
          ar: 'المحادثات المباشرة والجماعية',
          en: 'Direct and group conversations',
        ),
        onTap: () =>
            _openRuntimeFeaturePage(context, _RuntimeFeatureDestination.inbox),
      ),
      _QuickActionData(
        icon: Icons.storefront_rounded,
        title: l10n.discoverStoresTitle,
        subtitle: l10n.discoverStoresSubtitle,
        onTap: () =>
            _openRuntimeFeaturePage(context, _RuntimeFeatureDestination.stores),
      ),
      _QuickActionData(
        icon: Icons.local_taxi_rounded,
        title: l10n.requestTaxiTitle,
        subtitle: l10n.requestTaxiSubtitle,
        onTap: () =>
            _openRuntimeFeaturePage(context, _RuntimeFeatureDestination.taxi),
      ),
      _QuickActionData(
        icon: Icons.ondemand_video_rounded,
        title: l10n.watchReelsTitle,
        subtitle: l10n.watchReelsSubtitle,
        onTap: () =>
            _openRuntimeFeaturePage(context, _RuntimeFeatureDestination.reels),
      ),
      _QuickActionData(
        icon: Icons.receipt_long_rounded,
        title: l10n.ordersLabel,
        subtitle: l10n.ordersEmptySubtitle,
        onTap: () =>
            _openRuntimeFeaturePage(context, _RuntimeFeatureDestination.orders),
      ),
      _QuickActionData(
        icon: Icons.notifications_active_rounded,
        title: l10n.notificationsLabel,
        subtitle: l10n.notificationsPermissionDescription,
        onTap: () => _openRuntimeFeaturePage(
          context,
          _RuntimeFeatureDestination.notifications,
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.18,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: item.onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          item.icon,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _QuickActionData {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _UserTabShortcuts extends ConsumerWidget {
  const _UserTabShortcuts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => ref.read(_selectedTabProvider.notifier).state = 1,
          icon: const Icon(Icons.explore_rounded),
          label: Text(l10n.exploreLabel),
        ),
        FilledButton.tonalIcon(
          onPressed: () => ref.read(_selectedTabProvider.notifier).state = 2,
          icon: const Icon(Icons.ondemand_video_rounded),
          label: Text(l10n.reelsHubTitle),
        ),
        FilledButton.tonalIcon(
          onPressed: () => ref.read(_selectedTabProvider.notifier).state = 3,
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: Text(_runtimeText(context, ar: 'الرسائل', en: 'Inbox')),
        ),
        FilledButton.tonalIcon(
          onPressed: () => ref.read(_selectedTabProvider.notifier).state = 4,
          icon: const Icon(Icons.person_rounded),
          label: Text(l10n.profileLabel),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}

void _openRuntimeFeaturePage(
  BuildContext context,
  _RuntimeFeatureDestination destination,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => switch (destination) {
        _RuntimeFeatureDestination.stores => const _StoresHubScreen(),
        _RuntimeFeatureDestination.taxi => const _TaxiHubScreen(),
        _RuntimeFeatureDestination.orders => const _RuntimeOrdersHubScreen(),
        _RuntimeFeatureDestination.feed => const _RuntimeSharedFeedScreen(),
        _RuntimeFeatureDestination.search => const _RuntimeSharedSearchScreen(),
        _RuntimeFeatureDestination.reels =>
          const _RuntimeSharedReelsFeedScreen(),
        _RuntimeFeatureDestination.inbox => const _RuntimeInboxHubScreen(),
        _RuntimeFeatureDestination.notifications =>
          const _RuntimeNotificationsHubScreen(),
      },
    ),
  );
}

void _openRuntimeStoreDetails(BuildContext context, MerchantModel merchant) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _StoreDetailsScreen(merchant: merchant),
    ),
  );
}

class _RuntimeOrdersHubScreen extends StatelessWidget {
  const _RuntimeOrdersHubScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.ordersLabel)),
      body: const SafeArea(child: _UserOrdersTab()),
    );
  }
}

class _RuntimeInboxHubScreen extends StatelessWidget {
  const _RuntimeInboxHubScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_runtimeText(context, ar: 'الرسائل', en: 'Inbox')),
      ),
      body: const SafeArea(child: _UserInboxTab()),
    );
  }
}

void _openRuntimeOrderDetails(
  BuildContext context,
  Map<String, dynamic> order,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _RuntimeOrderDetailsScreen(order: order),
    ),
  );
}

void _openRuntimeRideDetails(BuildContext context, Map<String, dynamic> ride) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _RuntimeRideDetailsScreen(ride: ride),
    ),
  );
}

Future<void> _markRuntimeNotificationRead(
  ProviderContainer container,
  int notificationId,
) async {
  if (notificationId <= 0) return;
  try {
    await container
        .read(_runtimeNotificationsApiProvider)
        .markRead(notificationId);
  } catch (_) {
    // Keep notification routing best-effort.
  }
  container.invalidate(_runtimeNotificationsProvider);
  container.invalidate(_runtimeUnreadNotificationsCountProvider);
}

Future<void> _openRuntimeNotificationDetails(
  BuildContext context,
  Map<String, dynamic> notification,
) async {
  final l10n = context.l10n;
  final container = ProviderScope.containerOf(context, listen: false);
  final notificationId = _extractRuntimeInt(notification, const [
    'id',
    'notificationId',
    'notification_id',
  ]);
  if (notificationId != null) {
    await _markRuntimeNotificationRead(container, notificationId);
    if (!context.mounted) return;
  }
  final orderId = _extractRuntimeInt(notification, const [
    'orderId',
    'order_id',
  ]);
  final rideId = _extractRuntimeInt(notification, const ['rideId', 'ride_id']);
  final merchantId = _extractRuntimeInt(notification, const [
    'merchantId',
    'merchant_id',
    'storeId',
    'store_id',
  ]);
  final type = _tryReadString(notification['type'], fallback: '').toLowerCase();

  if (orderId != null || type.contains('order')) {
    final details = <String, dynamic>{...notification};
    if (orderId != null) {
      details['id'] = orderId;
    }
    details.putIfAbsent('status', () => notification['status'] ?? 'pending');
    details.putIfAbsent(
      'merchantName',
      () =>
          notification['merchantName'] ??
          notification['storeName'] ??
          notification['subject'],
    );
    details.putIfAbsent(
      'orderNumber',
      () => notification['reference'] ?? '#$orderId',
    );
    _openRuntimeOrderDetails(context, details);
    return;
  }

  if (rideId != null || type.contains('ride') || type.contains('taxi')) {
    final details = <String, dynamic>{...notification};
    if (rideId != null) {
      details['id'] = rideId;
    }
    details.putIfAbsent('status', () => notification['status'] ?? 'pending');
    details.putIfAbsent(
      'pickupLabel',
      () =>
          notification['pickupLabel'] ??
          notification['title'] ??
          l10n.runtimeTaxiPickupTitle,
    );
    details.putIfAbsent(
      'dropoffLabel',
      () =>
          notification['dropoffLabel'] ??
          notification['body'] ??
          l10n.runtimeTaxiDropoffTitle,
    );
    _openRuntimeRideDetails(context, details);
    return;
  }

  if (merchantId != null ||
      type.contains('merchant') ||
      type.contains('store')) {
    MerchantModel? merchant;
    List<MerchantModel> merchants = _fallbackRuntimeMerchants;
    try {
      merchants = await container.read(_runtimeMerchantListProvider.future);
    } catch (_) {
      merchants = _fallbackRuntimeMerchants;
    }
    if (!context.mounted) return;
    for (final item in merchants) {
      if (item.id == merchantId) {
        merchant = item;
        break;
      }
    }
    if (merchant != null) {
      _openRuntimeStoreDetails(context, merchant);
      return;
    }
    _openRuntimeFeaturePage(context, _RuntimeFeatureDestination.stores);
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          _RuntimeNotificationDetailsScreen(notification: notification),
    ),
  );
}

Future<void> _cancelRuntimeRide(
  BuildContext context,
  Map<String, dynamic> ride,
) async {
  final rideId = _tryReadInt(ride['id']) ?? 0;
  if (rideId <= 0) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = context.l10n;
  try {
    await container.read(_runtimeTaxiApiProvider).cancelRide(rideId);
    container.invalidate(_runtimeCurrentRideProvider);
    if (!context.mounted || messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.runtimeActionCompletedLabel)),
    );
  } catch (_) {
    if (!context.mounted || messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.runtimeActionFailedLabel)),
    );
  }
}

Future<void> _shareRuntimeRide(
  BuildContext context,
  Map<String, dynamic> ride,
) async {
  final rideId = _tryReadInt(ride['id']) ?? 0;
  if (rideId <= 0) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = context.l10n;
  try {
    final payload =
        await container
            .read(_runtimeTaxiApiProvider)
            .createShareToken(rideId) ??
        const <String, dynamic>{};
    final token = _tryReadString(
      payload['shareUrl'] ??
          payload['share_url'] ??
          payload['publicUrl'] ??
          payload['public_url'] ??
          payload['token'] ??
          payload['shareToken'],
    );
    if (token.isEmpty) {
      throw const FormatException('EMPTY_SHARE_TOKEN');
    }
    await Clipboard.setData(ClipboardData(text: token));
    if (!context.mounted || messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.runtimeShareRideCopiedMessage)),
    );
  } catch (_) {
    if (!context.mounted || messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.runtimeActionFailedLabel)),
    );
  }
}

class _RuntimeMerchantsApi {
  final Dio _dio;

  const _RuntimeMerchantsApi(this._dio);

  Future<List<MerchantModel>> list({
    String? search,
    String? activityType,
  }) async {
    final params = <String, dynamic>{};
    final trimmedSearch = search?.trim();
    if (trimmedSearch != null && trimmedSearch.isNotEmpty) {
      params['search'] = trimmedSearch;
    }
    if (activityType != null && activityType.trim().isNotEmpty) {
      params['activityType'] = activityType.trim();
    }
    final response = await _dio.get(
      '/api/merchants',
      queryParameters: params.isEmpty ? null : params,
    );
    final data = response.data;
    if (data is! List) return const <MerchantModel>[];
    return data
        .whereType<Map>()
        .map((item) => MerchantModel.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }
}

class _RuntimeTaxiApi {
  final Dio _dio;

  const _RuntimeTaxiApi(this._dio);

  Future<Map<String, dynamic>> createRide({
    required _RuntimeCoordinate pickup,
    required _RuntimeCoordinate dropoff,
    required String pickupLabel,
    required String dropoffLabel,
    required int proposedFareIqd,
    required String scheduleMode,
    DateTime? scheduledFor,
    String? couponCode,
    String? note,
  }) async {
    final response = await _dio.post(
      '/api/taxi/rides',
      data: {
        'pickupLatitude': pickup.latitude,
        'pickupLongitude': pickup.longitude,
        'dropoffLatitude': dropoff.latitude,
        'dropoffLongitude': dropoff.longitude,
        'pickupLabel': pickupLabel,
        'dropoffLabel': dropoffLabel,
        'proposedFareIqd': proposedFareIqd,
        'scheduleMode': scheduleMode,
        'searchRadiusM': 2500,
        if (scheduledFor != null)
          'scheduledFor': scheduledFor.toIso8601String(),
        if (couponCode != null && couponCode.trim().isNotEmpty)
          'couponCode': couponCode.trim().toUpperCase(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    final data = response.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {'ride': data};
  }

  Future<Map<String, dynamic>?> getCurrentRide() async {
    final response = await _dio.get('/api/taxi/rides/current');
    final data = response.data;
    if (data is! Map) return null;
    final payload = Map<String, dynamic>.from(data);
    final rideEnvelope = payload['ride'];
    if (rideEnvelope is! Map) return null;
    final envelopeMap = Map<String, dynamic>.from(rideEnvelope);
    final ride = envelopeMap['ride'];
    if (ride is! Map) return null;
    return Map<String, dynamic>.from(ride);
  }

  Future<void> cancelRide(int rideId) async {
    await _dio.post('/api/taxi/rides/$rideId/cancel');
  }

  Future<Map<String, dynamic>?> createShareToken(int rideId) async {
    final response = await _dio.post('/api/taxi/rides/$rideId/share-token');
    return _extractRuntimeObject(response.data, const [
      'data',
      'share',
      'item',
    ]);
  }
}

class _RuntimeNotificationsApi {
  final Dio _dio;

  const _RuntimeNotificationsApi(this._dio);

  Future<List<Map<String, dynamic>>> list({int limit = 20}) async {
    final response = await _dio.get(
      '/api/notifications',
      queryParameters: {'unreadOnly': 0, 'limit': limit},
    );
    return _extractRuntimeObjectList(response.data, const [
      'items',
      'notifications',
      'data',
    ]);
  }

  Future<int> unreadCount() async {
    final response = await _dio.get('/api/notifications/unread-count');
    final data = response.data;
    if (data is! Map) return 0;
    return _tryReadInt(data['unreadCount']) ?? 0;
  }

  Future<void> markRead(int notificationId) async {
    await _dio.patch('/api/notifications/$notificationId/read');
  }

  Future<void> markAllRead() async {
    await _dio.patch('/api/notifications/read-all');
  }
}

class _RuntimeOrdersApi {
  final Dio _dio;

  const _RuntimeOrdersApi(this._dio);

  Future<List<Map<String, dynamic>>> listMyOrders() async {
    final response = await _dio.get('/api/orders/my');
    return _extractRuntimeObjectList(response.data, const [
      'items',
      'orders',
      'data',
    ]);
  }
}

String? _readApiErrorMessage(DioException error) {
  final data = error.response?.data;
  if (data is Map) {
    final message = data['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
  }
  return null;
}

List<Map<String, dynamic>> _extractRuntimeObjectList(
  dynamic data,
  List<String> fallbackKeys,
) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
  if (data is Map) {
    final source = Map<String, dynamic>.from(data);
    for (final key in fallbackKeys) {
      final candidate = source[key];
      if (candidate is List) {
        return candidate
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
    }
  }
  return const <Map<String, dynamic>>[];
}

Map<String, dynamic>? _extractRuntimeObject(dynamic data, List<String> keys) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) {
    final source = Map<String, dynamic>.from(data);
    for (final key in keys) {
      final candidate = source[key];
      if (candidate is Map) {
        return Map<String, dynamic>.from(candidate);
      }
    }
  }
  return null;
}

int? _tryReadInt(dynamic value) {
  if (value == null) return null;
  return int.tryParse('$value');
}

int? _extractRuntimeInt(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final parsed = _tryReadInt(source[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

String _tryReadString(dynamic value, {String fallback = '-'}) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? fallback : text;
}

String _presentRuntimeRideStatus(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) return 'pending';
  return normalized.replaceAll('_', ' ');
}

const _fallbackRuntimeMerchants = <MerchantModel>[
  MerchantModel(
    id: 1,
    name: 'صيدلية الدواء السريع',
    type: 'market',
    activityType: 'pharmacy',
    description: 'وصفات، أدوية يومية، وتجهيز سريع.',
    workingHours: '24/7',
    isOpen: true,
    hasDiscountOffer: false,
    hasFreeDeliveryOffer: true,
    supportsChat: true,
    supportsAttachments: true,
    supportsPharmacyWorkflow: true,
    badges: ['وصفة', 'توصيل'],
  ),
  MerchantModel(
    id: 2,
    name: 'مطعم الدار',
    type: 'restaurant',
    activityType: 'restaurant',
    description: 'وجبات عراقية ومشاوي مع توصيل مرن.',
    workingHours: '10:00 - 01:00',
    isOpen: true,
    hasDiscountOffer: true,
    hasFreeDeliveryOffer: false,
    badges: ['عائلي', 'مشاوي'],
  ),
  MerchantModel(
    id: 3,
    name: 'ماركت الحي',
    type: 'market',
    activityType: 'supermarket',
    description: 'مواد يومية، خضار، ومنتجات منزلية.',
    workingHours: '08:00 - 12:00',
    isOpen: true,
    hasDiscountOffer: false,
    hasFreeDeliveryOffer: true,
    badges: ['سريع', 'منزل'],
  ),
  MerchantModel(
    id: 4,
    name: 'قهوة المسار',
    type: 'restaurant',
    activityType: 'coffee_drinks',
    description: 'قهوة مختصة ومشروبات باردة.',
    workingHours: '09:00 - 11:30',
    isOpen: false,
    hasDiscountOffer: true,
    hasFreeDeliveryOffer: false,
    badges: ['قهوة', 'حلويات'],
  ),
];

class _StoresHubScreen extends ConsumerStatefulWidget {
  const _StoresHubScreen();

  @override
  ConsumerState<_StoresHubScreen> createState() => _StoresHubScreenState();
}

class _StoresHubScreenState extends ConsumerState<_StoresHubScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(_runtimeStoreSearchProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final merchants = ref.watch(_runtimeMerchantListProvider);
    final selectedFilter = ref.watch(_runtimeStoreActivityFilterProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.storesHubTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: l10n.storesHubTitle,
            subtitle: l10n.storesHubSubtitle,
            icon: Icons.storefront_rounded,
          ),
          const SizedBox(height: 16),
          SearchBar(
            controller: _searchController,
            leading: const Icon(Icons.search_rounded),
            hintText: l10n.storesSearchHint,
            onChanged: (value) {
              ref.read(_runtimeStoreSearchProvider.notifier).state = value;
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StoreFilterChip(
                selected: selectedFilter == 'all',
                label: l10n.exploreLabel,
                onTap: () =>
                    ref
                            .read(_runtimeStoreActivityFilterProvider.notifier)
                            .state =
                        'all',
              ),
              _StoreFilterChip(
                selected: selectedFilter == 'restaurant',
                icon: Icons.restaurant_menu_rounded,
                label: l10n.storesCategoryRestaurants,
                onTap: () =>
                    ref
                            .read(_runtimeStoreActivityFilterProvider.notifier)
                            .state =
                        'restaurant',
              ),
              _StoreFilterChip(
                selected: selectedFilter == 'pharmacy',
                icon: Icons.local_pharmacy_rounded,
                label: l10n.storesCategoryPharmacies,
                onTap: () =>
                    ref
                            .read(_runtimeStoreActivityFilterProvider.notifier)
                            .state =
                        'pharmacy',
              ),
              _StoreFilterChip(
                selected: selectedFilter == 'supermarket',
                icon: Icons.shopping_cart_rounded,
                label: l10n.storesCategorySupermarket,
                onTap: () =>
                    ref
                            .read(_runtimeStoreActivityFilterProvider.notifier)
                            .state =
                        'supermarket',
              ),
              _StoreFilterChip(
                selected: selectedFilter == 'coffee_drinks',
                icon: Icons.coffee_rounded,
                label: l10n.storesCategoryCoffee,
                onTap: () =>
                    ref
                            .read(_runtimeStoreActivityFilterProvider.notifier)
                            .state =
                        'coffee_drinks',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionTitle(title: l10n.storesFeaturedSectionTitle),
          const SizedBox(height: 12),
          merchants.when(
            data: (items) {
              if (items.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.storesEmptyTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(l10n.storesEmptySubtitle),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _StorePreviewCard(merchant: items[i]),
                    if (i != items.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            },
            error: (_, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.storesEmptyTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(l10n.storesEmptySubtitle),
                  ],
                ),
              ),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreFilterChip extends StatelessWidget {
  final bool selected;
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _StoreFilterChip({
    required this.selected,
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: icon == null ? null : Icon(icon, size: 18),
      label: Text(label),
      showCheckmark: false,
    );
  }
}

class _TaxiHubScreen extends ConsumerStatefulWidget {
  const _TaxiHubScreen();

  @override
  ConsumerState<_TaxiHubScreen> createState() => _TaxiHubScreenState();
}

class _TaxiHubScreenState extends ConsumerState<_TaxiHubScreen> {
  late final TextEditingController _pickupController;
  late final TextEditingController _dropoffController;
  late final TextEditingController _fareController;
  late final TextEditingController _couponController;

  _RuntimeRideTimingMode _timingMode = _RuntimeRideTimingMode.now;
  _RuntimeRideStep _step = _RuntimeRideStep.timing;
  DateTime? _scheduledFor;
  double _distanceKm = 6;
  _RuntimeCoordinate? _pickupCoordinate;
  _RuntimeCoordinate? _dropoffCoordinate;
  bool _submitting = false;
  String? _validationMessage;
  Map<String, dynamic>? _submittedPayload;

  @override
  void initState() {
    super.initState();
    _pickupController = TextEditingController();
    _dropoffController = TextEditingController();
    final initialEstimate = _estimateFareFromDistanceKm(_distanceKm);
    _fareController = TextEditingController(
      text: '${initialEstimate.suggestedIqd}',
    );
    _couponController = TextEditingController();
    _pickupCoordinate = _runtimeFallbackPickup;
    _dropoffCoordinate = _offsetCoordinateFromDistance(
      _runtimeFallbackPickup,
      _distanceKm,
    );
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _fareController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  _RuntimeFareEstimateRange get _estimate =>
      _estimateFareFromDistanceKm(_distanceKm);

  int get _etaMinutes => (_distanceKm * 3).round().clamp(8, 90);

  void _syncDropoffCoordinate() {
    _dropoffCoordinate = _offsetCoordinateFromDistance(
      _pickupCoordinate ?? _runtimeFallbackPickup,
      _distanceKm,
    );
  }

  void _ensureRideCoordinates() {
    _pickupCoordinate ??= _runtimeFallbackPickup;
    _syncDropoffCoordinate();
  }

  Future<void> _pickSchedule(BuildContext context) async {
    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      firstDate: now,
      initialDate: _scheduledFor?.isAfter(now) == true ? _scheduledFor! : now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (selectedDate == null || !context.mounted) return;
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _scheduledFor != null
          ? TimeOfDay.fromDateTime(_scheduledFor!)
          : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (selectedTime == null) return;
    final candidate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    setState(() {
      _scheduledFor = candidate;
    });
  }

  bool _validateCurrentStep(BuildContext context) {
    final l10n = context.l10n;
    switch (_step) {
      case _RuntimeRideStep.timing:
        if (_timingMode == _RuntimeRideTimingMode.scheduled) {
          final candidate = _scheduledFor;
          if (candidate == null || !candidate.isAfter(DateTime.now())) {
            setState(() {
              _validationMessage = l10n.runtimeTaxiScheduleValidation;
            });
            return false;
          }
        }
        break;
      case _RuntimeRideStep.pickup:
        if (_pickupController.text.trim().isEmpty) {
          setState(() {
            _validationMessage = l10n.runtimeTaxiPickupValidation;
          });
          return false;
        }
        break;
      case _RuntimeRideStep.dropoff:
        if (_dropoffController.text.trim().isEmpty) {
          setState(() {
            _validationMessage = l10n.runtimeTaxiDropoffValidation;
          });
          return false;
        }
        break;
      case _RuntimeRideStep.summary:
        final fare = int.tryParse(_fareController.text.trim());
        if (fare == null || fare < 1500) {
          setState(() {
            _validationMessage = l10n.runtimeTaxiFareValidation;
          });
          return false;
        }
        break;
    }
    setState(() {
      _validationMessage = null;
    });
    return true;
  }

  void _goNext(BuildContext context) {
    if (!_validateCurrentStep(context)) return;
    setState(() {
      if (_step == _RuntimeRideStep.pickup) {
        _pickupCoordinate ??= _runtimeFallbackPickup;
        _syncDropoffCoordinate();
      }
      if (_step == _RuntimeRideStep.dropoff) {
        _syncDropoffCoordinate();
      }
      _step = switch (_step) {
        _RuntimeRideStep.timing => _RuntimeRideStep.pickup,
        _RuntimeRideStep.pickup => _RuntimeRideStep.dropoff,
        _RuntimeRideStep.dropoff => _RuntimeRideStep.summary,
        _RuntimeRideStep.summary => _RuntimeRideStep.summary,
      };
    });
  }

  void _goBack() {
    setState(() {
      _validationMessage = null;
      _step = switch (_step) {
        _RuntimeRideStep.timing => _RuntimeRideStep.timing,
        _RuntimeRideStep.pickup => _RuntimeRideStep.timing,
        _RuntimeRideStep.dropoff => _RuntimeRideStep.pickup,
        _RuntimeRideStep.summary => _RuntimeRideStep.dropoff,
      };
    });
  }

  Future<void> _fillCurrentLocation(BuildContext context) async {
    final l10n = context.l10n;
    final service = ref.read(locationPermissionServiceProvider);
    final status = await service.getStatus();
    if (!mounted) return;
    if (status.state == AppLocationPermissionState.grantedPrecise ||
        status.state == AppLocationPermissionState.grantedApproximate) {
      final position = await service.getCurrentPosition();
      final resolvedPickup = position == null
          ? _runtimeFallbackPickup
          : _RuntimeCoordinate(
              latitude: position.latitude,
              longitude: position.longitude,
            );
      _pickupController.text = l10n.runtimeTaxiCurrentLocationLabel;
      setState(() {
        _pickupCoordinate = resolvedPickup;
        _syncDropoffCoordinate();
        _validationMessage = null;
      });
      return;
    }
    setState(() {
      _validationMessage = l10n.taxiLocationNeedsAttention;
    });
  }

  Future<void> _submitRide(BuildContext context) async {
    if (!_validateCurrentStep(context)) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final fare = int.parse(_fareController.text.trim());
    _ensureRideCoordinates();
    final requestPayload = <String, dynamic>{
      'scheduleMode': _timingMode == _RuntimeRideTimingMode.now
          ? 'now'
          : 'scheduled',
      if (_scheduledFor != null)
        'scheduledFor': _scheduledFor!.toIso8601String(),
      'pickupLabel': _pickupController.text.trim(),
      'dropoffLabel': _dropoffController.text.trim(),
      'pickupLatitude': _pickupCoordinate!.latitude,
      'pickupLongitude': _pickupCoordinate!.longitude,
      'dropoffLatitude': _dropoffCoordinate!.latitude,
      'dropoffLongitude': _dropoffCoordinate!.longitude,
      'distanceKm': _distanceKm.toStringAsFixed(1),
      'etaMinutes': _etaMinutes,
      'proposedFareIqd': fare,
      'couponCode': _couponController.text.trim().toUpperCase(),
    };
    final authState = ref.read(authControllerProvider);
    setState(() {
      _submitting = true;
    });
    try {
      if (authState.user != null && authState.isUser) {
        final response = await ref
            .read(_runtimeTaxiApiProvider)
            .createRide(
              pickup: _pickupCoordinate!,
              dropoff: _dropoffCoordinate!,
              pickupLabel: _pickupController.text.trim(),
              dropoffLabel: _dropoffController.text.trim(),
              proposedFareIqd: fare,
              scheduleMode: _timingMode == _RuntimeRideTimingMode.now
                  ? 'now'
                  : 'scheduled',
              scheduledFor: _scheduledFor,
              couponCode: _couponController.text.trim(),
            );
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _submittedPayload = {'request': requestPayload, 'response': response};
          _validationMessage = null;
        });
        ref.invalidate(_runtimeCurrentRideProvider);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.runtimeTaxiSubmitCreated)),
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submittedPayload = requestPayload;
        _validationMessage = null;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.runtimeTaxiSubmitSuccess)),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      final message =
          _readApiErrorMessage(error) ?? l10n.runtimeTaxiSubmitFailed;
      setState(() {
        _submitting = false;
        _submittedPayload = requestPayload;
        _validationMessage = message;
      });
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submittedPayload = requestPayload;
        _validationMessage = l10n.runtimeTaxiSubmitFailed;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.runtimeTaxiSubmitFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(_locationStatusProvider);
    final currentRide = ref.watch(_runtimeCurrentRideProvider);
    final estimate = _estimate;
    final parsedFare = int.tryParse(_fareController.text.trim());
    final fareBelowSuggested =
        parsedFare != null &&
        parsedFare >= 1500 &&
        parsedFare < estimate.suggestedIqd;
    final isSummary = _step == _RuntimeRideStep.summary;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.taxiHubTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: l10n.taxiHubTitle,
            subtitle: l10n.taxiHubSubtitle,
            icon: Icons.local_taxi_rounded,
          ),
          const SizedBox(height: 16),
          _LocationStatusCard(
            locationStatus: status,
            onRefresh: () {
              ref.read(_locationRefreshTickProvider.notifier).state++;
            },
          ),
          if (currentRide.valueOrNull != null) ...[
            const SizedBox(height: 16),
            _RuntimeCurrentRideCard(ride: currentRide.valueOrNull!),
          ],
          const SizedBox(height: 16),
          _RuntimeTaxiStepHeader(step: _step),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_step == _RuntimeRideStep.timing) ...[
                    _SectionTitle(title: l10n.runtimeTaxiTimingTitle),
                    const SizedBox(height: 12),
                    SegmentedButton<_RuntimeRideTimingMode>(
                      segments: [
                        ButtonSegment(
                          value: _RuntimeRideTimingMode.now,
                          icon: const Icon(Icons.flash_on_rounded),
                          label: Text(l10n.runtimeTaxiRideNowLabel),
                        ),
                        ButtonSegment(
                          value: _RuntimeRideTimingMode.scheduled,
                          icon: const Icon(Icons.schedule_rounded),
                          label: Text(l10n.runtimeTaxiRideScheduleLabel),
                        ),
                      ],
                      selected: {_timingMode},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _timingMode = selection.first;
                          if (_timingMode == _RuntimeRideTimingMode.now) {
                            _scheduledFor = null;
                          }
                        });
                      },
                    ),
                    if (_timingMode == _RuntimeRideTimingMode.scheduled) ...[
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_rounded),
                        title: Text(l10n.runtimeTaxiScheduleTitle),
                        subtitle: Text(
                          _scheduledFor == null
                              ? l10n.runtimeTaxiScheduleHint
                              : _formatScheduledDate(_scheduledFor!),
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => _pickSchedule(context),
                          child: Text(l10n.runtimeTaxiChooseDateAction),
                        ),
                      ),
                    ],
                  ],
                  if (_step == _RuntimeRideStep.pickup) ...[
                    _SectionTitle(title: l10n.runtimeTaxiPickupTitle),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pickupController,
                      decoration: InputDecoration(
                        hintText: l10n.runtimeTaxiPickupHint,
                        prefixIcon: const Icon(Icons.trip_origin_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _fillCurrentLocation(context),
                          icon: const Icon(Icons.my_location_rounded),
                          label: Text(l10n.runtimeTaxiCurrentLocationAction),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _showRuntimeMessage(
                            context,
                            l10n.taxiOpenMapAction,
                          ),
                          icon: const Icon(Icons.map_rounded),
                          label: Text(l10n.taxiOpenMapAction),
                        ),
                      ],
                    ),
                  ],
                  if (_step == _RuntimeRideStep.dropoff) ...[
                    _SectionTitle(title: l10n.runtimeTaxiDropoffTitle),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _dropoffController,
                      decoration: InputDecoration(
                        hintText: l10n.runtimeTaxiDropoffHint,
                        prefixIcon: const Icon(Icons.flag_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.runtimeTaxiDistanceLabel(
                        _distanceKm.toStringAsFixed(1),
                      ),
                    ),
                    Slider(
                      value: _distanceKm,
                      min: 1,
                      max: 30,
                      divisions: 29,
                      label: '${_distanceKm.toStringAsFixed(1)} km',
                      onChanged: (value) {
                        setState(() {
                          _distanceKm = value;
                          _syncDropoffCoordinate();
                          if (_fareController.text.trim().isEmpty ||
                              int.tryParse(_fareController.text.trim()) ==
                                  estimate.suggestedIqd) {
                            _fareController.text = '${_estimate.suggestedIqd}';
                          }
                        });
                      },
                    ),
                  ],
                  if (isSummary) ...[
                    _SectionTitle(title: l10n.runtimeTaxiSummaryTitle),
                    const SizedBox(height: 12),
                    _TaxiSummaryRow(
                      icon: Icons.trip_origin_rounded,
                      label: l10n.runtimeTaxiPickupTitle,
                      value: _pickupController.text.trim(),
                    ),
                    const SizedBox(height: 10),
                    _TaxiSummaryRow(
                      icon: Icons.flag_rounded,
                      label: l10n.runtimeTaxiDropoffTitle,
                      value: _dropoffController.text.trim(),
                    ),
                    const SizedBox(height: 10),
                    _TaxiSummaryRow(
                      icon: Icons.route_rounded,
                      label: l10n.runtimeTaxiDistanceValueLabel,
                      value: '${_distanceKm.toStringAsFixed(1)} km',
                    ),
                    const SizedBox(height: 10),
                    _TaxiSummaryRow(
                      icon: Icons.schedule_rounded,
                      label: l10n.runtimeTaxiEtaLabel,
                      value: '$_etaMinutes min',
                    ),
                    const SizedBox(height: 16),
                    _FareEstimateCard(
                      lowIqd: estimate.lowIqd,
                      highIqd: estimate.highIqd,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _fareController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '${estimate.suggestedIqd}',
                        labelText: l10n.runtimeTaxiFareFieldLabel,
                        prefixIcon: const Icon(Icons.payments_outlined),
                      ),
                    ),
                    if (fareBelowSuggested) ...[
                      const SizedBox(height: 10),
                      Text(
                        l10n.runtimeTaxiFareWarning,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _couponController,
                      decoration: InputDecoration(
                        hintText: 'SAVE10',
                        labelText: l10n.runtimeTaxiCouponFieldLabel,
                        prefixIcon: const Icon(Icons.local_offer_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.runtimeTaxiPayloadPreviewTitle,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '{pickupLabel: "${_pickupController.text.trim()}", '
                              'dropoffLabel: "${_dropoffController.text.trim()}", '
                              'proposedFareIqd: ${parsedFare ?? 0}, '
                              'scheduleMode: "${_timingMode == _RuntimeRideTimingMode.now ? 'now' : 'scheduled'}"}',
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_submittedPayload != null) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_submittedPayload.toString()),
                        ),
                      ),
                    ],
                  ],
                  if (_validationMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _validationMessage!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (_step != _RuntimeRideStep.timing)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _goBack,
                            child: Text(l10n.runtimeTaxiBackAction),
                          ),
                        ),
                      if (_step != _RuntimeRideStep.timing)
                        const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _submitting
                              ? null
                              : isSummary
                              ? () => _submitRide(context)
                              : () => _goNext(context),
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  isSummary
                                      ? l10n.runtimeTaxiSubmitAction
                                      : l10n.runtimeTaxiContinueAction,
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
    );
  }
}

String _formatScheduledDate(DateTime value) {
  final yyyy = value.year.toString().padLeft(4, '0');
  final mm = value.month.toString().padLeft(2, '0');
  final dd = value.day.toString().padLeft(2, '0');
  final hh = value.hour.toString().padLeft(2, '0');
  final min = value.minute.toString().padLeft(2, '0');
  return '$yyyy-$mm-$dd • $hh:$min';
}

class _RuntimeTaxiStepHeader extends StatelessWidget {
  final _RuntimeRideStep step;

  const _RuntimeTaxiStepHeader({required this.step});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = <(_RuntimeRideStep, String, IconData)>[
      (
        _RuntimeRideStep.timing,
        l10n.runtimeTaxiTimingShort,
        Icons.schedule_rounded,
      ),
      (
        _RuntimeRideStep.pickup,
        l10n.runtimeTaxiPickupShort,
        Icons.trip_origin_rounded,
      ),
      (
        _RuntimeRideStep.dropoff,
        l10n.runtimeTaxiDropoffShort,
        Icons.flag_rounded,
      ),
      (
        _RuntimeRideStep.summary,
        l10n.runtimeTaxiSummaryShort,
        Icons.receipt_long_rounded,
      ),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in items) _StatusChip(icon: item.$3, label: item.$2),
      ],
    );
  }
}

class _TaxiSummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _TaxiSummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}

class _RuntimeCurrentRideCard extends StatelessWidget {
  final Map<String, dynamic> ride;

  const _RuntimeCurrentRideCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    final fare =
        _tryReadInt(ride['agreedFareIqd']) ??
        _tryReadInt(ride['proposedFareIqd']) ??
        0;
    final status = _presentRuntimeRideStatus(_tryReadString(ride['status']));
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openRuntimeRideDetails(context, ride),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.requestTaxiTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  _StatusChip(icon: Icons.local_taxi_rounded, label: status),
                ],
              ),
              const SizedBox(height: 12),
              _TaxiSummaryRow(
                icon: Icons.trip_origin_rounded,
                label: context.l10n.runtimeTaxiPickupTitle,
                value: _tryReadString(ride['pickupLabel']),
              ),
              const SizedBox(height: 10),
              _TaxiSummaryRow(
                icon: Icons.flag_rounded,
                label: context.l10n.runtimeTaxiDropoffTitle,
                value: _tryReadString(ride['dropoffLabel']),
              ),
              const SizedBox(height: 10),
              _TaxiSummaryRow(
                icon: Icons.payments_outlined,
                label: context.l10n.taxiEstimatedFareLabel,
                value: '${_formatIqd(fare)} د.ع',
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: () => _openRuntimeRideDetails(context, ride),
                icon: const Icon(Icons.route_rounded),
                label: Text(context.l10n.runtimeDetailsLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _ReelsHubScreen extends StatelessWidget {
  const _ReelsHubScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reelsHubTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: l10n.reelsHubTitle,
            subtitle: l10n.reelsHubSubtitle,
            icon: Icons.ondemand_video_rounded,
          ),
          const SizedBox(height: 16),
          _SectionTitle(title: l10n.reelsFeaturedSectionTitle),
          const SizedBox(height: 12),
          const _ReelPreviewCard(
            title: 'جولة سريعة داخل متجر جديد',
            subtitle: 'عروض يومية وتصوير قصير من داخل المتجر.',
          ),
          const SizedBox(height: 12),
          const _ReelPreviewCard(
            title: 'تحضير طلب صيدلية خلال دقائق',
            subtitle: 'كيف يجهز الطلب قبل خروجه للتوصيل.',
          ),
          const SizedBox(height: 12),
          const _ReelPreviewCard(
            title: 'رحلة تكسي من الباب إلى الوجهة',
            subtitle: 'لمحة سريعة عن تتبع الرحلة داخل التطبيق.',
          ),
        ],
      ),
    );
  }
}

class _RuntimeSharedFeedScreen extends ConsumerWidget {
  const _RuntimeSharedFeedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(_runtimeSocialFeedProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _runtimeText(context, ar: 'الفيد الاجتماعي', en: 'Social feed'),
        ),
      ),
      body: posts.when(
        data: (items) {
          final visibleItems = items.take(12).toList(growable: false);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeroPanel(
                title: _runtimeText(
                  context,
                  ar: 'الفيد الاجتماعي',
                  en: 'Social feed',
                ),
                subtitle: _runtimeText(
                  context,
                  ar: 'هذا السطح يستهلك نفس منشورات السوشل المشتركة بدل أي نسخة مبسطة داخل runtime.',
                  en: 'This surface uses the same shared social posts instead of a simplified runtime-only copy.',
                ),
                icon: Icons.dynamic_feed_rounded,
              ),
              const SizedBox(height: 16),
              if (visibleItems.isEmpty)
                _InfoCard(
                  icon: Icons.dynamic_feed_rounded,
                  title: _runtimeText(
                    context,
                    ar: 'لا توجد منشورات الآن',
                    en: 'No posts right now',
                  ),
                  subtitle: _runtimeText(
                    context,
                    ar: 'سيظهر أحدث محتوى السوشل هنا عندما تتوفر بيانات الفيد.',
                    en: 'Fresh social feed content will appear here once feed data is available.',
                  ),
                )
              else
                for (var i = 0; i < visibleItems.length; i++) ...[
                  SocialMediaCard(post: visibleItems[i]),
                  if (i != visibleItems.length - 1) const SizedBox(height: 12),
                ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _InfoCard(
              icon: Icons.error_outline_rounded,
              title: _runtimeText(
                context,
                ar: 'تعذر تحميل الفيد',
                en: 'Unable to load feed',
              ),
              subtitle: _runtimeText(
                context,
                ar: 'حدثت مشكلة أثناء تحميل منشورات السوشل المشتركة.',
                en: 'A problem occurred while loading shared social posts.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RuntimeSharedSearchScreen extends ConsumerStatefulWidget {
  const _RuntimeSharedSearchScreen();

  @override
  ConsumerState<_RuntimeSharedSearchScreen> createState() =>
      _RuntimeSharedSearchScreenState();
}

class _RuntimeSharedSearchScreenState
    extends ConsumerState<_RuntimeSharedSearchScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(_runtimeSocialSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    ref.read(_runtimeSocialSearchQueryProvider.notifier).state = value;
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(_runtimeSocialSearchQueryProvider).trim();
    final search = ref.watch(_runtimeSocialSearchProvider);
    final hashtags = ref.watch(_runtimeTrendingHashtagsProvider);
    final suggested = ref.watch(_runtimeSuggestedPeopleProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _runtimeText(context, ar: 'البحث الاجتماعي', en: 'Social search'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: _runtimeText(
                context,
                ar: 'ابحث عن حساب أو وسم أو محتوى',
                en: 'Search accounts, hashtags, or content',
              ),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          if (query.isEmpty) ...[
            _SectionTitle(
              title: _runtimeText(
                context,
                ar: 'حسابات مقترحة',
                en: 'Suggested people',
              ),
            ),
            const SizedBox(height: 12),
            suggested.when(
              data: (items) {
                if (items.isEmpty) {
                  return _InfoCard(
                    icon: Icons.person_search_rounded,
                    title: _runtimeText(
                      context,
                      ar: 'لا توجد اقتراحات الآن',
                      en: 'No suggestions right now',
                    ),
                    subtitle: _runtimeText(
                      context,
                      ar: 'سيظهر اقتراح الحسابات هنا عند توفرها.',
                      en: 'Suggested people will appear here when available.',
                    ),
                  );
                }
                final visibleItems = items.take(5).toList(growable: false);
                return Column(
                  children: [
                    for (var i = 0; i < visibleItems.length; i++) ...[
                      SocialSuggestedPersonRow(item: visibleItems[i]),
                      if (i != visibleItems.length - 1)
                        const SizedBox(height: 10),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            _SectionTitle(
              title: _runtimeText(
                context,
                ar: 'وسوم رائجة',
                en: 'Trending hashtags',
              ),
            ),
            const SizedBox(height: 12),
            hashtags.when(
              data: (items) {
                if (items.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: items
                      .take(8)
                      .map(
                        (tag) => _StatusChip(
                          icon: Icons.tag_rounded,
                          label: '#${tag.tag}',
                        ),
                      )
                      .toList(growable: false),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ] else
            search.when(
              data: (results) {
                if (results == null) {
                  return const SizedBox.shrink();
                }
                final users = results.users.take(5).toList(growable: false);
                final posts = results.posts.take(4).toList(growable: false);
                final reels = results.reels.take(3).toList(growable: false);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (users.isNotEmpty) ...[
                      _SectionTitle(
                        title: _runtimeText(
                          context,
                          ar: 'الحسابات',
                          en: 'Accounts',
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < users.length; i++) ...[
                        SocialSuggestedPersonRow(item: users[i]),
                        if (i != users.length - 1) const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 16),
                    ],
                    if (results.hashtags.isNotEmpty) ...[
                      _SectionTitle(
                        title: _runtimeText(
                          context,
                          ar: 'الوسوم',
                          en: 'Hashtags',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: results.hashtags
                            .take(8)
                            .map(
                              (tag) => _StatusChip(
                                icon: Icons.tag_rounded,
                                label: '#${tag.tag}',
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (posts.isNotEmpty) ...[
                      _SectionTitle(
                        title: _runtimeText(
                          context,
                          ar: 'منشورات',
                          en: 'Posts',
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < posts.length; i++) ...[
                        SocialMediaCard(post: posts[i]),
                        if (i != posts.length - 1) const SizedBox(height: 12),
                      ],
                    ],
                    if (reels.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionTitle(
                        title: _runtimeText(context, ar: 'ريلز', en: 'Reels'),
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < reels.length; i++) ...[
                        SocialMediaCard(post: reels[i]),
                        if (i != reels.length - 1) const SizedBox(height: 12),
                      ],
                    ],
                    if (users.isEmpty &&
                        results.hashtags.isEmpty &&
                        posts.isEmpty &&
                        reels.isEmpty)
                      _InfoCard(
                        icon: Icons.search_off_rounded,
                        title: _runtimeText(
                          context,
                          ar: 'لا توجد نتائج',
                          en: 'No results',
                        ),
                        subtitle: _runtimeText(
                          context,
                          ar: 'جرّب كلمات أخرى للبحث داخل السوشل.',
                          en: 'Try different words to search within the social surface.',
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _InfoCard(
                icon: Icons.error_outline_rounded,
                title: _runtimeText(
                  context,
                  ar: 'تعذر إكمال البحث',
                  en: 'Unable to search',
                ),
                subtitle: _runtimeText(
                  context,
                  ar: 'حدثت مشكلة أثناء البحث في السوشل.',
                  en: 'A problem occurred while searching the social surface.',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RuntimeSharedReelsFeedScreen extends ConsumerWidget {
  const _RuntimeSharedReelsFeedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final reels = ref.watch(_runtimeExploreReelsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reelsHubTitle)),
      body: reels.when(
        data: (items) {
          final visibleItems = items.take(8).toList(growable: false);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeroPanel(
                title: _runtimeText(
                  context,
                  ar: 'ريلز اليوم',
                  en: 'Today reels',
                ),
                subtitle: _runtimeText(
                  context,
                  ar: 'هذا السطح أصبح يقرأ من نفس ريلز السوشل المشتركة بدل البطاقات الوهمية القديمة.',
                  en: 'This surface now reads from the shared social reels feed instead of old placeholder cards.',
                ),
                icon: Icons.ondemand_video_rounded,
              ),
              const SizedBox(height: 16),
              if (visibleItems.isEmpty)
                _InfoCard(
                  icon: Icons.ondemand_video_rounded,
                  title: _runtimeText(
                    context,
                    ar: 'لا توجد ريلز الآن',
                    en: 'No reels right now',
                  ),
                  subtitle: _runtimeText(
                    context,
                    ar: 'سيظهر أحدث محتوى السوشل هنا عندما تتوفر بيانات الريلز.',
                    en: 'Fresh social reel content will appear here once reel data is available.',
                  ),
                )
              else
                for (var i = 0; i < visibleItems.length; i++) ...[
                  SocialMediaCard(post: visibleItems[i].post),
                  if (i != visibleItems.length - 1) const SizedBox(height: 12),
                ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _InfoCard(
              icon: Icons.error_outline_rounded,
              title: _runtimeText(
                context,
                ar: 'تعذر تحميل الريلز',
                en: 'Unable to load reels',
              ),
              subtitle: _runtimeText(
                context,
                ar: 'حدثت مشكلة أثناء تحميل ريلز السوشل المشتركة.',
                en: 'A problem occurred while loading shared social reels.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _RuntimeReelsFeedScreen extends ConsumerWidget {
  const _RuntimeReelsFeedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reelsHubTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _HeroPanel(
            title: 'ريلز اليوم',
            subtitle: 'لقطات سريعة من المجتمع والمتاجر والخدمات الأقرب إليك.',
            icon: Icons.ondemand_video_rounded,
          ),
          SizedBox(height: 16),
          _ReelPreviewCard(
            title: 'جولة سريعة داخل متجر جديد',
            subtitle: 'عروض يومية ولمحات قصيرة من داخل المتجر.',
          ),
          SizedBox(height: 12),
          _ReelPreviewCard(
            title: 'تحضير طلب صيدلية خلال دقائق',
            subtitle: 'كيف يجهز الطلب قبل خروجه للتوصيل.',
          ),
          SizedBox(height: 12),
          _ReelPreviewCard(
            title: 'رحلة تكسي من الباب إلى الوجهة',
            subtitle: 'لمحة سريعة عن تتبع الرحلة داخل التطبيق.',
          ),
        ],
      ),
    );
  }
}

class _RuntimeNotificationsHubScreen extends ConsumerWidget {
  const _RuntimeNotificationsHubScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notifications = ref.watch(_runtimeNotificationsProvider);
    final unreadCount = ref.watch(_runtimeUnreadNotificationsCountProvider);
    final hasUnread = unreadCount.maybeWhen(
      data: (value) => value > 0,
      orElse: () => false,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationsHubTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: () {
              ref.invalidate(_runtimeNotificationsProvider);
              ref.invalidate(_runtimeUnreadNotificationsCountProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (hasUnread)
            IconButton(
              tooltip: l10n.notificationsLabel,
              onPressed: () async {
                await ref.read(_runtimeNotificationsApiProvider).markAllRead();
                ref.invalidate(_runtimeNotificationsProvider);
                ref.invalidate(_runtimeUnreadNotificationsCountProvider);
              },
              icon: const Icon(Icons.done_all_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: l10n.notificationsHubTitle,
            subtitle: l10n.notificationsHubSubtitle,
            icon: Icons.notifications_active_rounded,
          ),
          const SizedBox(height: 16),
          unreadCount.when(
            data: (value) {
              if (value <= 0) return const SizedBox.shrink();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.mark_email_unread_rounded),
                  title: Text(l10n.notificationsLabel),
                  subtitle: Text('$value'),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          if (hasUnread) const SizedBox(height: 12),
          notifications.when(
            data: (items) {
              if (items.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        const Icon(Icons.notifications_none_rounded, size: 48),
                        const SizedBox(height: 10),
                        Text(
                          l10n.notificationsEmptyTitle,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.notificationsEmptySubtitle,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _RuntimeNotificationTile(notification: items[i]),
                  ],
                ],
              );
            },
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (_, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 48),
                    const SizedBox(height: 10),
                    Text(
                      l10n.notificationsEmptyTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.notificationsEmptySubtitle,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _NotificationsHubScreen extends ConsumerWidget {
  const _NotificationsHubScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // ignore: unused_local_variable
    final notifications = ref.watch(_runtimeNotificationsProvider);
    final unreadCount = ref.watch(_runtimeUnreadNotificationsCountProvider);
    // ignore: unused_local_variable
    final hasUnread = unreadCount.maybeWhen(
      data: (value) => value > 0,
      orElse: () => false,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsHubTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: l10n.notificationsHubTitle,
            subtitle: l10n.notificationsHubSubtitle,
            icon: Icons.notifications_active_rounded,
          ),
          const SizedBox(height: 16),
          const _NotificationTimelineCard(
            icon: Icons.shopping_bag_outlined,
            title: 'تم تجهيز طلبك',
            subtitle: 'مطعم الدار أنهى تجهيز الطلب وبانتظار المندوب.',
          ),
          const SizedBox(height: 12),
          const _NotificationTimelineCard(
            icon: Icons.local_taxi_outlined,
            title: 'الكابتن قريب منك',
            subtitle: 'سيصل خلال دقائق قليلة إلى نقطة الانطلاق.',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Icon(Icons.notifications_none_rounded, size: 48),
                  const SizedBox(height: 10),
                  Text(
                    l10n.notificationsEmptyTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.notificationsEmptySubtitle,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showRuntimeMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _RuntimeOrderTile extends StatelessWidget {
  final Map<String, dynamic> order;

  const _RuntimeOrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final id = _tryReadString(
      order['orderNumber'],
      fallback: '#${_tryReadInt(order['id']) ?? '-'}',
    );
    final status = _presentRuntimeRideStatus(
      _tryReadString(order['status'], fallback: 'pending'),
    );
    final total =
        _tryReadInt(order['total']) ??
        _tryReadInt(order['grandTotal']) ??
        _tryReadInt(order['subtotal']) ??
        0;
    final merchantName = _tryReadString(
      order['merchantName'] ?? order['merchant'] ?? order['storeName'],
      fallback: l10n.storesLabel,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openRuntimeOrderDetails(context, order),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(id, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      merchantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(status),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(_formatIqd(total)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuntimeNotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;

  const _RuntimeNotificationTile({required this.notification});

  IconData _resolveIcon(String type) {
    switch (type) {
      case 'order':
      case 'order_status':
        return Icons.shopping_bag_outlined;
      case 'taxi':
      case 'ride':
        return Icons.local_taxi_outlined;
      case 'chat':
      case 'message':
        return Icons.chat_bubble_outline_rounded;
      default:
        return Icons.notifications_active_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = _tryReadString(
      notification['title'] ?? notification['subject'],
      fallback: l10n.notificationsLabel,
    );
    final body = _tryReadString(
      notification['body'] ?? notification['message'],
      fallback: l10n.notificationsEmptySubtitle,
    );
    final type = _tryReadString(notification['type'], fallback: '');
    final createdAt = _tryReadString(notification['createdAt'], fallback: '');
    final isRead =
        notification['readAt'] != null ||
        notification['isRead'] == true ||
        notification['read'] == true;
    return Card(
      child: ListTile(
        onTap: () async {
          await _openRuntimeNotificationDetails(context, notification);
        },
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(_resolveIcon(type)),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(createdAt, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
        trailing: isRead
            ? const Icon(Icons.done_all_rounded, size: 18)
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }
}

class _RuntimeOrderDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> order;

  const _RuntimeOrderDetailsScreen({required this.order});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final orderId = _tryReadString(
      order['orderNumber'],
      fallback: '#${_tryReadInt(order['id']) ?? '-'}',
    );
    final merchantName = _tryReadString(
      order['merchantName'] ?? order['merchant'] ?? order['storeName'],
      fallback: l10n.storesLabel,
    );
    final status = _presentRuntimeRideStatus(
      _tryReadString(order['status'], fallback: 'pending'),
    );
    final total =
        _tryReadInt(order['total']) ??
        _tryReadInt(order['grandTotal']) ??
        _tryReadInt(order['subtotal']) ??
        0;

    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.ordersLabel} - ${l10n.runtimeDetailsLabel}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: orderId,
            subtitle: merchantName,
            icon: Icons.receipt_long_rounded,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TaxiSummaryRow(
                    icon: Icons.storefront_rounded,
                    label: l10n.storesLabel,
                    value: merchantName,
                  ),
                  const SizedBox(height: 10),
                  _TaxiSummaryRow(
                    icon: Icons.info_outline_rounded,
                    label: l10n.runtimeDetailsLabel,
                    value: status,
                  ),
                  const SizedBox(height: 10),
                  _TaxiSummaryRow(
                    icon: Icons.payments_outlined,
                    label: l10n.taxiEstimatedFareLabel,
                    value: '${_formatIqd(total)} IQD',
                  ),
                  if (_tryReadString(
                    order['createdAt'],
                    fallback: '',
                  ).isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _TaxiSummaryRow(
                      icon: Icons.schedule_rounded,
                      label: l10n.runtimeTodayLabel,
                      value: _tryReadString(order['createdAt'], fallback: ''),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _openRuntimeFeaturePage(
                    context,
                    _RuntimeFeatureDestination.stores,
                  ),
                  icon: const Icon(Icons.storefront_rounded),
                  label: Text(l10n.runtimeOpenLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.done_rounded),
                  label: Text(l10n.commonContinue),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RuntimeRideDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> ride;

  const _RuntimeRideDetailsScreen({required this.ride});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rideId = '#${_tryReadInt(ride['id']) ?? '-'}';
    final fare =
        _tryReadInt(ride['agreedFareIqd']) ??
        _tryReadInt(ride['proposedFareIqd']) ??
        0;
    final status = _tryReadString(ride['status'], fallback: 'pending');
    final normalizedStatus = status.toLowerCase();
    final canCancel =
        !normalizedStatus.contains('cancel') &&
        !normalizedStatus.contains('complete') &&
        !normalizedStatus.contains('delivered');
    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.requestTaxiTitle} - ${l10n.runtimeDetailsLabel}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: rideId,
            subtitle: _presentRuntimeRideStatus(status),
            icon: Icons.local_taxi_rounded,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TaxiSummaryRow(
                    icon: Icons.trip_origin_rounded,
                    label: l10n.runtimeTaxiPickupTitle,
                    value: _tryReadString(ride['pickupLabel']),
                  ),
                  const SizedBox(height: 10),
                  _TaxiSummaryRow(
                    icon: Icons.flag_rounded,
                    label: l10n.runtimeTaxiDropoffTitle,
                    value: _tryReadString(ride['dropoffLabel']),
                  ),
                  const SizedBox(height: 10),
                  _TaxiSummaryRow(
                    icon: Icons.payments_outlined,
                    label: l10n.taxiEstimatedFareLabel,
                    value: '${_formatIqd(fare)} IQD',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const _TaxiHubScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.route_rounded),
                  label: Text(l10n.runtimeTrackRideLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shareRuntimeRide(context, ride),
                  icon: const Icon(Icons.share_rounded),
                  label: Text(l10n.runtimeShareRideLabel),
                ),
              ),
            ],
          ),
          if (canCancel) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _cancelRuntimeRide(context, ride),
                icon: const Icon(Icons.close_rounded),
                label: Text(l10n.runtimeCancelRideLabel),
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () {
              final container = ProviderScope.containerOf(
                context,
                listen: false,
              );
              container.invalidate(_runtimeCurrentRideProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.commonRefresh),
          ),
        ],
      ),
    );
  }
}

class _RuntimeNotificationDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> notification;

  const _RuntimeNotificationDetailsScreen({required this.notification});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = _tryReadString(
      notification['title'] ?? notification['subject'],
      fallback: l10n.notificationsLabel,
    );
    final body = _tryReadString(
      notification['body'] ?? notification['message'],
      fallback: l10n.notificationsEmptySubtitle,
    );
    final type = _tryReadString(notification['type'], fallback: '-');
    final createdAt = _tryReadString(notification['createdAt'], fallback: '');

    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.notificationsLabel} - ${l10n.runtimeDetailsLabel}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: title,
            subtitle: body,
            icon: Icons.notifications_active_rounded,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TaxiSummaryRow(
                    icon: Icons.category_outlined,
                    label: l10n.runtimeDetailsLabel,
                    value: type,
                  ),
                  if (createdAt.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _TaxiSummaryRow(
                      icon: Icons.schedule_rounded,
                      label: l10n.runtimeTodayLabel,
                      value: createdAt,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const _RuntimeNotificationsHubScreen(),
              ),
            ),
            icon: const Icon(Icons.notifications_active_rounded),
            label: Text(l10n.runtimeOpenLabel),
          ),
        ],
      ),
    );
  }
}

class _StorePreviewCard extends StatelessWidget {
  final MerchantModel merchant;

  const _StorePreviewCard({required this.merchant});

  IconData _resolveIcon() {
    switch (merchant.activityType) {
      case 'restaurant':
        return Icons.restaurant_menu_rounded;
      case 'pharmacy':
        return Icons.local_pharmacy_rounded;
      case 'supermarket':
        return Icons.shopping_cart_rounded;
      case 'coffee_drinks':
        return Icons.coffee_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }

  String _deliveryEta() {
    switch (merchant.activityType) {
      case 'pharmacy':
        return '15-25 min';
      case 'restaurant':
        return '25-35 min';
      case 'supermarket':
        return '20-30 min';
      case 'coffee_drinks':
        return '18-28 min';
      default:
        return '20-35 min';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final badges = merchant.badges.take(3).toList(growable: false);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openRuntimeStoreDetails(context, merchant),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(_resolveIcon()),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          merchant.name,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          merchant.description ??
                              merchant.tagline ??
                              merchant.activityType,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _StatusChip(
                    icon: merchant.isOpen
                        ? Icons.check_circle_rounded
                        : Icons.schedule_rounded,
                    label: merchant.isOpen
                        ? l10n.storesOpenStatus
                        : l10n.storesClosedStatus,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    icon: Icons.delivery_dining_rounded,
                    label: '${l10n.storesDeliveryEtaLabel}: ${_deliveryEta()}',
                  ),
                  if (merchant.hasFreeDeliveryOffer)
                    _StatusChip(
                      icon: Icons.local_shipping_rounded,
                      label: l10n.storesFreeDeliveryBadge,
                    ),
                  if (merchant.hasDiscountOffer)
                    _StatusChip(
                      icon: Icons.local_offer_rounded,
                      label: l10n.storesOfferBadge,
                    ),
                  for (final badge in badges)
                    _StatusChip(icon: Icons.label_rounded, label: badge),
                ],
              ),
              if ((merchant.workingHours ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(merchant.workingHours!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StoreDetailsScreen extends StatelessWidget {
  final MerchantModel merchant;

  const _StoreDetailsScreen({required this.merchant});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final badges = merchant.badges.take(6).toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: Text(merchant.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: merchant.name,
            subtitle:
                merchant.description ??
                merchant.tagline ??
                merchant.activityType,
            icon: Icons.storefront_rounded,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusChip(
                        icon: merchant.isOpen
                            ? Icons.check_circle_rounded
                            : Icons.schedule_rounded,
                        label: merchant.isOpen
                            ? l10n.storesOpenStatus
                            : l10n.storesClosedStatus,
                      ),
                      if (merchant.hasFreeDeliveryOffer)
                        _StatusChip(
                          icon: Icons.local_shipping_rounded,
                          label: l10n.storesFreeDeliveryBadge,
                        ),
                      if (merchant.hasDiscountOffer)
                        _StatusChip(
                          icon: Icons.local_offer_rounded,
                          label: l10n.storesOfferBadge,
                        ),
                    ],
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final badge in badges)
                          _StatusChip(icon: Icons.label_rounded, label: badge),
                      ],
                    ),
                  ],
                  if ((merchant.workingHours ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      merchant.workingHours!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if ((merchant.serviceAreaNote ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      merchant.serviceAreaNote!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if ((merchant.phone ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(merchant.phone!, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          _StoreEntryActionsScreen(merchant: merchant),
                    ),
                  ),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(l10n.runtimeOpenLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const _TaxiHubScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.local_taxi_rounded),
                  label: Text(l10n.requestTaxiTitle),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StoreEntryActionsScreen extends StatelessWidget {
  final MerchantModel merchant;

  const _StoreEntryActionsScreen({required this.merchant});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text('${merchant.name} - ${l10n.runtimeOpenLabel}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: merchant.name,
            subtitle: merchant.description ?? l10n.discoverStoresSubtitle,
            icon: Icons.shopping_bag_outlined,
          ),
          const SizedBox(height: 16),
          _InfoCard(
            icon: Icons.shopping_cart_rounded,
            title: l10n.runtimeOpenLabel,
            subtitle: merchant.supportsChat
                ? l10n.notificationsPermissionDescription
                : l10n.discoverStoresSubtitle,
          ),
          const SizedBox(height: 12),
          if (merchant.supportsChat)
            _InfoCard(
              icon: Icons.chat_bubble_outline_rounded,
              title: l10n.notificationsLabel,
              subtitle: l10n.notificationsHubSubtitle,
            ),
          if (merchant.supportsPharmacyWorkflow) ...[
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.local_pharmacy_rounded,
              title: l10n.storesCategoryPharmacies,
              subtitle: l10n.discoverStoresSubtitle,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const _StoresHubScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.storefront_rounded),
                  label: Text(l10n.storesLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.done_rounded),
                  label: Text(l10n.commonContinue),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FareEstimateCard extends StatelessWidget {
  final int lowIqd;
  final int highIqd;

  const _FareEstimateCard({required this.lowIqd, required this.highIqd});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text(l10n.taxiEstimatedFareLabel)),
          Text(
            '${_formatIqd(lowIqd)} - ${_formatIqd(highIqd)}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ReelPreviewCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ReelPreviewCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.85),
                    Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.75),
                  ],
                ),
              ),
              child: const Center(
                child: Icon(Icons.play_circle_fill_rounded, size: 54),
              ),
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle),
          ],
        ),
      ),
    );
  }
}

class _NotificationTimelineCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _NotificationTimelineCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.secondary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _HeroPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(subtitle, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(icon, color: theme.colorScheme.onPrimary, size: 34),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.secondary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.secondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}
