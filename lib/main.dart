import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/settings/app_settings_controller.dart';
import 'core/theme/app_backdrop.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/ui/admin_dashboard_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/auth/ui/merchants_list_screen.dart';
import 'features/delivery/ui/delivery_dashboard_screen.dart';
import 'features/owner/ui/owner_dashboard_screen.dart';

void main() {
  runApp(const ProviderScope(child: BestOfferApp()));
}

class BestOfferApp extends ConsumerStatefulWidget {
  const BestOfferApp({super.key});

  @override
  ConsumerState<BestOfferApp> createState() => _BestOfferAppState();
}

class _BestOfferAppState extends ConsumerState<BestOfferApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(authControllerProvider.notifier).bootstrap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(appSettingsControllerProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: settings.locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      themeAnimationDuration: const Duration(milliseconds: 450),
      themeAnimationCurve: Curves.easeOutCubic,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return AppBackdrop(
          animationsEnabled: settings.animationsEnabled,
          weatherEffectsEnabled: settings.weatherEffectsEnabled,
          child: child,
        );
      },
      home: auth.isAuthed
          ? (auth.isBackoffice
                ? const AdminDashboardScreen()
                : auth.isOwner
                ? const OwnerDashboardScreen()
                : auth.isDelivery
                ? const DeliveryDashboardScreen()
                : const MerchantsListScreen())
          : const LoginScreen(),
    );
  }
}
