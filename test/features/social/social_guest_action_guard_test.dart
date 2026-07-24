import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/auth/auth_guard.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/social/ui/social_content_navigation.dart';
import 'package:maslaki/features/social/ui/social_profile_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState initial) {
    state = initial;
  }

  @override
  Future<void> bootstrap() async {}
}

Widget _harness({
  required AuthState auth,
  required Future<void> Function(BuildContext context) onTap,
}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => _FixedAuthController(ref, auth),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => onTap(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'guest action shows the unified sign-in gate with the required copy',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        _harness(
          auth: const AuthState(guestMode: true),
          onTap: (context) async {
            result = await requireAuthBeforeAction(
              context,
              featureArabic: 'الإعجاب',
              featureEnglish: 'liking',
            );
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // Exact required wording + both buttons.
      expect(find.text('سجّل الدخول للمتابعة'), findsOneWidget);
      expect(
        find.text('تحتاج إلى تسجيل الدخول لاستخدام هذه الميزة.'),
        findsOneWidget,
      );
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);

      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(result, isFalse, reason: 'cancelling the gate must block the action');
    },
  );

  testWidgets(
    'signed-in user passes the gate instantly with no sheet',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        _harness(
          auth: const AuthState(token: 'signed-in-token'),
          onTap: (context) async {
            result = await requireAuthBeforeAction(
              context,
              featureArabic: 'الإعجاب',
              featureEnglish: 'liking',
            );
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('سجّل الدخول للمتابعة'), findsNothing);
      expect(result, isTrue);
    },
  );

  testWidgets(
    'guest profile open is gated before navigation (no profile screen pushed)',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          auth: const AuthState(guestMode: true),
          onTap: (context) =>
              openSocialProfileGuarded(context, userId: 5, initialName: 'X'),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // The sign-in sheet appears and the profile route is never pushed.
      expect(find.text('سجّل الدخول للمتابعة'), findsOneWidget);
      expect(find.byType(SocialProfileScreen), findsNothing);
    },
  );
}
