import 'package:maslaki/features/merchants/models/merchant_model.dart';
import 'package:maslaki/features/merchants/ui/merchant_product_details_screen.dart';
import 'package:maslaki/features/products/models/product_model.dart';
import 'package:maslaki/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrapWithLocale(Widget child, Locale locale) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}

void main() {
  final merchant = MerchantModel(
    id: 7,
    name: 'Health Pharmacy',
    type: 'market',
    activityType: 'pharmacy',
    description: 'Medicines and wellness',
    isOpen: true,
    hasDiscountOffer: false,
    hasFreeDeliveryOffer: false,
    supportsPharmacyWorkflow: true,
  );

  const product = ProductModel(
    id: 11,
    merchantId: 7,
    name: 'Pain Reliever',
    description: '500mg capsules',
    price: 5000,
    discountedPrice: 4500,
    freeDelivery: false,
    requiresPrescription: true,
    requiresReview: true,
    isAvailable: true,
    sortOrder: 0,
  );

  testWidgets('pharmacy product details surface supports Arabic', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapWithLocale(
        MerchantProductDetailsScreen(
          merchant: merchant,
          product: product,
          similarProducts: const [],
          canOrder: true,
          unavailableLabel: 'غير متاح',
          onAddToCart:
              (
                _,
                _, {
                int? selectedVariantId,
                List<Map<String, dynamic>> selectedVariantSelections = const [],
              }) async {},
          onOpenProduct: (_) {},
        ),
        const Locale('ar'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('وصفة مطلوبة'), findsOneWidget);
    expect(find.text('مراجعة صيدلانية'), findsOneWidget);
    expect(find.text('إرسال للوصفة/المراجعة'), findsOneWidget);
    expect(find.text('مواد مشابهة من نفس المتجر'), findsOneWidget);
  });

  testWidgets('pharmacy product details surface supports English', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapWithLocale(
        MerchantProductDetailsScreen(
          merchant: merchant,
          product: product,
          similarProducts: const [],
          canOrder: true,
          unavailableLabel: 'Unavailable',
          onAddToCart:
              (
                _,
                _, {
                int? selectedVariantId,
                List<Map<String, dynamic>> selectedVariantSelections = const [],
              }) async {},
          onOpenProduct: (_) {},
        ),
        const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Prescription required'), findsOneWidget);
    expect(find.text('Pharmacist review'), findsOneWidget);
    expect(find.text('Send for prescription/review'), findsOneWidget);
    expect(find.text('Similar items from this store'), findsOneWidget);
  });
}
