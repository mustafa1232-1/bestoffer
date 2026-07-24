import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/social/state/social_reels_controller.dart';
import 'package:maslaki/features/social_v3/state/social_reels_v3_connector.dart';
import 'package:maslaki/l10n/app_localizations.dart';

/// Strings that must NEVER appear in the guest-facing content UI.
const List<String> _forbiddenGuestStrings = <String>[
  'تعذر تحميل الريلز',
  'تعذر تحميل المنشورات',
  'تعذر تحميل الستوري',
  'DioException',
  'status code',
  'request ID',
];

class _GuestAuthController extends AuthController {
  _GuestAuthController(super.ref) {
    state = const AuthState(guestMode: true);
  }

  @override
  Future<void> bootstrap() async {}
}

/// Reels controller stuck in a failed-empty state, with a no-op load so the
/// connector's bootstrap can't clear it.
class _FailedEmptyReelsController extends SocialReelsController {
  _FailedEmptyReelsController(super.ref) {
    // items defaults to an empty list.
    state = const SocialReelsState(error: kSocialReelsLoadFailedCode);
  }

  @override
  Future<void> load({
    bool refresh = true,
    Duration timeout = kSocialReelsLoadTimeout,
  }) async {}
}

Widget _app({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      locale: Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: SocialReelsV3Connector(),
    ),
  );
}

void _expectNoForbiddenStrings() {
  for (final forbidden in _forbiddenGuestStrings) {
    expect(
      find.textContaining(forbidden, findRichText: true),
      findsNothing,
      reason: 'Guest reels must not render the technical string "$forbidden".',
    );
  }
}

void main() {
  testWidgets(
    'guest reels load failure shows a clean empty area — no error, no Retry',
    (tester) async {
      await tester.pumpWidget(
        _app(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _GuestAuthController(ref),
            ),
            socialReelsControllerProvider.overrideWith(
              (ref) => _FailedEmptyReelsController(ref),
            ),
          ],
        ),
      );
      // Run the connector bootstrap microtask, then rebuild into the failed state.
      await tester.pump();
      await tester.pump();

      _expectNoForbiddenStrings();
      // No large in-page Retry button for the guest reels surface.
      expect(find.text('إعادة المحاولة'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      // The area is a clean, empty black surface.
      expect(find.byType(ColoredBox), findsWidgets);

      // Drain the single bounded background-retry timer so no timer is pending.
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'guest reels empty (no error) shows a clean empty area — no create prompt',
    (tester) async {
      await tester.pumpWidget(
        _app(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _GuestAuthController(ref),
            ),
            socialReelsControllerProvider.overrideWith(
              (ref) => _EmptyNoErrorReelsController(ref),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      _expectNoForbiddenStrings();
      // No "create reel" empty-state call-to-action for guests.
      expect(find.text('إنشاء ريل'), findsNothing);
      expect(find.text('Create reel'), findsNothing);
      expect(find.text('إعادة المحاولة'), findsNothing);
    },
  );
}

class _EmptyNoErrorReelsController extends SocialReelsController {
  _EmptyNoErrorReelsController(super.ref) {
    state = const SocialReelsState();
  }

  @override
  Future<void> load({
    bool refresh = true,
    Duration timeout = kSocialReelsLoadTimeout,
  }) async {}
}
