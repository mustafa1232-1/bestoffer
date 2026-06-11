class MerchantFinancialRequestModel {
  final int id;
  final String requestType;
  final String paymentScope;
  final String status;
  final double amount;
  final double requestedAmount;
  final double paidAmount;
  final bool isLocked;
  final bool canEditByMerchant;
  final bool canConfirmByMerchant;
  final String? paymentMethod;
  final String? paymentMethodOther;
  final String? paymentDate;
  final String? referenceCode;
  final String? receiverName;
  final String? selectionMode;
  final int linkedInvoiceCount;
  final Map<String, dynamic> selectionMeta;
  final String? note;
  final String? reviewNote;
  final String? internalAdminNote;
  final String? createdAt;
  final String? updatedAt;

  const MerchantFinancialRequestModel({
    required this.id,
    required this.requestType,
    required this.paymentScope,
    required this.status,
    required this.amount,
    required this.requestedAmount,
    required this.paidAmount,
    required this.isLocked,
    required this.canEditByMerchant,
    required this.canConfirmByMerchant,
    this.paymentMethod,
    this.paymentMethodOther,
    this.paymentDate,
    this.referenceCode,
    this.receiverName,
    this.selectionMode,
    this.linkedInvoiceCount = 0,
    this.selectionMeta = const {},
    this.note,
    this.reviewNote,
    this.internalAdminNote,
    this.createdAt,
    this.updatedAt,
  });

  factory MerchantFinancialRequestModel.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    bool b(dynamic v) =>
        v == true || '${v ?? ''}'.toLowerCase() == 'true' || '$v' == '1';

    return MerchantFinancialRequestModel(
      id: int.tryParse('${json['id'] ?? ''}') ?? 0,
      requestType: '${json['request_type'] ?? 'store_pays_app'}',
      paymentScope: '${json['payment_scope'] ?? 'all'}',
      status: '${json['status'] ?? ''}',
      amount: n(json['amount']),
      requestedAmount: n(json['requested_amount']),
      paidAmount: n(json['paid_amount']),
      isLocked: b(json['is_locked']),
      canEditByMerchant: b(json['can_edit_by_merchant']),
      canConfirmByMerchant: b(json['can_confirm_by_merchant']),
      paymentMethod: json['payment_method']?.toString(),
      paymentMethodOther: json['payment_method_other']?.toString(),
      paymentDate: json['payment_date']?.toString(),
      referenceCode: json['reference_code']?.toString(),
      receiverName: json['receiver_name']?.toString(),
      selectionMode: json['selection_mode']?.toString(),
      linkedInvoiceCount: int.tryParse('${json['linked_invoice_count'] ?? ''}') ?? 0,
      selectionMeta: json['selection_meta_json'] is Map
          ? Map<String, dynamic>.from(json['selection_meta_json'] as Map)
          : const {},
      note: json['note']?.toString(),
      reviewNote: json['review_note']?.toString(),
      internalAdminNote: json['internal_admin_note']?.toString(),
      createdAt: json['submitted_at']?.toString() ?? json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }
}
