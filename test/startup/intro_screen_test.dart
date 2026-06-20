import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/features/startup/state/app_startup_controller.dart';
import 'package:maslaki/features/startup/ui/intro_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeStartupController extends AppStartupController {
  bool retryCalled = false;

  _FakeStartupController(AppStartupState seededState)
    : super(store: SecureStore(), dio: Dio(), initialFirstLaunchDone: false) {
    state = seededState;
  }

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> checkServerReadiness() async {
    retryCalled = true;
  }

  @override
  Future<void> completeFirstLaunch() async {}
}

Widget _wrap(_FakeStartupController controller) {
  return ProviderScope(
    overrides: [appStartupControllerProvider.overrideWith((ref) => controller)],
    child: const MaterialApp(
      locale: Locale('en'),
      supportedLocales: [Locale('ar'), Locale('en')],
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: IntroScreen(),
    ),
  );
}

void main() {
  testWidgets('intro screen renders branded animated splash while waiting', (
    tester,
  ) async {
    final controller = _FakeStartupController(
      const AppStartupState(
        phase: AppStartupPhase.checkingServer,
        initialized: true,
        error: null,
        attempts: 2,
      ),
    );

    await tester.pumpWidget(_wrap(controller));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('Preparing Maslaki'), findsOneWidget);
    expect(find.text('Everything around you.'), findsOneWidget);
    expect(find.text('Maslaki Restaurants'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('intro screen exposes retry action on startup failure', (
    tester,
  ) async {
    final controller = _FakeStartupController(
      const AppStartupState(
        phase: AppStartupPhase.serverCheckFailed,
        initialized: true,
        error: 'Connection timeout while contacting server.',
        attempts: 3,
      ),
    );

    await tester.pumpWidget(_wrap(controller));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();

    expect(controller.retryCalled, isTrue);
  });
}
