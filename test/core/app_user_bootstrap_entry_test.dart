import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/app_user_bootstrap.dart';
import 'package:maslaki/core/notifications/local_notification_service.dart';
import 'package:maslaki/core/notifications/push_notification_service.dart';
import 'package:maslaki/core/realtime/maslaki_realtime_service.dart';
import 'package:maslaki/core/sections/section_availability_controller.dart';
import 'package:maslaki/core/settings/app_settings_controller.dart';
import 'package:maslaki/core/theme/theme_preset.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/presentation/login_screen.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/customer/ui/customer_home_selector_screen.dart';
import 'package:maslaki/features/notifications/data/notifications_api.dart';
import 'package:maslaki/features/startup/state/app_startup_controller.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }

  @override
  Future<void> bootstrap() async {}
}

class _FakeStartupController extends AppStartupController {
  _FakeStartupController()
    : super(store: SecureStore(), dio: Dio(), initialFirstLaunchDone: true) {
    state = const AppStartupState(
      phase: AppStartupPhase.ready,
      initialized: true,
      error: null,
      attempts: 0,
    );
  }

  @override
  Future<void> bootstrap() async {}
}

class _FakeSettingsController extends AppSettingsController {
  _FakeSettingsController() : super(SecureStore(), storageScope: 'test') {
    state = const AppSettingsState(
      locale: Locale('en'),
      animationsEnabled: false,
      weatherEffectsEnabled: false,
      themePreset: AppThemePreset.midnightBlue,
      loaded: true,
    );
  }

  @override
  Future<void> bootstrap() async {}
}

class _FakeSectionAvailabilityController extends SectionAvailabilityController {
  _FakeSectionAvailabilityController(super.ref) {
    state = const SectionAvailabilityState(initialized: true);
  }

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> refresh({bool silent = false}) async {}
}

class _FakeLocalNotificationService extends LocalNotificationService {
  @override
  Stream<NotificationTapPayload> get tapStream =>
      const Stream<NotificationTapPayload>.empty();

  @override
  Future<void> initialize() async {}

  @override
  void dispose() {}
}

class _FakePushNotificationService extends PushNotificationService {
  _FakePushNotificationService()
    : super(
        api: NotificationsApi(Dio()),
        local: _FakeLocalNotificationService(),
        store: SecureStore(),
      );

  @override
  Stream<NotificationTapPayload> get tapStream =>
      const Stream<NotificationTapPayload>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> syncToken() async {}

  @override
  Future<void> unregisterCurrentToken() async {}

  @override
  void dispose() {}
}

class _FakeMaslakiRealtimeService extends MaslakiRealtimeService {
  _FakeMaslakiRealtimeService() : super(Dio());

  @override
  Future<bool> bindAuthenticatedSession({bool force = false}) async => true;

  @override
  Future<void> clearSession() async {}

  @override
  Future<void> setAppActive(bool active) async {}
}

UserModel _customerUser() {
  return UserModel(
    id: 77,
    fullName: 'Customer User',
    phone: '07700000000',
    role: 'user',
    block: 'A1',
    buildingNumber: '11',
    apartment: '5',
    imageUrl: null,
    workTitle: null,
    workCompany: null,
    preferredLocale: 'ar',
    isSuperAdmin: false,
  );
}

void main() {
  testWidgets(
    'authenticated regular user lands on CustomerHomeSelectorScreen',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _FakeAuthController(
                ref,
                AuthState(user: _customerUser(), token: 'user-token'),
              ),
            ),
            appStartupControllerProvider.overrideWith(
              (ref) => _FakeStartupController(),
            ),
            appSettingsControllerProvider.overrideWith(
              (ref) => _FakeSettingsController(),
            ),
            sectionAvailabilityControllerProvider.overrideWith(
              (ref) => _FakeSectionAvailabilityController(ref),
            ),
            maslakiRealtimeServiceProvider.overrideWithValue(
              _FakeMaslakiRealtimeService(),
            ),
            localNotificationsProvider.overrideWithValue(
              _FakeLocalNotificationService(),
            ),
            pushNotificationsProvider.overrideWithValue(
              _FakePushNotificationService(),
            ),
          ],
          child: const MaslakiApp(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(CustomerHomeSelectorScreen), findsOneWidget);
    },
  );

  testWidgets('token without verified user stays on login screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) =>
                _FakeAuthController(ref, const AuthState(token: 'stale-token')),
          ),
          appStartupControllerProvider.overrideWith(
            (ref) => _FakeStartupController(),
          ),
          appSettingsControllerProvider.overrideWith(
            (ref) => _FakeSettingsController(),
          ),
          sectionAvailabilityControllerProvider.overrideWith(
            (ref) => _FakeSectionAvailabilityController(ref),
          ),
          maslakiRealtimeServiceProvider.overrideWithValue(
            _FakeMaslakiRealtimeService(),
          ),
          localNotificationsProvider.overrideWithValue(
            _FakeLocalNotificationService(),
          ),
          pushNotificationsProvider.overrideWithValue(
            _FakePushNotificationService(),
          ),
        ],
        child: const MaslakiApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(CustomerHomeSelectorScreen), findsNothing);
  });
}
