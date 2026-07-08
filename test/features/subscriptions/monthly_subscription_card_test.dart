import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/core/utils/currency.dart';
import 'package:maslaki/features/subscriptions/ui/monthly_subscription_card.dart';
import 'package:maslaki/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

Map<String, dynamic> _monthlySummary({
  num subscriptionAmount = 30000,
  num paidAmount = 12000,
  num remainingAmount = 18000,
  String status = 'partially_paid',
}) {
  return {
    'isMonthlySubscription': true,
    'commissionModel': 'monthly_subscription',
    'currentInvoice': {
      'id': 5,
      'billingMonth': '2026-07-01',
      'subscriptionAmount': subscriptionAmount,
      'paidAmount': paidAmount,
      'remainingAmount': remainingAmount,
      'status': status,
      'dueAt': '2026-08-01T00:00:00.000Z',
    },
    'report': {
      'totalRemaining': remainingAmount,
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the subscription card for a monthly_subscription merchant', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(MonthlySubscriptionCard(summary: _monthlySummary())),
    );
    await tester.pump();

    expect(find.byKey(const Key('monthly_subscription_card')), findsOneWidget);
    expect(find.text('Monthly subscription'), findsOneWidget);
    expect(find.text('Remaining'), findsOneWidget);
    expect(find.text(formatIqd(30000)), findsOneWidget); // subscription amount
    expect(find.text(formatIqd(18000)), findsWidgets); // remaining balance
    // Explicit separation-of-concerns note is visible to the store owner.
    expect(
      find.textContaining('Billed separately from per-order cash settlement.'),
      findsOneWidget,
    );
  });

  testWidgets('hides the card for a percentage merchant', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MonthlySubscriptionCard(
          summary: {'isMonthlySubscription': false, 'commissionModel': 'percentage'},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('monthly_subscription_card')), findsNothing);
    expect(find.text('Monthly subscription'), findsNothing);
  });

  testWidgets('hides the card when summary is null (no financial permission)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const MonthlySubscriptionCard(summary: null)),
    );
    await tester.pump();

    expect(find.byKey(const Key('monthly_subscription_card')), findsNothing);
  });
}
