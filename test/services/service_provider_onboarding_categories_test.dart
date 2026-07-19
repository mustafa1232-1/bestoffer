import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/services/data/services_api.dart';
import 'package:maslaki/features/services/ui/service_provider_onboarding_screen.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref) {
    state = AuthState(
      token: 'test-token',
      user: UserModel(
        id: 7,
        fullName: 'Test User',
        phone: '07700000000',
        role: 'user',
        block: 'A',
        buildingNumber: '10',
        apartment: '2',
        imageUrl: null,
        workTitle: null,
        workCompany: null,
        preferredLocale: 'ar',
        isSuperAdmin: false,
      ),
    );
  }

  @override
  Future<void> bootstrap() async {}
}

class _FakeServicesApi extends ServicesApi {
  final List<Map<String, dynamic>> _categories = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 1,
      'parentId': null,
      'level': 1,
      'name': 'تنظيف',
      'sortOrder': 1,
      'isActive': true,
      'isPublic': true,
      'children': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 11,
          'parentId': 1,
          'level': 2,
          'name': 'تنظيف شقق',
          'sortOrder': 1,
          'isActive': true,
          'isPublic': true,
          'children': const <Map<String, dynamic>>[],
        },
      ],
    },
    <String, dynamic>{
      'id': 2,
      'parentId': null,
      'level': 1,
      'name': 'كهرباء',
      'sortOrder': 2,
      'isActive': true,
      'isPublic': true,
      'children': const <Map<String, dynamic>>[],
    },
  ];

  _FakeServicesApi() : super(Dio());

  @override
  Future<List<Map<String, dynamic>>> listPublicCategories({String? q}) async {
    return _categories;
  }

  @override
  Future<Map<String, dynamic>> createPublicCategory({
    required String name,
    int? parentCategoryId,
  }) async {
    final nextId = _categories.length + 1;
    final category = <String, dynamic>{
      'id': nextId,
      'parentId': parentCategoryId,
      'level': parentCategoryId == null ? 1 : 2,
      'name': name,
      'sortOrder': nextId,
      'isActive': true,
      'isPublic': true,
      'children': const <Map<String, dynamic>>[],
    };
    if (parentCategoryId == null) {
      _categories.add(category);
    } else {
      final parentIndex = _categories.indexWhere(
        (item) => item['id'] == parentCategoryId,
      );
      if (parentIndex != -1) {
        final parent = Map<String, dynamic>.from(_categories[parentIndex]);
        final children = List<Map<String, dynamic>>.from(
          (parent['children'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map((child) => Map<String, dynamic>.from(child)),
        );
        children.add(category);
        parent['children'] = children;
        _categories[parentIndex] = parent;
      }
    }
    return <String, dynamic>{'category': category};
  }
}

Widget _buildApp(Widget home) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _FakeAuthController(ref)),
      servicesApiProvider.overrideWithValue(_FakeServicesApi()),
    ],
    child: MaterialApp(home: home),
  );
}

void main() {
  testWidgets('service onboarding can search and add service categories', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildApp(const ServiceProviderOnboardingScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('service_category_search_field')),
      'كهرباء',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('service_category_dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('كهرباء'), findsWidgets);
    expect(find.text('تنظيف'), findsNothing);

    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('service_category_new_field')),
      'خدمات توصيل',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('service_category_add_button')));
    await tester.pumpAndSettle();

    expect(find.text('خدمات توصيل'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
