import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/services/data/services_api.dart';
import 'package:maslaki/features/services/ui/service_provider_onboarding_screen.dart';
import 'package:maslaki/features/services/ui/services_marketplace_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  _FakeServicesApi() : super(Dio());

  @override
  Future<List<Map<String, dynamic>>> listPublicCategories() async {
    return <Map<String, dynamic>>[
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
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> searchPublicOfferings({
    String? q,
    int? categoryId,
    int? subcategoryId,
    String? city,
    String? area,
    String sort = 'newest',
    num? minPrice,
    num? maxPrice,
    num? ratingMin,
    bool? availableNow,
    bool? homeService,
    bool? emergency,
    bool? offersOnly,
    String? pricingModel,
    String? pricingUnit,
    int limit = 20,
    int offset = 0,
  }) async {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 1001,
        'providerId': 501,
        'mainCategoryId': 1,
        'mainCategoryName': 'تنظيف',
        'subcategoryId': 11,
        'subcategoryName': 'تنظيف شقق',
        'name': 'تنظيف شقة',
        'description': 'تنظيف شامل للشقة',
        'executionMode': 'home',
        'requiresSchedule': true,
        'requiresProviderApproval': false,
        'estimatedDurationMinutes': 120,
        'hasFixedPrice': false,
        'startsFromPrice': 25000,
        'inspectionRequired': false,
        'customQuoteOnly': false,
        'includesText': 'مواد تنظيف',
        'excludesText': null,
        'materialsText': null,
        'notes': null,
        'isActive': true,
        'isTemporarilyPaused': false,
        'moderationStatus': 'approved',
        'ratingAvg': 4.7,
        'ratingCount': 39,
        'provider': <String, dynamic>{
          'id': 501,
          'businessName': 'شركة النقاء',
          'city': 'بغداد',
          'area': 'الكرخ',
          'ratingAvg': 4.8,
          'ratingCount': 122,
          'completedOrdersCount': 310,
          'hasEmergencyService': true,
          'isFeatured': false,
          'logoUrl': null,
          'approvalStatus': 'approved',
          'averageResponseMinutes': 18,
          'isTemporarilyPaused': false,
        },
        'pricingOptions': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 9001,
            'offeringId': 1001,
            'pricingModel': 'starting_from',
            'pricingUnit': 'job',
            'label': null,
            'amount': 25000,
            'minAmount': null,
            'maxAmount': null,
            'visitFee': null,
            'currency': 'IQD',
            'inspectionRequired': false,
            'isDefault': true,
            'isActive': true,
          },
        ],
        'media': const <Map<String, dynamic>>[],
        'activePromotions': const <Map<String, dynamic>>[],
        'reviews': const <Map<String, dynamic>>[],
        'hasActivePromotion': false,
        'displayPriceText': 'يبدأ من 25000',
        'bookingCta': 'احجز الآن',
      },
    ];
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
  testWidgets(
    'services marketplace renders on narrow mobile without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(const ServicesMarketplaceScreen()));
      await tester.pumpAndSettle();

      expect(find.text('قسم الخدمات'), findsOneWidget);
      expect(find.text('تنظيف شقة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'service provider onboarding renders on narrow mobile without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildApp(const ServiceProviderOnboardingScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('اشتراك صاحب خدمة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
