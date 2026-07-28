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

  testWidgets('tobacco & hookah hub replaces cars in the market hubs', (
    tester,
  ) async {
    await _pumpMarket(tester);
    // The tobacco/hookah section is now offered where Cars used to be. Entry is
    // gated behind an 18+ confirmation handled inside _openSmokingSection.
    expect(find.text('Tobacco & Hookah'), findsWidgets);
    expect(find.text('Cars'), findsNothing);
  });

  testWidgets('phones are offered as a standalone market section', (
    tester,
  ) async {
    await _pumpMarket(tester);
    expect(find.text('Phones & Technology'), findsWidgets);
  });

  testWidgets('home furniture is offered as a dedicated market section', (
    tester,
  ) async {
    await _pumpMarket(tester);
    expect(find.text('Home Furniture'), findsWidgets);
  });
}
