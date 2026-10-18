import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/core/theme/theme_preset.dart';
import 'package:maslaki/features/mimo/chat/mimo_chat_api.dart';
import 'package:maslaki/features/mimo/mimo_character.dart';
import 'package:maslaki/features/mimo/mimo_navigation.dart';
import 'package:maslaki/features/mimo/mimo_overlay.dart';
import 'package:maslaki/features/mimo/mimo_perch.dart';
import 'package:maslaki/features/orders/models/order_model.dart';
import 'package:maslaki/features/orders/state/cart_controller.dart';
import 'package:maslaki/features/orders/state/orders_controller.dart';
import 'package:maslaki/features/products/models/product_model.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _Settings extends AppSettingsController {
  _Settings({bool proactive = true})
    : super(SecureStore(), storageScope: 'test') {
    state = AppSettingsState.initial().copyWith(
      locale: const Locale('ar'),
      animationsEnabled: false,
      weatherEffectsEnabled: false,
      themePreset: AppThemePreset.midnightBlue,
      mimoProactive: proactive,
      loaded: true,
    );
  }

  @override
  Future<void> bootstrap() async {}
}

class _Orders extends OrdersController {
  _Orders(super.ref);

  void setOrders(List<OrderModel> orders) {
    state = state.copyWith(orders: orders);
  }
}

class _NudgeApi extends MimoChatApi {
  _NudgeApi(this.next) : super(Dio());

  Map<String, dynamic>? next;
  final events = <String>[];
  int nudgeCalls = 0;

  @override
  Future<Map<String, dynamic>?> nudge(String lang) async {
    nudgeCalls++;
    return next;
  }

  @override
  Future<void> proactiveEvent({
    required String nudgeId,
    required String event,
    String? kind,
  }) async {
    events.add('$event:$nudgeId');
  }

  @override
  Stream<MimoStreamEvent> chat({
    required List<Map<String, dynamic>> messages,
    required String lang,
    Map<String, dynamic> context = const {},
    String summary = '',
    List<Map<String, dynamic>> attachments = const [],
    CancelToken? cancelToken,
  }) async* {
    yield const MimoStreamEvent('delta', {'text': 'تمام'});
    yield const MimoStreamEvent('done', {});
  }
}

OrderModel _order(String status) => OrderModel.fromJson({
  'id': 55,
  'merchant_id': 1,
  'customer_user_id': 7,
  'merchant_name': 'مشاوي أبو علي',
  'status': status,
  'items': const [],
});

Widget _page() => Scaffold(
  body: Column(
    children: [
      const SizedBox(height: 160),
      MimoPerch(
        home: true,
        alignX: 0.2,
        child: Container(height: 60, color: Colors.white),
      ),
    ],
  ),
);

Future<void> _frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  _NudgeApi? api,
  bool proactive = true,
  List<String>? chatOpens,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      appSettingsControllerProvider.overrideWith(
        (ref) => _Settings(proactive: proactive),
      ),
      ordersControllerProvider.overrideWith((ref) => _Orders(ref)),
      mimoChatApiProvider.overrideWithValue(api ?? _NudgeApi(null)),
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
        home: MimoOverlay(
          openChat: (_) async => chatOpens?.add('open'),
          child: _page(),
        ),
      ),
    ),
  );
  await _frames(tester, 1500);
  return container;
}

MimoOverlayState _state(WidgetTester tester) =>
    tester.state<MimoOverlayState>(find.byType(MimoOverlay));

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'mimo_greeted_v1': true});
  });

  test('order status lines speak Iraqi and name the store', () {
    expect(
      mimoOrderStatusLine('on_the_way', 'مشاوي أبو علي', ar: true)?.$2,
      'طلبك بالطريق! 🛵 حضّر نفسك',
    );
    final approved = mimoOrderStatusLine('approved', 'مشاوي', ar: true)!;
    expect(approved.$1, MimoMood.happy);
    expect(approved.$2, contains('من مشاوي'));
    expect(
      mimoOrderStatusLine('cancelled_by_store', '', ar: true)?.$1,
      MimoMood.sad,
    );
    expect(mimoOrderStatusLine('pending', 'x', ar: true), isNull);
    expect(
      mimoOrderStatusLine('delivered', '', ar: false)?.$2,
      'Delivered! Enjoy 😋',
    );
  });

  testWidgets('Mimo announces order status changes (not the first load)', (
    tester,
  ) async {
    final container = await _pump(tester);
    final orders = container.read(ordersControllerProvider.notifier) as _Orders;

    orders.setOrders([_order('pending')]);
    await _frames(tester, 100);
    expect(_state(tester).bubble, isNull, reason: 'first load is silent');

    orders.setOrders([_order('on_the_way')]);
    await _frames(tester, 100);
    expect(_state(tester).bubble, 'طلبك بالطريق! 🛵 حضّر نفثك');
    expect(_state(tester).mood, MimoMood.dancing);
    await _frames(tester, 5000);

    orders.setOrders([_order('cancelled_by_store')]);
    await _frames(tester, 100);
    expect(_state(tester).bubble, contains('انلغى طلبك'));
    expect(_state(tester).bubbleTappable, isTrue, reason: 'tap → help chat');
    await _frames(tester, 10000);
  });

  testWidgets('"ميمو يبادر" off keeps him quiet about orders', (tester) async {
    final container = await _pump(tester, proactive: false);
    final orders = container.read(ordersControllerProvider.notifier) as _Orders;
    orders.setOrders([_order('preparing')]);
    await _frames(tester, 100);
    orders.setOrders([_order('on_the_way')]);
    await _frames(tester, 100);
    expect(_state(tester).bubble, isNull);
    await _frames(tester, 10000);
  });

  testWidgets('daily nudge shows once, tap opens the chat with its message', (
    tester,
  ) async {
    final api = _NudgeApi({
      'id': 'habit:2026-10-18',
      'kind': 'habit',
      'mood': 'dancing',
      'text': 'مصطفى، الخميس سعيد! تريد نفس طلبك من مشاوي أبو علي؟',
      'action': {'type': 'chat', 'message': 'اريد نفس طلبي من مشاوي أبو علي'},
    });
    final opens = <String>[];
    await _pump(tester, api: api, chatOpens: opens);
    await _frames(tester, 9000);

    expect(api.nudgeCalls, 1);
    expect(_state(tester).bubble, contains('الخميث ثعيد'));
    expect(_state(tester).bubbleTappable, isTrue);
    expect(api.events, ['shown:habit:2026-10-18']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mimo_nudge_day'), isNotNull);

    await tester.tap(find.byIcon(Icons.touch_app_rounded));
    await _frames(tester, 300);
    expect(api.events.last, 'tapped:habit:2026-10-18');
    expect(opens, ['open']);
    expect(_state(tester).bubble, isNull);
    await _frames(tester, 3000);
  });

  testWidgets('no second nudge on the same day', (tester) async {
    SharedPreferences.setMockInitialValues({
      'mimo_greeted_v1': true,
      'mimo_nudge_day': DateTime.now().toIso8601String().substring(0, 10),
    });
    final api = _NudgeApi({'id': 'x', 'text': 'hi'});
    await _pump(tester, api: api);
    await _frames(tester, 9500);
    expect(api.nudgeCalls, 0);
  });

  testWidgets('forgotten cart: one reminder that opens the cart', (
    tester,
  ) async {
    final before = mimoForgottenCartDelay;
    mimoForgottenCartDelay = const Duration(seconds: 2);
    addTearDown(() => mimoForgottenCartDelay = before);
    final container = await _pump(tester);
    final requests = <String?>[];
    void onNav() => requests.add(MimoNavigation.requests.value?.section);
    MimoNavigation.requests.addListener(onNav);
    addTearDown(() => MimoNavigation.requests.removeListener(onNav));

    container
        .read(cartControllerProvider.notifier)
        .addItem(
          product: ProductModel.fromJson({
            'id': 1,
            'merchant_id': 1,
            'name': 'كباب',
            'price': 1000,
            'is_available': true,
          }),
          merchantId: 1,
          merchantName: 'A',
        );
    await _frames(tester, 2400);
    expect(_state(tester).bubble, contains('نثيت الثلة'));
    await tester.tap(find.byIcon(Icons.touch_app_rounded));
    await _frames(tester, 100);
    expect(requests.whereType<String>(), ['cart']);
    await _frames(tester, 8000);
  });
}
