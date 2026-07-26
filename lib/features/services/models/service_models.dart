import '../../../core/utils/parsers.dart';

double? parseNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return tryParseLocalizedDouble(text);
  }
  return null;
}

class ServiceCategoryModel {
  final int id;
  final int? parentId;
  final int level;
  final String name;
  final int sortOrder;
  final bool isActive;
  final bool isPublic;
  final List<ServiceCategoryModel> children;

  const ServiceCategoryModel({
    required this.id,
    required this.parentId,
    required this.level,
    required this.name,
    required this.sortOrder,
    required this.isActive,
    required this.isPublic,
    this.children = const <ServiceCategoryModel>[],
  });

  factory ServiceCategoryModel.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'] is List
        ? List<dynamic>.from(json['children'] as List)
        : const <dynamic>[];
    return ServiceCategoryModel(
      id: parseInt(json['id']),
      parentId: json['parentId'] == null ? null : parseInt(json['parentId']),
      level: parseInt(json['level']),
      name: parseString(json['name']),
      sortOrder: parseInt(json['sortOrder']),
      isActive: parseBool(json['isActive']),
      isPublic: parseBool(json['isPublic']),
      children: rawChildren
          .whereType<Map>()
          .map(
            (e) => ServiceCategoryModel.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
    );
  }
}

class ServicePricingOptionModel {
  final int id;
  final int offeringId;
  final String pricingModel;
  final String pricingUnit;
  final String? label;
  final double? amount;
  final double? minAmount;
  final double? maxAmount;
  final double? visitFee;
  final String currency;
  final bool inspectionRequired;
  final bool isDefault;
  final bool isActive;

  const ServicePricingOptionModel({
    required this.id,
    required this.offeringId,
    required this.pricingModel,
    required this.pricingUnit,
    required this.label,
    required this.amount,
    required this.minAmount,
    required this.maxAmount,
    required this.visitFee,
    required this.currency,
    required this.inspectionRequired,
    required this.isDefault,
    required this.isActive,
  });

  factory ServicePricingOptionModel.fromJson(Map<String, dynamic> json) {
    return ServicePricingOptionModel(
      id: parseInt(json['id']),
      offeringId: parseInt(json['offeringId']),
      pricingModel: parseString(json['pricingModel']),
      pricingUnit: parseString(json['pricingUnit']),
      label: parseNullableString(json['label']),
      amount: parseNullableDouble(json['amount']),
      minAmount: parseNullableDouble(json['minAmount']),
      maxAmount: parseNullableDouble(json['maxAmount']),
      visitFee: parseNullableDouble(json['visitFee']),
      currency: parseString(json['currency'], fallback: 'IQD'),
      inspectionRequired: parseBool(json['inspectionRequired']),
      isDefault: parseBool(json['isDefault']),
      isActive: parseBool(json['isActive'], fallback: true),
    );
  }

  String displayText() {
    if (pricingModel == 'inspection_required') return 'حسب المعاينة';
    if (pricingModel == 'custom_quote') return 'تسعير مخصص';
    if (pricingModel == 'starting_from' && amount != null) {
      return 'يبدأ من ${amount!.toStringAsFixed(amount!.truncateToDouble() == amount ? 0 : 2)}';
    }
    if (amount == null) return 'بعد المعاينة';
    final amountText = amount!.toStringAsFixed(
      amount!.truncateToDouble() == amount ? 0 : 2,
    );
    return '$amountText / ${_pricingUnitLabel(pricingUnit)}';
  }

  static String _pricingUnitLabel(String value) {
    switch (value) {
      case 'hour':
        return 'ساعة';
      case 'visit':
        return 'زيارة';
      case 'day':
        return 'يوم';
      case 'device':
        return 'جهاز';
      case 'room':
        return 'غرفة';
      case 'meter':
        return 'متر';
      case 'item':
        return 'قطعة';
      case 'package':
        return 'باقة';
      case 'job':
        return 'خدمة';
      default:
        return value;
    }
  }
}

class ServiceProviderSummaryModel {
  final int id;
  final String? businessName;
  final String? city;
  final String? area;
  final double? ratingAvg;
  final int? ratingCount;
  final int? completedOrdersCount;
  final bool hasEmergencyService;
  final bool isFeatured;
  final String? logoUrl;
  final String? approvalStatus;
  final int? averageResponseMinutes;
  final bool isTemporarilyPaused;

  const ServiceProviderSummaryModel({
    required this.id,
    required this.businessName,
    required this.city,
    required this.area,
    required this.ratingAvg,
    required this.ratingCount,
    required this.completedOrdersCount,
    required this.hasEmergencyService,
    required this.isFeatured,
    required this.logoUrl,
    required this.approvalStatus,
    required this.averageResponseMinutes,
    required this.isTemporarilyPaused,
  });

  factory ServiceProviderSummaryModel.fromJson(Map<String, dynamic> json) {
    return ServiceProviderSummaryModel(
      id: parseInt(json['id']),
      businessName: parseNullableString(json['businessName']),
      city: parseNullableString(json['city']),
      area: parseNullableString(json['area']),
      ratingAvg: parseNullableDouble(json['ratingAvg']),
      ratingCount: parseNullableInt(json['ratingCount']),
      completedOrdersCount: parseNullableInt(json['completedOrdersCount']),
      hasEmergencyService: parseBool(json['hasEmergencyService']),
      isFeatured: parseBool(json['isFeatured']),
      logoUrl: parseNullableString(json['logoUrl']),
      approvalStatus: parseNullableString(json['approvalStatus']),
      averageResponseMinutes: parseNullableInt(json['averageResponseMinutes']),
      isTemporarilyPaused: parseBool(json['isTemporarilyPaused']),
    );
  }
}

class ServicePromotionModel {
  final int id;
  final String title;
  final String? description;
  final String discountType;
  final double? discountValue;
  final double? specialPrice;
  final String? startsAt;
  final String? endsAt;
  final String? badgeColor;
  final bool isActive;

  const ServicePromotionModel({
    required this.id,
    required this.title,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.specialPrice,
    required this.startsAt,
    required this.endsAt,
    required this.badgeColor,
    required this.isActive,
  });

  factory ServicePromotionModel.fromJson(Map<String, dynamic> json) {
    return ServicePromotionModel(
      id: parseInt(json['id']),
      title: parseString(json['title']),
      description: parseNullableString(json['description']),
      discountType: parseString(json['discountType']),
      discountValue: parseNullableDouble(json['discountValue']),
      specialPrice: parseNullableDouble(json['specialPrice']),
      startsAt: parseNullableString(json['startsAt']),
      endsAt: parseNullableString(json['endsAt']),
      badgeColor: parseNullableString(json['badgeColor']),
      isActive: parseBool(json['isActive'], fallback: true),
    );
  }
}

class ServiceMediaModel {
  final int id;
  final String mediaUrl;
  final String mediaKind;

  const ServiceMediaModel({
    required this.id,
    required this.mediaUrl,
    required this.mediaKind,
  });

  factory ServiceMediaModel.fromJson(Map<String, dynamic> json) {
    return ServiceMediaModel(
      id: parseInt(json['id']),
      mediaUrl: parseString(json['mediaUrl']),
      mediaKind: parseString(json['mediaKind'], fallback: 'image'),
    );
  }
}

class ServiceReviewModel {
  final int id;
  final int requestId;
  final int rating;
  final String? comment;
  final String? customerFullName;
  final String? customerImageUrl;
  final String? createdAt;

  const ServiceReviewModel({
    required this.id,
    required this.requestId,
    required this.rating,
    required this.comment,
    required this.customerFullName,
    required this.customerImageUrl,
    required this.createdAt,
  });

  factory ServiceReviewModel.fromJson(Map<String, dynamic> json) {
    return ServiceReviewModel(
      id: parseInt(json['id']),
      requestId: parseInt(json['requestId']),
      rating: parseInt(json['rating']),
      comment: parseNullableString(json['comment']),
      customerFullName: parseNullableString(json['customerFullName']),
      customerImageUrl: parseNullableString(json['customerImageUrl']),
      createdAt: parseNullableString(json['createdAt']),
    );
  }
}

class ServiceOfferingModel {
  final int id;
  final int providerId;
  final int? mainCategoryId;
  final String? mainCategoryName;
  final int? subcategoryId;
  final String? subcategoryName;
  final String name;
  final String? description;
  final String executionMode;
  final bool requiresSchedule;
  final bool requiresProviderApproval;
  final int? estimatedDurationMinutes;
  final bool hasFixedPrice;
  final double? startsFromPrice;
  final bool inspectionRequired;
  final bool customQuoteOnly;
  final String? includesText;
  final String? excludesText;
  final String? materialsText;
  final String? notes;
  final String? moderationNote;
  final bool isActive;
  final bool isTemporarilyPaused;
  final String moderationStatus;
  final double ratingAvg;
  final int ratingCount;
  final ServiceProviderSummaryModel provider;
  final List<ServicePricingOptionModel> pricingOptions;
  final List<ServiceMediaModel> media;
  final List<ServicePromotionModel> activePromotions;
  final List<ServiceReviewModel> reviews;
  final bool hasActivePromotion;
  final String displayPriceText;
  final String bookingCta;

  const ServiceOfferingModel({
    required this.id,
    required this.providerId,
    required this.mainCategoryId,
    required this.mainCategoryName,
    required this.subcategoryId,
    required this.subcategoryName,
    required this.name,
    required this.description,
    required this.executionMode,
    required this.requiresSchedule,
    required this.requiresProviderApproval,
    required this.estimatedDurationMinutes,
    required this.hasFixedPrice,
    required this.startsFromPrice,
    required this.inspectionRequired,
    required this.customQuoteOnly,
    required this.includesText,
    required this.excludesText,
    required this.materialsText,
    required this.notes,
    required this.moderationNote,
    required this.isActive,
    required this.isTemporarilyPaused,
    required this.moderationStatus,
    required this.ratingAvg,
    required this.ratingCount,
    required this.provider,
    required this.pricingOptions,
    required this.media,
    required this.activePromotions,
    required this.reviews,
    required this.hasActivePromotion,
    required this.displayPriceText,
    required this.bookingCta,
  });

  factory ServiceOfferingModel.fromJson(Map<String, dynamic> json) {
    final pricingOptions = (json['pricingOptions'] is List)
        ? List<dynamic>.from(json['pricingOptions'] as List)
              .whereType<Map>()
              .map(
                (e) => ServicePricingOptionModel.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
        : const <ServicePricingOptionModel>[];

    final media = (json['media'] is List)
        ? List<dynamic>.from(json['media'] as List)
              .whereType<Map>()
              .map(
                (e) => ServiceMediaModel.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : const <ServiceMediaModel>[];

    final promotions = (json['activePromotions'] is List)
        ? List<dynamic>.from(json['activePromotions'] as List)
              .whereType<Map>()
              .map(
                (e) => ServicePromotionModel.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
        : const <ServicePromotionModel>[];

    final reviews = (json['reviews'] is List)
        ? List<dynamic>.from(json['reviews'] as List)
              .whereType<Map>()
              .map(
                (e) =>
                    ServiceReviewModel.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : const <ServiceReviewModel>[];

    final providerJson = json['provider'] is Map
        ? Map<String, dynamic>.from(json['provider'] as Map)
        : <String, dynamic>{'id': json['providerId']};

    final leadPricing = pricingOptions.firstWhere(
      (item) => item.isDefault,
      orElse: () => pricingOptions.isNotEmpty
          ? pricingOptions.first
          : _emptyPricing(json),
    );

    final fallbackPrice = leadPricing.id > 0
        ? leadPricing.displayText()
        : parseString(json['displayPriceText'], fallback: 'بعد المعاينة');

    return ServiceOfferingModel(
      id: parseInt(json['id']),
      providerId: parseInt(json['providerId']),
      mainCategoryId: parseNullableInt(json['mainCategoryId']),
      mainCategoryName: parseNullableString(json['mainCategoryName']),
      subcategoryId: parseNullableInt(json['subcategoryId']),
      subcategoryName: parseNullableString(json['subcategoryName']),
      name: parseString(json['name']),
      description: parseNullableString(json['description']),
      executionMode: parseString(json['executionMode'], fallback: 'both'),
      requiresSchedule: parseBool(json['requiresSchedule']),
      requiresProviderApproval: parseBool(json['requiresProviderApproval']),
      estimatedDurationMinutes: parseNullableInt(
        json['estimatedDurationMinutes'],
      ),
      hasFixedPrice: parseBool(json['hasFixedPrice']),
      startsFromPrice: parseNullableDouble(json['startsFromPrice']),
      inspectionRequired: parseBool(json['inspectionRequired']),
      customQuoteOnly: parseBool(json['customQuoteOnly']),
      includesText: parseNullableString(json['includesText']),
      excludesText: parseNullableString(json['excludesText']),
      materialsText: parseNullableString(json['materialsText']),
      notes: parseNullableString(json['notes']),
      moderationNote: parseNullableString(
        json['moderationNote'] ?? json['moderation_note'],
      ),
      isActive: parseBool(json['isActive'], fallback: true),
      isTemporarilyPaused: parseBool(json['isTemporarilyPaused']),
      moderationStatus: parseString(
        json['moderationStatus'],
        fallback: 'pending',
      ),
      ratingAvg: parseDouble(json['ratingAvg']),
      ratingCount: parseInt(json['ratingCount']),
      provider: ServiceProviderSummaryModel.fromJson(providerJson),
      pricingOptions: pricingOptions,
      media: media,
      activePromotions: promotions,
      reviews: reviews,
      hasActivePromotion:
          parseBool(json['hasActivePromotion']) || promotions.isNotEmpty,
      displayPriceText: parseString(
        json['displayPriceText'],
        fallback: fallbackPrice,
      ),
      bookingCta: parseString(json['bookingCta'], fallback: 'اطلب الخدمة'),
    );
  }

  String? get primaryMediaUrl => media.isNotEmpty ? media.first.mediaUrl : null;

  static ServicePricingOptionModel _emptyPricing(Map<String, dynamic> json) {
    return ServicePricingOptionModel(
      id: 0,
      offeringId: parseInt(json['id']),
      pricingModel: 'custom_quote',
      pricingUnit: 'job',
      label: null,
      amount: null,
      minAmount: null,
      maxAmount: null,
      visitFee: null,
      currency: 'IQD',
      inspectionRequired: true,
      isDefault: true,
      isActive: true,
    );
  }
}

class ServiceProviderProfileModel {
  final int id;
  final int userId;
  final String businessName;
  final String? logoUrl;
  final String? coverImageUrl;
  final String? mainCategoryName;
  final String? bio;
  final String? phone;
  final String? whatsappPhone;
  final String? city;
  final String? area;
  final String? addressLine;
  final bool servesAtHome;
  final bool servesAtShop;
  final bool servesRemote;
  final bool hasEmergencyService;
  final String providerApprovalStatus;
  final int completedOrdersCount;
  final double ratingAvg;
  final int ratingCount;
  final int? averageResponseMinutes;
  final List<Map<String, dynamic>> areas;
  final List<Map<String, dynamic>> availabilityRules;
  final List<ServiceOfferingModel> offerings;
  final List<ServicePromotionModel> activePromotions;
  final List<Map<String, dynamic>> portfolio;
  final List<ServiceReviewModel> reviews;

  const ServiceProviderProfileModel({
    required this.id,
    required this.userId,
    required this.businessName,
    required this.logoUrl,
    required this.coverImageUrl,
    required this.mainCategoryName,
    required this.bio,
    required this.phone,
    required this.whatsappPhone,
    required this.city,
    required this.area,
    required this.addressLine,
    required this.servesAtHome,
    required this.servesAtShop,
    required this.servesRemote,
    required this.hasEmergencyService,
    required this.providerApprovalStatus,
    required this.completedOrdersCount,
    required this.ratingAvg,
    required this.ratingCount,
    required this.averageResponseMinutes,
    required this.areas,
    required this.availabilityRules,
    required this.offerings,
    required this.activePromotions,
    required this.portfolio,
    required this.reviews,
  });

  factory ServiceProviderProfileModel.fromJson(Map<String, dynamic> json) {
    final offerings = (json['offerings'] is List)
        ? List<dynamic>.from(json['offerings'] as List)
              .whereType<Map>()
              .map(
                (e) =>
                    ServiceOfferingModel.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : const <ServiceOfferingModel>[];

    final promotions = (json['activePromotions'] is List)
        ? List<dynamic>.from(json['activePromotions'] as List)
              .whereType<Map>()
              .map(
                (e) => ServicePromotionModel.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
        : const <ServicePromotionModel>[];

    final reviews = (json['reviews'] is List)
        ? List<dynamic>.from(json['reviews'] as List)
              .whereType<Map>()
              .map(
                (e) =>
                    ServiceReviewModel.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : const <ServiceReviewModel>[];

    return ServiceProviderProfileModel(
      id: parseInt(json['id']),
      userId: parseInt(json['userId']),
      businessName: parseString(json['businessName']),
      logoUrl: parseNullableString(json['logoUrl']),
      coverImageUrl: parseNullableString(json['coverImageUrl']),
      mainCategoryName: parseNullableString(json['mainCategoryName']),
      bio: parseNullableString(json['bio']),
      phone: parseNullableString(json['phone']),
      whatsappPhone: parseNullableString(json['whatsappPhone']),
      city: parseNullableString(json['city']),
      area: parseNullableString(json['area']),
      addressLine: parseNullableString(json['addressLine']),
      servesAtHome: parseBool(json['servesAtHome'], fallback: true),
      servesAtShop: parseBool(json['servesAtShop']),
      servesRemote: parseBool(json['servesRemote']),
      hasEmergencyService: parseBool(json['hasEmergencyService']),
      providerApprovalStatus: parseString(
        json['providerApprovalStatus'],
        fallback: 'pending',
      ),
      completedOrdersCount: parseInt(json['completedOrdersCount']),
      ratingAvg: parseDouble(json['ratingAvg']),
      ratingCount: parseInt(json['ratingCount']),
      averageResponseMinutes: parseNullableInt(json['averageResponseMinutes']),
      areas: (json['areas'] is List)
          ? List<dynamic>.from(
              json['areas'] as List,
            ).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const <Map<String, dynamic>>[],
      availabilityRules: (json['availabilityRules'] is List)
          ? List<dynamic>.from(
              json['availabilityRules'] as List,
            ).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const <Map<String, dynamic>>[],
      offerings: offerings,
      activePromotions: promotions,
      portfolio: (json['portfolio'] is List)
          ? List<dynamic>.from(
              json['portfolio'] as List,
            ).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const <Map<String, dynamic>>[],
      reviews: reviews,
    );
  }
}

class ServiceQuoteModel {
  final int id;
  final int requestId;
  final int roundNo;
  final String quoteStatus;
  final String pricingModel;
  final String pricingUnit;
  final double? amount;
  final double? minAmount;
  final double? maxAmount;
  final double? visitFee;
  final String currency;
  final String? note;
  final String? createdAt;

  const ServiceQuoteModel({
    required this.id,
    required this.requestId,
    required this.roundNo,
    required this.quoteStatus,
    required this.pricingModel,
    required this.pricingUnit,
    required this.amount,
    required this.minAmount,
    required this.maxAmount,
    required this.visitFee,
    required this.currency,
    required this.note,
    required this.createdAt,
  });

  factory ServiceQuoteModel.fromJson(Map<String, dynamic> json) {
    return ServiceQuoteModel(
      id: parseInt(json['id']),
      requestId: parseInt(json['requestId']),
      roundNo: parseInt(json['roundNo']),
      quoteStatus: parseString(json['quoteStatus']),
      pricingModel: parseString(json['pricingModel']),
      pricingUnit: parseString(json['pricingUnit']),
      amount: parseNullableDouble(json['amount']),
      minAmount: parseNullableDouble(json['minAmount']),
      maxAmount: parseNullableDouble(json['maxAmount']),
      visitFee: parseNullableDouble(json['visitFee']),
      currency: parseString(json['currency'], fallback: 'IQD'),
      note: parseNullableString(json['note']),
      createdAt: parseNullableString(json['createdAt']),
    );
  }
}

class ServiceBookingPreviewSnapshotModel {
  final String pricingType;
  final String priceVersion;
  final double unitPriceIqd;
  final double quantity;
  final int durationMinutes;
  final double subtotalIqd;
  final double discountIqd;
  final double serviceFeeIqd;
  final double totalIqd;
  final Map<String, dynamic>? promotionSnapshot;
  final String expiresAt;
  final String? promotionType;

  const ServiceBookingPreviewSnapshotModel({
    required this.pricingType,
    required this.priceVersion,
    required this.unitPriceIqd,
    required this.quantity,
    required this.durationMinutes,
    required this.subtotalIqd,
    required this.discountIqd,
    required this.serviceFeeIqd,
    required this.totalIqd,
    required this.promotionSnapshot,
    required this.expiresAt,
    required this.promotionType,
  });

  factory ServiceBookingPreviewSnapshotModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final promotionSnapshot = json['promotionSnapshot'] is Map
        ? Map<String, dynamic>.from(json['promotionSnapshot'] as Map)
        : null;
    return ServiceBookingPreviewSnapshotModel(
      pricingType: parseString(json['pricingType']),
      priceVersion: parseString(json['priceVersion']),
      unitPriceIqd: parseDouble(json['unitPriceIqd']),
      quantity: parseDouble(json['quantity']),
      durationMinutes: parseInt(json['durationMinutes']),
      subtotalIqd: parseDouble(json['subtotalIqd']),
      discountIqd: parseDouble(json['discountIqd']),
      serviceFeeIqd: parseDouble(json['serviceFeeIqd']),
      totalIqd: parseDouble(json['totalIqd']),
      promotionSnapshot: promotionSnapshot,
      expiresAt: parseString(json['expiresAt']),
      promotionType: parseNullableString(json['promotionType']),
    );
  }
}

class ServiceBookingPreviewModel {
  final int offeringId;
  final int providerId;
  final int customerUserId;
  final String? providerBusinessName;
  final String? providerCity;
  final String? providerArea;
  final int? pricingOptionId;
  final ServiceBookingPreviewSnapshotModel preview;
  final Map<String, dynamic>? provider;
  final Map<String, dynamic>? pricingOption;
  final ServicePromotionModel? promotion;

  const ServiceBookingPreviewModel({
    required this.offeringId,
    required this.providerId,
    required this.customerUserId,
    required this.providerBusinessName,
    required this.providerCity,
    required this.providerArea,
    required this.pricingOptionId,
    required this.preview,
    required this.provider,
    required this.pricingOption,
    required this.promotion,
  });

  factory ServiceBookingPreviewModel.fromJson(Map<String, dynamic> json) {
    final providerJson = json['provider'] is Map
        ? Map<String, dynamic>.from(json['provider'] as Map)
        : null;
    final pricingOptionJson = json['pricingOption'] is Map
        ? Map<String, dynamic>.from(json['pricingOption'] as Map)
        : null;
    return ServiceBookingPreviewModel(
      offeringId: parseInt(json['offeringId']),
      providerId: parseInt(json['providerId']),
      customerUserId: parseInt(json['customerUserId']),
      providerBusinessName: parseNullableString(json['providerBusinessName']),
      providerCity: parseNullableString(json['providerCity']),
      providerArea: parseNullableString(json['providerArea']),
      pricingOptionId: parseNullableInt(json['pricingOptionId']),
      preview: ServiceBookingPreviewSnapshotModel.fromJson(
        Map<String, dynamic>.from(json['preview'] as Map),
      ),
      provider: providerJson,
      pricingOption: pricingOptionJson,
      promotion: json['promotion'] is Map
          ? ServicePromotionModel.fromJson(
              Map<String, dynamic>.from(json['promotion'] as Map),
            )
          : null,
    );
  }
}

class ServiceRequestModel {
  final int id;
  final String requestCode;
  final int customerUserId;
  final int providerId;
  final int offeringId;
  final String status;
  final String? bookingStatus;
  final int? bookingVersion;
  final String? bookingIdempotencyKey;
  final String? bookingPricingType;
  final String? bookingPriceVersion;
  final double? bookingUnitPriceIqd;
  final double? bookingQuantity;
  final int? bookingDurationMinutes;
  final double? bookingSubtotalIqd;
  final double? bookingDiscountIqd;
  final double? bookingServiceFeeIqd;
  final double? bookingTotalIqd;
  final Map<String, dynamic>? bookingPromotionSnapshot;
  final String? bookingExpiresAt;
  final String? bookingProviderCompletedAt;
  final String? bookingFinalizationDueAt;
  final String? bookingFinalizedAt;
  final String? bookingTransitionNote;
  final String? notes;
  final String? city;
  final String? area;
  final double? quantity;
  final double? durationHours;
  final double? finalPrice;
  final String? finalCurrency;
  final String? offeringName;
  final String? providerBusinessName;
  final String? createdAt;
  final List<Map<String, dynamic>> attachments;
  final List<ServiceQuoteModel> quotes;
  final List<Map<String, dynamic>> history;

  const ServiceRequestModel({
    required this.id,
    required this.requestCode,
    required this.customerUserId,
    required this.providerId,
    required this.offeringId,
    required this.status,
    required this.bookingStatus,
    required this.bookingVersion,
    required this.bookingIdempotencyKey,
    required this.bookingPricingType,
    required this.bookingPriceVersion,
    required this.bookingUnitPriceIqd,
    required this.bookingQuantity,
    required this.bookingDurationMinutes,
    required this.bookingSubtotalIqd,
    required this.bookingDiscountIqd,
    required this.bookingServiceFeeIqd,
    required this.bookingTotalIqd,
    required this.bookingPromotionSnapshot,
    required this.bookingExpiresAt,
    required this.bookingProviderCompletedAt,
    required this.bookingFinalizationDueAt,
    required this.bookingFinalizedAt,
    required this.bookingTransitionNote,
    required this.notes,
    required this.city,
    required this.area,
    required this.quantity,
    required this.durationHours,
    required this.finalPrice,
    required this.finalCurrency,
    required this.offeringName,
    required this.providerBusinessName,
    required this.createdAt,
    required this.attachments,
    required this.quotes,
    required this.history,
  });

  factory ServiceRequestModel.fromJson(Map<String, dynamic> json) {
    return ServiceRequestModel(
      id: parseInt(json['id']),
      requestCode: parseString(json['requestCode'], fallback: ''),
      customerUserId: parseInt(json['customerUserId']),
      providerId: parseInt(json['providerId']),
      offeringId: parseInt(json['offeringId']),
      status: parseString(json['status']),
      bookingStatus: parseNullableString(json['bookingStatus']),
      bookingVersion: parseNullableInt(json['bookingVersion']),
      bookingIdempotencyKey: parseNullableString(json['bookingIdempotencyKey']),
      bookingPricingType: parseNullableString(json['bookingPricingType']),
      bookingPriceVersion: parseNullableString(json['bookingPriceVersion']),
      bookingUnitPriceIqd: parseNullableDouble(json['bookingUnitPriceIqd']),
      bookingQuantity: parseNullableDouble(json['bookingQuantity']),
      bookingDurationMinutes: parseNullableInt(json['bookingDurationMinutes']),
      bookingSubtotalIqd: parseNullableDouble(json['bookingSubtotalIqd']),
      bookingDiscountIqd: parseNullableDouble(json['bookingDiscountIqd']),
      bookingServiceFeeIqd: parseNullableDouble(json['bookingServiceFeeIqd']),
      bookingTotalIqd: parseNullableDouble(json['bookingTotalIqd']),
      bookingPromotionSnapshot: json['bookingPromotionSnapshot'] is Map
          ? Map<String, dynamic>.from(json['bookingPromotionSnapshot'] as Map)
          : null,
      bookingExpiresAt: parseNullableString(json['bookingExpiresAt']),
      bookingProviderCompletedAt: parseNullableString(
        json['bookingProviderCompletedAt'],
      ),
      bookingFinalizationDueAt: parseNullableString(
        json['bookingFinalizationDueAt'],
      ),
      bookingFinalizedAt: parseNullableString(json['bookingFinalizedAt']),
      bookingTransitionNote: parseNullableString(json['bookingTransitionNote']),
      notes: parseNullableString(json['notes']),
      city: parseNullableString(json['city']),
      area: parseNullableString(json['area']),
      quantity: parseNullableDouble(json['quantity']),
      durationHours: parseNullableDouble(json['durationHours']),
      finalPrice: parseNullableDouble(json['finalPrice']),
      finalCurrency: parseNullableString(json['finalCurrency']),
      offeringName: parseNullableString(json['offeringName']),
      providerBusinessName: parseNullableString(json['providerBusinessName']),
      createdAt: parseNullableString(json['createdAt']),
      attachments: (json['attachments'] is List)
          ? List<dynamic>.from(
              json['attachments'] as List,
            ).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const <Map<String, dynamic>>[],
      quotes: (json['quotes'] is List)
          ? List<dynamic>.from(json['quotes'] as List)
                .whereType<Map>()
                .map(
                  (e) =>
                      ServiceQuoteModel.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const <ServiceQuoteModel>[],
      history: (json['history'] is List)
          ? List<dynamic>.from(
              json['history'] as List,
            ).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const <Map<String, dynamic>>[],
    );
  }
}

class ServiceProviderEmployeeProfileModel {
  final int id;
  final String roleTag;
  final String? displayName;
  final String? contactEmail;
  final List<String> permissions;
  final Map<String, bool> permissionMap;
  final bool isActive;
  final String? archivedAt;
  final String? notes;
  final int? invitedByUserId;
  final int? updatedByUserId;

  const ServiceProviderEmployeeProfileModel({
    required this.id,
    required this.roleTag,
    required this.displayName,
    required this.contactEmail,
    required this.permissions,
    required this.permissionMap,
    required this.isActive,
    required this.archivedAt,
    required this.notes,
    required this.invitedByUserId,
    required this.updatedByUserId,
  });

  factory ServiceProviderEmployeeProfileModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final permissions = (json['permissions'] is List)
        ? List<dynamic>.from(json['permissions'] as List)
              .map((value) => '$value')
              .where((value) => value.trim().isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final permissionMap = json['permissionMap'] is Map
        ? Map<String, bool>.from(
            (json['permissionMap'] as Map).map(
              (key, value) => MapEntry('$key', value == true),
            ),
          )
        : <String, bool>{
            for (final permission in permissions) permission: true,
          };
    return ServiceProviderEmployeeProfileModel(
      id: parseInt(json['id']),
      roleTag: parseString(json['roleTag'], fallback: 'staff'),
      displayName: parseNullableString(json['displayName']),
      contactEmail: parseNullableString(json['contactEmail']),
      permissions: permissions,
      permissionMap: permissionMap,
      isActive: parseBool(json['isActive'], fallback: true),
      archivedAt: parseNullableString(json['archivedAt']),
      notes: parseNullableString(json['notes']),
      invitedByUserId: parseNullableInt(json['invitedByUserId']),
      updatedByUserId: parseNullableInt(json['updatedByUserId']),
    );
  }
}

class ServiceProviderEmployeeModel {
  final int userId;
  final String fullName;
  final String phone;
  final String role;
  final String? imageUrl;
  final String? displayName;
  final String? contactEmail;
  final ServiceProviderEmployeeProfileModel? profile;

  const ServiceProviderEmployeeModel({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.imageUrl,
    required this.displayName,
    required this.contactEmail,
    required this.profile,
  });

  factory ServiceProviderEmployeeModel.fromJson(Map<String, dynamic> json) {
    final profileJson = json['profile'] is Map
        ? Map<String, dynamic>.from(json['profile'] as Map)
        : json['employeeProfile'] is Map
        ? Map<String, dynamic>.from(json['employeeProfile'] as Map)
        : null;
    return ServiceProviderEmployeeModel(
      userId: parseInt(json['userId']),
      fullName: parseString(json['fullName']),
      phone: parseString(json['phone']),
      role: parseString(json['role'], fallback: 'service_provider'),
      imageUrl: parseNullableString(json['imageUrl']),
      displayName: parseNullableString(json['displayName']),
      contactEmail: parseNullableString(json['contactEmail']),
      profile: profileJson == null
          ? null
          : ServiceProviderEmployeeProfileModel.fromJson(profileJson),
    );
  }
}

class ServiceProviderEmployeeActivityLogModel {
  final int id;
  final String workspaceKind;
  final int workspaceId;
  final int? employeeProfileId;
  final int employeeUserId;
  final String employeeFullName;
  final String employeePhone;
  final int? actorUserId;
  final String? actorFullName;
  final String actorRole;
  final String actionKey;
  final String? reason;
  final Map<String, dynamic> oldValue;
  final Map<String, dynamic> newValue;
  final String? note;
  final String? createdAt;

  const ServiceProviderEmployeeActivityLogModel({
    required this.id,
    required this.workspaceKind,
    required this.workspaceId,
    required this.employeeProfileId,
    required this.employeeUserId,
    required this.employeeFullName,
    required this.employeePhone,
    required this.actorUserId,
    required this.actorFullName,
    required this.actorRole,
    required this.actionKey,
    required this.reason,
    required this.oldValue,
    required this.newValue,
    required this.note,
    required this.createdAt,
  });

  factory ServiceProviderEmployeeActivityLogModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return ServiceProviderEmployeeActivityLogModel(
      id: parseInt(json['id']),
      workspaceKind: parseString(
        json['workspaceKind'],
        fallback: 'service_provider',
      ),
      workspaceId: parseInt(json['workspaceId']),
      employeeProfileId: parseNullableInt(json['employeeProfileId']),
      employeeUserId: parseInt(json['employeeUserId']),
      employeeFullName: parseString(json['employeeFullName']),
      employeePhone: parseString(json['employeePhone']),
      actorUserId: parseNullableInt(json['actorUserId']),
      actorFullName: parseNullableString(json['actorFullName']),
      actorRole: parseString(json['actorRole'], fallback: ''),
      actionKey: parseString(json['actionKey'], fallback: ''),
      reason: parseNullableString(json['reason']),
      oldValue: json['oldValue'] is Map
          ? Map<String, dynamic>.from(json['oldValue'] as Map)
          : <String, dynamic>{},
      newValue: json['newValue'] is Map
          ? Map<String, dynamic>.from(json['newValue'] as Map)
          : <String, dynamic>{},
      note: parseNullableString(json['note']),
      createdAt: parseNullableString(json['createdAt']),
    );
  }
}

class ServiceProviderWorkspaceAccessModel {
  final bool isOwner;
  final List<String> permissions;
  final Map<String, bool> permissionMap;
  final ServiceProviderEmployeeProfileModel? employeeProfile;

  const ServiceProviderWorkspaceAccessModel({
    required this.isOwner,
    required this.permissions,
    required this.permissionMap,
    required this.employeeProfile,
  });

  factory ServiceProviderWorkspaceAccessModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final permissions = (json['permissions'] is List)
        ? List<dynamic>.from(json['permissions'] as List)
              .map((value) => '$value')
              .where((value) => value.trim().isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final permissionMap = json['permissionMap'] is Map
        ? Map<String, bool>.from(
            (json['permissionMap'] as Map).map(
              (key, value) => MapEntry('$key', value == true),
            ),
          )
        : <String, bool>{
            for (final permission in permissions) permission: true,
          };
    final employeeProfile = json['employeeProfile'] is Map
        ? ServiceProviderEmployeeProfileModel.fromJson(
            Map<String, dynamic>.from(json['employeeProfile'] as Map),
          )
        : null;
    return ServiceProviderWorkspaceAccessModel(
      isOwner: parseBool(json['isOwner']),
      permissions: permissions,
      permissionMap: permissionMap,
      employeeProfile: employeeProfile,
    );
  }
}

class ServiceProviderWorkspaceModel {
  final ServiceProviderProfileModel provider;
  final Map<String, int> requestCounts;
  final List<ServicePromotionModel> promotions;
  final ServiceProviderWorkspaceAccessModel? access;
  final List<ServiceProviderEmployeeModel> employees;
  final List<ServiceProviderEmployeeActivityLogModel> activityLogs;
  final List<String> availablePermissions;

  const ServiceProviderWorkspaceModel({
    required this.provider,
    required this.requestCounts,
    required this.promotions,
    required this.access,
    required this.employees,
    required this.activityLogs,
    required this.availablePermissions,
  });

  factory ServiceProviderWorkspaceModel.fromJson(Map<String, dynamic> json) {
    final providerJson = json['provider'] is Map
        ? Map<String, dynamic>.from(json['provider'] as Map)
        : const <String, dynamic>{};

    final stitched = <String, dynamic>{
      ...providerJson,
      'areas': json['areas'],
      'availabilityRules': json['availabilityRules'],
      'offerings': json['offerings'],
      'portfolio': json['portfolio'],
      'reviews': const <dynamic>[],
      'activePromotions': json['promotions'],
    };

    final employees = (json['employees'] is List)
        ? List<dynamic>.from(json['employees'] as List)
              .whereType<Map>()
              .map(
                (e) => ServiceProviderEmployeeModel.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList(growable: false)
        : const <ServiceProviderEmployeeModel>[];

    final activityLogs = (json['activityLogs'] is List)
        ? List<dynamic>.from(json['activityLogs'] as List)
              .whereType<Map>()
              .map(
                (e) => ServiceProviderEmployeeActivityLogModel.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList(growable: false)
        : const <ServiceProviderEmployeeActivityLogModel>[];

    return ServiceProviderWorkspaceModel(
      provider: ServiceProviderProfileModel.fromJson(stitched),
      requestCounts: (json['requestCounts'] is Map)
          ? Map<String, int>.from(
              (json['requestCounts'] as Map).map(
                (key, value) => MapEntry('$key', parseInt(value)),
              ),
            )
          : const <String, int>{},
      promotions: (json['promotions'] is List)
          ? List<dynamic>.from(json['promotions'] as List)
                .whereType<Map>()
                .map(
                  (e) => ServicePromotionModel.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList(growable: false)
          : const <ServicePromotionModel>[],
      access: json['access'] is Map
          ? ServiceProviderWorkspaceAccessModel.fromJson(
              Map<String, dynamic>.from(json['access'] as Map),
            )
          : null,
      employees: employees,
      activityLogs: activityLogs,
      availablePermissions: (json['availablePermissions'] is List)
          ? List<dynamic>.from(json['availablePermissions'] as List)
                .map((value) => '$value')
                .where((value) => value.trim().isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }
}

class ServiceProviderApplicationProgressModel {
  final int applicationId;
  final String applicationCode;
  final String status;
  final String nextAction;
  final bool canLogin;
  final bool reusedExistingApplication;
  final bool compatibilityWarning;
  final String businessName;
  final String phone;
  final String? approvalNote;

  const ServiceProviderApplicationProgressModel({
    required this.applicationId,
    required this.applicationCode,
    required this.status,
    required this.nextAction,
    required this.canLogin,
    required this.reusedExistingApplication,
    required this.compatibilityWarning,
    required this.businessName,
    required this.phone,
    required this.approvalNote,
  });

  factory ServiceProviderApplicationProgressModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final applicationJson = json['application'] is Map
        ? Map<String, dynamic>.from(json['application'] as Map)
        : json['provider'] is Map
        ? Map<String, dynamic>.from(json['provider'] as Map)
        : json['request'] is Map
        ? Map<String, dynamic>.from(json['request'] as Map)
        : const <String, dynamic>{};
    final rawStatus = parseString(
      json['status'] ??
          applicationJson['providerApprovalStatus'] ??
          applicationJson['status'],
      fallback: 'submitted',
    );
    final normalizedStatus = _normalizeProviderApplicationStatus(rawStatus);
    return ServiceProviderApplicationProgressModel(
      applicationId: parseInt(applicationJson['id']),
      applicationCode: parseString(
        applicationJson['applicationCode'] ?? applicationJson['requestCode'],
        fallback: '',
      ),
      status: normalizedStatus,
      nextAction: parseString(
        json['nextAction'],
        fallback: 'wait_admin_review',
      ),
      canLogin: parseBool(json['canLogin']),
      reusedExistingApplication: parseBool(
        json['reusedExistingApplication'] ?? json['reusedActiveRequest'],
      ),
      compatibilityWarning: parseBool(json['compatibilityWarning']),
      businessName: parseString(applicationJson['businessName']),
      phone: parseString(applicationJson['phone']),
      approvalNote: parseNullableString(applicationJson['approvalNote']),
    );
  }
}

String _normalizeProviderApplicationStatus(String value) {
  switch (value.trim().toLowerCase()) {
    case 'not_submitted':
    case 'draft':
    case 'submitted':
    case 'under_review':
    case 'approved':
    case 'rejected':
    case 'suspended':
      return value.trim().toLowerCase();
    case 'pending':
    case 'pending_review':
      return 'under_review';
    default:
      return 'under_review';
  }
}
