import 'package:maslaki/core/files/local_image_file.dart';
import 'package:maslaki/features/auth/presentation/owner_register_screen.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/merchants/models/store_activity_model.dart';
import 'package:maslaki/features/merchants/state/merchants_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAuthController extends AuthController {
  _RecordingAuthController(super.ref);

  int registerOwnerCalls = 0;
  Map<String, dynamic>? lastPayload;

  @override
  Future<void> registerOwner(
    Map<String, dynamic> dto, {
    LocalImageFile? ownerImageFile,
    LocalImageFile? merchantImageFile,
  }) async {
    registerOwnerCalls += 1;
    lastPayload = dto;
    state = state.copyWith(
      loading: false,
      error: null,
      clearValidationError: true,
      clearErrorCode: true,
    );
  }
}

class _FakeMerchantsController extends MerchantsController {
  _FakeMerchantsController(super.ref);

  @override
  Future<void> load({String? type, String? search, bool force = false}) async {}

  @override
  Future<List<StoreActivityModel>> listActivities() async {
    return const <StoreActivityModel>[
      StoreActivityModel(
        activityType: 'pharmacy',
        baseType: 'market',
        displayNameEn: 'Pharmacy',
        displayNameAr: 'صيدلية',
        hasDiscoverySubcategories: true,
        supportsChat: true,
        supportsAttachments: true,
        supportsPharmacyWorkflow: true,
        internalCategoryMode: 'merchant_defined_with_templates_and_constraints',
        defaultServiceFlags: <String, dynamic>{'acceptsPrescriptions': true},
        defaultBadges: <String>['prescriptions'],
      ),
    ];
  }

  @override
  Future<List<StoreDiscoveryOptionModel>> listDiscoveryOptions({
    required String activityType,
  }) async {
    return const <StoreDiscoveryOptionModel>[
      StoreDiscoveryOptionModel(
        id: 1,
        activityType: 'pharmacy',
        code: 'prescriptions',
        labelEn: 'Prescriptions',
        labelAr: 'وصفات طبية',
        orderIndex: 1,
        metadata: <String, dynamic>{},
      ),
    ];
  }
}

Future<_RecordingAuthController> _pumpScreen(WidgetTester tester) async {
  late _RecordingAuthController authController;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) {
          authController = _RecordingAuthController(ref);
          return authController;
        }),
        merchantsControllerProvider.overrideWith(
          (ref) => _FakeMerchantsController(ref),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: OwnerRegisterScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return authController;
}

AppLocalizations _l10n(WidgetTester tester) {
  return AppLocalizations.of(tester.element(find.byType(OwnerRegisterScreen)));
}

void main() {
  testWidgets('activity selection is required before moving to details', (
    tester,
  ) async {
    await _pumpScreen(tester);
    final l10n = _l10n(tester);

    final continueFinder = find.text(l10n.commonContinue);
    await tester.ensureVisible(continueFinder);
    await tester.tap(continueFinder);
    await tester.pumpAndSettle();

    expect(find.text(l10n.validationReviewRequiredFields), findsOneWidget);
    expect(find.text(l10n.ownerRegisterLoginPhoneLabel), findsNothing);
  });

  testWidgets('activity list loads and shows pharmacy option', (tester) async {
    await _pumpScreen(tester);
    final l10n = _l10n(tester);

    expect(find.text('Pharmacy'), findsOneWidget);
    expect(find.text(l10n.commonContinue), findsOneWidget);
  });

  testWidgets(
    'discovery selection is required unless all categories is enabled',
    (tester) async {
      await _pumpScreen(tester);
      final l10n = _l10n(tester);

      await tester.tap(find.text('Pharmacy'));
      await tester.pumpAndSettle();

      final continueFinder = find.text(l10n.commonContinue);
      await tester.ensureVisible(continueFinder);
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();

      expect(find.text(l10n.ownerRegisterLoginPhoneLabel), findsNothing);
      expect(find.text(l10n.validationReviewRequiredFields), findsOneWidget);

      final allCategoriesFinder = find.text(
        l10n.addMerchantDiscoverySelectAllLabel,
      );
      await tester.ensureVisible(allCategoriesFinder);
      await tester.tap(allCategoriesFinder);
      await tester.pumpAndSettle();

      await tester.ensureVisible(continueFinder);
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();

      expect(find.text(l10n.ownerRegisterAccountOnly), findsOneWidget);
      expect(find.text(l10n.ownerRegisterLoginPhoneLabel), findsOneWidget);
    },
  );
}
