import 'package:maslaki/core/sections/section_availability_controller.dart';
import 'package:maslaki/core/sections/section_availability_models.dart';
import 'package:maslaki/core/files/local_image_file.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/services/data/services_api.dart';
import 'package:maslaki/features/services/models/service_models.dart';
import 'package:maslaki/features/services/ui/central_services_marketplace_screen.dart';
import 'package:maslaki/features/services/ui/central_service_request_screen.dart';
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

class _FakeSectionAvailabilityController extends SectionAvailabilityController {
  _FakeSectionAvailabilityController(super.ref) {
    state = SectionAvailabilityState(
      initialized: true,
      entries: <String, SectionAvailabilityEntry>{
        AppSectionKeys.services: fallbackOpenSectionEntry(
          AppSectionKeys.services,
          displayName: 'Services',
        ),
      },
    );
  }

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> refresh({bool silent = false}) async {}
}

class _FakeServicesApi extends ServicesApi {
  _FakeServicesApi({this.paintingAfterFirstSearch = false}) : super(Dio());

  final bool paintingAfterFirstSearch;
  int searchCalls = 0;

  Map<String, dynamic>? lastCentralRequest;

  @override
  Future<Map<String, dynamic>> createCentralServiceRequest(
    Map<String, dynamic> body, {
    List<LocalImageFile> attachmentFiles = const [],
  }) async {
    lastCentralRequest = Map<String, dynamic>.from(body);
    return <String, dynamic>{'id': 91, 'requestCode': 'SRV-91'};
  }

  @override
  Future<List<Map<String, dynamic>>> listCentralCatalog() async {
    final rows = <Map<String, dynamic>>[
      <String, dynamic>{
        'key': 'home_maintenance',
        'title': 'صيانة منزلية',
        'subtitle': 'كهرباء وسباكة وتبريد وتصليحات',
        'icon': 'home_repair_service',
        'color': '#3F6550',
        'emergency': false,
        'executionModes': <String>['home'],
        'quickIssues': <String>['كهرباء', 'سباكة'],
        'questions': const <Map<String, dynamic>>[],
      },
      <String, dynamic>{
        'key': 'sos',
        'title': 'SOS مساعدة عاجلة',
        'subtitle': 'أرسل موقعك وتفاصيل الحالة فوراً',
        'icon': 'sos',
        'color': '#A33A32',
        'emergency': true,
        'executionModes': <String>['home'],
        'quickIssues': <String>['إسعاف'],
        'questions': const <Map<String, dynamic>>[],
      },
    ];
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> listPublicCategories({String? q}) async {
    final rows = <Map<String, dynamic>>[
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
    return rows;
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
    searchCalls += 1;
    final rows = <Map<String, dynamic>>[
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
    if (paintingAfterFirstSearch && searchCalls > 1) {
      final painting = Map<String, dynamic>.from(rows.first)
        ..addAll(<String, dynamic>{
          'id': 1002,
          'mainCategoryId': 6,
          'mainCategoryName': 'دهان وديكور',
          'subcategoryId': null,
          'subcategoryName': null,
          'name': 'صبغ شقق',
          'description': 'صبغ وطلاء الشقق والمنازل',
        });
      rows.add(painting);
    }
    return rows;
  }
}

Widget _buildApp(Widget home, {ServicesApi? servicesApi}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _FakeAuthController(ref)),
      servicesApiProvider.overrideWithValue(servicesApi ?? _FakeServicesApi()),
      sectionAvailabilityControllerProvider.overrideWith(
        (ref) => _FakeSectionAvailabilityController(ref),
      ),
    ],
    child: MaterialApp(locale: const Locale('ar'), home: home),
  );
}

void main() {
  test('service price displays the operator custom label', () {
    const pricing = ServicePricingOptionModel(
      id: 1,
      offeringId: 2,
      pricingModel: 'fixed_package',
      pricingUnit: 'job',
      label: 'للساعة',
      amount: 5000,
      minAmount: null,
      maxAmount: null,
      visitFee: null,
      currency: 'IQD',
      inspectionRequired: false,
      isDefault: true,
      isActive: true,
    );

    expect(pricing.displayText(), '5,000 للساعة');
    expect(pricing.unitDisplayText(), 'للساعة');
  });

  test(
    'service promotion exposes the price before and after discount',
    () async {
      final rows = await _FakeServicesApi().searchPublicOfferings();
      final raw = Map<String, dynamic>.from(rows.first);
      raw['activePromotions'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 71,
          'title': 'خصم ترحيبي',
          'discountType': 'PERCENTAGE',
          'discountValue': 20,
          'specialPrice': null,
          'isActive': true,
        },
      ];
      final offering = ServiceOfferingModel.fromJson(raw);

      expect(offering.baseUnitPrice, 25000);
      expect(offering.discountedUnitPrice, 20000);
    },
  );

  testWidgets(
    'services marketplace renders on narrow mobile without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(const ServicesMarketplaceScreen()));
      await tester.pumpAndSettle();

      expect(find.text('خدمات مسلكي'), findsOneWidget);
      expect(find.text('صيانة منزلية'), findsOneWidget);
      expect(find.text('SOS مساعدة عاجلة'), findsOneWidget);
      expect(find.text('تنظيف شقة'), findsOneWidget);
      expect(find.text('كن مقدم خدمة'), findsNothing);
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

      expect(find.byType(ServiceProviderOnboardingScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening home maintenance refreshes and reveals painting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildApp(
        const CentralServicesMarketplaceScreen(),
        servicesApi: _FakeServicesApi(paintingAfterFirstSearch: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('صبغ شقق'), findsNothing);
    await tester.tap(find.text('صيانة منزلية'));
    await tester.pumpAndSettle();

    expect(find.text('صبغ شقق'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'central service quick issue prefills required details and saved address',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _FakeServicesApi();
      const service = CentralServiceCatalogItem(
        key: 'home_maintenance',
        title: 'صيانة منزلية',
        subtitle: 'كهرباء وسباكة وتبريد وتصليحات',
        icon: 'home_repair_service',
        color: '#3F6550',
        emergency: false,
        executionModes: <String>['home'],
        quickIssues: <String>['كهرباء', 'سباكة'],
        questions: <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'faultType',
            'label': 'ما نوع العطل؟',
            'type': 'text',
            'required': true,
          },
        ],
      );

      await tester.pumpWidget(
        _buildApp(
          const CentralServiceRequestScreen(service: service),
          servicesApi: api,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('كهرباء'));
      await tester.pump();
      await tester.tap(find.text('إرسال الطلب'));
      await tester.pumpAndSettle();

      expect(api.lastCentralRequest?['quickIssue'], 'كهرباء');
      expect(
        (api.lastCentralRequest?['intakeAnswers'] as Map?)?['faultType'],
        'كهرباء',
      );
      expect(api.lastCentralRequest?['area'], 'بلوك A');
      expect(api.lastCentralRequest?['addressLine'], 'عمارة 10، شقة 2');
      expect(find.text('تم إرسال طلبك'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
