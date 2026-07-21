import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/admin/data/admin_api.dart';
import 'package:maslaki/features/admin/state/admin_controller.dart';
import 'package:maslaki/features/admin/ui/admin_services_hub_screen.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';

class _ArrayJsonAdapter implements HttpClientAdapter {
  final Map<String, Object?> responses;

  _ArrayJsonAdapter(this.responses);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = responses[options.path];
    if (body == null) {
      return ResponseBody.fromString(
        jsonEncode({'error': 'unexpected path ${options.path}'}),
        404,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

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
        buildingNumber: '1',
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
}

class _FakeAdminApi extends AdminApi {
  _FakeAdminApi()
    : super(
        Dio()
          ..httpClientAdapter = _ArrayJsonAdapter({
            '/api/admin/services/providers/pending': [
              {
                'id': 1,
                'businessName': 'مزود تنظيف',
                'providerApprovalStatus': 'pending',
              },
            ],
            '/api/admin/services/offerings/pending': [
              {
                'id': 11,
                'providerId': 1,
                'name': 'تنظيف شقق',
                'moderationStatus': 'pending',
              },
            ],
          }),
      );

  @override
  Future<Map<String, dynamic>> getServiceAdminStats() async {
    return const <String, dynamic>{
      'providersByStatus': {'approved': 1},
      'offeringsByStatus': {'pending': 1},
      'reviews': {'total': 0, 'averageRating': 0},
      'topCategories': [
        {'id': 1, 'name': 'تنظيف شقق', 'offeringsCount': 1},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> listServiceCategorySuggestions({
    String categorySuggestionStatus = 'pending',
    int limit = 80,
    int offset = 0,
  }) async {
    return const <String, dynamic>{'items': <dynamic>[], 'total': 0};
  }

  @override
  Future<Map<String, dynamic>> listServiceReports({
    String status = 'pending',
    int limit = 80,
    int offset = 0,
  }) async {
    return const <String, dynamic>{'items': <dynamic>[], 'total': 0};
  }

  @override
  Future<Map<String, dynamic>> listServiceAdminRequests({
    String? requestStatus,
    int limit = 80,
    int offset = 0,
  }) async {
    return const <String, dynamic>{'items': <dynamic>[], 'total': 0};
  }

  @override
  Future<List<dynamic>> listServiceModuleSettings() async {
    return const <dynamic>[];
  }
}

class _ScenarioAdminApi extends AdminApi {
  _ScenarioAdminApi({this.failure, this.empty = false, this.delay})
    : super(Dio());

  final Object? failure;
  final bool empty;
  final Duration? delay;
  int loadCalls = 0;

  Future<T> _run<T>(T value) async {
    loadCalls++;
    final wait = delay;
    if (wait != null) {
      await Future<void>.delayed(wait);
    }
    final error = failure;
    if (error != null) throw error;
    return value;
  }

  Map<String, dynamic> get _itemsEnvelope {
    if (empty) return const <String, dynamic>{'items': <dynamic>[], 'total': 0};
    return const <String, dynamic>{
      'items': <dynamic>[
        {
          'id': 1,
          'businessName': 'مزود تنظيف',
          'providerApprovalStatus': 'pending',
        },
      ],
      'total': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> getServiceAdminStats() async {
    return _run(
      empty
          ? const <String, dynamic>{}
          : const <String, dynamic>{
              'providersByStatus': {'pending': 1},
            },
    );
  }

  @override
  Future<Map<String, dynamic>> listPendingServiceProviders({
    String providerStatus = 'pending',
    int limit = 80,
    int offset = 0,
  }) async => _run(_itemsEnvelope);

  @override
  Future<Map<String, dynamic>> listPendingServiceOfferings({
    String offeringStatus = 'pending',
    int limit = 80,
    int offset = 0,
  }) async => _run(
    empty
        ? const <String, dynamic>{'items': <dynamic>[], 'total': 0}
        : const <String, dynamic>{
            'items': <dynamic>[
              {'id': 11, 'name': 'تنظيف شقق', 'moderationStatus': 'pending'},
            ],
            'total': 1,
          },
  );

  @override
  Future<Map<String, dynamic>> listServiceCategorySuggestions({
    String categorySuggestionStatus = 'pending',
    int limit = 80,
    int offset = 0,
  }) async => _run(const <String, dynamic>{'items': <dynamic>[], 'total': 0});

  @override
  Future<Map<String, dynamic>> listServiceReports({
    String status = 'pending',
    int limit = 80,
    int offset = 0,
  }) async => _run(const <String, dynamic>{'items': <dynamic>[], 'total': 0});

  @override
  Future<Map<String, dynamic>> listServiceAdminRequests({
    String? requestStatus,
    int limit = 80,
    int offset = 0,
  }) async => _run(const <String, dynamic>{'items': <dynamic>[], 'total': 0});

  @override
  Future<List<dynamic>> listServiceModuleSettings() async =>
      _run(const <dynamic>[]);
}

DioException _dioFailure({
  required int statusCode,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final requestOptions = RequestOptions(path: '/api/admin/services/stats');
  return DioException(
    requestOptions: requestOptions,
    response: type == DioExceptionType.badResponse
        ? Response<Map<String, dynamic>>(
            requestOptions: requestOptions,
            statusCode: statusCode,
            data: <String, dynamic>{'message': 'SERVER_ERROR'},
          )
        : null,
    type: type,
  );
}

Widget _wrap(Widget child, {AdminApi? api}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _FakeAuthController(ref)),
      adminApiProvider.overrideWithValue(api ?? _FakeAdminApi()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  test(
    'admin API normalizes raw provider and offering lists into items envelopes',
    () async {
      final api = _FakeAdminApi();

      final providers = await api.listPendingServiceProviders();
      expect(providers['items'], isA<List>());
      expect((providers['items'] as List).length, 1);
      expect(providers['total'], 1);

      final offerings = await api.listPendingServiceOfferings();
      expect(offerings['items'], isA<List>());
      expect((offerings['items'] as List).length, 1);
      expect(offerings['total'], 1);
    },
  );

  testWidgets(
    'admin services hub renders pending services and formatted stats',
    (tester) async {
      await tester.pumpWidget(_wrap(const AdminServicesHubScreen()));
      await tester.pumpAndSettle();

      expect(find.text('مزود تنظيف'), findsOneWidget);
      expect(find.textContaining('تنظيف شقق'), findsWidgets);
      expect(find.text('1 عنصر'), findsWidgets);
      expect(find.textContaining('تنظيف شقق · 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('valid admin data is displayed without raw DioException', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const AdminServicesHubScreen(), api: _ScenarioAdminApi()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('مزود تنظيف'), findsOneWidget);
    expect(find.text('تنظيف شقق'), findsWidgets);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('RequestOptions'), findsNothing);
  });

  testWidgets('unauthorized role shows 403 permission UI, not empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AdminServicesHubScreen(),
        api: _ScenarioAdminApi(failure: _dioFailure(statusCode: 403)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('لا تملك صلاحية الوصول إلى إدارة الخدمات.'),
      findsOneWidget,
    );
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.textContaining('لا توجد بيانات حالية'), findsNothing);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('401 shows recovering session message, not raw DioException', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AdminServicesHubScreen(),
        api: _ScenarioAdminApi(failure: _dioFailure(statusCode: 401)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('جارٍ استعادة الجلسة وتحديث البيانات...'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('RequestOptions'), findsNothing);
    expect(find.textContaining('لا توجد بيانات حالية'), findsNothing);
  });

  testWidgets('timeout shows readable network message', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AdminServicesHubScreen(),
        api: _ScenarioAdminApi(
          failure: _dioFailure(
            statusCode: 0,
            type: DioExceptionType.connectionTimeout,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مجدداً.'),
      findsOneWidget,
    );
    expect(find.textContaining('Mozilla'), findsNothing);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('500 shows server message', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AdminServicesHubScreen(),
        api: _ScenarioAdminApi(failure: _dioFailure(statusCode: 500)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل بيانات الخدمات حالياً.'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('real empty 200 renders empty state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AdminServicesHubScreen(),
        api: _ScenarioAdminApi(empty: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('لا توجد بيانات'), findsWidgets);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('retry is disabled while loading to prevent parallel loads', (
    tester,
  ) async {
    final api = _ScenarioAdminApi(delay: const Duration(milliseconds: 200));
    await tester.pumpWidget(_wrap(const AdminServicesHubScreen(), api: api));
    await tester.pump();

    final iconButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.refresh_rounded).first,
    );
    expect(iconButton.onPressed, isNull);

    await tester.pumpAndSettle();
    expect(find.textContaining('DioException'), findsNothing);
  });
}
