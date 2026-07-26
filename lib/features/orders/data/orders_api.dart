import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/files/local_image_file.dart';
import '../../../core/realtime/maslaki_realtime_service.dart';
import '../models/product_review_model.dart';
import '../models/order_revision_model.dart';
import '../../notifications/data/notifications_api.dart';

class OrderActionReasonOption {
  final String actorScope;
  final String actionKind;
  final String reasonCode;
  final String label;
  final bool allowsOtherText;

  const OrderActionReasonOption({
    required this.actorScope,
    required this.actionKind,
    required this.reasonCode,
    required this.label,
    required this.allowsOtherText,
  });

  factory OrderActionReasonOption.fromMap(Map<String, dynamic> map) {
    final labelAr = '${map['reasonLabelAr'] ?? ''}'.trim();
    final labelEn = '${map['reasonLabelEn'] ?? ''}'.trim();
    return OrderActionReasonOption(
      actorScope: '${map['actorScope'] ?? ''}'.trim(),
      actionKind: '${map['actionKind'] ?? ''}'.trim(),
      reasonCode: '${map['reasonCode'] ?? ''}'.trim(),
      label: labelAr.isNotEmpty ? labelAr : labelEn,
      allowsOtherText: map['allowsOtherText'] == true,
    );
  }
}

class OrderTrackingLiveEvent {
  final String event;
  final Map<String, dynamic> data;
  final int? eventId;

  const OrderTrackingLiveEvent({
    required this.event,
    required this.data,
    this.eventId,
  });
}

/// عميل API الخاص بطلبات العميل والعناوين والمفضلة والتقييمات.
///
/// Critical notes:
/// - هذا الملف يترجم فقط بين Dart payloads وREST endpoints؛ لا يجب وضع
///   business validation معقدة هنا.
class OrdersApi {
  final Dio dio;
  final MaslakiRealtimeClient? realtime;

  OrdersApi(this.dio, {this.realtime});

  /// ينشئ طلباً جديداً، ويدعم رفع صورة مرفقة اختيارية عبر multipart.
  Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final data = await _withOptionalOrderImage(body, imageFile);
    final response = await dio.post('/api/orders', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> previewOrder(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final data = await _withOptionalOrderImage(body, imageFile);
    final response = await dio.post('/api/orders/preview', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// يجلب طلبات المستخدم.
  /// - إذا تم تمرير `limit` (أو `offset > 0`) يستخدم pagination.
  /// - إذا لم يُمرَّر `limit` يرجع السلوك الرجعي (كل الطلبات حسب الخادم).
  Future<List<dynamic>> listMyOrders({int? limit, int offset = 0}) async {
    final shouldPaginate = (limit != null && limit > 0) || offset > 0;
    final response = await dio.get(
      '/api/orders/my',
      queryParameters: shouldPaginate
          ? {
              if (limit != null && limit > 0) 'limit': limit,
              if (offset > 0) 'offset': offset,
            }
          : null,
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> getTrackingSnapshot(int orderId) async {
    final response = await dio.get('/api/orders/$orderId/tracking');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createTrackingShareToken(int orderId) async {
    final response = await dio.post('/api/orders/$orderId/share-token');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getPublicTrackingByToken(String token) async {
    final response = await dio.get('/api/orders/public/track/$token');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Stream<OrderTrackingLiveEvent> streamPublicTrackingByToken(
    String token,
  ) async* {
    final response = await dio.get<ResponseBody>(
      '/api/orders/public/track/$token/stream',
      options: Options(
        responseType: ResponseType.stream,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(hours: 1),
        headers: const {'Accept': 'text/event-stream'},
      ),
    );

    final body = response.data;
    if (body == null) return;

    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    var eventName = 'message';
    var dataBuffer = '';

    await for (final line in lines) {
      if (line.startsWith('retry:') || line.startsWith('id:')) {
        continue;
      }
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
        continue;
      }
      if (line.startsWith('data:')) {
        final chunk = line.substring(5).trimLeft();
        dataBuffer = dataBuffer.isEmpty ? chunk : '$dataBuffer\n$chunk';
        continue;
      }
      if (line.isNotEmpty) continue;
      if (dataBuffer.isEmpty) {
        eventName = 'message';
        continue;
      }

      final decoded = _parseSsePayload(dataBuffer);
      yield OrderTrackingLiveEvent(event: eventName, data: decoded);
      eventName = 'message';
      dataBuffer = '';
    }
  }

  Stream<OrderTrackingLiveEvent> streamTrackingEvents({
    required int orderId,
    int? lastEventId,
  }) {
    return _streamSupabaseFirst(
      openRealtime: () async => await realtime?.subscribeDefaultUserChannel(),
      fallback: () => NotificationsApi(dio)
          .streamEvents(lastEventId: lastEventId, channel: 'notifications')
          .where(
            (event) =>
                _matchesOrderTrackingEvent(event.event, event.data, orderId),
          )
          .map(
            (event) => OrderTrackingLiveEvent(
              event: event.event,
              data: event.data,
              eventId: event.eventId,
            ),
          ),
    ).where(
      (event) =>
          event.event == 'connected' ||
          event.event == 'resync_required' ||
          _matchesOrderTrackingEvent(event.event, event.data, orderId),
    );
  }

  Stream<OrderTrackingLiveEvent> _streamSupabaseFirst({
    required Future<Stream<MaslakiRealtimeEvent>?> Function() openRealtime,
    required Stream<OrderTrackingLiveEvent> Function() fallback,
  }) {
    late final StreamController<OrderTrackingLiveEvent> controller;
    StreamSubscription<dynamic>? activeSubscription;
    var usingFallback = false;

    Future<void> attachFallback() async {
      if (usingFallback || controller.isClosed) return;
      usingFallback = true;
      await activeSubscription?.cancel();
      activeSubscription = fallback().listen(
        controller.add,
        onError: controller.addError,
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
      );
    }

    Future<void> bootstrap() async {
      try {
        final realtimeStream = await openRealtime();
        if (realtimeStream == null) {
          await attachFallback();
          return;
        }
        controller.add(
          const OrderTrackingLiveEvent(
            event: 'connected',
            data: <String, dynamic>{},
          ),
        );
        activeSubscription = realtimeStream.listen(
          (event) {
            controller.add(
              OrderTrackingLiveEvent(
                event: event.event,
                data: event.data,
                eventId: event.eventId,
              ),
            );
          },
          onError: (_) => unawaited(attachFallback()),
          onDone: () => unawaited(attachFallback()),
          cancelOnError: false,
        );
      } catch (_) {
        await attachFallback();
      }
    }

    controller = StreamController<OrderTrackingLiveEvent>(
      onListen: () {
        unawaited(bootstrap());
      },
      onCancel: () async {
        await activeSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  bool _matchesOrderTrackingEvent(
    String eventName,
    Map<String, dynamic> data,
    int orderId,
  ) {
    if (eventName == 'resync_required') {
      return true;
    }
    final rawOrderId =
        data['orderId'] ??
        data['order_id'] ??
        (data['payload'] is Map ? (data['payload'] as Map)['orderId'] : null) ??
        (data['payload'] is Map
            ? (data['payload'] as Map)['order_id']
            : null) ??
        (data['order'] is Map ? (data['order'] as Map)['id'] : null) ??
        (data['notification'] is Map
            ? (data['notification'] as Map)['order_id']
            : null) ??
        (data['notification'] is Map
            ? (data['notification'] as Map)['orderId']
            : null);
    return int.tryParse('$rawOrderId') == orderId;
  }

  /// يحاول المسار الحديث لتأكيد الاستلام، ثم يعود إلى المسار القديم
  /// للتوافق مع خوادم أقدم إذا أعادت 404.
  Future<void> confirmDelivered(int orderId) async {
    try {
      await dio.post('/api/orders/$orderId/customer/confirm-received');
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      await dio.post('/api/orders/$orderId/confirm-delivered');
    }
  }

  /// نسخة endpoint الحديثة التي تعيد payload تفصيلياً بعد تأكيد الاستلام.
  Future<Map<String, dynamic>> confirmReceivedV2(
    int orderId, {
    String? note,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/customer/confirm-received',
      data: {'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> rateDelivery({
    required int orderId,
    required int rating,
    String? review,
  }) async {
    await dio.post(
      '/api/orders/$orderId/rate-delivery',
      data: {'rating': rating, 'review': review},
    );
  }

  Future<void> rateMerchant({
    required int orderId,
    required int rating,
    String? review,
  }) async {
    await dio.post(
      '/api/orders/$orderId/rate-merchant',
      data: {'rating': rating, 'review': review},
    );
  }

  Future<List<OrderRevisionModel>> listOrderRevisions(int orderId) async {
    final response = await dio.get('/api/orders/$orderId/revisions');
    final data = Map<String, dynamic>.from(response.data as Map? ?? const {});
    final items = List<dynamic>.from(data['items'] as List? ?? const []);
    return items
        .whereType<Map>()
        .map(
          (entry) =>
              OrderRevisionModel.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false);
  }

  Future<OrderRevisionBundle> approveOrderRevision({
    required int orderId,
    required int revisionId,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/revisions/$revisionId/customer-approve',
      data: {'note': note},
    );
    return OrderRevisionBundle.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<OrderRevisionBundle> rejectOrderRevision({
    required int orderId,
    required int revisionId,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/revisions/$revisionId/reject',
      data: {'note': note},
    );
    return OrderRevisionBundle.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> reorder({required int orderId, String? note}) async {
    await dio.post('/api/orders/$orderId/reorder', data: {'note': note});
  }

  Future<Map<String, dynamic>> getOrderGroupDetails(int groupId) async {
    final response = await dio.get('/api/orders/groups/$groupId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> cancelOrderByCustomer({
    required int orderId,
    required String reasonCode,
    String? reasonText,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/cancel',
      data: {
        'reasonCode': reasonCode,
        if (reasonText != null && reasonText.trim().isNotEmpty)
          'reasonText': reasonText.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> requestReturnByCustomer({
    required int orderId,
    required String reasonCode,
    String? reasonText,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/request-return',
      data: {
        'reasonCode': reasonCode,
        if (reasonText != null && reasonText.trim().isNotEmpty)
          'reasonText': reasonText.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<OrderActionReasonOption>> listOrderActionReasons({
    required String actorScope,
    required String actionKind,
  }) async {
    final response = await dio.get(
      '/api/orders/action-reasons',
      queryParameters: {'actorScope': actorScope, 'actionKind': actionKind},
    );
    final map = Map<String, dynamic>.from(response.data as Map? ?? const {});
    final items = List<dynamic>.from(map['items'] as List? ?? const []);
    return items
        .map(
          (entry) => OrderActionReasonOption.fromMap(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .where((entry) => entry.reasonCode.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<int>> listFavoriteProductIds() async {
    final response = await dio.get('/api/orders/favorites/ids');
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = List<dynamic>.from(map['productIds'] as List? ?? const []);
    return raw.map((e) => int.tryParse('$e') ?? 0).where((e) => e > 0).toList();
  }

  Future<void> addFavoriteProduct(int productId) async {
    await dio.post('/api/orders/favorites/$productId');
  }

  Future<void> removeFavoriteProduct(int productId) async {
    await dio.delete('/api/orders/favorites/$productId');
  }

  Future<FavoriteProductsPage> listFavoriteProducts({
    int? merchantId,
    int limit = 40,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/orders/favorites',
      queryParameters: {
        if (merchantId != null && merchantId > 0) 'merchantId': merchantId,
        'limit': limit,
        'offset': offset,
      },
    );
    final data = response.data;
    if (data is List) {
      return FavoriteProductsPage(
        items: List<dynamic>.from(data),
        nextOffset: null,
      );
    }
    final map = Map<String, dynamic>.from((data as Map?) ?? const {});
    return FavoriteProductsPage(
      items: List<dynamic>.from(map['items'] as List? ?? const []),
      nextOffset: int.tryParse('${map['nextOffset'] ?? ''}'),
    );
  }

  Future<List<dynamic>> listDeliveryAddresses() async {
    final response = await dio.get('/api/auth/account/addresses');
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createDeliveryAddress(
    Map<String, dynamic> body,
  ) async {
    final response = await dio.post('/api/auth/account/addresses', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateDeliveryAddress(
    int addressId,
    Map<String, dynamic> body,
  ) async {
    final response = await dio.put(
      '/api/auth/account/addresses/$addressId',
      data: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> setDefaultDeliveryAddress(int addressId) async {
    final response = await dio.patch(
      '/api/auth/account/addresses/$addressId/default',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteDeliveryAddress(int addressId) async {
    await dio.delete('/api/auth/account/addresses/$addressId');
  }

  // ─── Coupons ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> validateCoupon({
    required String code,
    int? merchantId,
    required double orderSubtotal,
  }) async {
    final payload = <String, dynamic>{
      'code': code,
      'orderSubtotal': orderSubtotal,
    };
    if (merchantId != null) {
      payload['merchantId'] = merchantId;
    }

    final r = await dio.post('/api/coupons/validate', data: payload);
    return Map<String, dynamic>.from(r.data as Map);
  }

  // ─── Product reviews ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> listProductReviews(
    int productId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final r = await dio.get(
      '/api/orders/products/$productId/reviews',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<ProductReview> submitProductReview(
    int productId, {
    required int rating,
    String? body,
    int? orderId,
  }) async {
    final payload = <String, dynamic>{'rating': rating};
    if (body != null && body.isNotEmpty) {
      payload['body'] = body;
    }
    if (orderId != null) {
      payload['orderId'] = orderId;
    }

    final r = await dio.post(
      '/api/orders/products/$productId/reviews',
      data: payload,
    );
    final map = Map<String, dynamic>.from(r.data as Map);
    final rawReview = map['review'];
    if (rawReview is! Map) {
      throw StateError('INVALID_REVIEW_RESPONSE');
    }
    return ProductReview.fromJson(Map<String, dynamic>.from(rawReview));
  }

  Future<void> deleteProductReview(int productId) async {
    await dio.delete('/api/orders/products/$productId/reviews');
  }

  Future<Map<String, dynamic>> searchProductsGlobal({
    required String query,
    String sort = 'best_offers',
    String? merchantType,
    bool onlyAvailable = false,
    bool onlyDiscounted = false,
    double? minPrice,
    double? maxPrice,
    double? minRating,
    String? city,
    String? block,
    int limit = 40,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'q': query,
      'sort': sort,
      if (merchantType != null && merchantType.isNotEmpty)
        'merchantType': merchantType,
      if (onlyAvailable) 'onlyAvailable': true,
      if (onlyDiscounted) 'onlyDiscounted': true,
      // ignore: use_null_aware_elements
      if (minPrice case final value?) 'minPrice': value,
      // ignore: use_null_aware_elements
      if (maxPrice case final value?) 'maxPrice': value,
      // ignore: use_null_aware_elements
      if (minRating case final value?) 'minRating': value,
      if (city != null && city.isNotEmpty) 'city': city,
      if (block != null && block.isNotEmpty) 'block': block,
      'limit': limit,
      'offset': offset,
    };
    try {
      final response = await dio.get(
        '/api/search/products',
        queryParameters: params,
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      final fallback = await dio.get(
        '/api/commerce/search/products',
        queryParameters: params,
      );
      return Map<String, dynamic>.from(fallback.data as Map);
    }
  }

  Map<String, dynamic> _parseSsePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {'value': decoded};
    } catch (_) {
      return {'raw': raw};
    }
  }
}

class FavoriteProductsPage {
  final List<dynamic> items;
  final int? nextOffset;

  const FavoriteProductsPage({required this.items, required this.nextOffset});
}

/// يبني body مناسباً للطلب العادي أو multipart إذا كانت هناك صورة مرفقة.
Future<Object> _withOptionalOrderImage(
  Map<String, dynamic> body,
  LocalImageFile? imageFile,
) async {
  if (imageFile == null) return body;

  final map = <String, dynamic>{...body};
  if (body.containsKey('items')) {
    map['items'] = jsonEncode(body['items']);
  }
  if (body.containsKey('storeOrders')) {
    map['storeOrders'] = jsonEncode(body['storeOrders']);
  }
  map['imageFile'] = await imageFile.toMultipartFile();
  return FormData.fromMap(map);
}
