import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/core/theme/theme_preset.dart';
import 'package:maslaki/features/mimo/guide/mimo_target.dart';
import 'package:maslaki/features/mimo/mimo_overlay.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _Settings extends AppSettingsController {
  _Settings() : super(SecureStore(), storageScope: 'test') {
    state = AppSettingsState.initial().copyWith(
      locale: const Locale('ar'),
      animationsEnabled: true,
      weatherEffectsEnabled: false,
      themePreset: AppThemePreset.midnightBlue,
      mimoProactive: false,
      loaded: true,
    );
  }

  @override
  Future<void> bootstrap() async {}
}

final taps = <String>[];

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    void open() {
      taps.add('section:shopping');
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const _Market()));
    }

    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 200),
          MimoTarget(
            id: 'section:shopping',
            label: 'التسوق',
            onTap: open,
            child: const SizedBox(width: 80, height: 60, child: Text('التسوق')),
          ),
        ],
      ),
    );
  }
}

class _Market extends StatefulWidget {
  const _Market();

  @override
  State<_Market> createState() => _MarketState();
}

class _MarketState extends State<_Market> {
  String? group;
  static final scroll = ScrollController();

  @override
  Widget build(BuildContext context) {
    void openStore(int i) {
      taps.add('store:$i');
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(body: Center(child: Text('store-$i'))),
        ),
      );
    }

    return Scaffold(
      body: ListView(
        controller: scroll,
        children: [
          const SizedBox(height: 120),
          MimoTarget(
            id: 'shop-group:food',
            label: 'مطاعم',
            onTap: () {
              taps.add('shop-group:food');
              setState(() => group = 'food');
            },
            child: const SizedBox(height: 60, child: Text('مطاعم')),
          ),
          for (var i = 1; i <= 40; i++)
            MimoTarget(
              id: 'store:$i',
              label: 'متجر $i',
              onTap: () => openStore(i),
              child: SizedBox(height: 120, child: Text('متجر $i')),
            ),
        ],
      ),
    );
  }
}

Future<void> _frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  taps.clear();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsControllerProvider.overrideWith((ref) => _Settings()),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MimoOverlay(openChat: null, child: child!),
        home: const _Home(),
      ),
    ),
  );
  await _frames(tester, 1500);
}

MimoOverlayState _state(WidgetTester tester) =>
    tester.state<MimoOverlayState>(find.byType(MimoOverlay));

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'mimo_greeted_v1': true});
  });

  testWidgets(
    'Mimo taps the section, the category, scrolls to the store, checks its '
    'name and opens it',
    (tester) async {
      await _pump(tester);
      bool? result;
      MimoGuide.run(const [
        MimoTourStep('section:shopping'),
        MimoTourStep('shop-group:food'),
        MimoTourStep('store:37', expectName: 'متجر 37'),
      ]).then((r) => result = r);

      await _frames(tester, 400);
      expect(_state(tester).touring, isTrue);
      await _frames(tester, 9000);

      expect(result, isTrue);
      expect(taps, ['section:shopping', 'shop-group:food', 'store:37']);
      expect(find.text('store-37'), findsOneWidget);
      expect(_MarketState.scroll.offset, greaterThan(2000), reason: 'scrolled');
      await _frames(tester, 2000);
    },
  );

  testWidgets('a different name on the card → Mimo refuses to tap it', (
    tester,
  ) async {
    await _pump(tester);
    bool? result;
    MimoGuide.run(const [
      MimoTourStep('section:shopping'),
      MimoTourStep('store:2', expectName: 'مطعم غير موجود'),
    ]).then((r) => result = r);
    await _frames(tester, 1800);

    expect(_state(tester).bubble, contains('مو هذا'));
    expect(result, isFalse);
    expect(taps, ['section:shopping']);
    expect(find.text('store-2'), findsNothing);
    await _frames(tester, 3000);
  });

  testWidgets('a target that never appears → false so the app opens it '
      'directly', (tester) async {
    await _pump(tester);
    bool? result;
    MimoGuide.run(const [
      MimoTourStep('section:nowhere'),
    ]).then((r) => result = r);
    await _frames(tester, 7000);
    expect(result, isFalse);
    expect(taps, isEmpty);
    await _frames(tester, 2000);
  });
}
