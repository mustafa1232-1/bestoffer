import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

import '../models/pharmacy_models.dart';

class PharmacyApi {
  final Dio dio;

  PharmacyApi(this.dio);

  Future<PharmacyConversationModel> createConversation({
    required int merchantId,
    String? initialMessage,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await dio.post(
      '/api/pharmacy/conversations',
      data: {
        'merchantId': merchantId,
        if (initialMessage != null && initialMessage.trim().isNotEmpty)
          'initialMessage': initialMessage.trim(),
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return PharmacyConversationModel.fromJson(
      Map<String, dynamic>.from(data['conversation'] as Map? ?? const {}),
    );
  }

  Future<List<PharmacyConversationModel>> listConversations({
    String? status,
    String? bucket,
    String? q,
    int limit = 50,
  }) async {
    final response = await dio.get(
      '/api/pharmacy/conversations',
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (bucket != null && bucket.trim().isNotEmpty) 'bucket': bucket.trim(),
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'limit': limit,
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final items = List<dynamic>.from(data['items'] ?? const <dynamic>[]);
    return items
        .whereType<Map>()
        .map(
          (item) => PharmacyConversationModel.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<PharmacyConversationDetailsModel> getConversationDetails({
    required int conversationId,
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/pharmacy/conversations/$conversationId',
      queryParameters: {'limit': limit},
    );
    return PharmacyConversationDetailsModel.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<PharmacyMessageModel> sendMessage({
    required int conversationId,
    required String message,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await dio.post(
      '/api/pharmacy/conversations/$conversationId/messages',
      data: {
        'message': message,
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return PharmacyMessageModel.fromJson(
      Map<String, dynamic>.from(data['item'] as Map? ?? const {}),
    );
  }

  Future<PharmacyMessageModel> uploadAttachment({
    required int conversationId,
    required PlatformFile file,
    Map<String, dynamic>? metadata,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        file.bytes ?? const <int>[],
        filename: file.name,
      ),
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
    });
    final response = await dio.post(
      '/api/pharmacy/conversations/$conversationId/attachments',
      data: form,
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return PharmacyMessageModel.fromJson(
      Map<String, dynamic>.from(data['message'] as Map? ?? const {}),
    );
  }

  Future<PharmacyProposedCartModel> createProposedCart({
    required int conversationId,
    required List<Map<String, dynamic>> items,
    required double deliveryFee,
    String? notes,
    DateTime? expiresAt,
  }) async {
    final response = await dio.post(
      '/api/pharmacy/conversations/$conversationId/proposed-carts',
      data: {
        'items': items,
        'deliveryFee': deliveryFee,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return PharmacyProposedCartModel.fromJson(
      Map<String, dynamic>.from(data['cart'] as Map? ?? const {}),
    );
  }

  Future<PharmacyProposedCartModel> acceptCart(int cartId) async {
    final response = await dio.post('/api/pharmacy/proposed-carts/$cartId/accept');
    final data = Map<String, dynamic>.from(response.data as Map);
    return PharmacyProposedCartModel.fromJson(
      Map<String, dynamic>.from(data['cart'] as Map? ?? const {}),
    );
  }

  Future<PharmacyProposedCartModel> rejectCart(int cartId) async {
    final response = await dio.post('/api/pharmacy/proposed-carts/$cartId/reject');
    final data = Map<String, dynamic>.from(response.data as Map);
    return PharmacyProposedCartModel.fromJson(
      Map<String, dynamic>.from(data['cart'] as Map? ?? const {}),
    );
  }

  Future<PharmacyProposedCartModel> requestCartRevision({
    required int cartId,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/pharmacy/proposed-carts/$cartId/request-revision',
      data: {
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return PharmacyProposedCartModel.fromJson(
      Map<String, dynamic>.from(data['cart'] as Map? ?? const {}),
    );
  }

  Future<int> convertCartToOrder({
    required int cartId,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/pharmacy/proposed-carts/$cartId/convert-to-order',
      data: {
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return (data['orderId'] as num?)?.toInt() ?? 0;
  }

  Future<String> requestAttachmentAccessUrl(int attachmentId) async {
    final response = await dio.get(
      '/api/pharmacy/attachments/$attachmentId/access-url',
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['url']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> attachmentContent(int attachmentId) async {
    try {
      final response = await dio.get('/api/pharmacy/attachments/$attachmentId/content');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      final accessUrl = await requestAttachmentAccessUrl(attachmentId);
      return {'url': accessUrl};
    }
  }
}
