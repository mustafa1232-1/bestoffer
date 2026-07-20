import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/customer/ui/customer_main_market_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

Future<void> _pumpMarket(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
}

void main() {
  testWidgets('main market screen pins pharmacy hub in visible cards', (
    tester,
  ) async {
    await _pumpMarket(tester);
    expect(find.text('Pharmacies'), findsWidgets);
  });

  testWidgets('market hub cards use the Maslaki design-system card', (
    tester,
  ) async {
    await _pumpMarket(tester);
    // Cards render via the central MaslakiCard (light premium surface) rather
    // than ad-hoc dark gradient blocks.
    expect(find.byType(MaslakiCard), findsWidgets);
  });

  testWidgets('fashion market is offered as a dedicated category', (
    tester,
  ) async {
    await _pumpMarket(tester);
    expect(find.text('Fashion market'), findsWidgets);
  });
}
