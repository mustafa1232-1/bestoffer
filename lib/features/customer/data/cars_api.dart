import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../models/car_listing_model.dart';

final carsApiProvider = Provider<CarsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return CarsApi(dio);
});

class CarsApi {
  final Dio _dio;
  static final Map<String, _CarsCacheEntry> _cache = {};
  static const Duration _brandsCacheTtl = Duration(minutes: 10);
  static const Duration _modelsCacheTtl = Duration(minutes: 10);
  static const Duration _browseCacheTtl = Duration(minutes: 2);
  static const Duration _smartCacheTtl = Duration(minutes: 1);

  CarsApi(this._dio);

  Future<List<String>> listBrands({
    String? search,
    bool forceRefresh = false,
  }) async {
    final query = <String, dynamic>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final key = _cacheKey('brands', query);
    if (!forceRefresh) {
      final cached = _readCache<List<String>>(key);
      if (cached != null) return List<String>.from(cached);
    }

    final response = await _dio.get('/api/cars/brands', queryParameters: query);
    final map = Map<String, dynamic>.from(response.data as Map);
    final rows = List<dynamic>.from(map['brands'] as List? ?? const []);
    final items = rows
        .whereType<Map>()
        .map((e) => '${e['name'] ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    _writeCache(key, items, _brandsCacheTtl);
    return items;
  }

  Future<List<String>> listModels({
    required String brand,
    String? search,
    bool forceRefresh = false,
  }) async {
    final query = <String, dynamic>{
      'brand': brand,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final key = _cacheKey('models', query);
    if (!forceRefresh) {
      final cached = _readCache<List<String>>(key);
      if (cached != null) return List<String>.from(cached);
    }

    final response = await _dio.get('/api/cars/models', queryParameters: query);
    final map = Map<String, dynamic>.from(response.data as Map);
    final rows = List<dynamic>.from(map['models'] as List? ?? const []);
    final items = rows
        .whereType<Map>()
        .map((e) => '${e['name'] ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    _writeCache(key, items, _modelsCacheTtl);
    return items;
  }

  Future<Map<String, dynamic>> browse({
    String? brand,
    String? model,
    String? search,
    String condition = 'any',
    String bodyType = 'any',
    int? yearFrom,
    int? yearTo,
    int limit = 180,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final query = <String, dynamic>{
      if (brand?.trim().isNotEmpty ?? false) 'brand': brand!.trim(),
      if (model?.trim().isNotEmpty ?? false) 'model': model!.trim(),
      if (search?.trim().isNotEmpty ?? false) 'search': search!.trim(),
      'condition': condition,
      'bodyType': bodyType,
      // ignore: use_null_aware_elements
      if (yearFrom != null) 'yearFrom': yearFrom,
      // ignore: use_null_aware_elements
      if (yearTo != null) 'yearTo': yearTo,
      'limit': limit,
      'offset': offset,
    };
    final key = _cacheKey('browse', query);
    if (!forceRefresh) {
      final cached = _readCache<Map<String, dynamic>>(key);
      if (cached != null) return Map<String, dynamic>.from(cached);
    }

    final response = await _dio.get('/api/cars/browse', queryParameters: query);
    final out = Map<String, dynamic>.from(response.data as Map);
    _writeCache(key, out, _browseCacheTtl);
    return out;
  }

  Future<Map<String, dynamic>> smartSearch(
    Map<String, dynamic> body, {
    bool forceRefresh = false,
  }) async {
    final key = _cacheKey('smart', body);
    if (!forceRefresh) {
      final cached = _readCache<Map<String, dynamic>>(key);
      if (cached != null) return Map<String, dynamic>.from(cached);
    }

    final response = await _dio.post('/api/cars/smart-search', data: body);
    final out = Map<String, dynamic>.from(response.data as Map);
    _writeCache(key, out, _smartCacheTtl);
    return out;
  }

  Future<Map<String, dynamic>> entitlements({bool forceRefresh = false}) async {
    const key = 'entitlements';
    if (!forceRefresh) {
      final cached = _readCache<Map<String, dynamic>>(key);
      if (cached != null) return Map<String, dynamic>.from(cached);
    }

    final response = await _dio.get('/api/cars/entitlements');
    final out = Map<String, dynamic>.from(response.data as Map);
    _writeCache(key, out, const Duration(minutes: 1));
    return out;
  }

  Future<List<Map<String, dynamic>>> listSellerListings({
    String? brand,
    String? model,
    String? search,
    String? city,
    String? condition,
    String? bodyType,
    double? minPrice,
    double? maxPrice,
    String sort = 'recent',
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _dio.get(
      '/api/cars/listings',
      queryParameters: {
        if (brand?.trim().isNotEmpty ?? false) 'brand': brand!.trim(),
        if (model?.trim().isNotEmpty ?? false) 'model': model!.trim(),
        if (search?.trim().isNotEmpty ?? false) 'search': search!.trim(),
        if (city?.trim().isNotEmpty ?? false) 'city': city!.trim(),
        if (condition?.trim().isNotEmpty ?? false)
          'condition': condition!.trim(),
        if (bodyType?.trim().isNotEmpty ?? false) 'bodyType': bodyType!.trim(),
        ...?(minPrice != null ? {'minPrice': minPrice} : null),
        ...?(maxPrice != null ? {'maxPrice': maxPrice} : null),
        'sort': sort,
        'limit': limit,
        'offset': offset,
      },
    );
    final raw = response.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listMarketplaceListings(
    CarListingQuery query, {
    int limit = 20,
    int offset = 0,
  }) {
    return listSellerListings(
      brand: query.brand,
      model: query.model,
      search: query.search,
      city: query.city,
      condition: query.condition,
      bodyType: query.bodyType,
      minPrice: query.minPrice,
      maxPrice: query.maxPrice,
      sort: query.sort,
      limit: limit,
      offset: offset,
    );
  }

  Future<Map<String, dynamic>> getSellerListing(int listingId) async {
    final response = await _dio.get('/api/cars/listings/$listingId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getListing(int listingId) {
    return getSellerListing(listingId);
  }

  Future<Map<String, dynamic>> workspace() async {
    final response = await _dio.get('/api/cars/workspace');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createSellerListing(
    Map<String, dynamic> body, {
    List<MultipartFile> imageFiles = const [],
  }) async {
    final map = <String, dynamic>{};
    body.forEach((key, value) {
      if (value == null) return;
      map[key] = value;
    });
    if (imageFiles.isNotEmpty) {
      map['imageFiles'] = imageFiles;
    }
    final response = await _dio.post(
      '/api/cars/listings',
      data: FormData.fromMap(map),
    );
    clearCache();
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateSellerListing(
    int listingId,
    Map<String, dynamic> body, {
    List<MultipartFile> imageFiles = const [],
  }) async {
    final map = <String, dynamic>{};
    body.forEach((key, value) {
      if (value == null) return;
      map[key] = value;
    });
    if (imageFiles.isNotEmpty) {
      map['imageFiles'] = imageFiles;
    }
    final response = await _dio.patch(
      '/api/cars/listings/$listingId',
      data: FormData.fromMap(map),
    );
    clearCache();
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> markSellerListingStatus(
    int listingId, {
    required String nextStatus,
  }) async {
    await _dio.post(
      '/api/cars/listings/$listingId/mark-status',
      data: {'nextStatus': nextStatus},
    );
    clearCache();
  }

  void clearCache() {
    _cache.clear();
  }

  T? _readCache<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.expiresAt.isBefore(DateTime.now())) {
      _cache.remove(key);
      return null;
    }
    final value = entry.value;
    if (value is T) return value as T;
    return null;
  }

  void _writeCache(String key, Object value, Duration ttl) {
    _cache[key] = _CarsCacheEntry(
      value: value,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  String _cacheKey(String bucket, Map<String, dynamic> payload) {
    final normalized = _canonical(payload);
    return '$bucket::$normalized';
  }

  String _canonical(Map<String, dynamic> source) {
    final keys = source.keys.map((e) => e.toString()).toList()..sort();
    final pairs = <String>[];
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      if (value is Map<String, dynamic>) {
        pairs.add('$key={${_canonical(value)}}');
        continue;
      }
      if (value is List) {
        pairs.add('$key=[${value.map((e) => '$e').join(',')}]');
        continue;
      }
      pairs.add('$key=$value');
    }
    return pairs.join('&');
  }
}

class _CarsCacheEntry {
  final Object value;
  final DateTime expiresAt;

  const _CarsCacheEntry({required this.value, required this.expiresAt});
}
