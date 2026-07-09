import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/features/customer/ui/fashion_market_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('ar')}) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.dark(),
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Fashion Market landing shows only نسائي / رجالي first (Arabic)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const FashionMarketScreen()));
    await tester.pump();

    expect(find.byKey(const Key('fashion_department_women')), findsOneWidget);
    expect(find.byKey(const Key('fashion_department_men')), findsOneWidget);
    expect(find.text('نسائي'), findsOneWidget);
    expect(find.text('رجالي'), findsOneWidget);
    // The old deep subcategory split (shoes/bags/etc.) is NOT on the landing.
    expect(find.textContaining('أحذية'), findsNothing);
    expect(find.textContaining('حقائب'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English locale shows Women / Men', (tester) async {
    await tester.pumpWidget(
      _wrap(const FashionMarketScreen(), locale: const Locale('en')),
    );
    await tester.pump();

    expect(find.text('Women'), findsOneWidget);
    expect(find.text('Men'), findsOneWidget);
  });

  testWidgets('tapping a department is tappable (navigation wired)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const FashionMarketScreen()));
    await tester.pump();

    // The card is an actionable InkWell (has an onTap) — proves selection is wired.
    final women = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('fashion_department_women')),
        matching: find.byType(InkWell),
      ),
    );
    expect(women.onTap, isNotNull);
  });
}
