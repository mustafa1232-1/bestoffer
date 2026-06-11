import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/admin/models/pending_delivery_account_model.dart';
import 'package:maslaki/features/admin/models/pending_taxi_cash_payment_model.dart';
import 'package:maslaki/features/admin/models/pending_taxi_profile_edit_request_model.dart';
import 'package:maslaki/features/admin/state/admin_controller.dart';
import 'package:maslaki/features/admin/ui/admin_taxi_captain_requests_screen.dart';
import 'package:maslaki/features/admin/ui/admin_taxi_cash_payments_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAdminController extends AdminController {
  _FakeAdminController(super.ref, AdminState initialState) {
    state = initialState;
  }

  @override
  Future<void> bootstrap() async {}
}

PendingDeliveryAccountModel _pendingCaptain() {
  return PendingDeliveryAccountModel(
    id: 11,
    fullName: 'Captain One',
    phone: '07700000011',
    block: 'A1',
    buildingNumber: '10',
    apartment: '1',
    createdAt: DateTime(2026, 1, 1),
    vehicleType: 'sedan',
    carMake: 'Toyota',
    carModel: 'Corolla',
    carYear: 2020,
    carColor: 'White',
    plateNumber: '12345',
    profileImageUrl: null,
    carImageUrl: null,
  );
}

PendingTaxiProfileEditRequestModel _pendingEdit() {
  return PendingTaxiProfileEditRequestModel(
    id: 71,
    captainUserId: 11,
    fullName: 'Captain One',
    phone: '07700000011',
    block: 'A1',
    buildingNumber: '10',
    apartment: '1',
    captainNote: null,
    requestedAt: DateTime(2026, 1, 2),
    requestedChanges: const <String, dynamic>{
      'carModel': 'Camry',
      'plateNumber': '67890',
    },
    currentProfile: const <String, dynamic>{
      'carModel': 'Corolla',
      'plateNumber': '12345',
    },
  );
}

PendingTaxiCashPaymentModel _pendingCashPayment() {
  return PendingTaxiCashPaymentModel(
    captainUserId: 11,
    fullName: 'Captain One',
    phone: '07700000011',
    block: 'A1',
    buildingNumber: '10',
    apartment: '1',
    profileImageUrl: null,
    carImageUrl: null,
    carMake: 'Toyota',
    carModel: 'Corolla',
    carYear: 2020,
    plateNumber: '12345',
    cashPaymentRequestedAt: DateTime(2026, 1, 3),
    monthlyFeeIqd: 45000,
    discountPercent: 20,
    discountedMonthlyFeeIqd: 36000,
    dueAmountIqd: 36000,
  );
}

Future<void> _pumpWithAdminState(
  WidgetTester tester, {
  required Widget child,
  required AdminState state,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminControllerProvider.overrideWith(
          (ref) => _FakeAdminController(ref, state),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cash payments screen opens inline validation sheet', (
    tester,
  ) async {
    final state = AdminState(
      pendingTaxiCashPayments: <PendingTaxiCashPaymentModel>[
        _pendingCashPayment(),
      ],
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _pumpWithAdminState(
      tester,
      state: state,
      child: const AdminTaxiCashPaymentsScreen(),
    );

    expect(find.text('Captain One'), findsOneWidget);
    await tester.tap(find.text(l10n.adminTaxiCashPaymentsConfirm));
    await tester.pumpAndSettle();

    expect(find.text(l10n.adminTaxiCashPaymentsReviewTitle), findsOneWidget);
    expect(find.text(l10n.adminTaxiCashPaymentsCycleDaysLabel), findsOneWidget);
    expect(find.text(l10n.adminTaxiCashPaymentsApplyAndConfirm), findsOneWidget);
  });

  testWidgets('captain requests screen shows details buttons and review sheet', (
    tester,
  ) async {
    final state = AdminState(
      pendingTaxiCaptainAccounts: <PendingDeliveryAccountModel>[
        _pendingCaptain(),
      ],
      pendingTaxiProfileEditRequests: <PendingTaxiProfileEditRequestModel>[
        _pendingEdit(),
      ],
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _pumpWithAdminState(
      tester,
      state: state,
      child: const AdminTaxiCaptainRequestsScreen(),
    );

    expect(find.text(l10n.commonDetails), findsOneWidget);
    await tester.tap(find.text(l10n.adminTaxiCaptainProfileEditsTab));
    await tester.pumpAndSettle();

    expect(find.text(l10n.commonDetails), findsOneWidget);
    await tester.tap(find.text(l10n.commonOpen));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminTaxiCaptainReviewEditRequestTitle), findsOneWidget);
  });
}
