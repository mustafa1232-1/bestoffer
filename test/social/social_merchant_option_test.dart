import 'package:flutter_test/flutter_test.dart';
import 'package:social_core/social_models.dart';

void main() {
  test('SocialMerchantOption reads backend activityType', () {
    final merchant = SocialMerchantOption.fromJson({
      'id': 8,
      'name': 'Fashion House',
      'type': 'market',
      'activity_type': 'fashion_clothing',
      'phone': '0770000000',
      'image_url': '/merchant.jpg',
      'can_review': true,
      'eligible_orders_count': 11,
    });

    expect(merchant.type, 'market');
    expect(merchant.activityType, 'fashion_clothing');
    expect(merchant.canReview, isTrue);
    expect(merchant.eligibleOrdersCount, 11);
  });
}
