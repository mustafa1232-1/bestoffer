import '../../../core/utils/parsers.dart';

class MerchantDiscoveryModel {
  final DateTime? generatedAt;
  final String? type;
  final MerchantDiscoveryRanking ranking;
  final CustomerShoppingProfile profile;
  final MerchantDiscoveryAlgorithm algorithm;
  final List<MerchantInsightModel> merchants;

  const MerchantDiscoveryModel({
    required this.generatedAt,
    required this.type,
    required this.ranking,
    required this.profile,
    required this.algorithm,
    required this.merchants,
  });

  factory MerchantDiscoveryModel.fromJson(Map<String, dynamic> json) {
    final merchantsRaw = List<dynamic>.from(
      json['merchants'] as List? ?? const <dynamic>[],
    );

    return MerchantDiscoveryModel(
      generatedAt: parseNullableDateTime(json['generatedAt']),
      type: parseNullableString(json['type']),
      ranking: MerchantDiscoveryRanking.fromJson(
        Map<String, dynamic>.from(json['ranking'] as Map? ?? const {}),
      ),
      profile: CustomerShoppingProfile.fromJson(
        Map<String, dynamic>.from(json['profile'] as Map? ?? const {}),
      ),
      algorithm: MerchantDiscoveryAlgorithm.fromJson(
        Map<String, dynamic>.from(json['algorithm'] as Map? ?? const {}),
      ),
      merchants: merchantsRaw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(MerchantInsightModel.fromJson)
          .toList(),
    );
  }

  Map<int, MerchantInsightModel> get insightsByMerchantId =>
      <int, MerchantInsightModel>{
        for (final merchant in merchants) merchant.merchantId: merchant,
      };
}

class MerchantDiscoveryRanking {
  final List<int> fastest;
  final List<int> topRated;
  final List<int> bestOffers;
  final List<int> bestValue;
  final List<int> mostOrdered;
  final List<MerchantReorderCandidate> reorder;

  const MerchantDiscoveryRanking({
    required this.fastest,
    required this.topRated,
    required this.bestOffers,
    required this.bestValue,
    required this.mostOrdered,
    required this.reorder,
  });

  factory MerchantDiscoveryRanking.fromJson(Map<String, dynamic> json) {
    final reorderRaw = List<dynamic>.from(
      json['reorder'] as List? ?? const <dynamic>[],
    );
    return MerchantDiscoveryRanking(
      fastest: _parseIdList(json['fastest']),
      topRated: _parseIdList(json['topRated']),
      bestOffers: _parseIdList(json['bestOffers']),
      bestValue: _parseIdList(json['bestValue']),
      mostOrdered: _parseIdList(json['mostOrdered']),
      reorder: reorderRaw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(MerchantReorderCandidate.fromJson)
          .toList(),
    );
  }
}

class MerchantReorderCandidate {
  final int merchantId;
  final int? lastOrderId;
  final DateTime? lastOrderedAt;
  final int userOrdersCount;
  final int lastOrderItemsCount;
  final double lastOrderTotalAmount;

  const MerchantReorderCandidate({
    required this.merchantId,
    required this.lastOrderId,
    required this.lastOrderedAt,
    required this.userOrdersCount,
    required this.lastOrderItemsCount,
    required this.lastOrderTotalAmount,
  });

  factory MerchantReorderCandidate.fromJson(Map<String, dynamic> json) {
    return MerchantReorderCandidate(
      merchantId: parseInt(json['merchantId']),
      lastOrderId: json['lastOrderId'] == null
          ? null
          : parseInt(json['lastOrderId']),
      lastOrderedAt: parseNullableDateTime(json['lastOrderedAt']),
      userOrdersCount: parseInt(json['userOrdersCount']),
      lastOrderItemsCount: parseInt(json['lastOrderItemsCount']),
      lastOrderTotalAmount: parseDouble(json['lastOrderTotalAmount']),
    );
  }
}

class CustomerShoppingProfile {
  final int ordersCount120d;
  final int deliveredCount120d;
  final double avgOrderValue120d;
  final double totalSpend120d;
  final int ordersCountInCategory120d;
  final double avgOrderValueInCategory120d;
  final String spendingBand;
  final String priceSensitivity;
  final List<ProfileTypeMixItem> preferredMerchantTypeMix;
  final List<ProfileTopMerchantItem> topMerchants;
  final List<ProfileHourItem> peakOrderHours;

  const CustomerShoppingProfile({
    required this.ordersCount120d,
    required this.deliveredCount120d,
    required this.avgOrderValue120d,
    required this.totalSpend120d,
    required this.ordersCountInCategory120d,
    required this.avgOrderValueInCategory120d,
    required this.spendingBand,
    required this.priceSensitivity,
    required this.preferredMerchantTypeMix,
    required this.topMerchants,
    required this.peakOrderHours,
  });

  factory CustomerShoppingProfile.fromJson(Map<String, dynamic> json) {
    final mixRaw = List<dynamic>.from(
      json['preferredMerchantTypeMix'] as List? ?? const <dynamic>[],
    );
    final topMerchantsRaw = List<dynamic>.from(
      json['topMerchants'] as List? ?? const <dynamic>[],
    );
    final peakHoursRaw = List<dynamic>.from(
      json['peakOrderHours'] as List? ?? const <dynamic>[],
    );

    return CustomerShoppingProfile(
      ordersCount120d: parseInt(json['ordersCount120d']),
      deliveredCount120d: parseInt(json['deliveredCount120d']),
      avgOrderValue120d: parseDouble(json['avgOrderValue120d']),
      totalSpend120d: parseDouble(json['totalSpend120d']),
      ordersCountInCategory120d: parseInt(json['ordersCountInCategory120d']),
      avgOrderValueInCategory120d: parseDouble(
        json['avgOrderValueInCategory120d'],
      ),
      spendingBand: parseString(json['spendingBand'], fallback: 'new_customer'),
      priceSensitivity: parseString(
        json['priceSensitivity'],
        fallback: 'balanced',
      ),
      preferredMerchantTypeMix: mixRaw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(ProfileTypeMixItem.fromJson)
          .toList(),
      topMerchants: topMerchantsRaw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(ProfileTopMerchantItem.fromJson)
          .toList(),
      peakOrderHours: peakHoursRaw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(ProfileHourItem.fromJson)
          .toList(),
    );
  }
}

class ProfileTypeMixItem {
  final String type;
  final int ordersCount;

  const ProfileTypeMixItem({required this.type, required this.ordersCount});

  factory ProfileTypeMixItem.fromJson(Map<String, dynamic> json) {
    return ProfileTypeMixItem(
      type: parseString(json['type']),
      ordersCount: parseInt(json['ordersCount']),
    );
  }
}

class ProfileTopMerchantItem {
  final int merchantId;
  final String merchantName;
  final int ordersCount;
  final DateTime? lastOrderedAt;

  const ProfileTopMerchantItem({
    required this.merchantId,
    required this.merchantName,
    required this.ordersCount,
    required this.lastOrderedAt,
  });

  factory ProfileTopMerchantItem.fromJson(Map<String, dynamic> json) {
    return ProfileTopMerchantItem(
      merchantId: parseInt(json['merchantId']),
      merchantName: parseString(json['merchantName']),
      ordersCount: parseInt(json['ordersCount']),
      lastOrderedAt: parseNullableDateTime(json['lastOrderedAt']),
    );
  }
}

class ProfileHourItem {
  final int hour;
  final int ordersCount;

  const ProfileHourItem({required this.hour, required this.ordersCount});

  factory ProfileHourItem.fromJson(Map<String, dynamic> json) {
    return ProfileHourItem(
      hour: parseInt(json['hour']),
      ordersCount: parseInt(json['ordersCount']),
    );
  }
}

class MerchantDiscoveryAlgorithm {
  final String version;
  final bool nearestDistanceUsed;
  final Map<String, double> weights;

  const MerchantDiscoveryAlgorithm({
    required this.version,
    required this.nearestDistanceUsed,
    required this.weights,
  });

  factory MerchantDiscoveryAlgorithm.fromJson(Map<String, dynamic> json) {
    final weightsRaw = Map<String, dynamic>.from(
      json['weights'] as Map? ?? const {},
    );
    return MerchantDiscoveryAlgorithm(
      version: parseString(json['version'], fallback: 'unknown'),
      nearestDistanceUsed: parseBool(
        json['nearestDistanceUsed'],
        fallback: false,
      ),
      weights: <String, double>{
        for (final entry in weightsRaw.entries)
          entry.key: parseDouble(entry.value),
      },
    );
  }
}

class MerchantInsightModel {
  final int merchantId;
  final String name;
  final String type;
  final String? description;
  final String? phone;
  final String? imageUrl;
  final bool isOpen;
  final bool hasDiscountOffer;
  final bool hasFreeDeliveryOffer;
  final int totalOrders;
  final int deliveredOrders;
  final int cancelledOrders;
  final int ratingCount;
  final double avgMerchantRating;
  final double weightedRating;
  final double avgDeliveryMinutes;
  final double onTimeRate;
  final double avgEffectivePrice;
  final double minEffectivePrice;
  final double avgOrderAmount;
  final double maxDiscountPercent;
  final int discountItemsCount;
  final int freeDeliveryItemsCount;
  final double completionRate;
  final String priceTier;
  final double speedScore;
  final double qualityScore;
  final double valueScore;
  final double offerScore;
  final double popularityScore;
  final double compositeScore;
  final int userOrdersCount;
  final int? lastUserOrderId;
  final DateTime? lastUserOrderedAt;
  final double lastUserTotalAmount;
  final int lastUserItemsCount;
  final DateTime? lastOrderedAt;

  const MerchantInsightModel({
    required this.merchantId,
    required this.name,
    required this.type,
    required this.description,
    required this.phone,
    required this.imageUrl,
    required this.isOpen,
    required this.hasDiscountOffer,
    required this.hasFreeDeliveryOffer,
    required this.totalOrders,
    required this.deliveredOrders,
    required this.cancelledOrders,
    required this.ratingCount,
    required this.avgMerchantRating,
    required this.weightedRating,
    required this.avgDeliveryMinutes,
    required this.onTimeRate,
    required this.avgEffectivePrice,
    required this.minEffectivePrice,
    required this.avgOrderAmount,
    required this.maxDiscountPercent,
    required this.discountItemsCount,
    required this.freeDeliveryItemsCount,
    required this.completionRate,
    required this.priceTier,
    required this.speedScore,
    required this.qualityScore,
    required this.valueScore,
    required this.offerScore,
    required this.popularityScore,
    required this.compositeScore,
    required this.userOrdersCount,
    required this.lastUserOrderId,
    required this.lastUserOrderedAt,
    required this.lastUserTotalAmount,
    required this.lastUserItemsCount,
    required this.lastOrderedAt,
  });

  factory MerchantInsightModel.fromJson(Map<String, dynamic> json) {
    return MerchantInsightModel(
      merchantId: parseInt(json['merchantId']),
      name: parseString(json['name']),
      type: parseString(json['type']),
      description: parseNullableString(json['description']),
      phone: parseNullableString(json['phone']),
      imageUrl: parseNullableString(json['imageUrl']),
      isOpen: parseBool(json['isOpen'], fallback: true),
      hasDiscountOffer: parseBool(json['hasDiscountOffer']),
      hasFreeDeliveryOffer: parseBool(json['hasFreeDeliveryOffer']),
      totalOrders: parseInt(json['totalOrders']),
      deliveredOrders: parseInt(json['deliveredOrders']),
      cancelledOrders: parseInt(json['cancelledOrders']),
      ratingCount: parseInt(json['ratingCount']),
      avgMerchantRating: parseDouble(json['avgMerchantRating']),
      weightedRating: parseDouble(json['weightedRating']),
      avgDeliveryMinutes: parseDouble(json['avgDeliveryMinutes']),
      onTimeRate: parseDouble(json['onTimeRate']),
      avgEffectivePrice: parseDouble(json['avgEffectivePrice']),
      minEffectivePrice: parseDouble(json['minEffectivePrice']),
      avgOrderAmount: parseDouble(json['avgOrderAmount']),
      maxDiscountPercent: parseDouble(json['maxDiscountPercent']),
      discountItemsCount: parseInt(json['discountItemsCount']),
      freeDeliveryItemsCount: parseInt(json['freeDeliveryItemsCount']),
      completionRate: parseDouble(json['completionRate']),
      priceTier: parseString(json['priceTier'], fallback: 'unknown'),
      speedScore: parseDouble(json['speedScore']),
      qualityScore: parseDouble(json['qualityScore']),
      valueScore: parseDouble(json['valueScore']),
      offerScore: parseDouble(json['offerScore']),
      popularityScore: parseDouble(json['popularityScore']),
      compositeScore: parseDouble(json['compositeScore']),
      userOrdersCount: parseInt(json['userOrdersCount']),
      lastUserOrderId: json['lastUserOrderId'] == null
          ? null
          : parseInt(json['lastUserOrderId']),
      lastUserOrderedAt: parseNullableDateTime(json['lastUserOrderedAt']),
      lastUserTotalAmount: parseDouble(json['lastUserTotalAmount']),
      lastUserItemsCount: parseInt(json['lastUserItemsCount']),
      lastOrderedAt: parseNullableDateTime(json['lastOrderedAt']),
    );
  }
}

List<int> _parseIdList(dynamic raw) {
  final values = List<dynamic>.from(raw as List? ?? const <dynamic>[]);
  return values.map(parseInt).where((id) => id > 0).toList();
}
