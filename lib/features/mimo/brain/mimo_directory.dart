import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/state/auth_controller.dart';
import '../../merchants/shopping_groups.dart';

/// One store as Mimo knows it: where it is in the app and how good it is.
class MimoStore {
  const MimoStore({
    required this.id,
    required this.name,
    this.type = 'market',
    this.activityType = '',
    this.pharmacy = false,
    this.rating,
    this.ratingCount = 0,
    this.orders = 0,
    this.isOpen = true,
    this.offer = false,
    this.freeDelivery = false,
    this.area,
    this.logoUrl,
    this.tagline,
    this.etaMin,
    this.etaMax,
  });

  final int id;
  final String name;
  final String type;
  final String activityType;
  final bool pharmacy;
  final double? rating;
  final int ratingCount;
  final int orders;
  final bool isOpen;
  final bool offer;
  final bool freeDelivery;
  final String? area;
  final String? logoUrl;
  final String? tagline;
  final int? etaMin;
  final int? etaMax;

  /// The shopping card this store is listed under (null = "كل المتاجر").
  String? get group => shoppingGroupOf(
    type: type,
    activityType: activityType,
    supportsPharmacy: pharmacy,
  );

  factory MimoStore.fromJson(Map<String, dynamic> j) => MimoStore(
    id: (j['id'] as num?)?.toInt() ?? 0,
    name: '${j['name'] ?? ''}'.trim(),
    type: '${j['type'] ?? 'market'}',
    activityType: '${j['activityType'] ?? ''}',
    pharmacy: j['pharmacy'] == true,
    rating: (j['rating'] as num?)?.toDouble(),
    ratingCount: (j['ratingCount'] as num?)?.toInt() ?? 0,
    orders: (j['orders'] as num?)?.toInt() ?? 0,
    isOpen: j['isOpen'] != false,
    offer: j['offer'] == true,
    freeDelivery: j['freeDelivery'] == true,
    area: _s(j['area']),
    logoUrl: _s(j['logoUrl']),
    tagline: _s(j['tagline']),
    etaMin: (j['etaMin'] as num?)?.toInt(),
    etaMax: (j['etaMax'] as num?)?.toInt(),
  );

  /// Same shape as the cards Mimo's AI sends, so the chat renders both alike.
  Map<String, dynamic> toCard() => {
    'id': id,
    'name': name,
    'type': type,
    'activityType': activityType,
    'rating': rating ?? 0,
    'ratingsCount': ratingCount,
    'completedOrders': orders,
    'isOpen': isOpen,
    'hasOffer': offer,
    'freeDelivery': freeDelivery,
    'logoUrl': logoUrl,
    if (pharmacy) 'pharmacy': true,
  };
}

/// One service offering (a craftsman / professional).
class MimoService {
  const MimoService({
    required this.id,
    required this.name,
    this.category,
    this.subcategory,
    this.provider,
    this.area,
    this.rating,
    this.ratingCount = 0,
    this.orders = 0,
    this.startsFrom,
  });

  final int id;
  final String name;
  final String? category;
  final String? subcategory;
  final String? provider;
  final String? area;
  final double? rating;
  final int ratingCount;
  final int orders;
  final double? startsFrom;

  factory MimoService.fromJson(Map<String, dynamic> j) => MimoService(
    id: (j['id'] as num?)?.toInt() ?? 0,
    name: '${j['name'] ?? ''}'.trim(),
    category: _s(j['category']),
    subcategory: _s(j['subcategory']),
    provider: _s(j['provider']),
    area: _s(j['area']),
    rating: (j['rating'] as num?)?.toDouble(),
    ratingCount: (j['ratingCount'] as num?)?.toInt() ?? 0,
    orders: (j['orders'] as num?)?.toInt() ?? 0,
    startsFrom: (j['startsFrom'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toCard() => {
    'id': id,
    'title': name,
    'provider': provider ?? '',
    'rating': rating ?? 0,
    'reviews': ratingCount,
    'price': ?startsFrom,
  };
}

class MimoDirectory {
  const MimoDirectory({this.stores = const [], this.services = const []});

  final List<MimoStore> stores;
  final List<MimoService> services;

  bool get isEmpty => stores.isEmpty && services.isEmpty;

  factory MimoDirectory.fromJson(Map<String, dynamic> j) => MimoDirectory(
    stores: [
      for (final e in (j['stores'] as List? ?? const []))
        if (e is Map) MimoStore.fromJson(Map<String, dynamic>.from(e)),
    ].where((s) => s.id > 0 && s.name.isNotEmpty).toList(growable: false),
    services: [
      for (final e in (j['services'] as List? ?? const []))
        if (e is Map) MimoService.fromJson(Map<String, dynamic>.from(e)),
    ].where((s) => s.id > 0 && s.name.isNotEmpty).toList(growable: false),
  );
}

String? _s(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty ? null : s;
}

/// Loads the directory: instantly from the phone's cache, then refreshes from
/// the server in the background (at most once a minute).
class MimoDirectoryController extends StateNotifier<MimoDirectory> {
  MimoDirectoryController(this._fetch) : super(const MimoDirectory()) {
    _loadCached();
  }

  static const _cacheKey = 'mimo_directory_v1';
  final Future<Map<String, dynamic>?> Function() _fetch;
  DateTime? _fetchedAt;
  Future<void>? _inFlight;

  Future<void> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && state.isEmpty) {
        state = MimoDirectory.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      }
    } catch (_) {}
  }

  /// Refreshes unless fresh; never throws.
  Future<void> refresh({bool force = false}) {
    final at = _fetchedAt;
    if (!force &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 1)) {
      return Future.value();
    }
    return _inFlight ??= _doRefresh().whenComplete(() => _inFlight = null);
  }

  Future<void> _doRefresh() async {
    try {
      final json = await _fetch();
      if (json == null) return;
      final next = MimoDirectory.fromJson(json);
      if (next.isEmpty) return;
      _fetchedAt = DateTime.now();
      if (mounted) state = next;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(json));
    } catch (_) {}
  }
}

final mimoDirectoryProvider =
    StateNotifierProvider<MimoDirectoryController, MimoDirectory>((ref) {
      final dio = ref.read(dioClientProvider).dio;
      return MimoDirectoryController(() async {
        final r = await dio.get('/api/mimo/directory');
        return r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
      });
    });
