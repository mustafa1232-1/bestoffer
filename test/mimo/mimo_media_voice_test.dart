import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maslaki/core/files/local_image_file.dart';
import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/core/theme/theme_preset.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/mimo/chat/mimo_chat_api.dart';
import 'package:maslaki/features/mimo/chat/mimo_chat_sheet.dart';
import 'package:maslaki/features/mimo/chat/mimo_speech.dart';
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

class _Api extends MimoChatApi {
  _Api() : super(Dio());

  final uploads = <String>[];
  final sentAttachments = <List<Map<String, dynamic>>>[];
  final sentText = <String>[];

  @override
  Future<Map<String, dynamic>> uploadPhoto(LocalImageFile file) async {
    uploads.add(file.name);
    return {
      'fileUrl': '/uploads/support/${file.name}',
      'mimeType': 'image/png',
      'fileName': file.name,
    };
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
    sentText.add('${messages.last['content']}');
    sentAttachments.add(attachments);
    yield const MimoStreamEvent('delta', {'text': 'وصلتني، شكد حلوة!'});
    yield const MimoStreamEvent('done', {});
  }
}

class _Speech implements MimoSpeech {
  void Function(String text, bool isFinal)? onText;
  final spoken = <String>[];
  bool available = true;

  @override
  Future<bool> listen({
    required String lang,
    required void Function(String text, bool isFinal) onText,
  }) async {
    this.onText = onText;
    return available;
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> speak(String text, {required String lang}) async {
    spoken.add(text);
  }

  @override
  Future<void> stopSpeaking() async {}
}

// 1×1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Future<(_Api, _Speech)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _Api();
  final speech = _Speech();
  final container = ProviderContainer(
    overrides: [
      mimoChatApiProvider.overrideWithValue(api),
      mimoSpeechProvider.overrideWithValue(speech),
      mimoPhotoPickerProvider.overrideWithValue(
        ({required bool camera}) async =>
            LocalImageFile(name: 'meal.png', path: null, bytes: _png),
      ),
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
  return (api, speech);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a photo is uploaded to our server and sent with the message', (
    tester,
  ) async {
    final (api, _) = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('mimo-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('من المعرض'));
    await tester.pumpAndSettle();

    // Preview above the input; with a photo the button is "send", not mic.
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('mic')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('send')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(api.uploads, ['meal.png']);
    expect(api.sentText.single, '📷 صورة');
    expect(
      api.sentAttachments.single.single['fileUrl'],
      '/uploads/support/meal.png',
    );
    expect(find.byKey(const ValueKey('mimo-user-photo')), findsOneWidget);
    expect(find.text('وصلتني، شكد حلوة!'), findsOneWidget);
  });

  testWidgets('talk with the mic: live transcript then auto-send', (
    tester,
  ) async {
    final (api, speech) = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('mic')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mic-on')), findsOneWidget);
    expect(find.text('أسمعك… تكلم'), findsOneWidget);

    speech.onText!('ابي كباب', false);
    await tester.pump();
    expect(find.text('ابي كباب'), findsOneWidget);

    speech.onText!('ابي كباب للعشا', true);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(api.sentText.single, 'ابي كباب للعشا');
    expect(find.byKey(const ValueKey('mic-on')), findsNothing);
  });

  testWidgets('speaker on: Mimo reads his reply aloud (with his lisp)', (
    tester,
  ) async {
    final (_, speech) = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('mimo-speaker')));
    await tester.pump();
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'شلونك');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(speech.spoken, ['وصلتني، شكد حلوة!']);
  });

  testWidgets('mic unavailable shows a friendly hint', (tester) async {
    final (_, speech) = await _pump(tester);
    speech.available = false;
    await tester.tap(find.byKey(const ValueKey('mic')));
    await tester.pump();
    expect(find.text('ما گدرت أسمعك، تأكد من إذن الميكروفون'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  test('speakable text drops emoji and links', () {
    expect(
      mimoSpeakableText('وصل طلبك! 😋 شوف https://x.com/a **هنا**'),
      'وصل طلبك! شوف هنا',
    );
  });
}
