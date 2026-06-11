import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/customer/ui/customer_main_market_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

void main() {
  testWidgets('main market screen pins pharmacy hub in visible cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: CustomerMainMarketScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Pharmacies'), findsWidgets);
  });
}
