import 'package:maslaki/features/merchants/models/store_activity_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses store activity definition payload', () {
    final model = StoreActivityModel.fromJson({
      'activityType': 'pharmacy',
      'baseType': 'market',
      'displayNameEn': 'Pharmacy',
      'displayNameAr': 'صيدلية',
      'hasDiscoverySubcategories': true,
      'supportsChat': true,
      'supportsAttachments': true,
      'supportsPharmacyWorkflow': true,
      'internalCategoryMode': 'merchant_defined_with_templates_and_constraints',
      'defaultServiceFlags': {'acceptsPrescription': true},
      'defaultBadges': ['24h', 'delivery'],
    });

    expect(model.activityType, 'pharmacy');
    expect(model.baseType, 'market');
    expect(model.hasDiscoverySubcategories, isTrue);
    expect(model.supportsPharmacyWorkflow, isTrue);
    expect(model.defaultServiceFlags['acceptsPrescription'], isTrue);
    expect(model.defaultBadges, contains('24h'));
  });

  test('parses discovery option payload', () {
    final option = StoreDiscoveryOptionModel.fromJson({
      'id': 11,
      'activityType': 'restaurant',
      'code': 'grills',
      'labelEn': 'Grills',
      'labelAr': 'مشويات',
      'orderIndex': 4,
    });

    expect(option.id, 11);
    expect(option.code, 'grills');
    expect(option.localizedLabel(true), 'مشويات');
  });
}
