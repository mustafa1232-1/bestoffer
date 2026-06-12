import 'package:app_store_runtime/app_store_runtime.dart';
import 'package:core_auth/core_auth.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _SeededAuthController extends AuthController {
  _SeededAuthController(AuthState seededState) : super() {
    state = seededState;
  }

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> logout() async {
    state = const AuthState.guest();
  }
}

Future<void> _flushUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int maxTries = 12,
}) async {
  for (var i = 0; i < maxTries; i++) {
    await _flushUi(tester);
    if (finder.evaluate().isNotEmpty) return;
  }
  debugDumpApp();
}

void main() {
  testWidgets('store app login boot then logout', (tester) async {
    final scope = 'store_test_login_${DateTime.now().microsecondsSinceEpoch}';
    late _SeededAuthController controller;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsStorageScopeProvider.overrideWithValue(scope),
          authControllerProvider.overrideWith((ref) {
            controller = _SeededAuthController(const AuthState.guest());
            return controller;
          }),
        ],
        child: const MaslakiStoreApp(
          skipBootstrap: true,
          useNetworkAuth: false,
        ),
      ),
    );
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('store_login_button')),
    );

    expect(find.byKey(const Key('store_login_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('store_login_button')));
    await _flushUi(tester);
    expect(controller.state.isAuthed, isTrue);
    expect(find.byKey(const Key('store_logout_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('store_logout_button')));
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('store_login_button')),
    );
    expect(controller.state.isAuthed, isFalse);
    expect(find.byKey(const Key('store_login_button')), findsOneWidget);
  });

  testWidgets('store app logs out on role mismatch', (tester) async {
    final scope =
        'store_test_role_mismatch_${DateTime.now().microsecondsSinceEpoch}';
    late _SeededAuthController controller;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsStorageScopeProvider.overrideWithValue(scope),
          authControllerProvider.overrideWith((ref) {
            controller = _SeededAuthController(
              const AuthState.authenticated(AuthRoleScope.delivery),
            );
            return controller;
          }),
        ],
        child: const MaslakiStoreApp(
          skipBootstrap: true,
          useNetworkAuth: false,
        ),
      ),
    );
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('store_login_button')),
    );

    expect(controller.state.isAuthed, isFalse);
    expect(find.byKey(const Key('store_login_button')), findsOneWidget);
  });
}
