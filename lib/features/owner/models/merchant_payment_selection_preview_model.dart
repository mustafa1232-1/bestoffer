import 'merchant_receivable_invoice_model.dart';

class MerchantPaymentSelectionPreviewSummary {
  final int invoicesCount;
  final double subtotal;
  final double commissionAmount;
  final double serviceFeeAmount;
  final double appDeliveryFeeAmount;
  final double storeDeliveryFeeAmount;
  final double appReceivableAmount;
  final double storeNetAmount;
  final String? oldestIssuedAt;
  final String? latestIssuedAt;

  const MerchantPaymentSelectionPreviewSummary({
    required this.invoicesCount,
    required this.subtotal,
    required this.commissionAmount,
    required this.serviceFeeAmount,
    required this.appDeliveryFeeAmount,
    required this.storeDeliveryFeeAmount,
    required this.appReceivableAmount,
    required this.storeNetAmount,
    this.oldestIssuedAt,
    this.latestIssuedAt,
  });

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  factory MerchantPaymentSelectionPreviewSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return MerchantPaymentSelectionPreviewSummary(
      invoicesCount: int.tryParse('${json['invoicesCount'] ?? ''}') ?? 0,
      subtotal: _toDouble(json['subtotal']),
      commissionAmount: _toDouble(json['commissionAmount']),
      serviceFeeAmount: _toDouble(json['serviceFeeAmount']),
      appDeliveryFeeAmount: _toDouble(json['appDeliveryFeeAmount']),
      storeDeliveryFeeAmount: _toDouble(json['storeDeliveryFeeAmount']),
      appReceivableAmount: _toDouble(json['appReceivableAmount']),
      storeNetAmount: _toDouble(json['storeNetAmount']),
      oldestIssuedAt: json['oldestIssuedAt']?.toString(),
      latestIssuedAt: json['latestIssuedAt']?.toString(),
    );
  }
}

class MerchantPaymentSelectionPreviewModel {
  final String selectionMode;
  final double? requestedAmount;
  final bool exactMatch;
  final bool requiresAmountConfirmation;
  final double? confirmedAdjustedAmount;
  final double finalizedAmount;
  final double nearestLowerAmount;
  final double nearestHigherAmount;
  final String? adjustmentDirection;
  final String message;
  final List<int> selectedInvoiceIds;
  final List<MerchantReceivableInvoiceModel> invoices;
  final MerchantPaymentSelectionPreviewSummary summary;

  const MerchantPaymentSelectionPreviewModel({
    required this.selectionMode,
    required this.requestedAmount,
    required this.exactMatch,
    required this.requiresAmountConfirmation,
    required this.confirmedAdjustedAmount,
    required this.finalizedAmount,
    required this.nearestLowerAmount,
    required this.nearestHigherAmount,
    required this.adjustmentDirection,
    required this.message,
    required this.selectedInvoiceIds,
    required this.invoices,
    required this.summary,
  });

  static double? _toNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}');
  }

  factory MerchantPaymentSelectionPreviewModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final summaryMap = Map<String, dynamic>.from(
      (json['summary'] as Map?) ?? const {},
    );
    final invoicesRaw = List<dynamic>.from(json['invoices'] as List? ?? const []);
    final idsRaw = List<dynamic>.from(
      json['selectedInvoiceIds'] as List? ?? const [],
    );
    return MerchantPaymentSelectionPreviewModel(
      selectionMode: '${json['selectionMode'] ?? 'all_invoices'}',
      requestedAmount: _toNullableDouble(json['requestedAmount']),
      exactMatch: json['exactMatch'] == true,
      requiresAmountConfirmation: json['requiresAmountConfirmation'] == true,
      confirmedAdjustedAmount: _toNullableDouble(json['confirmedAdjustedAmount']),
      finalizedAmount: _toNullableDouble(json['finalizedAmount']) ?? 0,
      nearestLowerAmount: _toNullableDouble(json['nearestLowerAmount']) ?? 0,
      nearestHigherAmount: _toNullableDouble(json['nearestHigherAmount']) ?? 0,
      adjustmentDirection: json['adjustmentDirection']?.toString(),
      message: '${json['message'] ?? ''}',
      selectedInvoiceIds: idsRaw
          .map((value) => int.tryParse('$value') ?? 0)
          .where((value) => value > 0)
          .toList(growable: false),
      invoices: invoicesRaw
          .whereType<Map>()
          .map(
            (row) => MerchantReceivableInvoiceModel.fromJson(
              row.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList(growable: false),
      summary: MerchantPaymentSelectionPreviewSummary.fromJson(summaryMap),
    );
  }
}
