import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/core/utils/currency.dart';
import 'package:maslaki/features/subscriptions/state/admin_subscriptions_controller.dart';
import 'package:maslaki/features/subscriptions/ui/admin_merchant_subscriptions_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAdminSubscriptionsController extends AdminSubscriptionsController {
  _FakeAdminSubscriptionsController(super.ref, AdminSubscriptionsState initial) {
    state = initial;
  }

  int recordPaymentCalls = 0;
  int waiveCalls = 0;
  num? lastAmount;
  String? lastReason;

  @override
  Future<void> bootstrap({String? status}) async {}

  @override
  Future<void> recordPayment({
    required int invoiceId,
    required num amount,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    recordPaymentCalls += 1;
    lastAmount = amount;
    state = state.copyWith(saving: false);
  }

  @override
  Future<void> waiveInvoice({
    required int invoiceId,
    required String reason,
  }) async {
    waiveCalls += 1;
    lastReason = reason;
    state = state.copyWith(saving: false);
  }
}

Widget _wrap({
  required AdminSubscriptionsState initialState,
  required void Function(_FakeAdminSubscriptionsController) onCreated,
}) {
  return ProviderScope(
    overrides: [
      adminSubscriptionsControllerProvider.overrideWith((ref) {
        final controller = _FakeAdminSubscriptionsController(ref, initialState);
        onCreated(controller);
        return controller;
      }),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.dark(),
      home: const AdminMerchantSubscriptionsScreen(),
    ),
  );
}

AdminSubscriptionsState _stateWithInvoice({
  num subscriptionAmount = 30000,
  num paidAmount = 0,
  num remainingAmount = 30000,
  String status = 'pending',
}) {
  return AdminSubscriptionsState(
    invoices: [
      {
        'id': 9,
        'merchantName': 'Green Market',
        'billingMonth': '2026-07-01',
        'subscriptionAmount': subscriptionAmount,
        'paidAmount': paidAmount,
        'remainingAmount': remainingAmount,
        'status': status,
        'dueAt': '2026-08-01T00:00:00.000Z',
      },
    ],
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders merchant subscription invoice cards', (tester) async {
    late _FakeAdminSubscriptionsController controller;
    await tester.pumpWidget(
      _wrap(
        initialState: _stateWithInvoice(),
        onCreated: (c) => controller = c,
      ),
    );
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Green Market'), findsOneWidget);
    expect(find.text('Receive payment'), findsOneWidget);
    expect(controller.recordPaymentCalls, 0);
  });

  testWidgets('exact payment submits the full remaining amount', (tester) async {
    late _FakeAdminSubscriptionsController controller;
    await tester.pumpWidget(
      _wrap(
        initialState: _stateWithInvoice(),
        onCreated: (c) => controller = c,
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Receive payment'));
    await _settle(tester);

    // Amount is prefilled with the remaining balance -> exact settlement.
    await tester.tap(find.text('Confirm'));
    await _settle(tester);

    expect(controller.recordPaymentCalls, 1);
    expect(controller.lastAmount, 30000);
  });

  testWidgets('partial payment previews the remaining balance', (tester) async {
    late _FakeAdminSubscriptionsController controller;
    await tester.pumpWidget(
      _wrap(
        initialState: _stateWithInvoice(),
        onCreated: (c) => controller = c,
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Receive payment'));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, '12000');
    await _settle(tester);

    final projected = tester.widget<Text>(find.byKey(const Key('projected_remaining')));
    expect(projected.data, contains(formatIqd(18000)));

    await tester.tap(find.text('Confirm'));
    await _settle(tester);
    expect(controller.recordPaymentCalls, 1);
    expect(controller.lastAmount, 12000);
  });

  testWidgets('waive requires a reason before submitting', (tester) async {
    late _FakeAdminSubscriptionsController controller;
    await tester.pumpWidget(
      _wrap(
        initialState: _stateWithInvoice(),
        onCreated: (c) => controller = c,
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Waive'));
    await _settle(tester);

    // Tap the confirm "Waive" button in the dialog with an empty reason.
    await tester.tap(find.text('Waive').last);
    await _settle(tester);

    expect(controller.waiveCalls, 0);
    expect(find.text('A waive reason is required.'), findsOneWidget);
  });
}
