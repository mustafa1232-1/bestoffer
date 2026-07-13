import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/delivery/data/delivery_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'delivery support requests opt out of terminal session invalidation',
    () async {
      final captured = <Map<String, dynamic>>[];
      final dio = Dio(
        BaseOptions(baseUrl: 'https://bestoffer-production.up.railway.app'),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured.add(<String, dynamic>{
              'path': options.path,
              'method': options.method,
              'extra': Map<String, dynamic>.from(options.extra),
            });
            final data = switch (options.path) {
              '/api/courier/orders' => <String, dynamic>{'orders': <dynamic>[]},
              '/api/delivery/orders/current' => <dynamic>[],
              '/api/courier/dashboard' => <String, dynamic>{},
              '/api/delivery/analytics' => <String, dynamic>{},
              '/api/courier/requests' => <String, dynamic>{
                'items': <dynamic>[],
              },
              '/api/courier/competitions' => <String, dynamic>{
                'competitions': <dynamic>[],
              },
              '/api/courier/competition-progress' => <String, dynamic>{
                'items': <dynamic>[],
              },
              '/api/courier/competitions/achievements/summary' =>
                <String, dynamic>{'summary': <String, dynamic>{}},
              '/api/delivery/end-day/readiness' => <String, dynamic>{
                'canEndDay': true,
                'openSettlements': <dynamic>[],
              },
              '/api/courier/presence' => <String, dynamic>{
                'presence': <String, dynamic>{},
              },
              _ => <String, dynamic>{},
            };
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: data,
                statusCode: 200,
              ),
            );
          },
        ),
      );

      final api = DeliveryApi(dio);

      await api.ordersV2(skipTerminalSessionInvalidation: true);
      await api.dashboardV2(skipTerminalSessionInvalidation: true);
      await api.requestsV2(skipTerminalSessionInvalidation: true);
      await api.competitionsV2(skipTerminalSessionInvalidation: true);
      await api.competitionProgressV2(skipTerminalSessionInvalidation: true);
      await api.competitionAchievementsSummaryV2(
        skipTerminalSessionInvalidation: true,
      );
      await api.endDayReadiness(skipTerminalSessionInvalidation: true);
      await api.upsertPresence(
        skipTerminalSessionInvalidation: true,
        isOnline: true,
      );

      expect(captured, hasLength(8));
      for (final request in captured) {
        final extra = request['extra'] as Map<String, dynamic>;
        expect(extra['skipTerminalSessionInvalidation'], isTrue);
        expect(extra['skipAuthRefresh'], isTrue);
      }
    },
  );
}
