import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../../merchants/state/merchants_controller.dart';
import '../models/customer_ad_board_item.dart';

final customerAdBoardControllerProvider =
    StateNotifierProvider<
      CustomerAdBoardController,
      AsyncValue<List<CustomerAdBoardItem>>
    >((ref) => CustomerAdBoardController(ref));

class CustomerAdBoardController
    extends StateNotifier<AsyncValue<List<CustomerAdBoardItem>>> {
  final Ref ref;
  String? _loadedType;
  String? _loadedPlacement;
  Future<void>? _inFlight;

  CustomerAdBoardController(this.ref) : super(const AsyncValue.loading());

  /// The ad board is a customer-only surface: the backend guards
  /// `GET /api/merchants/ad-board` with `requireCustomer` (role `user` only).
  /// Calling it from a non-customer session (owner/store/admin/hr/delivery)
  /// returns 403 FORBIDDEN_CUSTOMER_ONLY and spams production logs, so we skip
  /// the request entirely for those sessions and present an empty board.
  bool _isCustomerSession() {
    final role = ref.read(authControllerProvider).user?.role;
    return role != null && role.trim().toLowerCase() == 'user';
  }

  Future<void> load({
    String? type,
    String placement = 'HOME_MAIN',
    bool force = false,
  }) {
    final normalizedType = type?.trim().toLowerCase();
    final normalizedPlacement = placement.trim().toUpperCase();
    if (!_isCustomerSession()) {
      _loadedType = normalizedType;
      _loadedPlacement = normalizedPlacement;
      state = const AsyncValue.data(<CustomerAdBoardItem>[]);
      return Future.value();
    }
    final hasLoadedCurrent = _loadedType == normalizedType &&
        _loadedPlacement == normalizedPlacement &&
        state.hasValue;
    if (!force && hasLoadedCurrent) {
      return Future.value();
    }
    if (!force && _inFlight != null) {
      return _inFlight!;
    }

    final future = _performLoad(
      normalizedType,
      normalizedPlacement: normalizedPlacement,
    );
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }

  Future<void> _performLoad(
    String? normalizedType, {
    required String normalizedPlacement,
  }) async {
    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }
    try {
      final raw = await ref
          .read(merchantsApiProvider)
          .adBoard(type: normalizedType, placement: normalizedPlacement);
      final items = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(CustomerAdBoardItem.fromJson)
          .toList();
      _loadedType = normalizedType;
      _loadedPlacement = normalizedPlacement;
      state = AsyncValue.data(items);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

/// A placement-scoped ad request. Used by the marketplace home & category ad
/// widgets which each fetch an independent, non-duplicated ad from the same
/// `ad_board` backend but with a different placement/category target.
class MarketplaceAdRequest {
  final String placement;
  final String? type;
  final String? categoryKey;
  final String? activityType;

  const MarketplaceAdRequest({
    required this.placement,
    this.type,
    this.categoryKey,
    this.activityType,
  });

  @override
  bool operator ==(Object other) =>
      other is MarketplaceAdRequest &&
      other.placement == placement &&
      other.type == type &&
      other.categoryKey == categoryKey &&
      other.activityType == activityType;

  @override
  int get hashCode => Object.hash(placement, type, categoryKey, activityType);
}

/// Fetches the highest-priority active ad for a placement. Returns null when
/// there is no eligible ad so the surface can collapse fully. Customer-only:
/// non-customer sessions resolve to null without hitting the network.
final marketplaceAdProvider =
    FutureProvider.family<CustomerAdBoardItem?, MarketplaceAdRequest>((
      ref,
      request,
    ) async {
      final role = ref.read(authControllerProvider).user?.role;
      final isCustomer = role != null && role.trim().toLowerCase() == 'user';
      if (!isCustomer) return null;

      final raw = await ref.read(merchantsApiProvider).adBoard(
            type: request.type,
            placement: request.placement,
            categoryKey: request.categoryKey,
            activityType: request.activityType,
          );
      final items = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(CustomerAdBoardItem.fromJson)
          .where((ad) => ad.placement == request.placement)
          .toList();
      if (items.isEmpty) return null;
      // Backend already orders category-specific over general, then by
      // priority; the first row is the winning ad for this surface.
      return items.first;
    });
