import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/files/local_image_file.dart';
import 'package:maslaki/features/services/data/services_api.dart';
import 'package:maslaki/features/services/models/service_models.dart';
import 'package:maslaki/features/services/state/service_provider_workspace_controller.dart';
import 'package:maslaki/features/services/ui/service_provider_workspace_screen.dart';
import 'package:maslaki/core/workspaces/workspace_permissions.dart';

class _FakeServiceProviderWorkspaceController
    extends ServiceProviderWorkspaceController {
  _FakeServiceProviderWorkspaceController(
    super.ref,
    ServiceProviderWorkspaceState initialState,
  ) {
    state = initialState;
  }

  @override
  Future<void> loadWorkspace() async {}

  @override
  Future<void> loadRequests({String? status}) async {}
}

class _FakeServicesApi extends ServicesApi {
  final List<Map<String, dynamic>> _categories = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 1,
      'parentId': null,
      'level': 1,
      'name': 'تنظيف شقق',
      'sortOrder': 1,
      'isActive': true,
      'isPublic': true,
      'children': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 101,
          'parentId': 1,
          'level': 2,
          'name': 'تنظيف عميق',
          'sortOrder': 1,
          'isActive': true,
          'isPublic': true,
          'children': <Map<String, dynamic>>[],
        },
      ],
    },
  ];
  final List<Map<String, dynamic>> createdOfferings = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> updatedOfferings = <Map<String, dynamic>>[];

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
    final existingIds = <int>{
      for (final category in _categories)
        if (category['id'] is num) (category['id'] as num).toInt(),
      for (final category in _categories)
        for (final child
            in (category['children'] as List? ?? const <dynamic>[]))
          if (child is Map && child['id'] is num) (child['id'] as num).toInt(),
    };
    final nextId = existingIds.isEmpty
        ? 101
        : existingIds.reduce((a, b) => a > b ? a : b) + 1;
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
      final rootIndex = _categories.indexWhere(
        (item) => item['id'] == parentCategoryId,
      );
      if (rootIndex != -1) {
        final root = Map<String, dynamic>.from(_categories[rootIndex]);
        final children = List<Map<String, dynamic>>.from(
          (root['children'] as List? ?? const <dynamic>[]).whereType<Map>().map(
            (child) => Map<String, dynamic>.from(child),
          ),
        );
        children.add(category);
        root['children'] = children;
        _categories[rootIndex] = root;
      }
    }

    return <String, dynamic>{'category': category};
  }

  @override
  Future<Map<String, dynamic>> createOffering(
    Map<String, dynamic> body, {
    List<LocalImageFile> mediaFiles = const [],
  }) async {
    createdOfferings.add(Map<String, dynamic>.from(body));
    return <String, dynamic>{
      'offering': <String, dynamic>{
        'id': 900 + createdOfferings.length,
        'name': body['name'],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> updateOffering(
    int offeringId,
    Map<String, dynamic> body, {
    List<LocalImageFile> mediaFiles = const [],
  }) async {
    updatedOfferings.add(<String, dynamic>{
      'offeringId': offeringId,
      ...Map<String, dynamic>.from(body),
    });
    return <String, dynamic>{
      'offering': <String, dynamic>{
        'id': offeringId,
        'name': body['name'] ?? 'Updated Service',
      },
    };
  }
}

ServiceProviderWorkspaceModel _workspace() {
  return ServiceProviderWorkspaceModel.fromJson(<String, dynamic>{
    'provider': <String, dynamic>{
      'id': 88,
      'userId': 7,
      'businessName': 'Atlas Services',
      'logoUrl': null,
      'coverImageUrl': null,
      'mainCategoryName': 'Services',
      'bio': 'Workspace for testing',
      'phone': '07712345678',
      'whatsappPhone': null,
      'city': 'Baghdad',
      'area': 'Karrada',
      'addressLine': 'Main street',
      'servesAtHome': true,
      'servesAtShop': true,
      'servesRemote': false,
      'hasEmergencyService': false,
      'providerApprovalStatus': 'approved',
      'completedOrdersCount': 4,
      'ratingAvg': 4.8,
      'ratingCount': 10,
      'averageResponseMinutes': 15,
      'areas': const <Map<String, dynamic>>[],
      'availabilityRules': const <Map<String, dynamic>>[],
      'offerings': const <Map<String, dynamic>>[],
      'activePromotions': const <Map<String, dynamic>>[],
      'portfolio': const <Map<String, dynamic>>[],
      'reviews': const <Map<String, dynamic>>[],
    },
    'requestCounts': <String, int>{
      'pending': 0,
      'awaiting_provider': 0,
      'accepted': 0,
      'scheduled': 0,
      'in_progress': 0,
      'completed': 0,
    },
    'promotions': const <Map<String, dynamic>>[],
    'access': <String, dynamic>{
      'isOwner': true,
      'permissions': const <String>[],
      'permissionMap': <String, bool>{
        'view_service_requests': true,
        'create_services': true,
        'edit_services': true,
        'manage_employees': true,
        'view_audit_log': true,
      },
      'employeeProfile': null,
    },
    'employees': const <Map<String, dynamic>>[],
    'activityLogs': const <Map<String, dynamic>>[],
    'availablePermissions': workspacePermissionCatalog(
      WorkspacePermissionKind.serviceProvider,
    ),
    'areas': const <Map<String, dynamic>>[],
    'availabilityRules': const <Map<String, dynamic>>[],
    'offerings': const <Map<String, dynamic>>[],
    'portfolio': const <Map<String, dynamic>>[],
  });
}

ServiceProviderWorkspaceModel _workspaceWithOfferings(
  List<Map<String, dynamic>> offerings,
) {
  final workspace = _workspace();
  return ServiceProviderWorkspaceModel.fromJson(<String, dynamic>{
    'provider': <String, dynamic>{
      'id': workspace.provider.id,
      'userId': workspace.provider.userId,
      'businessName': workspace.provider.businessName,
      'logoUrl': workspace.provider.logoUrl,
      'coverImageUrl': workspace.provider.coverImageUrl,
      'mainCategoryName': workspace.provider.mainCategoryName,
      'bio': workspace.provider.bio,
      'phone': workspace.provider.phone,
      'whatsappPhone': workspace.provider.whatsappPhone,
      'city': workspace.provider.city,
      'area': workspace.provider.area,
      'addressLine': workspace.provider.addressLine,
      'servesAtHome': workspace.provider.servesAtHome,
      'servesAtShop': workspace.provider.servesAtShop,
      'servesRemote': workspace.provider.servesRemote,
      'hasEmergencyService': workspace.provider.hasEmergencyService,
      'providerApprovalStatus': workspace.provider.providerApprovalStatus,
      'completedOrdersCount': workspace.provider.completedOrdersCount,
      'ratingAvg': workspace.provider.ratingAvg,
      'ratingCount': workspace.provider.ratingCount,
      'averageResponseMinutes': workspace.provider.averageResponseMinutes,
      'areas': const <Map<String, dynamic>>[],
      'availabilityRules': const <Map<String, dynamic>>[],
      'offerings': offerings,
      'activePromotions': const <Map<String, dynamic>>[],
      'portfolio': const <Map<String, dynamic>>[],
      'reviews': const <Map<String, dynamic>>[],
    },
    'requestCounts': <String, int>{
      'pending': 0,
      'awaiting_provider': 0,
      'accepted': 0,
      'scheduled': 0,
      'in_progress': 0,
      'completed': 0,
    },
    'promotions': const <Map<String, dynamic>>[],
    'access': <String, dynamic>{
      'isOwner': true,
      'permissions': const <String>[],
      'permissionMap': <String, bool>{
        'view_service_requests': true,
        'create_services': true,
        'edit_services': true,
        'manage_employees': true,
        'view_audit_log': true,
      },
      'employeeProfile': null,
    },
    'employees': const <Map<String, dynamic>>[],
    'activityLogs': const <Map<String, dynamic>>[],
    'availablePermissions': workspacePermissionCatalog(
      WorkspacePermissionKind.serviceProvider,
    ),
    'areas': const <Map<String, dynamic>>[],
    'availabilityRules': const <Map<String, dynamic>>[],
    'offerings': offerings,
    'portfolio': const <Map<String, dynamic>>[],
  });
}

void main() {
  testWidgets(
    'service provider employee dialog uses service permissions only',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serviceProviderWorkspaceControllerProvider.overrideWith(
              (ref) => _FakeServiceProviderWorkspaceController(
                ref,
                ServiceProviderWorkspaceState(workspace: _workspace()),
              ),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            home: ServiceProviderWorkspaceScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inviteButton = find.byIcon(Icons.person_add_alt_1_outlined);
      expect(inviteButton, findsOneWidget);
      await tester.ensureVisible(inviteButton);
      await tester.tap(inviteButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Invite employee'), findsOneWidget);
      expect(find.textContaining('View service requests'), findsWidgets);
      expect(find.textContaining('Manage employees'), findsWidgets);
      expect(find.textContaining('View orders'), findsNothing);
    },
  );

  testWidgets(
    'service provider can add a subcategory from the create offering dialog',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serviceProviderWorkspaceControllerProvider.overrideWith(
              (ref) => _FakeServiceProviderWorkspaceController(
                ref,
                ServiceProviderWorkspaceState(workspace: _workspace()),
              ),
            ),
            servicesApiProvider.overrideWithValue(_FakeServicesApi()),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: ServiceProviderWorkspaceScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final createButton = find.text('خدمة جديدة');
      expect(createButton, findsOneWidget);
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('service_subcategory_dropdown')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('service_add_subcategory_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('service_add_subcategory_button')));
      await tester.pumpAndSettle();

      expect(find.text('إضافة فئة فرعية'), findsWidgets);

      await tester.enterText(find.byType(TextField).last, 'تنظيف حمامات');
      await tester.tap(find.text('حفظ').last);
      await tester.pumpAndSettle();

      expect(find.text('تنظيف حمامات'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'service provider can create an offering without crashing after submit',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeApi = _FakeServicesApi();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serviceProviderWorkspaceControllerProvider.overrideWith(
              (ref) => _FakeServiceProviderWorkspaceController(
                ref,
                ServiceProviderWorkspaceState(workspace: _workspace()),
              ),
            ),
            servicesApiProvider.overrideWithValue(fakeApi),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: ServiceProviderWorkspaceScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final createButton = find.text('خدمة جديدة');
      expect(createButton, findsOneWidget);
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('service_add_subcategory_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'تنظيف حمامات');
      await tester.tap(find.text('حفظ').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'تنظيف شقق');
      await tester.enterText(find.byType(TextField).at(1), 'تنظيف شامل للشقة');

      await tester.tap(find.text('إنشاء').last);
      await tester.pumpAndSettle();

      expect(fakeApi.createdOfferings, hasLength(1));
      expect(fakeApi.createdOfferings.single['name'], 'تنظيف شقق');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'service provider can edit a moderated offering and resubmit it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeApi = _FakeServicesApi();
      final workspace = _workspaceWithOfferings([
        <String, dynamic>{
          'id': 901,
          'providerId': 88,
          'mainCategoryId': 1,
          'mainCategoryName': 'تنظيف شقق',
          'subcategoryId': 101,
          'subcategoryName': 'تنظيف عميق',
          'name': 'تنظيف شقق',
          'description': 'وصف الخدمة',
          'executionMode': 'both',
          'requiresSchedule': false,
          'requiresProviderApproval': true,
          'estimatedDurationMinutes': 90,
          'hasFixedPrice': false,
          'startsFromPrice': 35000,
          'inspectionRequired': true,
          'customQuoteOnly': false,
          'includesText': 'Included',
          'excludesText': 'Excluded',
          'materialsText': 'Materials',
          'notes': 'ملاحظة',
          'moderationNote': 'يرجى إضافة صورة أوضح للخدمة',
          'isActive': true,
          'isTemporarilyPaused': false,
          'moderationStatus': 'changes_requested',
          'ratingAvg': 4.6,
          'ratingCount': 8,
          'provider': <String, dynamic>{
            'id': 88,
            'businessName': 'Atlas Services',
            'city': 'Baghdad',
            'area': 'Karrada',
            'ratingAvg': 4.8,
            'ratingCount': 10,
            'completedOrdersCount': 4,
            'hasEmergencyService': false,
            'isFeatured': false,
            'logoUrl': null,
            'approvalStatus': 'approved',
            'averageResponseMinutes': 15,
            'isTemporarilyPaused': false,
          },
          'pricingOptions': const <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'offeringId': 901,
              'pricingModel': 'custom_quote',
              'pricingUnit': 'job',
              'label': 'Default',
              'amount': null,
              'minAmount': null,
              'maxAmount': null,
              'visitFee': null,
              'currency': 'IQD',
              'inspectionRequired': true,
              'isDefault': true,
              'isActive': true,
            },
          ],
          'media': const <Map<String, dynamic>>[],
          'activePromotions': const <Map<String, dynamic>>[],
          'reviews': const <Map<String, dynamic>>[],
          'hasActivePromotion': false,
          'displayPriceText': 'بعد المعاينة',
          'bookingCta': 'اطلب الخدمة',
        },
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serviceProviderWorkspaceControllerProvider.overrideWith(
              (ref) => _FakeServiceProviderWorkspaceController(
                ref,
                ServiceProviderWorkspaceState(workspace: workspace),
              ),
            ),
            servicesApiProvider.overrideWithValue(fakeApi),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: ServiceProviderWorkspaceScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final editButton = find.text('تعديل');
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      expect(find.text('تعديل الخدمة'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'تنظيف شقق مطور');
      await tester.tap(find.text('حفظ التعديلات'));
      await tester.pumpAndSettle();

      expect(fakeApi.updatedOfferings, hasLength(1));
      expect(fakeApi.updatedOfferings.single['offeringId'], 901);
      expect(fakeApi.updatedOfferings.single['name'], 'تنظيف شقق مطور');
      expect(tester.takeException(), isNull);
    },
  );
}
