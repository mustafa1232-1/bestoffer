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

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _FakeAuthController(ref)),
      adminApiProvider.overrideWithValue(_FakeAdminApi()),
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
}
