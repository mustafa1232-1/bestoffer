// ignore_for_file: prefer_const_constructors

import 'package:maslaki/features/admin/data/admin_api.dart';
import 'package:maslaki/features/admin/state/admin_controller.dart';
import 'package:maslaki/features/admin/ui/admin_dashboard_screen.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/social/state/social_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_core/social_api.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref) {
    state = AuthState(
      token: 'token',
      user: UserModel(
        id: 1,
        fullName: 'Super Admin',
        phone: '07700000000',
        role: 'admin',
        block: 'A',
        buildingNumber: 'A101',
        apartment: '1',
        imageUrl: null,
        workTitle: null,
        workCompany: null,
        preferredLocale: 'ar',
        isSuperAdmin: true,
      ),
    );
  }

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> logout() async {}
}

class _FakeAdminController extends AdminController {
  _FakeAdminController(super.ref) {
    state = const AdminState();
  }

  @override
  Future<void> bootstrap() async {}
}

class _FakeAdminApi extends AdminApi {
  _FakeAdminApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> ordersOverview({
    String status = 'all',
    String period = 'all',
    String? from,
    String? to,
    String? search,
    int limit = 60,
    int offset = 0,
  }) async {
    return <String, dynamic>{
      'summary': const <String, dynamic>{
        'totalOrders': 4,
        'completedOrders': 3,
        'cancelledOrders': 1,
        'inProgressOrders': 0,
      },
      'items': const <dynamic>[],
      'total': 0,
      'limit': limit,
      'offset': offset,
    };
  }

  @override
  Future<Map<String, dynamic>> adminFinancialKpis({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    return <String, dynamic>{
      'window': <String, dynamic>{'period': period},
      'totals': const <String, dynamic>{
        'currency': 'IQD',
        'totalSales': 0,
        'totalCommission': 0,
        'totalServiceFees': 0,
        'totalAppDeliveryFees': 0,
        'totalStoreDeliveryFees': 0,
        'totalAppDue': 0,
        'totalStoreNetSales': 0,
        'totalCollected': 0,
        'netReceivables': 0,
        'outstandingToCollect': 0,
        'totalSalesOrders': 0,
        'totalCollectionOperations': 0,
      },
    };
  }
}

class _FlakyAdminApi extends _FakeAdminApi {
  bool _ordersFailedOnce = false;

  @override
  Future<Map<String, dynamic>> ordersOverview({
    String status = 'all',
    String period = 'all',
    String? from,
    String? to,
    String? search,
    int limit = 60,
    int offset = 0,
  }) async {
    if (!_ordersFailedOnce) {
      _ordersFailedOnce = true;
      throw DioException(
        requestOptions: RequestOptions(
          path: '/api/admin/orders/overview',
          method: 'GET',
        ),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(
            path: '/api/admin/orders/overview',
            method: 'GET',
          ),
          statusCode: 401,
          data: const <String, dynamic>{'message': 'INVALID_TOKEN'},
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return super.ordersOverview(
      status: status,
      period: period,
      from: from,
      to: to,
      search: search,
      limit: limit,
      offset: offset,
    );
  }
}

class _FakeSocialApi extends SocialApi {
  _FakeSocialApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> listCommunityScopes() async {
    return const <String, dynamic>{'scopes': <dynamic>[]};
  }
}

void main() {
  testWidgets('super admin drawer supports search and opens orders page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(ref),
          ),
          adminControllerProvider.overrideWith(
            (ref) => _FakeAdminController(ref),
          ),
          adminApiProvider.overrideWithValue(_FakeAdminApi()),
          socialApiProvider.overrideWithValue(_FakeSocialApi()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const AdminDashboardScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('Orders & operations'), findsOneWidget);
    expect(find.text('All orders'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'AI DEV SUPPORT');
    await tester.pumpAndSettle();
    expect(find.text('AI DEV SUPPORT'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'All orders');
    await tester.pumpAndSettle();
    final allOrdersTileText = find.text('All orders').last;
    await tester.ensureVisible(allOrdersTileText);
    await tester.tap(allOrdersTileText, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('All orders'), findsWidgets);
  });

  testWidgets('admin dashboard retries transient summary failures', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(ref),
          ),
          adminControllerProvider.overrideWith(
            (ref) => _FakeAdminController(ref),
          ),
          adminApiProvider.overrideWithValue(_FlakyAdminApi()),
          socialApiProvider.overrideWithValue(_FakeSocialApi()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const AdminDashboardScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not load the orders summary right now.'),
      findsNothing,
    );
    expect(find.text('4'), findsWidgets);
  });

}
