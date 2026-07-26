import '../../../core/utils/parsers.dart';

class OrderRevisionBundle {
  final OrderRevisionModel revision;
  final List<OrderRevisionItemModel> items;
  final List<OrderRevisionApprovalModel> approvals;
  final List<OrderRevisionEventModel> events;
  final List<OrderRevisionFinancialAdjustmentModel> adjustments;

  const OrderRevisionBundle({
    required this.revision,
    this.items = const [],
    this.approvals = const [],
    this.events = const [],
    this.adjustments = const [],
  });

  factory OrderRevisionBundle.fromJson(Map<String, dynamic> json) {
    return OrderRevisionBundle(
      revision: OrderRevisionModel.fromJson(_map(json['revision'])),
      items: _list(json['items']).map(OrderRevisionItemModel.fromJson).toList(),
      approvals: _list(
        json['approvals'],
      ).map(OrderRevisionApprovalModel.fromJson).toList(),
      events: _list(
        json['events'],
      ).map(OrderRevisionEventModel.fromJson).toList(),
      adjustments: _list(
        json['adjustments'],
      ).map(OrderRevisionFinancialAdjustmentModel.fromJson).toList(),
    );
  }
}

class OrderRevisionModel {
  final int id;
  final int orderId;
  final int supportTicketId;
  final int versionNumber;
  final int baseOrderVersion;
  final String status;
  final String reason;
  final double priceDifference;
  final OrderRevisionTotals originalTotals;
  final OrderRevisionTotals proposedTotals;
  final List<OrderRevisionLineSnapshot> originalItems;
  final List<OrderRevisionLineSnapshot> proposedItems;
  final List<String> approvalsRequired;
  final Map<String, dynamic> paymentEffect;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const OrderRevisionModel({
    required this.id,
    required this.orderId,
    required this.supportTicketId,
    required this.versionNumber,
    required this.baseOrderVersion,
    required this.status,
    required this.reason,
    required this.priceDifference,
    required this.originalTotals,
    required this.proposedTotals,
    required this.originalItems,
    required this.proposedItems,
    required this.approvalsRequired,
    required this.paymentEffect,
    this.createdAt,
    this.expiresAt,
  });

  factory OrderRevisionModel.fromJson(Map<String, dynamic> json) {
    return OrderRevisionModel(
      id: parseInt(json['id']),
      orderId: parseInt(json['order_id'] ?? json['orderId']),
      supportTicketId: parseInt(
        json['support_ticket_id'] ?? json['supportTicketId'],
      ),
      versionNumber: parseInt(json['version_number'] ?? json['versionNumber']),
      baseOrderVersion: parseInt(
        json['base_order_version'] ?? json['baseOrderVersion'],
        fallback: 1,
      ),
      status: parseString(json['status']).toUpperCase(),
      reason: parseString(json['reason']),
      priceDifference: parseDouble(
        json['price_difference'] ?? json['priceDifference'],
      ),
      originalTotals: OrderRevisionTotals.fromJson(
        _map(json['original_totals_json'] ?? json['originalTotals']),
      ),
      proposedTotals: OrderRevisionTotals.fromJson(
        _map(json['proposed_totals_json'] ?? json['proposedTotals']),
      ),
      originalItems: _list(
        json['original_items_json'] ?? json['originalItems'],
      ).map(OrderRevisionLineSnapshot.fromJson).toList(),
      proposedItems: _list(
        json['proposed_items_json'] ?? json['proposedItems'],
      ).map(OrderRevisionLineSnapshot.fromJson).toList(),
      approvalsRequired: _stringList(
        json['approvals_required_json'] ?? json['approvalsRequired'],
      ),
      paymentEffect: _map(json['payment_effect_json'] ?? json['paymentEffect']),
      createdAt: parseNullableDateTime(json['created_at'] ?? json['createdAt']),
      expiresAt: parseNullableDateTime(json['expires_at'] ?? json['expiresAt']),
    );
  }

  bool get isWaitingForCustomer =>
      status == 'AWAITING_CUSTOMER' || status == 'AWAITING_BOTH';
  bool get isWaitingForMerchant =>
      status == 'AWAITING_MERCHANT' || status == 'AWAITING_BOTH';
  bool get canApply => status == 'APPROVED';
  bool get isApplied => status == 'APPLIED';
  bool get isTerminal => const {
    'APPLIED',
    'REJECTED',
    'CANCELLED',
    'EXPIRED',
    'FAILED',
  }.contains(status);
}

class OrderRevisionTotals {
  final double subtotal;
  final double serviceFee;
  final double deliveryFee;
  final double couponDiscountTotal;
  final double totalAmount;

  const OrderRevisionTotals({
    required this.subtotal,
    required this.serviceFee,
    required this.deliveryFee,
    required this.couponDiscountTotal,
    required this.totalAmount,
  });

  factory OrderRevisionTotals.fromJson(Map<String, dynamic> json) {
    return OrderRevisionTotals(
      subtotal: parseDouble(json['subtotal']),
      serviceFee: parseDouble(json['serviceFee'] ?? json['service_fee']),
      deliveryFee: parseDouble(json['deliveryFee'] ?? json['delivery_fee']),
      couponDiscountTotal: parseDouble(
        json['couponDiscountTotal'] ?? json['coupon_discount_total'],
      ),
      totalAmount: parseDouble(json['totalAmount'] ?? json['total_amount']),
    );
  }
}

class OrderRevisionLineSnapshot {
  final int? orderItemId;
  final int productId;
  final int? variantId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const OrderRevisionLineSnapshot({
    this.orderItemId,
    required this.productId,
    this.variantId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory OrderRevisionLineSnapshot.fromJson(Map<String, dynamic> json) {
    return OrderRevisionLineSnapshot(
      orderItemId: parseNullableInt(
        json['orderItemId'] ?? json['order_item_id'],
      ),
      productId: parseInt(json['productId'] ?? json['product_id']),
      variantId: parseNullableInt(json['variantId'] ?? json['variant_id']),
      productName: parseString(json['productName'] ?? json['product_name']),
      quantity: parseInt(json['quantity']),
      unitPrice: parseDouble(json['unitPrice'] ?? json['unit_price']),
      lineTotal: parseDouble(json['lineTotal'] ?? json['line_total']),
    );
  }
}

class OrderRevisionItemModel {
  final int id;
  final String action;
  final int productId;
  final int quantityBefore;
  final int quantityAfter;
  final double lineTotalBefore;
  final double lineTotalAfter;

  const OrderRevisionItemModel({
    required this.id,
    required this.action,
    required this.productId,
    required this.quantityBefore,
    required this.quantityAfter,
    required this.lineTotalBefore,
    required this.lineTotalAfter,
  });

  factory OrderRevisionItemModel.fromJson(Map<String, dynamic> json) {
    return OrderRevisionItemModel(
      id: parseInt(json['id']),
      action: parseString(json['action']),
      productId: parseInt(json['product_id'] ?? json['productId']),
      quantityBefore: parseInt(
        json['quantity_before'] ?? json['quantityBefore'],
      ),
      quantityAfter: parseInt(json['quantity_after'] ?? json['quantityAfter']),
      lineTotalBefore: parseDouble(
        json['line_total_before'] ?? json['lineTotalBefore'],
      ),
      lineTotalAfter: parseDouble(
        json['line_total_after'] ?? json['lineTotalAfter'],
      ),
    );
  }
}

class OrderRevisionApprovalModel {
  final String type;
  final String status;
  final DateTime? decidedAt;

  const OrderRevisionApprovalModel({
    required this.type,
    required this.status,
    this.decidedAt,
  });

  factory OrderRevisionApprovalModel.fromJson(Map<String, dynamic> json) {
    return OrderRevisionApprovalModel(
      type: parseString(
        json['approval_type'] ?? json['approvalType'],
      ).toUpperCase(),
      status: parseString(json['status']).toUpperCase(),
      decidedAt: parseNullableDateTime(json['decided_at'] ?? json['decidedAt']),
    );
  }
}

class OrderRevisionEventModel {
  final String eventType;
  final String? fromStatus;
  final String? toStatus;
  final DateTime? createdAt;

  const OrderRevisionEventModel({
    required this.eventType,
    this.fromStatus,
    this.toStatus,
    this.createdAt,
  });

  factory OrderRevisionEventModel.fromJson(Map<String, dynamic> json) {
    return OrderRevisionEventModel(
      eventType: parseString(json['event_type'] ?? json['eventType']),
      fromStatus: parseNullableString(
        json['from_status'] ?? json['fromStatus'],
      ),
      toStatus: parseNullableString(json['to_status'] ?? json['toStatus']),
      createdAt: parseNullableDateTime(json['created_at'] ?? json['createdAt']),
    );
  }
}

class OrderRevisionFinancialAdjustmentModel {
  final String type;
  final double amount;
  final String direction;
  final String status;

  const OrderRevisionFinancialAdjustmentModel({
    required this.type,
    required this.amount,
    required this.direction,
    required this.status,
  });

  factory OrderRevisionFinancialAdjustmentModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return OrderRevisionFinancialAdjustmentModel(
      type: parseString(json['adjustment_type'] ?? json['adjustmentType']),
      amount: parseDouble(json['amount']),
      direction: parseString(json['direction']),
      status: parseString(json['status']),
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', value));
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _list(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) => entry.map((key, value) => MapEntry('$key', value)))
      .toList(growable: false);
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((entry) => '$entry'.toUpperCase()).toList(growable: false);
}
