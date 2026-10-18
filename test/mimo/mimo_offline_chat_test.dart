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
import 'package:maslaki/features/mimo/brain/mimo_directory.dart';
import 'package:maslaki/features/mimo/chat/mimo_chat_api.dart';
import 'package:maslaki/features/mimo/chat/mimo_chat_controller.dart';
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

/// The AI: either "no credit" (fallback) or a normal reply; counts calls.
class _Api extends MimoChatApi {
  _Api({this.fallback = false}) : super(Dio());

  final bool fallback;
  int calls = 0;

  @override
  Stream<MimoStreamEvent> chat({
    required List<Map<String, dynamic>> messages,
    required String lang,
    Map<String, dynamic> context = const {},
    String summary = '',
    List<Map<String, dynamic>> attachments = const [],
    CancelToken? cancelToken,
  }) async* {
    calls++;
    if (fallback) {
      yield const MimoStreamEvent('delta', {'text': 'هسه دماغي شوية تعبان'});
      yield const MimoStreamEvent('done', {'fallback': true});
      return;
    }
    yield const MimoStreamEvent('delta', {'text': 'باريس'});
    yield const MimoStreamEvent('done', {});
  }
}

const _directory = {
  'stores': [
    {
      'id': 1,
      'name': 'مشاوي أبو علي',
      'type': 'restaurant',
      'activityType': 'restaurant',
      'rating': 4.6,
      'ratingCount': 80,
      'orders': 420,
    },
    {
      'id': 5,
      'name': 'أسواق النخلة',
      'type': 'market',
      'activityType': 'supermarket',
      'orders': 60,
    },
  ],
  'services': [],
};

Future<(ProviderContainer, _Api)> _setup(
  WidgetTester tester, {
  bool fallback = false,
}) async {
  final api = _Api(fallback: fallback);
  final container = ProviderContainer(
    overrides: [
      mimoChatApiProvider.overrideWithValue(api),
      mimoDirectoryProvider.overrideWith(
        (ref) => MimoDirectoryController(() async => _directory),
      ),
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
        home: SizedBox(),
      ),
    ),
  );
  return (container, api);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('"اختارلي" is answered instantly from the app, no AI call', (
    tester,
  ) async {
    final (container, api) = await _setup(tester);
    await container
        .read(mimoChatControllerProvider.notifier)
        .send('جوعان، اختارلي انت');
    await tester.pump();

    final reply = container.read(mimoChatControllerProvider).messages.last;
    expect(api.calls, 0);
    expect(reply.text, contains('«مشاوي أبو علي»'));
    expect(reply.blocks.first.type, 'stores');
    expect(reply.refs, contains('store#1'));
    expect(container.read(mimoChatControllerProvider).sending, isFalse);
  });

  testWidgets('other questions still go to the AI', (tester) async {
    final (container, api) = await _setup(tester);
    await container
        .read(mimoChatControllerProvider.notifier)
        .send('شنو عاصمة فرنسا؟');
    await tester.pump();
    expect(api.calls, 1);
    expect(
      container.read(mimoChatControllerProvider).messages.last.text,
      'باريس',
    );
  });

  testWidgets('AI out of credit → Mimo answers from the app data instead', (
    tester,
  ) async {
    final (container, api) = await _setup(tester, fallback: true);
    await container
        .read(mimoChatControllerProvider.notifier)
        .send('شي من نخله');
    await tester.pump();
    final reply = container.read(mimoChatControllerProvider).messages.last;
    expect(api.calls, 1);
    expect(reply.text, isNot(contains('تعبان')));
    expect(reply.blocks.first.items.single['name'], 'أسواق النخلة');
  });
}
