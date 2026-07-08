class MerchantReceivableInvoiceModel {
  final int id;
  final int orderId;
  final String invoiceNumber;
  final String? issuedAt;
  final String orderStatus;
  final double subtotal;
  final double commissionAmount;
  final double serviceFeeAmount;
  final double appDeliveryFeeAmount;
  final double storeDeliveryFeeAmount;
  final double appReceivableAmount;
  final double storeNetAmount;
  final double storeNetReceivedAmount;
  final double appDueFromDelivery;
  final double differenceAmount;
  final String? differenceReason;
  final bool storeCashConfirmed;
  final String settlementStatus;
  final double paidAmount;
  final double outstandingAmount;
  final String invoiceStatus;

  const MerchantReceivableInvoiceModel({
    required this.id,
    required this.orderId,
    required this.invoiceNumber,
    this.issuedAt,
    required this.orderStatus,
    required this.subtotal,
    required this.commissionAmount,
    required this.serviceFeeAmount,
    required this.appDeliveryFeeAmount,
    required this.storeDeliveryFeeAmount,
    required this.appReceivableAmount,
    required this.storeNetAmount,
    required this.storeNetReceivedAmount,
    required this.appDueFromDelivery,
    required this.differenceAmount,
    this.differenceReason,
    required this.storeCashConfirmed,
    required this.settlementStatus,
    required this.paidAmount,
    required this.outstandingAmount,
    required this.invoiceStatus,
  });

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  factory MerchantReceivableInvoiceModel.fromJson(Map<String, dynamic> json) {
    return MerchantReceivableInvoiceModel(
      id: int.tryParse('${json['id'] ?? ''}') ?? 0,
      orderId: int.tryParse('${json['order_id'] ?? ''}') ?? 0,
      invoiceNumber: '${json['invoice_number'] ?? 'INV'}',
      issuedAt: json['issued_at']?.toString(),
      orderStatus: '${json['order_status'] ?? ''}',
      subtotal: _toDouble(json['subtotal']),
      commissionAmount: _toDouble(json['commission_amount']),
      serviceFeeAmount: _toDouble(json['service_fee_amount']),
      appDeliveryFeeAmount: _toDouble(json['app_delivery_fee_amount']),
      storeDeliveryFeeAmount: _toDouble(json['store_delivery_fee_amount']),
      appReceivableAmount: _toDouble(json['app_receivable_amount']),
      storeNetAmount: _toDouble(json['store_net_amount']),
      storeNetReceivedAmount: _toDouble(
        json['store_net_received_amount'] ?? json['storeNetReceivedAmount'],
      ),
      appDueFromDelivery: _toDouble(
        json['app_due_from_delivery'] ?? json['appDueFromDelivery'],
      ),
      differenceAmount: _toDouble(
        json['difference_amount'] ?? json['differenceAmount'],
      ),
      differenceReason:
          json['difference_reason']?.toString() ?? json['differenceReason']?.toString(),
      storeCashConfirmed:
          json['store_cash_confirmed'] == true || json['storeCashConfirmed'] == true,
      settlementStatus: '${json['settlement_status'] ?? json['settlementStatus'] ?? 'pending_store_confirmation'}',
      paidAmount: _toDouble(json['paid_amount']),
      outstandingAmount: _toDouble(json['outstanding_amount']),
      invoiceStatus: '${json['invoice_status'] ?? 'unpaid'}',
    );
  }

  double get effectiveStoreNetReceivedAmount =>
      storeNetReceivedAmount > 0 ? storeNetReceivedAmount : storeNetAmount;

  double get effectiveAppDueFromDelivery =>
      appDueFromDelivery > 0 ? appDueFromDelivery : appReceivableAmount;
}
