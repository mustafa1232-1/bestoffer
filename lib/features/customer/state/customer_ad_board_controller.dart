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

  Future<void> load({String? type, bool force = false}) {
    final normalizedType = type?.trim().toLowerCase();
    if (!_isCustomerSession()) {
      _loadedType = normalizedType;
      state = const AsyncValue.data(<CustomerAdBoardItem>[]);
      return Future.value();
    }
    final hasLoadedCurrent = _loadedType == normalizedType && state.hasValue;
    if (!force && hasLoadedCurrent) {
      return Future.value();
    }
    if (!force && _inFlight != null) {
      return _inFlight!;
    }

    final future = _performLoad(normalizedType);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }

  Future<void> _performLoad(String? normalizedType) async {
    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }
    try {
      final raw = await ref
          .read(merchantsApiProvider)
          .adBoard(type: normalizedType);
      final items = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(CustomerAdBoardItem.fromJson)
          .toList();
      _loadedType = normalizedType;
      state = AsyncValue.data(items);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}
