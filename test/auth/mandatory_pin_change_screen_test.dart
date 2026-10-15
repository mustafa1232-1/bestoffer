import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/auth/presentation/mandatory_pin_change_screen.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';

class _AuthSpy extends AuthController {
  _AuthSpy(super.ref);
  final calls = <List<String>>[];

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> completeTemporaryPinChange(
    String currentPin,
    String newPin,
  ) async {
    calls.add([currentPin, newPin]);
    throw StateError('Keep the screen open for assertions');
  }
}

void main() {
  for (final initialPin in ['', '639281', '1234']) {
    testWidgets('uses actual temporary PIN with initial value "$initialPin"', (
      tester,
    ) async {
      late _AuthSpy auth;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith((ref) => auth = _AuthSpy(ref)),
          ],
          child: MaterialApp(
            home: MandatoryPinChangeScreen(initialPin: initialPin),
          ),
        ),
      );
        ProviderScope.containerOf(
          tester.element(find.byType(MandatoryPinChangeScreen)),
        ).read(authControllerProvider);
        final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      expect(
        tester.widget<TextField>(fields.first).controller!.text,
        initialPin,
      );
      if (initialPin.isEmpty) {
        await tester.enterText(fields.last, '762815');
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        expect(auth.calls, isEmpty);
        await tester.enterText(fields.first, '639281');
      }
      await tester.enterText(fields.last, '762815');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(auth.calls.single, [
        initialPin.isEmpty ? '639281' : initialPin,
        '762815',
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rejects reusing the temporary PIN', (tester) async {
    late _AuthSpy auth;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth = _AuthSpy(ref)),
        ],
        child: const MaterialApp(
          home: MandatoryPinChangeScreen(initialPin: '639281'),
        ),
      ),
    );
    ProviderScope.containerOf(
      tester.element(find.byType(MandatoryPinChangeScreen)),
    ).read(authControllerProvider);
    await tester.enterText(find.byType(TextField).last, '639281');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(auth.calls, isEmpty);
  });
}
