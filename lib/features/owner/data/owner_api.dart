import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/files/local_image_file.dart';

class OwnerApi {
  final Dio dio;

  OwnerApi(this.dio);

  Future<Map<String, dynamic>> getMerchant() async {
    final response = await dio.get('/api/owner/merchant');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> acceptFinancialTerms() async {
    final response = await dio.post(
      '/api/owner/merchant/financial-terms/accept',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> rejectFinancialTerms({String? note}) async {
    final response = await dio.post(
      '/api/owner/merchant/financial-terms/reject',
      data: note == null || note.trim().isEmpty
          ? const {}
          : {'note': note.trim()},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateMerchant(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final requestData = await _withOptionalImage(body, imageFile: imageFile);
    final response = await dio.put('/api/owner/merchant', data: requestData);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> listCategories() async {
    final response = await dio.get('/api/owner/categories');
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createCategory(Map<String, dynamic> body) async {
    final response = await dio.post('/api/owner/categories', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateCategory(
    int categoryId,
    Map<String, dynamic> body,
  ) async {
    final response = await dio.put(
      '/api/owner/categories/$categoryId',
      data: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteCategory(int categoryId) async {
    await dio.delete('/api/owner/categories/$categoryId');
  }

  Future<List<dynamic>> listProducts() async {
    final response = await dio.get('/api/owner/products');
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
    List<LocalImageFile> galleryFiles = const [],
    List<LocalImageFile> variantFiles = const [],
  }) async {
    final requestData = await _withProductImages(
      body,
      imageFile: imageFile,
      galleryFiles: galleryFiles,
      variantFiles: variantFiles,
    );
    final response = await dio.post('/api/owner/products', data: requestData);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> listOffers() async {
    final response = await dio.get('/api/owner/offers');
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createOffer(Map<String, dynamic> body) async {
    final response = await dio.post('/api/owner/offers', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateOffer(
    int offerId,
    Map<String, dynamic> body,
  ) async {
    final response = await dio.patch('/api/owner/offers/$offerId', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteOffer(int offerId) async {
    await dio.delete('/api/owner/offers/$offerId');
  }

  Future<Map<String, dynamic>> updateProduct(
    int productId,
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
    List<LocalImageFile> galleryFiles = const [],
    List<LocalImageFile> variantFiles = const [],
  }) async {
    final requestData = await _withProductImages(
      body,
      imageFile: imageFile,
      galleryFiles: galleryFiles,
      variantFiles: variantFiles,
    );
    final response = await dio.put(
      '/api/owner/products/$productId',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteProduct(int productId) async {
    await dio.delete('/api/owner/products/$productId');
  }

  Future<List<dynamic>> listDeliveryAgents() async {
    final response = await dio.get('/api/owner/delivery-agents');
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> listAccountants() async {
    final response = await dio.get('/api/owner/accountants');
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> listHrStaff() async {
    final response = await dio.get('/api/owner/hr-staff');
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> searchStaffUsers({
    String search = '',
    int limit = 100,
  }) async {
    final response = await dio.get(
      '/api/owner/staff/users/search',
      queryParameters: {'search': search, 'limit': limit},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createDeliveryAgent(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final requestData = await _withOptionalImage(body, imageFile: imageFile);
    final response = await dio.post(
      '/api/owner/delivery-agents',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> assignExistingDeliveryAgent({
    required int userId,
  }) async {
    final response = await dio.post(
      '/api/owner/staff/delivery/assign-existing',
      data: {'userId': userId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createAccountant(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final requestData = await _withOptionalImage(body, imageFile: imageFile);
    final response = await dio.post(
      '/api/owner/accountants',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> assignExistingAccountant({
    required int userId,
  }) async {
    final response = await dio.post(
      '/api/owner/staff/accountants/assign-existing',
      data: {'userId': userId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createHrStaff(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final requestData = await _withOptionalImage(body, imageFile: imageFile);
    final response = await dio.post('/api/owner/hr-staff', data: requestData);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> assignExistingHrStaff({
    required int userId,
  }) async {
    final response = await dio.post(
      '/api/owner/staff/hr/assign-existing',
      data: {'userId': userId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> listCurrentOrders() async {
    final response = await dio.get('/api/owner/orders/current');
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> listOrderHistory({String? date}) async {
    final response = await dio.get(
      '/api/owner/orders/history',
      queryParameters: date == null ? null : {'date': date},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<void> updateOrderStatus({
    required int orderId,
    required String status,
    int? estimatedPrepMinutes,
    int? estimatedDeliveryMinutes,
  }) async {
    await dio.patch(
      '/api/owner/orders/$orderId/status',
      data: {
        'status': status,
        'estimatedPrepMinutes': estimatedPrepMinutes,
        'estimatedDeliveryMinutes': estimatedDeliveryMinutes,
      },
    );
  }

  Future<void> assignDelivery({
    required int orderId,
    int? deliveryUserId,
    String assignmentMode = 'platform_delivery',
  }) async {
    await dio.patch(
      '/api/owner/orders/$orderId/assign-delivery',
      data: {
        'deliveryUserId': deliveryUserId,
        'assignmentMode': assignmentMode,
      },
    );
  }

  Future<Map<String, dynamic>> markOrderItemUnavailable({
    required int orderId,
    required int productId,
  }) async {
    final response = await dio.patch(
      '/api/owner/orders/$orderId/items/$productId/unavailable',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> analytics() async {
    final response = await dio.get('/api/owner/analytics');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> ordersPrintReport({required String period}) async {
    final response = await dio.get(
      '/api/owner/orders/print-report',
      queryParameters: {'period': period},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> settlementSummary() async {
    final response = await dio.get('/api/owner/settlements/summary');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> requestSettlement({String? note}) async {
    final response = await dio.post(
      '/api/owner/settlements/request',
      data: {'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> startPreparingV2({
    required int orderId,
    int? preferredCourierUserId,
    int? estimatedPrepMinutes,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/store/start-preparing',
      data: {
        'preferredCourierUserId': preferredCourierUserId,
        'estimatedPrepMinutes': estimatedPrepMinutes,
        'note': note,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> assignCourierV2({
    required int orderId,
    required int courierUserId,
    String assignmentMode = 'manual',
    String? note,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/store/assign-courier',
      data: {
        'courierUserId': courierUserId,
        'assignmentMode': assignmentMode,
        'note': note,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> readyForPickupV2({
    required int orderId,
    int? estimatedDeliveryMinutes,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/store/ready-for-pickup',
      data: {
        'estimatedDeliveryMinutes': estimatedDeliveryMinutes,
        'note': note,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> merchantDashboardV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    final query = <String, dynamic>{'period': period};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final response = await dio.get(
      '/api/merchant/dashboard',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> merchantKpisV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    final query = <String, dynamic>{'period': period};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final response = await dio.get(
      '/api/merchant/kpis',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> merchantTopProductsV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    final query = <String, dynamic>{'period': period};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final response = await dio.get(
      '/api/merchant/top-products',
      queryParameters: query,
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    return List<dynamic>.from(map['rows'] as List? ?? const []);
  }

  Future<List<dynamic>> merchantTopCategoriesV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    final query = <String, dynamic>{'period': period};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final response = await dio.get(
      '/api/merchant/top-categories',
      queryParameters: query,
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    return List<dynamic>.from(map['rows'] as List? ?? const []);
  }

  Future<Map<String, dynamic>> merchantOrdersReportsV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    final query = <String, dynamic>{'period': period};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final response = await dio.get(
      '/api/merchant/orders/reports',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> merchantCustomerReliability({
    required int customerUserId,
  }) async {
    final response = await dio.get(
      '/api/merchant/customers/$customerUserId/reliability',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> merchantVerifiedReviews({
    int limit = 40,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/merchant/reviews/verified',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> merchantCouriersV2() async {
    final response = await dio.get('/api/merchant/couriers');
    final map = Map<String, dynamic>.from(response.data as Map);
    return List<dynamic>.from(map['couriers'] as List? ?? const []);
  }

  Future<Map<String, dynamic>> createMerchantCourierV2({
    required int deliveryUserId,
    String? vehicleType,
    String? coverageBlock,
  }) async {
    final response = await dio.post(
      '/api/merchant/couriers',
      data: {
        'deliveryUserId': deliveryUserId,
        'vehicleType': vehicleType,
        'coverageBlock': coverageBlock,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> patchMerchantCourierV2({
    required int courierUserId,
    bool? isActive,
    String? availabilityStatus,
    String? vehicleType,
  }) async {
    final response = await dio.patch(
      '/api/merchant/couriers/$courierUserId',
      data: {
        'isActive': isActive,
        'availabilityStatus': availabilityStatus,
        'vehicleType': vehicleType,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> merchantReceivablesV2() async {
    final response = await dio.get('/api/merchant/receivables');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> merchantReceivablesLedgerV2({
    int limit = 100,
    int offset = 0,
    String ledgerType = 'all',
  }) async {
    final response = await dio.get(
      '/api/merchant/receivables/ledger',
      queryParameters: {
        'limit': limit,
        'offset': offset,
        'ledgerType': ledgerType,
      },
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    return List<dynamic>.from(map['rows'] as List? ?? const []);
  }

  Future<Map<String, dynamic>> merchantReceivableInvoicesV2({
    int limit = 500,
    int offset = 0,
    String period = 'all',
    String? from,
    String? to,
    bool? onlyOpen,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      'offset': offset,
      'period': period,
    };
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    if (onlyOpen != null) query['onlyOpen'] = onlyOpen;
    final response = await dio.get(
      '/api/merchant/receivable-invoices',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> previewPaymentSelectionV2({
    required String selectionMode,
    List<int> selectedInvoiceIds = const [],
    double? amount,
    double? targetAmount,
    double? confirmedAdjustedAmount,
  }) async {
    final response = await dio.post(
      '/api/merchant/payment-requests/preview-selection',
      data: {
        'selectionMode': selectionMode,
        'selectedInvoiceIds': selectedInvoiceIds,
        'amount': amount,
        'targetAmount': targetAmount,
        'confirmedAdjustedAmount': confirmedAdjustedAmount,
      }..removeWhere((_, value) => value == null),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createPaymentRequestV2({
    String requestType = 'store_pays_app',
    required String paymentScope,
    double? amount,
    String? proofFileUrl,
    String? note,
    String? paymentMethod,
    String? paymentMethodOther,
    String? paymentAt,
    String? referenceCode,
    String? receiverName,
    String? selectionMode,
    List<int> selectedInvoiceIds = const [],
    double? targetAmount,
    double? confirmedAdjustedAmount,
    Map<String, dynamic>? selectionMeta,
  }) async {
    final response = await dio.post(
      '/api/merchant/payment-requests',
      data: {
        'requestType': requestType,
        'paymentScope': paymentScope,
        'amount': amount,
        'proofFileUrl': proofFileUrl,
        'note': note,
        'paymentMethod': paymentMethod,
        'paymentMethodOther': paymentMethodOther,
        'paymentAt': paymentAt,
        'referenceCode': referenceCode,
        'receiverName': receiverName,
        'selectionMode': selectionMode,
        'selectedInvoiceIds': selectedInvoiceIds,
        'targetAmount': targetAmount,
        'confirmedAdjustedAmount': confirmedAdjustedAmount,
        'selectionMeta': selectionMeta,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listPaymentRequestsV2({
    String? requestType,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/merchant/payment-requests',
      queryParameters: {
        if (requestType != null && requestType.trim().isNotEmpty)
          'requestType': requestType.trim(),
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> paymentRequestDetailsV2(
    int paymentRequestId,
  ) async {
    final response = await dio.get(
      '/api/merchant/payment-requests/$paymentRequestId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> paymentRequestInvoicesV2(
    int paymentRequestId,
  ) async {
    final response = await dio.get(
      '/api/merchant/payment-requests/$paymentRequestId/invoices',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> patchPaymentRequestV2({
    required int paymentRequestId,
    String? paymentScope,
    double? amount,
    String? note,
    String? proofFileUrl,
    String? paymentMethod,
    String? paymentMethodOther,
    String? paymentAt,
    String? referenceCode,
    String? receiverName,
    String? selectionMode,
    List<int> selectedInvoiceIds = const [],
    double? targetAmount,
    double? confirmedAdjustedAmount,
    Map<String, dynamic>? selectionMeta,
    bool? resubmit,
  }) async {
    final response = await dio.patch(
      '/api/merchant/payment-requests/$paymentRequestId',
      data: {
        'paymentScope': paymentScope,
        'amount': amount,
        'note': note,
        'proofFileUrl': proofFileUrl,
        'paymentMethod': paymentMethod,
        'paymentMethodOther': paymentMethodOther,
        'paymentAt': paymentAt,
        'referenceCode': referenceCode,
        'receiverName': receiverName,
        'selectionMode': selectionMode,
        'selectedInvoiceIds': selectedInvoiceIds,
        'targetAmount': targetAmount,
        'confirmedAdjustedAmount': confirmedAdjustedAmount,
        'selectionMeta': selectionMeta,
        'resubmit': resubmit,
      }..removeWhere((_, value) => value == null),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> confirmPaymentRequestReceivedV2({
    required int paymentRequestId,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/merchant/payment-requests/$paymentRequestId/confirm-received',
      data: {'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> reportPaymentRequestIssueV2({
    required int paymentRequestId,
    required String issueNote,
  }) async {
    final response = await dio.post(
      '/api/merchant/payment-requests/$paymentRequestId/report-issue',
      data: {'issueNote': issueNote},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> reviewCourierCancelRequestV2({
    required int orderId,
    required String decision,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/store/review-cancel-request',
      data: {
        'decision': decision,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}

Future<Object> _withOptionalImage(
  Map<String, dynamic> body, {
  required LocalImageFile? imageFile,
}) async {
  if (imageFile == null) return body;
  final map = <String, dynamic>{
    ...body,
    'imageFile': await imageFile.toMultipartFile(),
  };
  return FormData.fromMap(map);
}

Future<Object> _withProductImages(
  Map<String, dynamic> body, {
  required LocalImageFile? imageFile,
  required List<LocalImageFile> galleryFiles,
  required List<LocalImageFile> variantFiles,
}) async {
  if (imageFile == null && galleryFiles.isEmpty && variantFiles.isEmpty) {
    return body;
  }
  final map = <String, dynamic>{...body};
  for (final key in const [
    'attributes',
    'variantGroups',
    'variants',
    'media',
    'metadataJson',
    'richCatalog',
  ]) {
    final value = map[key];
    if (value is List || value is Map) map[key] = jsonEncode(value);
  }
  if (imageFile != null) map['imageFile'] = await imageFile.toMultipartFile();
  if (galleryFiles.isNotEmpty) {
    map['galleryFiles'] = await Future.wait(
      galleryFiles.map((file) => file.toMultipartFile()),
    );
  }
  if (variantFiles.isNotEmpty) {
    map['variantFiles'] = await Future.wait(
      variantFiles.map((file) => file.toMultipartFile()),
    );
  }
  return FormData.fromMap(map);
}
