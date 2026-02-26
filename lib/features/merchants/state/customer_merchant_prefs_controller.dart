import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';

class CustomerMerchantPrefsState {
  final bool loading;
  final Set<int> favoriteMerchantIds;
  final List<int> recentMerchantIds;

  const CustomerMerchantPrefsState({
    this.loading = false,
    this.favoriteMerchantIds = const <int>{},
    this.recentMerchantIds = const <int>[],
  });

  CustomerMerchantPrefsState copyWith({
    bool? loading,
    Set<int>? favoriteMerchantIds,
    List<int>? recentMerchantIds,
  }) {
    return CustomerMerchantPrefsState(
      loading: loading ?? this.loading,
      favoriteMerchantIds: favoriteMerchantIds ?? this.favoriteMerchantIds,
      recentMerchantIds: recentMerchantIds ?? this.recentMerchantIds,
    );
  }
}

final customerMerchantPrefsProvider =
    StateNotifierProvider<
      CustomerMerchantPrefsController,
      CustomerMerchantPrefsState
    >((ref) => CustomerMerchantPrefsController(ref));

class CustomerMerchantPrefsController
    extends StateNotifier<CustomerMerchantPrefsState> {
  static const _favoritesKeyPrefix = 'customer_favorite_merchants';
  static const _recentKeyPrefix = 'customer_recent_merchants';
  static const _recentLimit = 12;

  final Ref ref;

  CustomerMerchantPrefsController(this.ref)
    : super(const CustomerMerchantPrefsState());

  Future<void> bootstrap({required int userId}) async {
    state = state.copyWith(loading: true);
    final store = ref.read(secureStoreProvider);
    final favoritesRaw = await store.readString(_favoritesKey(userId));
    final recentRaw = await store.readString(_recentKey(userId));

    state = CustomerMerchantPrefsState(
      loading: false,
      favoriteMerchantIds: _parseIntSet(favoritesRaw),
      recentMerchantIds: _parseIntList(recentRaw),
    );
  }

  Future<void> toggleFavorite({
    required int userId,
    required int merchantId,
  }) async {
    final next = <int>{...state.favoriteMerchantIds};
    if (next.contains(merchantId)) {
      next.remove(merchantId);
    } else {
      next.add(merchantId);
    }
    state = state.copyWith(favoriteMerchantIds: next);
    await _persistFavorites(userId, next);
  }

  Future<void> markVisited({
    required int userId,
    required int merchantId,
  }) async {
    final next = <int>[
      merchantId,
      ...state.recentMerchantIds.where((id) => id != merchantId),
    ];
    if (next.length > _recentLimit) {
      next.removeRange(_recentLimit, next.length);
    }
    state = state.copyWith(recentMerchantIds: next);
    await _persistRecent(userId, next);
  }

  Future<void> clearRecent({required int userId}) async {
    state = state.copyWith(recentMerchantIds: const <int>[]);
    await _persistRecent(userId, const <int>[]);
  }

  Future<void> _persistFavorites(int userId, Set<int> ids) async {
    final store = ref.read(secureStoreProvider);
    final data = jsonEncode(ids.toList()..sort());
    await store.writeString(_favoritesKey(userId), data);
  }

  Future<void> _persistRecent(int userId, List<int> ids) async {
    final store = ref.read(secureStoreProvider);
    await store.writeString(_recentKey(userId), jsonEncode(ids));
  }

  String _favoritesKey(int userId) => '$_favoritesKeyPrefix:$userId';

  String _recentKey(int userId) => '$_recentKeyPrefix:$userId';
}

Set<int> _parseIntSet(String? raw) => _parseIntList(raw).toSet();

List<int> _parseIntList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <int>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <int>[];
    return decoded
        .map((e) => int.tryParse('$e') ?? 0)
        .where((id) => id > 0)
        .toList();
  } catch (_) {
    return const <int>[];
  }
}
