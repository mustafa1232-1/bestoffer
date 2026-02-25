import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../auth/state/auth_controller.dart';
import '../data/orders_api.dart';
import '../models/order_model.dart';
import 'cart_controller.dart';
import 'delivery_address_controller.dart';

final ordersApiProvider = Provider<OrdersApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return OrdersApi(dio);
});

final ordersControllerProvider =
    StateNotifierProvider<OrdersController, OrdersState>((ref) {
      return OrdersController(ref);
    });

class OrdersState {
  final bool loading;
  final bool placingOrder;
  final List<OrderModel> orders;
  final Set<int> favoriteProductIds;
  final String? error;

  const OrdersState({
    this.loading = false,
    this.placingOrder = false,
    this.orders = const [],
    this.favoriteProductIds = const <int>{},
    this.error,
  });

  OrdersState copyWith({
    bool? loading,
    bool? placingOrder,
    List<OrderModel>? orders,
    Set<int>? favoriteProductIds,
    String? error,
  }) {
    return OrdersState(
      loading: loading ?? this.loading,
      placingOrder: placingOrder ?? this.placingOrder,
      orders: orders ?? this.orders,
      favoriteProductIds: favoriteProductIds ?? this.favoriteProductIds,
      error: error,
    );
  }
}

class OrdersController extends StateNotifier<OrdersState> {
  final Ref ref;
  Timer? _liveOrdersTimer;
  bool _liveFetchInFlight = false;

  OrdersController(this.ref) : super(const OrdersState());

  Future<void> loadMyOrders({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(loading: true, error: null);
    }
    try {
      final response = await ref.read(ordersApiProvider).listMyOrders();
      final orders = <OrderModel>[];
      var skipped = 0;
      for (final entry in response) {
        try {
          if (entry is Map) {
            orders.add(OrderModel.fromJson(Map<String, dynamic>.from(entry)));
          } else {
            skipped += 1;
          }
        } catch (_) {
          skipped += 1;
        }
      }
      state = state.copyWith(
        loading: silent ? state.loading : false,
        orders: orders,
        error: skipped > 0
            ? 'تم تجاهل بعض الطلبات بسبب بيانات غير مكتملة'
            : null,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        loading: silent ? state.loading : false,
        error: _mapError(e),
      );
    } catch (_) {
      state = state.copyWith(
        loading: silent ? state.loading : false,
        error: 'فشل تحميل الطلبات',
      );
    }
  }

  void startLiveOrders({Duration interval = const Duration(seconds: 4)}) {
    _liveOrdersTimer?.cancel();
    _liveOrdersTimer = Timer.periodic(interval, (_) async {
      if (_liveFetchInFlight) return;
      _liveFetchInFlight = true;
      try {
        await loadMyOrders(silent: true);
      } finally {
        _liveFetchInFlight = false;
      }
    });
  }

  void stopLiveOrders() {
    _liveOrdersTimer?.cancel();
    _liveOrdersTimer = null;
  }

  Future<bool> checkout({String? note, LocalImageFile? imageFile}) async {
    final cart = ref.read(cartControllerProvider);
    final addressState = ref.read(deliveryAddressControllerProvider);
    final selectedAddress = addressState.selectedAddress;
    if (cart.merchantId == null || cart.items.isEmpty) {
      state = state.copyWith(error: 'السلة فارغة');
      return false;
    }
    if (selectedAddress == null) {
      state = state.copyWith(
        error: 'الرجاء اختيار عنوان توصيل قبل إتمام الطلب',
      );
      return false;
    }

    state = state.copyWith(placingOrder: true, error: null);

    try {
      final cleanedNote = note?.trim();

      await ref.read(ordersApiProvider).createOrder({
        'merchantId': cart.merchantId,
        'note': (cleanedNote == null || cleanedNote.isEmpty)
            ? null
            : cleanedNote,
        'addressId': selectedAddress.id,
        'items': cart.items
            .map((i) => {'productId': i.product.id, 'quantity': i.quantity})
            .toList(),
      }, imageFile: imageFile);

      ref.read(cartControllerProvider.notifier).clear();
      await loadMyOrders();
      state = state.copyWith(placingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(placingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(placingOrder: false, error: 'فشل إرسال الطلب');
      return false;
    }
  }

  Future<bool> confirmDelivered(int orderId) async {
    state = state.copyWith(error: null);
    try {
      await ref.read(ordersApiProvider).confirmDelivered(orderId);
      await loadMyOrders();
      return true;
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(error: 'فشل تأكيد الاستلام');
      return false;
    }
  }

  Future<void> rateDelivery({
    required int orderId,
    required int rating,
    String? review,
  }) async {
    state = state.copyWith(error: null);
    try {
      await ref
          .read(ordersApiProvider)
          .rateDelivery(orderId: orderId, rating: rating, review: review);
      await loadMyOrders();
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
    } catch (_) {
      state = state.copyWith(error: 'فشل إرسال تقييم الدلفري');
    }
  }

  Future<void> rateMerchant({
    required int orderId,
    required int rating,
    String? review,
  }) async {
    state = state.copyWith(error: null);
    try {
      await ref
          .read(ordersApiProvider)
          .rateMerchant(orderId: orderId, rating: rating, review: review);
      await loadMyOrders();
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
    } catch (_) {
      state = state.copyWith(error: 'فشل إرسال تقييم المتجر');
    }
  }

  Future<void> reorder(int orderId, {String? note}) async {
    state = state.copyWith(placingOrder: true, error: null);
    try {
      await ref.read(ordersApiProvider).reorder(orderId: orderId, note: note);
      await loadMyOrders();
      state = state.copyWith(placingOrder: false);
    } on DioException catch (e) {
      state = state.copyWith(placingOrder: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(placingOrder: false, error: 'فشل إعادة الطلب');
    }
  }

  Future<void> loadFavoriteProductIds() async {
    try {
      final ids = await ref.read(ordersApiProvider).listFavoriteProductIds();
      state = state.copyWith(favoriteProductIds: ids.toSet());
    } catch (_) {
      // Ignore silently to avoid interrupting ordering flow.
    }
  }

  Future<void> toggleFavoriteProduct(int productId, bool nextFavorite) async {
    state = state.copyWith(error: null);
    final before = state.favoriteProductIds;
    final optimistic = <int>{...before};
    if (nextFavorite) {
      optimistic.add(productId);
    } else {
      optimistic.remove(productId);
    }
    state = state.copyWith(favoriteProductIds: optimistic);

    try {
      if (nextFavorite) {
        await ref.read(ordersApiProvider).addFavoriteProduct(productId);
      } else {
        await ref.read(ordersApiProvider).removeFavoriteProduct(productId);
      }
    } on DioException catch (e) {
      state = state.copyWith(favoriteProductIds: before, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        favoriteProductIds: before,
        error: 'فشل تحديث المفضلة',
      );
    }
  }

  String _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    return 'حدث خطأ في الاتصال بالخادم';
  }

  @override
  void dispose() {
    stopLiveOrders();
    super.dispose();
  }
}
