import '../../../core/utils/parsers.dart';

class AssistantMessageModel {
  final int id;
  final String role; // user | assistant | system
  final String text;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;

  const AssistantMessageModel({
    required this.id,
    required this.role,
    required this.text,
    required this.metadata,
    required this.createdAt,
  });

  bool get isUser => role == 'user';

  factory AssistantMessageModel.fromJson(Map<String, dynamic> j) {
    final rawMetadata = j['metadata'];
    return AssistantMessageModel(
      id: parseInt(j['id']),
      role: parseString(j['role'], fallback: 'assistant'),
      text: parseString(j['text']),
      metadata: rawMetadata is Map
          ? Map<String, dynamic>.from(rawMetadata)
          : null,
      createdAt: _parseDate(j['createdAt'] ?? j['created_at']),
    );
  }
}

class AssistantMerchantSuggestionModel {
  final int merchantId;
  final String merchantName;
  final String merchantType;
  final String? merchantImageUrl;
  final double averageScore;
  final double minPrice;
  final double maxPrice;
  final double avgRating;
  final int completedOrders;
  final bool hasFreeDelivery;
  final List<String> topProducts;

  const AssistantMerchantSuggestionModel({
    required this.merchantId,
    required this.merchantName,
    required this.merchantType,
    required this.merchantImageUrl,
    required this.averageScore,
    required this.minPrice,
    required this.maxPrice,
    required this.avgRating,
    required this.completedOrders,
    required this.hasFreeDelivery,
    required this.topProducts,
  });

  factory AssistantMerchantSuggestionModel.fromJson(Map<String, dynamic> j) {
    final rawTopProducts = j['topProducts'];
    return AssistantMerchantSuggestionModel(
      merchantId: parseInt(j['merchantId']),
      merchantName: parseString(j['merchantName']),
      merchantType: parseString(j['merchantType']),
      merchantImageUrl: parseNullableString(j['merchantImageUrl']),
      averageScore: parseDouble(j['averageScore']),
      minPrice: parseDouble(j['minPrice']),
      maxPrice: parseDouble(j['maxPrice']),
      avgRating: parseDouble(j['avgRating']),
      completedOrders: parseInt(j['completedOrders']),
      hasFreeDelivery: j['hasFreeDelivery'] == true,
      topProducts: rawTopProducts is List
          ? rawTopProducts
                .map((e) => parseString(e))
                .where((e) => e.isNotEmpty)
                .toList()
          : const <String>[],
    );
  }
}

class AssistantProductSuggestionModel {
  final int productId;
  final int merchantId;
  final String merchantName;
  final String productName;
  final String? categoryName;
  final double effectivePrice;
  final double basePrice;
  final double? discountedPrice;
  final String? offerLabel;
  final bool freeDelivery;
  final String? productImageUrl;
  final double merchantAvgRating;
  final int merchantCompletedOrders;
  final bool isFavorite;
  final double score;

  const AssistantProductSuggestionModel({
    required this.productId,
    required this.merchantId,
    required this.merchantName,
    required this.productName,
    required this.categoryName,
    required this.effectivePrice,
    required this.basePrice,
    required this.discountedPrice,
    required this.offerLabel,
    required this.freeDelivery,
    required this.productImageUrl,
    required this.merchantAvgRating,
    required this.merchantCompletedOrders,
    required this.isFavorite,
    required this.score,
  });

  factory AssistantProductSuggestionModel.fromJson(Map<String, dynamic> j) {
    return AssistantProductSuggestionModel(
      productId: parseInt(j['productId']),
      merchantId: parseInt(j['merchantId']),
      merchantName: parseString(j['merchantName']),
      productName: parseString(j['productName']),
      categoryName: parseNullableString(j['categoryName']),
      effectivePrice: parseDouble(j['effectivePrice']),
      basePrice: parseDouble(j['basePrice']),
      discountedPrice: j['discountedPrice'] == null
          ? null
          : parseDouble(j['discountedPrice']),
      offerLabel: parseNullableString(j['offerLabel']),
      freeDelivery: j['freeDelivery'] == true,
      productImageUrl: parseNullableString(j['productImageUrl']),
      merchantAvgRating: parseDouble(j['merchantAvgRating']),
      merchantCompletedOrders: parseInt(j['merchantCompletedOrders']),
      isFavorite: j['isFavorite'] == true,
      score: parseDouble(j['score']),
    );
  }
}

class AssistantDraftItemModel {
  final int productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const AssistantDraftItemModel({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory AssistantDraftItemModel.fromJson(Map<String, dynamic> j) {
    return AssistantDraftItemModel(
      productId: parseInt(j['productId']),
      productName: parseString(j['productName']),
      quantity: parseInt(j['quantity'], fallback: 1),
      unitPrice: parseDouble(j['unitPrice']),
      lineTotal: parseDouble(j['lineTotal']),
    );
  }
}

class AssistantDraftOrderModel {
  final String token;
  final int merchantId;
  final String merchantName;
  final String merchantType;
  final int? addressId;
  final String? addressLabel;
  final String? addressCity;
  final String? addressBlock;
  final String? addressBuildingNumber;
  final String? addressApartment;
  final String? note;
  final List<AssistantDraftItemModel> items;
  final double subtotal;
  final double serviceFee;
  final double deliveryFee;
  final double totalAmount;
  final String? rationale;
  final String status;
  final DateTime? expiresAt;

  const AssistantDraftOrderModel({
    required this.token,
    required this.merchantId,
    required this.merchantName,
    required this.merchantType,
    required this.addressId,
    required this.addressLabel,
    required this.addressCity,
    required this.addressBlock,
    required this.addressBuildingNumber,
    required this.addressApartment,
    required this.note,
    required this.items,
    required this.subtotal,
    required this.serviceFee,
    required this.deliveryFee,
    required this.totalAmount,
    required this.rationale,
    required this.status,
    required this.expiresAt,
  });

  factory AssistantDraftOrderModel.fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'];
    return AssistantDraftOrderModel(
      token: parseString(j['token']),
      merchantId: parseInt(j['merchantId']),
      merchantName: parseString(j['merchantName']),
      merchantType: parseString(j['merchantType']),
      addressId: j['addressId'] == null ? null : parseInt(j['addressId']),
      addressLabel: parseNullableString(j['addressLabel']),
      addressCity: parseNullableString(j['addressCity']),
      addressBlock: parseNullableString(j['addressBlock']),
      addressBuildingNumber: parseNullableString(j['addressBuildingNumber']),
      addressApartment: parseNullableString(j['addressApartment']),
      note: parseNullableString(j['note']),
      items: rawItems is List
          ? rawItems
                .map(
                  (e) => AssistantDraftItemModel.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList()
          : const <AssistantDraftItemModel>[],
      subtotal: parseDouble(j['subtotal']),
      serviceFee: parseDouble(j['serviceFee']),
      deliveryFee: parseDouble(j['deliveryFee']),
      totalAmount: parseDouble(j['totalAmount']),
      rationale: parseNullableString(j['rationale']),
      status: parseString(j['status'], fallback: 'pending'),
      expiresAt: _parseDate(j['expiresAt']),
    );
  }
}

class AssistantCreatedOrderModel {
  final int id;
  final String status;
  final int merchantId;
  final String merchantName;
  final double totalAmount;
  final DateTime? createdAt;

  const AssistantCreatedOrderModel({
    required this.id,
    required this.status,
    required this.merchantId,
    required this.merchantName,
    required this.totalAmount,
    required this.createdAt,
  });

  factory AssistantCreatedOrderModel.fromJson(Map<String, dynamic> j) {
    return AssistantCreatedOrderModel(
      id: parseInt(j['id']),
      status: parseString(j['status']),
      merchantId: parseInt(j['merchantId']),
      merchantName: parseString(j['merchantName']),
      totalAmount: parseDouble(j['totalAmount']),
      createdAt: _parseDate(j['createdAt']),
    );
  }
}

class AssistantAddressOptionModel {
  final int id;
  final String label;
  final String city;
  final String block;
  final String buildingNumber;
  final String apartment;
  final bool isDefault;

  const AssistantAddressOptionModel({
    required this.id,
    required this.label,
    required this.city,
    required this.block,
    required this.buildingNumber,
    required this.apartment,
    required this.isDefault,
  });

  String get summary =>
      '$city - بلوك $block - عمارة $buildingNumber - شقة $apartment';

  factory AssistantAddressOptionModel.fromJson(Map<String, dynamic> j) {
    return AssistantAddressOptionModel(
      id: parseInt(j['id']),
      label: parseString(j['label']),
      city: parseString(j['city']),
      block: parseString(j['block']),
      buildingNumber: parseString(j['buildingNumber']),
      apartment: parseString(j['apartment']),
      isDefault: j['isDefault'] == true,
    );
  }
}

class AssistantChatPayloadModel {
  final int sessionId;
  final List<AssistantMessageModel> messages;
  final List<AssistantMerchantSuggestionModel> merchants;
  final List<AssistantProductSuggestionModel> products;
  final AssistantDraftOrderModel? draftOrder;
  final AssistantCreatedOrderModel? createdOrder;
  final List<AssistantAddressOptionModel> addresses;
  final Map<String, dynamic>? profile;
  final AssistantMessageModel? assistantMessage;

  const AssistantChatPayloadModel({
    required this.sessionId,
    required this.messages,
    required this.merchants,
    required this.products,
    required this.draftOrder,
    required this.createdOrder,
    required this.addresses,
    required this.profile,
    required this.assistantMessage,
  });

  factory AssistantChatPayloadModel.fromJson(Map<String, dynamic> j) {
    final rawMessages = j['messages'];
    final rawMerchants = j['suggestions'] is Map
        ? (j['suggestions'] as Map)['merchants']
        : j['merchants'];
    final rawProducts = j['suggestions'] is Map
        ? (j['suggestions'] as Map)['products']
        : j['products'];
    final rawAddresses = j['addresses'];

    return AssistantChatPayloadModel(
      sessionId: parseInt(j['sessionId']),
      messages: rawMessages is List
          ? rawMessages
                .map(
                  (e) => AssistantMessageModel.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList()
          : const <AssistantMessageModel>[],
      merchants: rawMerchants is List
          ? rawMerchants
                .map(
                  (e) => AssistantMerchantSuggestionModel.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList()
          : const <AssistantMerchantSuggestionModel>[],
      products: rawProducts is List
          ? rawProducts
                .map(
                  (e) => AssistantProductSuggestionModel.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList()
          : const <AssistantProductSuggestionModel>[],
      draftOrder: j['draftOrder'] is Map
          ? AssistantDraftOrderModel.fromJson(
              Map<String, dynamic>.from(j['draftOrder'] as Map),
            )
          : null,
      createdOrder: j['createdOrder'] is Map
          ? AssistantCreatedOrderModel.fromJson(
              Map<String, dynamic>.from(j['createdOrder'] as Map),
            )
          : null,
      addresses: rawAddresses is List
          ? rawAddresses
                .map(
                  (e) => AssistantAddressOptionModel.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList()
          : const <AssistantAddressOptionModel>[],
      profile: j['profile'] is Map
          ? Map<String, dynamic>.from(j['profile'] as Map)
          : null,
      assistantMessage: j['assistantMessage'] is Map
          ? AssistantMessageModel.fromJson(
              Map<String, dynamic>.from(j['assistantMessage'] as Map),
            )
          : null,
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
