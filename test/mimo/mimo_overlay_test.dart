import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/core/theme/theme_preset.dart';
import 'package:maslaki/features/mimo/mimo_character.dart';
import 'package:maslaki/features/mimo/mimo_overlay.dart';
import 'package:maslaki/features/mimo/mimo_perch.dart';
import 'package:maslaki/features/orders/state/cart_controller.dart';
import 'package:maslaki/features/products/models/product_model.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _Settings extends AppSettingsController {
  _Settings() : super(SecureStore(), storageScope: 'test') {
    state = AppSettingsState.initial().copyWith(
      locale: const Locale('ar'),
      animationsEnabled: true,
      weatherEffectsEnabled: false,
      themePreset: AppThemePreset.midnightBlue,
      loaded: true,
    );
  }

  @override
  Future<void> bootstrap() async {}
}

const _homeKey = Key('home-perch');
const _cardKey = Key('lower-card');

Widget _page() {
  Widget card(Key key, double h) => Container(
    key: key,
    height: h,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
  );
  return Scaffold(
    backgroundColor: const Color(0xFFECE9DF),
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 140),
          MimoPerch(home: true, alignX: 0.2, child: card(_homeKey, 60)),
          const SizedBox(height: 220),
          card(_cardKey, 120),
        ],
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

double _top(WidgetTester tester, Key key) =>
    tester.getTopLeft(find.byKey(key)).dy;

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'mimo_greeted_v1': true});
  });

  testWidgets('Mimo sits home, is carried onto a card, falls, climbs, hides', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late _Settings settings;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsControllerProvider.overrideWith((ref) {
            settings = _Settings();
            return settings;
          }),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: MimoOverlay(openChat: null, child: _page()),
        ),
      ),
    );
    MimoOverlayState state() =>
        tester.state<MimoOverlayState>(find.byType(MimoOverlay));
    double feet() => state().position.dy + MimoOverlay.height * 0.935;

    // Drops in from the top and sits on the home perch.
    await _frames(tester, 1500);
    expect(state().mode, MimoMode.seated);
    expect(feet(), closeTo(_top(tester, _homeKey) + 2, 3));

    // A seated Mimo paints his own idle animation without rebuilding the
    // customer shell every frame.
    final mimo = find.byType(MimoCharacter).last;
    final settledMimo = tester.widget<MimoCharacter>(mimo);
    await _frames(tester, 500);
    expect(tester.widget<MimoCharacter>(mimo), same(settledMimo));

    // Long-press to pick him up, carry him above the lower card, let go.
    final gesture = await tester.startGesture(tester.getCenter(mimo));
    await _frames(tester, 400);
    expect(state().mode, MimoMode.dragging);
    final cardTop = _top(tester, _cardKey);
    await gesture.moveTo(Offset(200, cardTop - 120));
    await _frames(tester, 200);
    await gesture.up();
    await _frames(tester, 1200);
    expect(state().mode, MimoMode.seated);
    expect(feet(), closeTo(cardTop + 2, 3), reason: 'landed on the card');

    // Dropped below everything: hits the floor, then climbs up to the card.
    final g2 = await tester.startGesture(tester.getCenter(mimo));
    await _frames(tester, 400);
    await g2.moveTo(const Offset(200, 740));
    await _frames(tester, 100);
    await g2.up();
    await _frames(tester, 5000);
    expect(state().mode, MimoMode.seated);
    expect(feet(), closeTo(cardTop + 2, 3), reason: 'climbed back up');

    // Tap: a little reaction with a speech bubble.
    await tester.tap(find.byType(MimoCharacter).last);
    await _frames(tester, 100);
    expect(state().bubble, isNotNull);

    // Switching him off waves goodbye and removes him.
    await settings.setMimoEnabled(false);
    await _frames(tester, 1500);
    expect(state().mode, MimoMode.off);
    expect(find.byType(MimoCharacter), findsNothing);

    // Wait out pending reaction timers.
    await _frames(tester, 3000);
  });

  testWidgets('Mimo reacts to a huge cart and to ordering from 2 stores', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        appSettingsControllerProvider.overrideWith((ref) => _Settings()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: MimoOverlay(openChat: null, child: _page()),
        ),
      ),
    );
    await _frames(tester, 1500);
    MimoOverlayState state() =>
        tester.state<MimoOverlayState>(find.byType(MimoOverlay));
    final cart = container.read(cartControllerProvider.notifier);
    ProductModel product(int id, int merchant) => ProductModel.fromJson({
      'id': id,
      'merchant_id': merchant,
      'name': 'p$id',
      'price': 1000,
      'is_available': true,
    });

    cart.addItem(product: product(1, 1), merchantId: 1, merchantName: 'A');
    await _frames(tester, 100);
    cart.addItem(product: product(2, 2), merchantId: 2, merchantName: 'B');
    await _frames(tester, 200);
    expect(state().bubble, contains('مثلكي'), reason: 'multi-store fun fact');
    expect(state().mood, MimoMood.wink);

    await _frames(tester, 3600);
    cart.addItem(
      product: product(3, 1),
      merchantId: 1,
      merchantName: 'A',
      quantity: 7,
    );
    await _frames(tester, 200);
    expect(state().bubble, 'واو! وحدك راح تاكل كل هذا!!!!!');
    expect(state().mood, MimoMood.shocked);
    await _frames(tester, 1600);
    expect(state().bubble, contains('بالعافية'));
    expect(state().mood, MimoMood.laughing);
    await _frames(tester, 3000);
  });

  testWidgets(
    'Mimo respects reduced motion and keeps bubbles on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(220, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsControllerProvider.overrideWith((ref) => _Settings()),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: MimoOverlay(openChat: null, child: _page()),
          ),
        ),
      );

      await _frames(tester, 1500);
      final state = tester.state<MimoOverlayState>(find.byType(MimoOverlay));
      final mimo = tester.widget<MimoCharacter>(
        find.byType(MimoCharacter).last,
      );
      expect(mimo.animate, isFalse);

      await tester.tap(find.byType(MimoCharacter).last);
      await tester.pump();
      final bubble = state.bubble;
      expect(bubble, isNotNull);
      final bubbleRect = tester.getRect(find.byKey(ValueKey(bubble)));
      expect(bubbleRect.left, greaterThanOrEqualTo(0));
      expect(bubbleRect.right, lessThanOrEqualTo(220));

      await _frames(tester, 3000);
    },
  );
}
