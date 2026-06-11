import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/social/ui/widgets/social_community_sheets.dart';
import 'package:maslaki/l10n/app_localizations.dart';

Widget _app() {
  return const ProviderScope(
    child: MaterialApp(
      locale: Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: ScopedCommunityPostSheet(scopeType: 'city', scopeCode: 'baghdad'),
      ),
    ),
  );
}

void main() {
  testWidgets('community post sheet shows inline caption validation error', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(_app());

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.validationRequiredField('Post text')),
      findsOneWidget,
    );
  });
}
