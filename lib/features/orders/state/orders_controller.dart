import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/realtime/maslaki_realtime_service.dart';
import '../../auth/state/auth_controller.dart';
import '../data/orders_api.dart';
import '../models/order_model.dart';
import 'cart_controller.dart';
import 'delivery_address_controller.dart';

final ordersApiProvider = Provider<OrdersApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return OrdersApi(
    dio,
    realtime: ref.read(maslakiRealtimeServiceProvider),
  );
});

final ordersControllerProvider =
    StateNotifierProvider<OrdersController, OrdersState>((ref) {
      return OrdersController(ref);
    });

/// حالة تدفق طلبات العميل: القائمة الحالية، حالة الإنشاء، ومفضلات المنتجات.
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

/// المتحكم المركزي لطلبات العميل وسير checkout وpolling الطلبات الحية.
///
/// Critical notes:
/// - هذا المتحكم خاص بالعميل النهائي. عند اكتشاف دور backoffice/owner/
///   delivery يتم إيقاف polling لتجنب استدعاءات خاطئة وصلاحيات مرفوضة.
class OrdersController extends StateNotifier<OrdersState> {
  final Ref ref;
  Timer? _liveOrdersTimer;
  bool _liveFetchInFlight = false;
  bool _disposed = false;

  OrdersController(this.ref) : super(const OrdersState());

  void _setStateSafely(OrdersState nextState) {
    if (_disposed) return;
    state = nextState;
  }

  bool _canRunCustomerPolling() {
    final auth = ref.read(authControllerProvider);
    return auth.isAuthed &&
        !auth.isBackoffice &&
        !auth.isOwner &&
        !auth.isDelivery;
  }

  bool _isCustomerForbiddenError(DioException error) {
    if (error.response?.statusCode != 403) return false;
    final data = error.response?.data;
    if (data is! Map) return false;
    final message = '${data['message'] ?? ''}'.trim().toUpperCase();
    final code = '${data['code'] ?? ''}'.trim().toUpperCase();
    return message == 'FORBIDDEN_CUSTOMER_ONLY' ||
        code == 'FORBIDDEN_CUSTOMER_ONLY';
  }

  /// يحمل طلبات العميل الحالية مع حماية ضد البيانات الجزئية أو النماذج
  /// غير المكتملة القادمة من API.
  Future<void> loadMyOrders({bool silent = false}) async {
    if (_disposed) return;
    if (!_canRunCustomerPolling()) {
      stopLiveOrders();
      return;
    }
    if (!silent) {
      _setStateSafely(state.copyWith(loading: true, error: null));
    }
    try {
      final response = await ref.read(ordersApiProvider).listMyOrders();
      if (_disposed) return;
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
      _setStateSafely(
        state.copyWith(
          loading: silent ? state.loading : false,
          orders: orders,
          error: skipped > 0
              ? 'تم تجاهل بعض الطلبات بسبب بيانات غير مكتملة'
              : null,
        ),
      );
    } on DioException catch (e) {
      if (_disposed) return;
      _setStateSafely(
        state.copyWith(
          loading: silent ? state.loading : false,
          error: _mapError(e),
        ),
      );
      if (_isCustomerForbiddenError(e)) {
        stopLiveOrders();
      }
    } catch (_) {
      if (_disposed) return;
      _setStateSafely(
        state.copyWith(
          loading: silent ? state.loading : false,
          error: 'فشل تحميل الطلبات',
        ),
      );
    }
  }

  /// يبدأ polling دوري للطلبات طالما المستخدم في سياق عميل عادي.
  void startLiveOrders({Duration interval = const Duration(seconds: 10)}) {
    if (!_canRunCustomerPolling()) {
      stopLiveOrders();
      return;
    }
    _liveOrdersTimer?.cancel();
    _liveOrdersTimer = Timer.periodic(interval, (_) async {
      if (_disposed) return;
      if (_liveFetchInFlight) return;
      if (!_canRunCustomerPolling()) {
        stopLiveOrders();
        return;
      }
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

  /// ينفذ checkout الكامل اعتماداً على السلة والعنوان المختار الحاليين.
  ///
  /// Return value:
  /// - `true` عند نجاح إنشاء الطلب وتفريغ السلة.
  ///
  /// Maintenance notes:
  /// - إذا فشل checkout ظاهرياً لكن الطلب أنشئ فعلاً، افحص هذا المسار مع
  ///   `OrdersApi.createOrder`, حالة السلة، ثم refresh اللاحق للطلبات.
  Future<bool> checkout({
    String? note,
    LocalImageFile? imageFile,
    int? couponId,
    String? couponCode,
  }) async {
    final cart = ref.read(cartControllerProvider);
    var addressState = ref.read(deliveryAddressControllerProvider);
    var selectedAddress = addressState.selectedAddress;
    if (cart.items.isEmpty) {
      _setStateSafely(state.copyWith(error: 'السلة فارغة'));
      return false;
    }
    if (selectedAddress == null) {
      await ref
          .read(deliveryAddressControllerProvider.notifier)
          .bootstrap(silent: true);
      addressState = ref.read(deliveryAddressControllerProvider);
      selectedAddress = addressState.selectedAddress;
    }
    if (selectedAddress == null) {
      _setStateSafely(
        state.copyWith(error: 'الرجاء اختيار عنوان توصيل قبل إتمام الطلب'),
      );
      return false;
    }

    _setStateSafely(state.copyWith(placingOrder: true, error: null));

    try {
      final cleanedNote = note?.trim();

      final payload = <String, dynamic>{
        'note': (cleanedNote == null || cleanedNote.isEmpty) ? null : cleanedNote,
        'addressId': selectedAddress.id,
      };
      if (cart.storesCount > 1) {
        payload['storeOrders'] = cart.storeSections
            .map(
              (section) => {
                'merchantId': section.merchantId,
                'items': section.items
                    .map(
                      (i) => {
                        'productId': i.product.id,
                        'quantity': i.quantity,
                        if (i.selectedModifiers.isNotEmpty)
                          'selectedModifiers': i.selectedModifiers,
                        if (i.selectedVariantSelections.isNotEmpty)
                          'selectedVariantSelections':
                              i.selectedVariantSelections,
                      },
                    )
                    .toList(),
              },
            )
            .toList();
      } else {
        payload['merchantId'] = cart.merchantId;
        payload['items'] = cart.items
            .map(
              (i) => {
                'productId': i.product.id,
                'quantity': i.quantity,
                if (i.selectedModifiers.isNotEmpty)
                  'selectedModifiers': i.selectedModifiers,
                if (i.selectedVariantSelections.isNotEmpty)
                  'selectedVariantSelections': i.selectedVariantSelections,
              },
            )
            .toList();
        if (couponId != null && couponId > 0) {
          payload['couponId'] = couponId;
        }
        if (couponCode != null && couponCode.trim().isNotEmpty) {
          payload['couponCode'] = couponCode.trim();
        }
      }

      await ref.read(ordersApiProvider).createOrder(payload, imageFile: imageFile);

      ref.read(cartControllerProvider.notifier).clear();
      await loadMyOrders();
      _setStateSafely(state.copyWith(placingOrder: false));
      return true;
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(placingOrder: false, error: _mapError(e)));
      return false;
    } catch (_) {
      _setStateSafely(
        state.copyWith(placingOrder: false, error: 'فشل إرسال الطلب'),
      );
      return false;
    }
  }

  Future<bool> confirmDelivered(int orderId) async {
    _setStateSafely(state.copyWith(error: null));
    try {
      await ref.read(ordersApiProvider).confirmDelivered(orderId);
      await ref
          .read(localNotificationsProvider)
          .cancelCustomerConfirmationReminder(orderId);
      await loadMyOrders();
      return true;
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(error: _mapError(e)));
      return false;
    } catch (_) {
      _setStateSafely(state.copyWith(error: 'فشل تأكيد الاستلام'));
      return false;
    }
  }

  Future<void> rateDelivery({
    required int orderId,
    required int rating,
    String? review,
  }) async {
    _setStateSafely(state.copyWith(error: null));
    try {
      await ref
          .read(ordersApiProvider)
          .rateDelivery(orderId: orderId, rating: rating, review: review);
      await loadMyOrders();
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(error: _mapError(e)));
    } catch (_) {
      _setStateSafely(state.copyWith(error: 'فشل إرسال تقييم الدلفري'));
    }
  }

  Future<void> rateMerchant({
    required int orderId,
    required int rating,
    String? review,
  }) async {
    _setStateSafely(state.copyWith(error: null));
    try {
      await ref
          .read(ordersApiProvider)
          .rateMerchant(orderId: orderId, rating: rating, review: review);
      await loadMyOrders();
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(error: _mapError(e)));
    } catch (_) {
      _setStateSafely(state.copyWith(error: 'فشل إرسال تقييم المتجر'));
    }
  }

  /// يعيد استخدام عناصر طلب سابق لإنشاء طلب جديد من الواجهة.
  Future<void> reorder(int orderId, {String? note}) async {
    _setStateSafely(state.copyWith(placingOrder: true, error: null));
    try {
      await ref.read(ordersApiProvider).reorder(orderId: orderId, note: note);
      await loadMyOrders();
      _setStateSafely(state.copyWith(placingOrder: false));
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(placingOrder: false, error: _mapError(e)));
    } catch (_) {
      _setStateSafely(
        state.copyWith(placingOrder: false, error: 'فشل إعادة الطلب'),
      );
    }
  }

  Future<bool> cancelOrderByCustomer({
    required int orderId,
    required String reasonCode,
    String? reasonText,
  }) async {
    _setStateSafely(state.copyWith(error: null));
    try {
      await ref.read(ordersApiProvider).cancelOrderByCustomer(
            orderId: orderId,
            reasonCode: reasonCode,
            reasonText: reasonText,
          );
      await loadMyOrders();
      return true;
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(error: _mapError(e)));
      return false;
    } catch (_) {
      _setStateSafely(
        state.copyWith(error: 'تعذر إلغاء الطلب في الوقت الحالي.'),
      );
      return false;
    }
  }

  Future<bool> requestReturnByCustomer({
    required int orderId,
    required String reasonCode,
    String? reasonText,
  }) async {
    _setStateSafely(state.copyWith(error: null));
    try {
      await ref.read(ordersApiProvider).requestReturnByCustomer(
            orderId: orderId,
            reasonCode: reasonCode,
            reasonText: reasonText,
          );
      await loadMyOrders();
      return true;
    } on DioException catch (e) {
      _setStateSafely(state.copyWith(error: _mapError(e)));
      return false;
    } catch (_) {
      _setStateSafely(
        state.copyWith(error: 'تعذر إرسال طلب الإرجاع الآن.'),
      );
      return false;
    }
  }

  Future<void> loadFavoriteProductIds() async {
    try {
      final ids = await ref.read(ordersApiProvider).listFavoriteProductIds();
      _setStateSafely(state.copyWith(favoriteProductIds: ids.toSet()));
    } catch (_) {
      // Ignore silently to avoid interrupting ordering flow.
    }
  }

  Future<void> toggleFavoriteProduct(int productId, bool nextFavorite) async {
    _setStateSafely(state.copyWith(error: null));
    final before = state.favoriteProductIds;
    final optimistic = <int>{...before};
    if (nextFavorite) {
      optimistic.add(productId);
    } else {
      optimistic.remove(productId);
    }
    _setStateSafely(state.copyWith(favoriteProductIds: optimistic));

    try {
      if (nextFavorite) {
        await ref.read(ordersApiProvider).addFavoriteProduct(productId);
      } else {
        await ref.read(ordersApiProvider).removeFavoriteProduct(productId);
      }
    } on DioException catch (e) {
      _setStateSafely(
        state.copyWith(favoriteProductIds: before, error: _mapError(e)),
      );
    } catch (_) {
      _setStateSafely(
        state.copyWith(favoriteProductIds: before, error: 'فشل تحديث المفضلة'),
      );
    }
  }

  String _mapError(DioException e) {
    return mapDioError(
      e,
      fallback: 'تعذر الاتصال بالخادم.',
      appendRequestId: true,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    stopLiveOrders();
    super.dispose();
  }
}
