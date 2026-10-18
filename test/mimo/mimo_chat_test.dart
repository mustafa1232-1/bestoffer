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

const _product = {
  'id': 12,
  'merchant_id': 1,
  'name': 'نص كيلو كباب',
  'price': 12000,
  'is_available': true,
};

List<List<MimoStreamEvent>> _script() => [
  [
    const MimoStreamEvent('status', {'text': 'دا أختارلك الأحسن...'}),
    const MimoStreamEvent('delta', {'text': 'اخترتلك نص كيلو كباب '}),
    const MimoStreamEvent('delta', {'text': 'من مشاوي أبو علي. شنو رأيك؟'}),
    const MimoStreamEvent('ui', {
      'type': 'products',
      'items': [
        {
          'id': 12,
          'name': 'نص كيلو كباب',
          'price': 12000,
          'originalPrice': 12000,
          'store': {'id': 1, 'name': 'مشاوي أبو علي'},
          'note': 'أكثر شي ينطلب، 420 طلب',
        },
      ],
    }),
    const MimoStreamEvent('ui', {
      'type': 'replies',
      'options': ['ضيفه للسلة', 'شوفلي غيره'],
    }),
    const MimoStreamEvent('ui', {'type': 'mood', 'mood': 'yummy'}),
    const MimoStreamEvent('done', {
      'refs': 'product#12 "نص كيلو كباب" store#1',
    }),
  ],
  [
    const MimoStreamEvent('delta', {'text': 'دوس على الزر وينضاف للسلة'}),
    const MimoStreamEvent('ui', {
      'type': 'cart_proposal',
      'quantity': 2,
      'product': _product,
      'store': {'id': 1, 'name': 'مشاوي أبو علي'},
      'hasOptions': false,
    }),
    const MimoStreamEvent('ui', {'type': 'mood', 'mood': 'happy'}),
    const MimoStreamEvent('done', {'refs': 'proposed product#12 ×2'}),
  ],
];

Future<(_FakeApi, ProviderContainer)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 900);
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
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showMimoChat(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  return (api, container);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('welcome greets by name with the lisp and offers sections', (
    tester,
  ) async {
    await _pump(tester);
    // "شتريد تسوي" → "شتريد تثوي": Mimo's lisp.
    expect(find.text('هلا مصطفى! شتريد تثوي اليوم؟'), findsOneWidget);
    expect(find.text('اختارلي'), findsOneWidget);
    expect(find.text('تكسي'), findsOneWidget);
  });

  testWidgets('chat streams Mimo, shows cards, remembers them, adds to cart', (
    tester,
  ) async {
    final (api, container) = await _pump(tester);

    // Tap a quick pick → sent as the user's message.
    await tester.tap(find.text('اختارلي'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(api.sent.single.single['content'], 'جوعان، اختارلي انت');
    expect(api.contexts.single['cart'], isA<Map>());
    // Streamed text joined, with the lisp ("سـ" → "ثـ" does not apply here).
    expect(
      find.text('اخترتلك نص كيلو كباب من مشاوي أبو علي. شنو رأيك؟'),
      findsOneWidget,
    );
    expect(find.text('أكثر شي ينطلب، 420 طلب'), findsOneWidget);
    expect(container.read(mimoChatControllerProvider).mood, MimoMood.yummy);

    // Reply chip → second turn carries Mimo's memory of the shown card.
    await tester.tap(find.text('ضيفه للسلة'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final second = api.sent[1];
    expect(second.length, 3);
    expect(second[1]['role'], 'assistant');
    expect(second[1]['refs'], contains('product#12'));

    // The cart proposal asks before adding; confirming adds 2.
    expect(find.text('دوث على الزر وينضاف للثلة'), findsOneWidget);
    await tester.tap(find.text('ضيف'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final cart = container.read(cartControllerProvider);
    expect(cart.totalItems, 2);
    expect(cart.items.single.merchantId, 1);
    expect(find.textContaining('ضفت نص كيلو كباب للثلة'), findsOneWidget);
  });

  testWidgets('Mimo looks at what the user types', (tester) async {
    await _pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'مشتهي تمن');
    await tester.pump();
    final mimo = tester.widget<MimoCharacter>(find.byType(MimoCharacter).first);
    expect(mimo.mood, MimoMood.down);
  });

  test('controller keeps a failed turn out of the history', () async {
    final failing = _ThrowingApi();
    final container = ProviderContainer(
      overrides: [
        mimoChatApiProvider.overrideWithValue(failing),
        appSettingsControllerProvider.overrideWith((ref) => _Settings()),
      ],
    );
    addTearDown(container.dispose);
    final chat = container.read(mimoChatControllerProvider.notifier);
    await chat.send('هلا');
    final state = container.read(mimoChatControllerProvider);
    expect(state.sending, isFalse);
    expect(state.mood, MimoMood.sad);
    expect(state.messages.last.failed, isTrue);
  });

  test('long chats send the running summary instead of old messages', () async {
    final api = _SummaryApi();
    final container = ProviderContainer(
      overrides: [
        mimoChatApiProvider.overrideWithValue(api),
        appSettingsControllerProvider.overrideWith((ref) => _Settings()),
      ],
    );
    addTearDown(container.dispose);
    final chat = container.read(mimoChatControllerProvider.notifier);
    await chat.send('اسمي علي وامتحاني الخميس');
    await chat.send('شنو يوم امتحاني؟');
    expect(api.summaries, ['', 'اسمه علي وامتحانه الخميس']);
    // The summarized first message is not re-sent; Mimo's reply and the new
    // question are.
    expect(api.sent[1].map((m) => m['content']), ['تمام', 'شنو يوم امتحاني؟']);
    // The user still sees the whole conversation.
    expect(container.read(mimoChatControllerProvider).messages.length, 4);
  });
}

class _SummaryApi extends MimoChatApi {
  _SummaryApi() : super(Dio());

  final sent = <List<Map<String, dynamic>>>[];
  final summaries = <String>[];

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
    summaries.add(summary);
    yield const MimoStreamEvent('delta', {'text': 'تمام'});
    // First turn: the server folded the first message into a summary.
    yield MimoStreamEvent(
      'done',
      sent.length == 1
          ? {'refs': '', 'summary': 'اسمه علي وامتحانه الخميس', 'summarized': 1}
          : {'refs': ''},
    );
  }
}

class _ThrowingApi extends MimoChatApi {
  _ThrowingApi() : super(Dio());

  @override
  Stream<MimoStreamEvent> chat({
    required List<Map<String, dynamic>> messages,
    required String lang,
    Map<String, dynamic> context = const {},
    String summary = '',
    List<Map<String, dynamic>> attachments = const [],
    CancelToken? cancelToken,
  }) => Stream.error(DioException(requestOptions: RequestOptions()));
}
