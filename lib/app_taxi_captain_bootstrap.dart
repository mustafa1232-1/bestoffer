import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'core/i18n/app_localizations_context.dart';
import 'core/media/media_cache_service.dart';
import 'core/settings/app_settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/maslaki_brand_mark.dart';
import 'core/widgets/maslaki_wordmark.dart';
import 'features/auth/presentation/role_login_screen.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/taxi/ui/taxi_captain_dashboard_screen.dart';
import 'l10n/app_localizations.dart';

/// Dedicated bootstrap for taxi captain app surface in the root app.
///
/// Uses the full captain workspace (`TaxiCaptainDashboardScreen`) instead of
/// the lightweight runtime shell.
void runTaxiCaptainAppBootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        appSettingsStorageScopeProvider.overrideWithValue('taxi_captain'),
      ],
      child: const MaslakiTaxiCaptainApp(),
    ),
  );
}

class MaslakiTaxiCaptainApp extends ConsumerStatefulWidget {
  const MaslakiTaxiCaptainApp({super.key});

  @override
  ConsumerState<MaslakiTaxiCaptainApp> createState() =>
      _MaslakiTaxiCaptainAppState();
}

class _MaslakiTaxiCaptainAppState extends ConsumerState<MaslakiTaxiCaptainApp> {
  bool _bootstrapped = false;
  bool _roleMismatchLogoutInFlight = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(mediaCacheServiceProvider).scheduleMaintenance();
      await ref.read(authControllerProvider.notifier).bootstrap();
      if (!mounted) return;
      setState(() {
        _bootstrapped = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    Intl.defaultLocale = settings.locale.languageCode;

    if (auth.isAuthed && !auth.isTaxiCaptain && !_roleMismatchLogoutInFlight) {
      _roleMismatchLogoutInFlight = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref.read(authControllerProvider.notifier).logout();
        _roleMismatchLogoutInFlight = false;
      });
    } else if (!auth.isAuthed || auth.isTaxiCaptain) {
      _roleMismatchLogoutInFlight = false;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (ctx) => ctx.l10n.taxiCaptainAppTitle,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.light(preset: settings.themePreset),
      darkTheme: AppTheme.dark(preset: settings.themePreset),
      themeMode: ThemeMode.dark,
      builder: (ctx, child) {
        if (child == null) return const SizedBox.shrink();
        return AppBackdrop(
          animationsEnabled: settings.animationsEnabled,
          weatherEffectsEnabled: settings.weatherEffectsEnabled,
          child: AppResponsiveShell(child: child),
        );
      },
      home: !_bootstrapped
          ? const _TaxiCaptainSplashScreen()
          : auth.isAuthed && auth.isTaxiCaptain
          ? const TaxiCaptainDashboardScreen()
          : const RoleLoginScreen(scope: RoleLoginScope.taxiCaptain),
    );
  }
}

class _TaxiCaptainSplashScreen extends StatelessWidget {
  const _TaxiCaptainSplashScreen();

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: MaslakiCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MaslakiBrandMark(
                  size: 72,
                  shape: MaslakiBrandShape.circle,
                ),
                const SizedBox(height: 16),
                const MaslakiWordmark(
                  arabicSize: 30,
                  subtitle: 'تطبيق الكابتن',
                  crossAxisAlignment: CrossAxisAlignment.center,
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.taxiCaptainAppTitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    backgroundColor: tokens.surfaceSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
