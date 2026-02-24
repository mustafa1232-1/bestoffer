import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/currency.dart';
import '../../auth/state/auth_controller.dart';
import '../../orders/models/order_model.dart';
import '../data/delivery_api.dart';

final deliveryApiProvider = Provider<DeliveryApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return DeliveryApi(dio);
});

final deliveryControllerProvider =
    StateNotifierProvider<DeliveryController, DeliveryState>((ref) {
      return DeliveryController(ref);
    });

class DeliveryState {
  final bool loading;
  final bool saving;
  final List<OrderModel> currentOrders;
  final List<OrderModel> historyOrders;
  final Map<String, dynamic> analytics;
  final String? error;
  final String? lastArchiveMessage;

  const DeliveryState({
    this.loading = false,
    this.saving = false,
    this.currentOrders = const [],
    this.historyOrders = const [],
    this.analytics = const {},
    this.error,
    this.lastArchiveMessage,
  });

  DeliveryState copyWith({
    bool? loading,
    bool? saving,
    List<OrderModel>? currentOrders,
    List<OrderModel>? historyOrders,
    Map<String, dynamic>? analytics,
    String? error,
    String? lastArchiveMessage,
  }) {
    return DeliveryState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      currentOrders: currentOrders ?? this.currentOrders,
      historyOrders: historyOrders ?? this.historyOrders,
      analytics: analytics ?? this.analytics,
      error: error,
      lastArchiveMessage: lastArchiveMessage ?? this.lastArchiveMessage,
    );
  }
}

class DeliveryController extends StateNotifier<DeliveryState> {
  final Ref ref;

  DeliveryController(this.ref) : super(const DeliveryState());

  Future<void> bootstrap({String? historyDate}) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final currentResponse = await ref
          .read(deliveryApiProvider)
          .currentOrders();
      final historyResponse = await ref
          .read(deliveryApiProvider)
          .history(date: historyDate);
      final analyticsResponse = await ref.read(deliveryApiProvider).analytics();

      final currentOrders = currentResponse
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final historyOrders = historyResponse
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      state = state.copyWith(
        loading: false,
        currentOrders: currentOrders,
        historyOrders: historyOrders,
        analytics: analyticsResponse,
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(loading: false, error: 'فشل تحميل بيانات الدلفري');
    }
  }

  Future<void> claimOrder(int orderId) async {
    state = state.copyWith(saving: true, error: null);
    try {
      await ref.read(deliveryApiProvider).claimOrder(orderId);
      await bootstrap();
      state = state.copyWith(saving: false);
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'فشل استلام الطلب');
    }
  }

  Future<void> startOrder(int orderId, {int? estimatedDeliveryMinutes}) async {
    state = state.copyWith(saving: true, error: null);
    try {
      await ref
          .read(deliveryApiProvider)
          .startOrder(
            orderId,
            estimatedDeliveryMinutes: estimatedDeliveryMinutes,
          );
      await bootstrap();
      state = state.copyWith(saving: false);
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'فشل تحديث حالة الطلب');
    }
  }

  Future<void> markDelivered(int orderId) async {
    state = state.copyWith(saving: true, error: null);
    try {
      await ref.read(deliveryApiProvider).markDelivered(orderId);
      await bootstrap();
      state = state.copyWith(saving: false);
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'فشل إنهاء الطلب');
    }
  }

  Future<void> endDay() async {
    state = state.copyWith(saving: true, error: null);
    try {
      final summary = await ref.read(deliveryApiProvider).endDay();
      final count = summary['ordersCount'] ?? 0;
      final date = summary['archiveDate'] ?? '';
      final amount = summary['totalAmount'] ?? 0;
      await bootstrap();
      state = state.copyWith(
        saving: false,
        lastArchiveMessage:
            'تم إنهاء يوم $date - $count طلب - الإجمالي ${formatIqd(amount)}',
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'فشل إنهاء اليوم');
    }
  }

  String _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return 'حدث خطأ في الاتصال بالخادم';
  }
}
