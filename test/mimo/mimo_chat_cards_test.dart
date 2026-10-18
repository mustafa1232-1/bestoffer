import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/core/theme/theme_preset.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/mimo/chat/mimo_chat_api.dart';
import 'package:maslaki/features/mimo/chat/mimo_chat_controller.dart';
import 'package:maslaki/features/mimo/chat/mimo_chat_sheet.dart';
import 'package:maslaki/features/mimo/mimo_character.dart';
import 'package:maslaki/features/mimo/mimo_navigation.dart';
import 'package:maslaki/features/orders/state/cart_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _Settings extends AppSettingsController {
  _Settings() : super(SecureStore(), storageScope: 'test') {
    state = AppSettingsState.initial().copyWith(
      locale: const Locale('ar'),
      animationsEnabled: false,
      weatherEffectsEnabled: false,
      themePreset: AppThemePreset.midnightBlue,
      loaded: true,
    );
  }

  @override
  Future<void> bootstrap() async {}
}

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = AuthState(
      user: UserModel(
        id: 7,
        fullName: 'مصطفى سالم',
        phone: '07701234567',
        role: 'user',
        block: 'A1',
        buildingNumber: '3',
        apartment: '9',
        imageUrl: null,
        workTitle: null,
        workCompany: null,
        preferredLocale: 'ar',
        isSuperAdmin: false,
      ),
      token: 't',
    );
  }

  @override
  Future<void> bootstrap() async {}
}

/// Replays scripted turns and records what the app sent.
class _FakeApi extends MimoChatApi {
  _FakeApi(this.turns) : super(Dio());

  final List<List<MimoStreamEvent>> turns;
  final sent = <List<Map<String, dynamic>>>[];
  final contexts = <Map<String, dynamic>>[];
  final ratings = <bool>[];
  final accepted = <List<Map<String, dynamic>>>[];

  @override
  Future<void> feedback({
    required bool up,
    required String question,
    required String answer,
    String? refs,
  }) async => ratings.add(up);

  @override
  Future<void> cartAdded(List<Map<String, dynamic>> items) async =>
      accepted.add(items);

  @override
  Stream<MimoStreamEvent> chat({
    required List<Map<String, dynamic>> messages,
    required String lang,
    Map<String, dynamic> context = const {},
    String summary = '',
    List<Map<String, dynamic>> attachments = const [],
    CancelToken? cancelToken,
  }) async* {
    sent.add(messages);
    contexts.add(context);
    for (final e in turns.removeAt(0)) {
      yield e;
    }
  }
}

Map<String, dynamic> _p(int id, String name, int price) => {
  'id': id,
  'merchant_id': 1,
  'name': name,
  'price': price,
  'is_available': true,
};

List<List<MimoStreamEvent>> _script() => [
  [
    const MimoStreamEvent('delta', {'text': 'رتبتلك غدا لـ8 والمجموع 90,500'}),
    const MimoStreamEvent('ui', {
      'type': 'quote',
      'exact': true,
      'subtotal': 88000,
      'discounts': 0,
      'delivery': 2000,
      'serviceFee': 500,
      'total': 90500,
    }),
    MimoStreamEvent('ui', {
      'type': 'cart_bundle',
      'items': [
        {
          'product': _p(1004, 'مشاوي مشكلة لشخصين', 22000),
          'store': {'id': 1, 'name': 'مشاوي أبو علي'},
          'quantity': 4,
        },
        {
          'product': _p(1005, 'تكة لحم', 11000),
          'store': {'id': 1, 'name': 'مشاوي أبو علي'},
          'quantity': 1,
        },
      ],
    }),
    const MimoStreamEvent('ui', {
      'type': 'services',
      'items': [
        {
          'id': 701,
          'title': 'تصليح تسربات',
          'provider': 'أبو مصطفى للسباكة',
          'rating': 4.8,
          'reviews': 64,
          'price': 'تبدأ من 15,000 د.ع',
          'note': 'أعلى تقييم',
        },
      ],
    }),
    const MimoStreamEvent('ui', {
      'type': 'ticket',
      'ticketId': 55,
      'ticketNumber': 'SUP-55',
      'priority': 'urgent',
    }),
    const MimoStreamEvent('ui', {'type': 'mood', 'mood': 'yummy'}),
    const MimoStreamEvent('done', {'refs': ''}),
  ],
];

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('bill, add-all bundle, services and 👍 all work', (tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FakeApi(_script());
    final container = ProviderContainer(
      overrides: [
        mimoChatApiProvider.overrideWithValue(api),
        appSettingsControllerProvider.overrideWith((ref) => _Settings()),
        authControllerProvider.overrideWith((ref) => _Auth(ref)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: MimoChatSheet()),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'عندي 8 ضيوف');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('الفاتورة المتوقعة'), findsOneWidget);
    expect(find.text('90,500 د.ع'), findsOneWidget);
    expect(find.text('أبو مصطفى للسباكة'), findsOneWidget);

    await tester.tap(find.text('ضيفهم كلهم'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final cart = container.read(cartControllerProvider);
    expect(cart.totalItems, 5);
    expect(api.accepted.single.length, 2);
    expect(find.textContaining('ضفت 5 غرض'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.thumb_up_alt_outlined).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(api.ratings, [true]);
    expect(container.read(mimoChatControllerProvider).mood, MimoMood.love);
    expect(find.text('شكراً! تعلمت'), findsOneWidget);

    // The escalation card lets the user follow the ticket.
    expect(find.text('وصلت مشكلتك للإدارة'), findsOneWidget);
    expect(find.text('SUP-55'), findsOneWidget);
    await tester.ensureVisible(find.text('تابعها'));
    await tester.tap(find.text('تابعها'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(MimoNavigation.requests.value?.ticketId, 55);
  });
}
