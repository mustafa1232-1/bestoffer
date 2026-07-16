import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/merchants/models/merchant_model.dart';

void main() {
  group('MerchantModel storefront contract', () {
    test('parses logo/cover/ETA/fee/min-order/verified + hasActiveOffer', () {
      final m = MerchantModel.fromJson(const {
        'id': 7,
        'name': 'متجر بسماية',
        'type': 'market',
        'is_open': true,
        'logo_url': 'https://cdn/x/logo.png',
        'cover_image_url': 'https://cdn/x/cover.png',
        'delivery_eta_min_minutes': 20,
        'delivery_eta_max_minutes': 35,
        'delivery_fee': 3000,
        'minimum_order': 10000,
        'is_verified': true,
        'has_active_offer': true,
        'rating_count': 125,
        'avg_merchant_rating': 4.7,
      });

      expect(m.logoUrl, 'https://cdn/x/logo.png');
      expect(m.coverImageUrl, 'https://cdn/x/cover.png');
      expect(m.deliveryEtaMinMinutes, 20);
      expect(m.deliveryEtaMaxMinutes, 35);
      expect(m.deliveryFee, 3000);
      expect(m.minimumOrder, 10000);
      expect(m.isVerified, true);
      expect(m.hasActiveOffer, true);
      expect(m.hasDeliveryEta, true);
      expect(m.hasDeliveryFee, true);
      expect(m.ratingCount, 125);
      expect(m.avgMerchantRating, 4.7);
    });

    test('unset storefront fields are null (unknown, not fabricated)', () {
      final m = MerchantModel.fromJson(const {
        'id': 8,
        'name': 'متجر جديد',
        'type': 'restaurant',
        'is_open': false,
        'rating_count': 0,
      });

      expect(m.logoUrl, isNull);
      expect(m.coverImageUrl, isNull);
      expect(m.deliveryEtaMinMinutes, isNull);
      expect(m.deliveryFee, isNull);
      expect(m.minimumOrder, isNull);
      expect(m.isVerified, false);
      expect(m.hasDeliveryEta, false);
      expect(m.hasDeliveryFee, false);
      // Zero reviews → the card must show "متجر جديد", i.e. ratingCount == 0.
      expect(m.ratingCount, 0);
    });

    test('hasActiveOffer derives from discount/free-delivery when not provided', () {
      final m = MerchantModel.fromJson(const {
        'id': 9,
        'name': 's',
        'type': 'market',
        'is_open': true,
        'has_free_delivery_offer': true,
      });
      expect(m.hasActiveOffer, true);
    });
  });
}
