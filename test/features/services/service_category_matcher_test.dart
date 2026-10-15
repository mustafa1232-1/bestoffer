import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/services/domain/service_category_matcher.dart';
import 'package:maslaki/features/services/models/service_models.dart';

CentralServiceCatalogItem _category(String key, String title) =>
    CentralServiceCatalogItem(
      key: key,
      title: title,
      subtitle: '',
      icon: '',
      color: '',
      emergency: false,
      executionModes: const [],
      quickIssues: const [],
      questions: const [],
    );

ServiceOfferingModel _offering({
  required String name,
  String? mainCategoryName,
}) => ServiceOfferingModel.fromJson(<String, dynamic>{
  'id': 80,
  'providerId': 1,
  'name': name,
  'mainCategoryName': mainCategoryName,
});

void main() {
  test(
    'medical wound-care service is not duplicated under apartment cleaning',
    () {
      final offering = _offering(
        name: 'ضماده و تنظيف العملية',
        mainCategoryName: 'خدمات طبية',
      );

      expect(
        offeringBelongsToCategory(_category('medical', 'خدمات طبية'), offering),
        isTrue,
      );
      expect(
        offeringBelongsToCategory(
          _category('cleaning', 'تنظيف الشقق'),
          offering,
        ),
        isFalse,
      );
    },
  );

  test('known cleaning root remains in apartment cleaning', () {
    final offering = _offering(
      name: 'تنظيف شقق',
      mainCategoryName: 'تنظيف منازل',
    );

    expect(
      offeringBelongsToCategory(_category('cleaning', 'تنظيف الشقق'), offering),
      isTrue,
    );
    expect(
      offeringBelongsToCategory(_category('medical', 'خدمات طبية'), offering),
      isFalse,
    );
  });

  test(
    'name fallback remains available for offerings without a known root',
    () {
      final offering = _offering(name: 'صبغ شقق');

      expect(
        offeringBelongsToCategory(
          _category('home_maintenance', 'صيانة منزلية'),
          offering,
        ),
        isTrue,
      );
    },
  );
}
