import '../../../core/utils/parsers.dart';

class CarListingMediaModel {
  final int id;
  final String imageUrl;
  final int sortOrder;

  const CarListingMediaModel({
    required this.id,
    required this.imageUrl,
    required this.sortOrder,
  });

  factory CarListingMediaModel.fromJson(Map<String, dynamic> j) {
    return CarListingMediaModel(
      id: parseInt(j['id']),
      imageUrl: parseString(j['imageUrl'] ?? j['image_url']),
      sortOrder: parseInt(j['sortOrder'] ?? j['sort_order']),
    );
  }
}

class CarListingModel {
  final int id;
  final int ownerId;
  final String? ownerFullName;
  final String status;
  final String title;
  final String? description;
  final String brand;
  final String model;
  final int modelYear;
  final String condition;
  final double price;
  final int? mileageKm;
  final String? city;
  final String phone;
  final String transmission;
  final String fuelType;
  final String bodyType;
  final String? color;
  final String? lastVisibleStatus;
  final DateTime? hiddenDueSubscriptionExpiryAt;
  final DateTime? soldAt;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<CarListingMediaModel> media;

  const CarListingModel({
    required this.id,
    required this.ownerId,
    required this.ownerFullName,
    required this.status,
    required this.title,
    required this.description,
    required this.brand,
    required this.model,
    required this.modelYear,
    required this.condition,
    required this.price,
    required this.mileageKm,
    required this.city,
    required this.phone,
    required this.transmission,
    required this.fuelType,
    required this.bodyType,
    required this.color,
    required this.lastVisibleStatus,
    required this.hiddenDueSubscriptionExpiryAt,
    required this.soldAt,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.media,
  });

  factory CarListingModel.fromJson(Map<String, dynamic> j) {
    final rawMedia = List<dynamic>.from(j['media'] as List? ?? const []);
    return CarListingModel(
      id: parseInt(j['id']),
      ownerId: parseInt(j['ownerId'] ?? j['owner_id']),
      ownerFullName: parseNullableString(
        j['ownerFullName'] ?? j['owner_full_name'],
      ),
      status: parseString(j['status']),
      title: parseString(j['title']),
      description: parseNullableString(j['description']),
      brand: parseString(j['brand']),
      model: parseString(j['model']),
      modelYear: parseInt(j['modelYear'] ?? j['model_year']),
      condition: parseString(j['condition'], fallback: 'used'),
      price: parseDouble(j['price']),
      mileageKm: j['mileageKm'] == null && j['mileage_km'] == null
          ? null
          : parseInt(j['mileageKm'] ?? j['mileage_km']),
      city: parseNullableString(j['city']),
      phone: parseString(j['phone']),
      transmission: parseString(j['transmission'], fallback: 'automatic'),
      fuelType: parseString(j['fuelType'] ?? j['fuel_type'], fallback: 'fuel'),
      bodyType: parseString(j['bodyType'] ?? j['body_type'], fallback: 'sedan'),
      color: parseNullableString(j['color']),
      lastVisibleStatus: parseNullableString(
        j['lastVisibleStatus'] ?? j['last_visible_status'],
      ),
      hiddenDueSubscriptionExpiryAt: _parseDate(
        j['hiddenDueSubscriptionExpiryAt'] ??
            j['hidden_due_subscription_expiry_at'],
      ),
      soldAt: _parseDate(j['soldAt'] ?? j['sold_at']),
      archivedAt: _parseDate(j['archivedAt'] ?? j['archived_at']),
      createdAt: _parseDate(j['createdAt'] ?? j['created_at']),
      updatedAt: _parseDate(j['updatedAt'] ?? j['updated_at']),
      media: rawMedia
          .whereType<Map>()
          .map(
            (e) => CarListingMediaModel.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
    );
  }

  CarListingModel copyWith({
    String? status,
    List<CarListingMediaModel>? media,
  }) {
    return CarListingModel(
      id: id,
      ownerId: ownerId,
      ownerFullName: ownerFullName,
      status: status ?? this.status,
      title: title,
      description: description,
      brand: brand,
      model: model,
      modelYear: modelYear,
      condition: condition,
      price: price,
      mileageKm: mileageKm,
      city: city,
      phone: phone,
      transmission: transmission,
      fuelType: fuelType,
      bodyType: bodyType,
      color: color,
      lastVisibleStatus: lastVisibleStatus,
      hiddenDueSubscriptionExpiryAt: hiddenDueSubscriptionExpiryAt,
      soldAt: soldAt,
      archivedAt: archivedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      media: media ?? this.media,
    );
  }
}

class CarsWorkspaceModel {
  final bool carSellerMonthly;
  final List<int> syncChangedListingIds;
  final Map<String, dynamic> counts;
  final List<CarListingModel> listings;

  const CarsWorkspaceModel({
    required this.carSellerMonthly,
    required this.syncChangedListingIds,
    required this.counts,
    required this.listings,
  });

  factory CarsWorkspaceModel.fromJson(Map<String, dynamic> j) {
    final counts = j['counts'] is Map
        ? Map<String, dynamic>.from(j['counts'] as Map)
        : const <String, dynamic>{};
    final listings = List<dynamic>.from(j['listings'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => CarListingModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    final syncChanged = List<dynamic>.from(
      j['syncChangedListingIds'] as List? ?? const [],
    ).map((e) => parseInt(e)).where((e) => e > 0).toList(growable: false);
    return CarsWorkspaceModel(
      carSellerMonthly: parseBool(
        j['entitlement'] is Map
            ? (j['entitlement'] as Map)['carSellerMonthly']
            : j['carSellerMonthly'],
      ),
      syncChangedListingIds: syncChanged,
      counts: counts,
      listings: listings,
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

class CarListingQuery {
  final String? brand;
  final String? model;
  final String? search;
  final String? city;
  final String? condition;
  final String? bodyType;
  final double? minPrice;
  final double? maxPrice;
  final String sort;

  const CarListingQuery({
    this.brand,
    this.model,
    this.search,
    this.city,
    this.condition,
    this.bodyType,
    this.minPrice,
    this.maxPrice,
    this.sort = 'recent',
  });

  Map<String, dynamic> toJson({int limit = 24, int offset = 0}) {
    return {
      if ((brand ?? '').trim().isNotEmpty) 'brand': brand!.trim(),
      if ((model ?? '').trim().isNotEmpty) 'model': model!.trim(),
      if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
      if ((city ?? '').trim().isNotEmpty) 'city': city!.trim(),
      if ((condition ?? '').trim().isNotEmpty) 'condition': condition!.trim(),
      if ((bodyType ?? '').trim().isNotEmpty) 'bodyType': bodyType!.trim(),
      if (minPrice != null) 'minPrice': minPrice,
      if (maxPrice != null) 'maxPrice': maxPrice,
      'sort': sort,
      'limit': limit,
      'offset': offset,
    };
  }

  CarListingQuery copyWith({
    Object? brand = _sentinel,
    Object? model = _sentinel,
    Object? search = _sentinel,
    Object? city = _sentinel,
    Object? condition = _sentinel,
    Object? bodyType = _sentinel,
    Object? minPrice = _sentinel,
    Object? maxPrice = _sentinel,
    String? sort,
  }) {
    return CarListingQuery(
      brand: identical(brand, _sentinel) ? this.brand : brand as String?,
      model: identical(model, _sentinel) ? this.model : model as String?,
      search: identical(search, _sentinel) ? this.search : search as String?,
      city: identical(city, _sentinel) ? this.city : city as String?,
      condition: identical(condition, _sentinel)
          ? this.condition
          : condition as String?,
      bodyType: identical(bodyType, _sentinel)
          ? this.bodyType
          : bodyType as String?,
      minPrice: identical(minPrice, _sentinel)
          ? this.minPrice
          : minPrice as double?,
      maxPrice: identical(maxPrice, _sentinel)
          ? this.maxPrice
          : maxPrice as double?,
      sort: sort ?? this.sort,
    );
  }
}

const Object _sentinel = Object();
