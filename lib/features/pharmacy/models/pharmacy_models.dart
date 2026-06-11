import '../../../core/utils/parsers.dart';

class PharmacyConversationCustomerModel {
  final int userId;
  final String? fullName;
  final String? phone;

  const PharmacyConversationCustomerModel({
    required this.userId,
    required this.fullName,
    required this.phone,
  });

  factory PharmacyConversationCustomerModel.fromJson(Map<String, dynamic> json) {
    return PharmacyConversationCustomerModel(
      userId: parseInt(json['userId'] ?? json['user_id']),
      fullName: parseNullableString(json['fullName'] ?? json['full_name']),
      phone: parseNullableString(json['phone']),
    );
  }
}

class PharmacyConversationModel {
  final int id;
  final int merchantId;
  final int customerUserId;
  final String? merchantName;
  final String? merchantImageUrl;
  final String status;
  final String bucket;
  final String? activityType;
  final String? conversationType;
  final String? closedReason;
  final Map<String, dynamic> metadata;
  final int? linkedOrderId;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool supportsChat;
  final bool supportsAttachments;
  final bool supportsPharmacyWorkflow;
  final int messagesCount;
  final PharmacyConversationCustomerModel? customer;

  const PharmacyConversationModel({
    required this.id,
    required this.merchantId,
    required this.customerUserId,
    required this.merchantName,
    required this.merchantImageUrl,
    required this.status,
    required this.bucket,
    required this.activityType,
    required this.conversationType,
    required this.closedReason,
    required this.metadata,
    required this.linkedOrderId,
    required this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
    required this.supportsChat,
    required this.supportsAttachments,
    required this.supportsPharmacyWorkflow,
    required this.messagesCount,
    required this.customer,
  });

  factory PharmacyConversationModel.fromJson(Map<String, dynamic> json) {
    final customerRaw = json['customer'];
    final metadataRaw = json['metadata'];
    return PharmacyConversationModel(
      id: parseInt(json['id']),
      merchantId: parseInt(json['merchantId'] ?? json['merchant_id']),
      customerUserId: parseInt(
        json['customerUserId'] ?? json['customer_user_id'],
      ),
      merchantName: parseNullableString(
        json['merchantName'] ?? json['merchant_name'],
      ),
      merchantImageUrl: parseNullableString(
        json['merchantImageUrl'] ?? json['merchant_image_url'],
      ),
      status: parseString(json['status'], fallback: 'open'),
      bucket: parseString(json['bucket'], fallback: 'active'),
      activityType: parseNullableString(
        json['activityType'] ?? json['activity_type'],
      ),
      conversationType: parseNullableString(
        json['conversationType'] ?? json['conversation_type'],
      ),
      closedReason: parseNullableString(
        json['closedReason'] ?? json['closed_reason'],
      ),
      metadata: metadataRaw is Map
          ? Map<String, dynamic>.from(metadataRaw)
          : const <String, dynamic>{},
      linkedOrderId:
          json['linkedOrderId'] == null && json['linked_order_id'] == null
          ? null
          : parseInt(json['linkedOrderId'] ?? json['linked_order_id']),
      lastMessageAt: parseNullableDateTime(
        json['lastMessageAt'] ?? json['last_message_at'],
      ),
      createdAt: parseNullableDateTime(json['createdAt'] ?? json['created_at']),
      updatedAt: parseNullableDateTime(json['updatedAt'] ?? json['updated_at']),
      supportsChat: parseBool(json['supportsChat'] ?? json['supports_chat']),
      supportsAttachments: parseBool(
        json['supportsAttachments'] ?? json['supports_attachments'],
      ),
      supportsPharmacyWorkflow: parseBool(
        json['supportsPharmacyWorkflow'] ?? json['supports_pharmacy_workflow'],
      ),
      messagesCount: parseInt(json['messagesCount'] ?? json['messages_count']),
      customer: customerRaw is Map
          ? PharmacyConversationCustomerModel.fromJson(
              Map<String, dynamic>.from(customerRaw),
            )
          : null,
    );
  }
}

class PharmacyMessageModel {
  final int id;
  final int conversationId;
  final String senderType;
  final int? senderUserId;
  final String? senderFullName;
  final String messageType;
  final String? text;
  final int? attachmentId;
  final String? attachmentUrl;
  final String? attachmentMimeType;
  final String? attachmentName;
  final int? proposedCartId;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  const PharmacyMessageModel({
    required this.id,
    required this.conversationId,
    required this.senderType,
    required this.senderUserId,
    required this.senderFullName,
    required this.messageType,
    required this.text,
    required this.attachmentId,
    required this.attachmentUrl,
    required this.attachmentMimeType,
    required this.attachmentName,
    required this.proposedCartId,
    required this.metadata,
    required this.createdAt,
  });

  factory PharmacyMessageModel.fromJson(Map<String, dynamic> json) {
    final metadataRaw = json['metadata'];
    return PharmacyMessageModel(
      id: parseInt(json['id']),
      conversationId: parseInt(
        json['conversationId'] ?? json['conversation_id'],
      ),
      senderType: parseString(json['senderType'] ?? json['sender_type']),
      senderUserId:
          json['senderUserId'] == null && json['sender_user_id'] == null
          ? null
          : parseInt(json['senderUserId'] ?? json['sender_user_id']),
      senderFullName: parseNullableString(
        json['senderFullName'] ?? json['sender_full_name'],
      ),
      messageType: parseString(json['messageType'] ?? json['message_type']),
      text: parseNullableString(json['text']),
      attachmentId:
          json['attachmentId'] == null && json['attachment_id'] == null
          ? null
          : parseInt(json['attachmentId'] ?? json['attachment_id']),
      attachmentUrl: parseNullableString(
        json['attachmentUrl'] ?? json['attachment_url'],
      ),
      attachmentMimeType: parseNullableString(
        json['attachmentMimeType'] ?? json['attachment_mime_type'],
      ),
      attachmentName: parseNullableString(
        json['attachmentName'] ?? json['attachment_name'],
      ),
      proposedCartId:
          json['proposedCartId'] == null && json['proposed_cart_id'] == null
          ? null
          : parseInt(json['proposedCartId'] ?? json['proposed_cart_id']),
      metadata: metadataRaw is Map
          ? Map<String, dynamic>.from(metadataRaw)
          : const <String, dynamic>{},
      createdAt: parseNullableDateTime(json['createdAt'] ?? json['created_at']),
    );
  }
}

class PharmacyProposedCartItemModel {
  final int id;
  final int proposedCartId;
  final int? productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final bool requiresPrescription;
  final bool requiresReview;
  final String? alternativeGroupId;
  final String? note;
  final Map<String, dynamic> metadata;

  const PharmacyProposedCartItemModel({
    required this.id,
    required this.proposedCartId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.requiresPrescription,
    required this.requiresReview,
    required this.alternativeGroupId,
    required this.note,
    required this.metadata,
  });

  factory PharmacyProposedCartItemModel.fromJson(Map<String, dynamic> json) {
    final metadataRaw = json['metadata'];
    return PharmacyProposedCartItemModel(
      id: parseInt(json['id']),
      proposedCartId: parseInt(
        json['proposedCartId'] ?? json['proposed_cart_id'],
      ),
      productId: json['productId'] == null && json['product_id'] == null
          ? null
          : parseInt(json['productId'] ?? json['product_id']),
      productName: parseString(
        json['productName'] ?? json['product_name'],
        fallback: '',
      ),
      quantity: parseInt(json['quantity']),
      unitPrice: parseDouble(json['unitPrice'] ?? json['unit_price']),
      lineTotal: parseDouble(json['lineTotal'] ?? json['line_total']),
      requiresPrescription: parseBool(
        json['requiresPrescription'] ?? json['requires_prescription'],
      ),
      requiresReview: parseBool(json['requiresReview'] ?? json['requires_review']),
      alternativeGroupId: parseNullableString(
        json['alternativeGroupId'] ?? json['alternative_group_id'],
      ),
      note: parseNullableString(json['note']),
      metadata: metadataRaw is Map
          ? Map<String, dynamic>.from(metadataRaw)
          : const <String, dynamic>{},
    );
  }
}

class PharmacyProposedCartModel {
  final int id;
  final int conversationId;
  final int version;
  final String status;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String? notes;
  final DateTime? expiresAt;
  final DateTime? confirmedAt;
  final DateTime? rejectedAt;
  final DateTime? revisionRequestedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? createdByUserId;
  final List<PharmacyProposedCartItemModel> items;

  const PharmacyProposedCartModel({
    required this.id,
    required this.conversationId,
    required this.version,
    required this.status,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.notes,
    required this.expiresAt,
    required this.confirmedAt,
    required this.rejectedAt,
    required this.revisionRequestedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.createdByUserId,
    required this.items,
  });

  factory PharmacyProposedCartModel.fromJson(Map<String, dynamic> json) {
    final rawItems = List<dynamic>.from(json['items'] ?? const <dynamic>[]);
    return PharmacyProposedCartModel(
      id: parseInt(json['id']),
      conversationId: parseInt(
        json['conversationId'] ?? json['conversation_id'],
      ),
      version: parseInt(json['version']),
      status: parseString(json['status'], fallback: 'proposed'),
      subtotal: parseDouble(json['subtotal']),
      deliveryFee: parseDouble(json['deliveryFee'] ?? json['delivery_fee']),
      total: parseDouble(json['total']),
      notes: parseNullableString(json['notes']),
      expiresAt: parseNullableDateTime(json['expiresAt'] ?? json['expires_at']),
      confirmedAt: parseNullableDateTime(
        json['confirmedAt'] ?? json['confirmed_at'],
      ),
      rejectedAt: parseNullableDateTime(
        json['rejectedAt'] ?? json['rejected_at'],
      ),
      revisionRequestedAt: parseNullableDateTime(
        json['revisionRequestedAt'] ?? json['revision_requested_at'],
      ),
      createdAt: parseNullableDateTime(json['createdAt'] ?? json['created_at']),
      updatedAt: parseNullableDateTime(json['updatedAt'] ?? json['updated_at']),
      createdByUserId:
          json['createdByUserId'] == null && json['created_by_user_id'] == null
          ? null
          : parseInt(json['createdByUserId'] ?? json['created_by_user_id']),
      items: rawItems
          .whereType<Map>()
          .map(
            (item) => PharmacyProposedCartItemModel.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
}

class PharmacyConversationDetailsModel {
  final PharmacyConversationModel conversation;
  final List<PharmacyMessageModel> messages;
  final PharmacyProposedCartModel? latestProposedCart;

  const PharmacyConversationDetailsModel({
    required this.conversation,
    required this.messages,
    required this.latestProposedCart,
  });

  factory PharmacyConversationDetailsModel.fromJson(Map<String, dynamic> json) {
    final rawMessages = List<dynamic>.from(json['messages'] ?? const <dynamic>[]);
    final cartRaw = json['latestProposedCart'] ?? json['latest_proposed_cart'];
    return PharmacyConversationDetailsModel(
      conversation: PharmacyConversationModel.fromJson(
        Map<String, dynamic>.from(json['conversation'] as Map? ?? const {}),
      ),
      messages: rawMessages
          .whereType<Map>()
          .map(
            (item) => PharmacyMessageModel.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      latestProposedCart: cartRaw is Map
          ? PharmacyProposedCartModel.fromJson(Map<String, dynamic>.from(cartRaw))
          : null,
    );
  }
}
