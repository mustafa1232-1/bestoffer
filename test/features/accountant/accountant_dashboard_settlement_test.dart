import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/features/accountant/state/accountant_controller.dart';
import 'package:maslaki/features/accountant/ui/accountant_dashboard_screen.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }

  @override
  Future<void> bootstrap() async {}
}

class _FakeAccountantController extends AccountantController {
  _FakeAccountantController(super.ref, AccountantState initialState) {
    state = initialState;
  }

  int confirmSettlementCalls = 0;
  num? lastActualAmount;
  String? lastDifferenceReason;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> confirmSettlement({
    required int settlementId,
    String? note,
    num? actualAmount,
    String? differenceReason,
  }) async {
    confirmSettlementCalls += 1;
    lastActualAmount = actualAmount;
    lastDifferenceReason = differenceReason;
    state = state.copyWith(saving: false);
  }
}

Widget _wrap(
  Widget child, {
  required AccountantState initialState,
  required void Function(_FakeAccountantController controller)
  onControllerCreated,
}) {
  final authState = AuthState(
    token: 'test-token',
    user: UserModel(
      id: 1,
      fullName: 'Tester',
      phone: '07700000000',
      role: 'accountant',
      block: '1',
      buildingNumber: '1',
      apartment: '1',
      imageUrl: null,
      workTitle: null,
      workCompany: null,
      preferredLocale: 'ar',
      isSuperAdmin: false,
    ),
  );

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => _FakeAuthController(ref, authState),
      ),
      accountantControllerProvider.overrideWith((ref) {
        final controller = _FakeAccountantController(ref, initialState);
        onControllerCreated(controller);
        return controller;
      }),
    ],
    child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.dark(),
      home: child,
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('accountant settlement requires a reason when amounts differ', (
    tester,
  ) async {
    late _FakeAccountantController controller;
    await tester.pumpWidget(
      _wrap(
        const AccountantDashboardScreen(),
        initialState: const AccountantState(
          summary: <String, dynamic>{
            'balance': 0,
            'pendingAmount': 8750,
            'pendingCount': 1,
          },
          pendingSettlements: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 9,
              'deliveryFullName': 'Courier One',
              'deliveryPhone': '07700000001',
              'archiveDate': '2026-07-05',
              'ordersCount': 3,
              'totalAmount': 11250,
              'storeNetReceivedAmount': 8750,
              'appDueFromDelivery': 1500,
              'differenceAmount': 0,
            },
          ],
        ),
        onControllerCreated: (value) => controller = value,
      ),
    );
    await _settle(tester);

    expect(tester.takeException(), isNull);

    await tester.tap(find.text('ذمم الدلفري'));
    await _settle(tester);

    expect(find.text('تأكيد الاستلام'), findsOneWidget);
    await tester.tap(find.text('تأكيد الاستلام'));
    await _settle(tester);

    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));

    await tester.enterText(textFields.at(0), '8700');
    await _settle(tester);

    await tester.tap(find.text('تأكيد الاستلام').last);
    await _settle(tester);

    expect(controller.confirmSettlementCalls, 0);
    expect(
      find.textContaining('أدخل سبب الفرق عند اختلاف المبلغ.'),
      findsOneWidget,
    );
  });
}
