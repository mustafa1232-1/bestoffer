import '../../../core/utils/parsers.dart';

class RealEstateListingMediaModel {
  final int id;
  final String imageUrl;
  final int sortOrder;

  const RealEstateListingMediaModel({
    required this.id,
    required this.imageUrl,
    required this.sortOrder,
  });

  factory RealEstateListingMediaModel.fromJson(Map<String, dynamic> j) {
    return RealEstateListingMediaModel(
      id: parseInt(j['id']),
      imageUrl: parseString(j['imageUrl'] ?? j['image_url']),
      sortOrder: parseInt(j['sortOrder'] ?? j['sort_order']),
    );
  }
}

class RealEstateListingModel {
  final int id;
  final int ownerId;
  final String? ownerFullName;
  final String? ownerPhone;
  final String purpose;
  final String status;
  final String title;
  final String? description;
  final int areaSqm;
  final double bankSettlementAmount;
  final String bankSettlementMode;
  final bool furnished;
  final String? furnishingDescription;
  final String phone;
  final double price;
  final String? city;
  final String? block;
  final String? buildingNumber;
  final String? apartmentNumber;
  final int? roomsCount;
  final int? bathroomsCount;
  final int? floorNumber;
  final String paymentMethod;
  final bool isFeatured;
  final int viewCount;
  final bool isSaved;
  final Map<String, dynamic> detailsJson;
  final String? reviewNote;
  final int? reviewedByUserId;
  final DateTime? reviewedAt;
  final String? lastVisibleStatus;
  final DateTime? hiddenDueSubscriptionExpiryAt;
  final DateTime? soldAt;
  final DateTime? rentedAt;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<RealEstateListingMediaModel> media;

  const RealEstateListingModel({
    required this.id,
    required this.ownerId,
    required this.ownerFullName,
    required this.ownerPhone,
    required this.purpose,
    required this.status,
    required this.title,
    required this.description,
    required this.areaSqm,
    required this.bankSettlementAmount,
    required this.bankSettlementMode,
    required this.furnished,
    required this.furnishingDescription,
    required this.phone,
    required this.price,
    required this.city,
    required this.block,
    required this.buildingNumber,
    required this.apartmentNumber,
    required this.roomsCount,
    required this.bathroomsCount,
    required this.floorNumber,
    required this.paymentMethod,
    required this.isFeatured,
    required this.viewCount,
    required this.isSaved,
    required this.detailsJson,
    required this.reviewNote,
    required this.reviewedByUserId,
    required this.reviewedAt,
    required this.lastVisibleStatus,
    required this.hiddenDueSubscriptionExpiryAt,
    required this.soldAt,
    required this.rentedAt,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.media,
  });

  factory RealEstateListingModel.fromJson(Map<String, dynamic> j) {
    final rawMedia = List<dynamic>.from(j['media'] as List? ?? const []);
    return RealEstateListingModel(
      id: parseInt(j['id']),
      ownerId: parseInt(j['ownerId'] ?? j['owner_id']),
      ownerFullName: parseNullableString(
        j['ownerFullName'] ?? j['owner_full_name'],
      ),
      ownerPhone: parseNullableString(j['ownerPhone'] ?? j['owner_phone']),
      purpose: parseString(j['purpose']),
      status: parseString(j['status']),
      title: parseString(j['title']),
      description: parseNullableString(j['description']),
      areaSqm: parseInt(j['areaSqm'] ?? j['area_sqm']),
      bankSettlementAmount: parseDouble(
        j['bankSettlementAmount'] ?? j['bank_settlement_amount'],
      ),
      bankSettlementMode: parseString(
        j['bankSettlementMode'] ?? j['bank_settlement_mode'],
        fallback: 'none',
      ),
      furnished: parseBool(j['furnished']),
      furnishingDescription: parseNullableString(
        j['furnishingDescription'] ?? j['furnishing_description'],
      ),
      phone: parseString(j['phone']),
      price: parseDouble(j['price']),
      city: parseNullableString(j['city']),
      block: parseNullableString(j['block']),
      buildingNumber: parseNullableString(
        j['buildingNumber'] ?? j['building_number'],
      ),
      apartmentNumber: parseNullableString(
        j['apartmentNumber'] ?? j['apartment_number'],
      ),
      roomsCount: parseNullableInt(j['roomsCount'] ?? j['rooms_count']),
      bathroomsCount: parseNullableInt(
        j['bathroomsCount'] ?? j['bathrooms_count'],
      ),
      floorNumber: parseNullableInt(j['floorNumber'] ?? j['floor_number']),
      paymentMethod: parseString(
        j['paymentMethod'] ?? j['payment_method'],
        fallback: 'cash',
      ),
      isFeatured: parseBool(j['isFeatured'] ?? j['is_featured']),
      viewCount: parseInt(j['viewCount'] ?? j['view_count']),
      isSaved: parseBool(j['isSaved'] ?? j['is_saved']),
      detailsJson: j['detailsJson'] is Map
          ? Map<String, dynamic>.from(j['detailsJson'] as Map)
          : j['details_json'] is Map
              ? Map<String, dynamic>.from(j['details_json'] as Map)
              : const <String, dynamic>{},
      reviewNote: parseNullableString(j['reviewNote'] ?? j['review_note']),
      reviewedByUserId: parseNullableInt(
        j['reviewedByUserId'] ?? j['reviewed_by_user_id'],
      ),
      reviewedAt: _parseDate(j['reviewedAt'] ?? j['reviewed_at']),
      lastVisibleStatus: parseNullableString(
        j['lastVisibleStatus'] ?? j['last_visible_status'],
      ),
      hiddenDueSubscriptionExpiryAt: _parseDate(
        j['hiddenDueSubscriptionExpiryAt'] ??
            j['hidden_due_subscription_expiry_at'],
      ),
      soldAt: _parseDate(j['soldAt'] ?? j['sold_at']),
      rentedAt: _parseDate(j['rentedAt'] ?? j['rented_at']),
      archivedAt: _parseDate(j['archivedAt'] ?? j['archived_at']),
      createdAt: _parseDate(j['createdAt'] ?? j['created_at']),
      updatedAt: _parseDate(j['updatedAt'] ?? j['updated_at']),
      media: rawMedia
          .whereType<Map>()
          .map(
            (e) => RealEstateListingMediaModel.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false),
    );
  }

  RealEstateListingModel copyWith({
    bool? isSaved,
    String? status,
    int? viewCount,
    List<RealEstateListingMediaModel>? media,
  }) {
    return RealEstateListingModel(
      id: id,
      ownerId: ownerId,
      ownerFullName: ownerFullName,
      ownerPhone: ownerPhone,
      purpose: purpose,
      status: status ?? this.status,
      title: title,
      description: description,
      areaSqm: areaSqm,
      bankSettlementAmount: bankSettlementAmount,
      bankSettlementMode: bankSettlementMode,
      furnished: furnished,
      furnishingDescription: furnishingDescription,
      phone: phone,
      price: price,
      city: city,
      block: block,
      buildingNumber: buildingNumber,
      apartmentNumber: apartmentNumber,
      roomsCount: roomsCount,
      bathroomsCount: bathroomsCount,
      floorNumber: floorNumber,
      paymentMethod: paymentMethod,
      isFeatured: isFeatured,
      viewCount: viewCount ?? this.viewCount,
      isSaved: isSaved ?? this.isSaved,
      detailsJson: detailsJson,
      reviewNote: reviewNote,
      reviewedByUserId: reviewedByUserId,
      reviewedAt: reviewedAt,
      lastVisibleStatus: lastVisibleStatus,
      hiddenDueSubscriptionExpiryAt: hiddenDueSubscriptionExpiryAt,
      soldAt: soldAt,
      rentedAt: rentedAt,
      archivedAt: archivedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      media: media ?? this.media,
    );
  }
}

class RealEstateWorkspaceModel {
  final bool propertySellerMonthly;
  final List<int> syncChangedListingIds;
  final Map<String, dynamic> counts;
  final List<RealEstateListingModel> listings;

  const RealEstateWorkspaceModel({
    required this.propertySellerMonthly,
    required this.syncChangedListingIds,
    required this.counts,
    required this.listings,
  });

  factory RealEstateWorkspaceModel.fromJson(Map<String, dynamic> j) {
    final counts = j['counts'] is Map
        ? Map<String, dynamic>.from(j['counts'] as Map)
        : const <String, dynamic>{};
    final listings = List<dynamic>.from(j['listings'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (e) => RealEstateListingModel.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList(growable: false);
    final syncChanged =
        List<dynamic>.from(j['syncChangedListingIds'] as List? ?? const [])
            .map((e) => parseInt(e))
            .where((e) => e > 0)
            .toList(growable: false);

    return RealEstateWorkspaceModel(
      propertySellerMonthly: parseBool(
        j['entitlement'] is Map
            ? (j['entitlement'] as Map)['propertySellerMonthly']
            : j['propertySellerMonthly'],
      ),
      syncChangedListingIds: syncChanged,
      counts: counts,
      listings: listings,
    );
  }
}

class RealEstateListingQuery {
  final String? purpose;
  final String? search;
  final String? city;
  final String? block;
  final int? areaSqm;
  final int? areaMin;
  final int? areaMax;
  final bool? furnished;
  final bool availableOnly;
  final bool featuredOnly;
  final String? bankSettlementMode;
  final String? paymentMethod;
  final double? minPrice;
  final double? maxPrice;
  final int? roomsCount;
  final int? bathroomsCount;
  final int? floorMin;
  final int? floorMax;
  final String sort;

  const RealEstateListingQuery({
    this.purpose,
    this.search,
    this.city,
    this.block,
    this.areaSqm,
    this.areaMin,
    this.areaMax,
    this.furnished,
    this.availableOnly = true,
    this.featuredOnly = false,
    this.bankSettlementMode,
    this.paymentMethod,
    this.minPrice,
    this.maxPrice,
    this.roomsCount,
    this.bathroomsCount,
    this.floorMin,
    this.floorMax,
    this.sort = 'recent',
  });

  Map<String, dynamic> toJson({int limit = 24, int offset = 0}) {
    return {
      if (purpose != null && purpose!.isNotEmpty) 'purpose': purpose,
      if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
      if ((city ?? '').trim().isNotEmpty) 'city': city!.trim(),
      if ((block ?? '').trim().isNotEmpty) 'block': block!.trim(),
      if (areaSqm != null) 'areaSqm': areaSqm,
      if (areaMin != null) 'areaMin': areaMin,
      if (areaMax != null) 'areaMax': areaMax,
      if (furnished != null) 'furnished': furnished,
      if (availableOnly) 'availableOnly': true,
      if (featuredOnly) 'featuredOnly': true,
      if ((bankSettlementMode ?? '').trim().isNotEmpty)
        'bankSettlementMode': bankSettlementMode!.trim(),
      if ((paymentMethod ?? '').trim().isNotEmpty)
        'paymentMethod': paymentMethod!.trim(),
      if (minPrice != null) 'minPrice': minPrice,
      if (maxPrice != null) 'maxPrice': maxPrice,
      if (roomsCount != null) 'roomsCount': roomsCount,
      if (bathroomsCount != null) 'bathroomsCount': bathroomsCount,
      if (floorMin != null) 'floorMin': floorMin,
      if (floorMax != null) 'floorMax': floorMax,
      'sort': sort,
      'limit': limit,
      'offset': offset,
    };
  }

  RealEstateListingQuery copyWith({
    Object? purpose = _sentinel,
    Object? search = _sentinel,
    Object? city = _sentinel,
    Object? block = _sentinel,
    Object? areaSqm = _sentinel,
    Object? areaMin = _sentinel,
    Object? areaMax = _sentinel,
    Object? furnished = _sentinel,
    bool? availableOnly,
    bool? featuredOnly,
    Object? bankSettlementMode = _sentinel,
    Object? paymentMethod = _sentinel,
    Object? minPrice = _sentinel,
    Object? maxPrice = _sentinel,
    Object? roomsCount = _sentinel,
    Object? bathroomsCount = _sentinel,
    Object? floorMin = _sentinel,
    Object? floorMax = _sentinel,
    String? sort,
  }) {
    return RealEstateListingQuery(
      purpose: identical(purpose, _sentinel) ? this.purpose : purpose as String?,
      search: identical(search, _sentinel) ? this.search : search as String?,
      city: identical(city, _sentinel) ? this.city : city as String?,
      block: identical(block, _sentinel) ? this.block : block as String?,
      areaSqm: identical(areaSqm, _sentinel) ? this.areaSqm : areaSqm as int?,
      areaMin: identical(areaMin, _sentinel) ? this.areaMin : areaMin as int?,
      areaMax: identical(areaMax, _sentinel) ? this.areaMax : areaMax as int?,
      furnished: identical(furnished, _sentinel)
          ? this.furnished
          : furnished as bool?,
      availableOnly: availableOnly ?? this.availableOnly,
      featuredOnly: featuredOnly ?? this.featuredOnly,
      bankSettlementMode: identical(bankSettlementMode, _sentinel)
          ? this.bankSettlementMode
          : bankSettlementMode as String?,
      paymentMethod: identical(paymentMethod, _sentinel)
          ? this.paymentMethod
          : paymentMethod as String?,
      minPrice: identical(minPrice, _sentinel)
          ? this.minPrice
          : minPrice as double?,
      maxPrice: identical(maxPrice, _sentinel)
          ? this.maxPrice
          : maxPrice as double?,
      roomsCount: identical(roomsCount, _sentinel)
          ? this.roomsCount
          : roomsCount as int?,
      bathroomsCount: identical(bathroomsCount, _sentinel)
          ? this.bathroomsCount
          : bathroomsCount as int?,
      floorMin: identical(floorMin, _sentinel)
          ? this.floorMin
          : floorMin as int?,
      floorMax: identical(floorMax, _sentinel)
          ? this.floorMax
          : floorMax as int?,
      sort: sort ?? this.sort,
    );
  }
}

const Object _sentinel = Object();

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
