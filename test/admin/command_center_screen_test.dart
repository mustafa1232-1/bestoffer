import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/admin/data/admin_api.dart';
import 'package:maslaki/features/admin/state/admin_controller.dart';
import 'package:maslaki/features/admin/ui/command_center_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAdminApi extends AdminApi {
  _FakeAdminApi({required this.overview, this.failure}) : super(Dio());

  final Map<String, dynamic> overview;
  final Object? failure;

  @override
  Future<Map<String, dynamic>> monitoringOverview() async {
    final error = failure;
    if (error != null) throw error;
    return overview;
  }
}

Widget _wrap(AdminApi api) {
  return ProviderScope(
    overrides: [adminApiProvider.overrideWithValue(api)],
    child: const MaterialApp(
      locale: Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: CommandCenterScreen(),
    ),
  );
}

void main() {
  testWidgets('shows only permission-filtered cards returned by backend', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _FakeAdminApi(
          overview: {
            'generatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
            'cards': [
              {
                'key': 'orders',
                'title': 'Orders gate',
                'available': true,
                'detailPath': '/admin/monitoring/orders',
                'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
                'counters': {'active': 3, 'needsAttention': 1},
              },
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Orders gate'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('Needs attention'), findsWidgets);
    expect(find.text('Taxi monitoring'), findsNothing);
  });

  testWidgets('does not render raw DioException on overview failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _FakeAdminApi(
          overview: const {},
          failure: DioException(
            requestOptions: RequestOptions(
              path: '/api/admin/monitoring/overview',
            ),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(
                path: '/api/admin/monitoring/overview',
              ),
              statusCode: 500,
              data: {'message': 'SERVER_ERROR'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('RequestOptions'), findsNothing);
    expect(find.text('Unable to load the command center.'), findsOneWidget);
  });
}
