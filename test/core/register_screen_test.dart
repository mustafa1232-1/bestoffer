import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/files/local_image_file.dart';
import 'package:maslaki/features/auth/presentation/register_screen.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _ThrowingAuthController extends AuthController {
  _ThrowingAuthController(super.ref);

  @override
  Future<void> register(
    Map<String, dynamic> dto, {
    LocalImageFile? imageFile,
  }) async {
    throw Exception('boom');
  }
}

Finder _stringDropdowns() {
  return find.byWidgetPredicate(
    (widget) => widget is DropdownButtonFormField<String>,
  );
}

void main() {
  testWidgets(
    'register screen shows snackbar instead of crashing on unexpected submit error',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _ThrowingAuthController(ref),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: RegisterScreen(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'Test User');
      await tester.enterText(find.byType(TextField).at(1), '07700000000');
      await tester.enterText(find.byType(TextField).at(2), '1234');

      await tester.tap(_stringDropdowns().at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A').last);
      await tester.pumpAndSettle();

      await tester.tap(_stringDropdowns().at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A101').last);
      await tester.pumpAndSettle();

      await tester.tap(_stringDropdowns().at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('G01').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Create Account').last);
      await tester.tap(find.text('Create Account').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to create the account right now. Please try again.'),
        findsOneWidget,
      );
    },
  );
}
