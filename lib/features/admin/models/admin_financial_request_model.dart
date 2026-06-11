class AdminFinancialRequestModel {
  final int id;
  final int merchantId;
  final String merchantName;
  final String requestType;
  final String paymentScope;
  final String status;
  final double amount;
  final double requestedAmount;
  final double paidAmount;
  final bool isLocked;
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
  final String? submittedAt;

  const AdminFinancialRequestModel({
    required this.id,
    required this.merchantId,
    required this.merchantName,
    required this.requestType,
    required this.paymentScope,
    required this.status,
    required this.amount,
    required this.requestedAmount,
    required this.paidAmount,
    required this.isLocked,
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
    this.submittedAt,
  });

  factory AdminFinancialRequestModel.fromJson(
    Map<String, dynamic> json, {
    int merchantId = 0,
    String merchantName = '',
  }) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    bool b(dynamic v) =>
        v == true || '${v ?? ''}'.toLowerCase() == 'true' || '$v' == '1';

    return AdminFinancialRequestModel(
      id: int.tryParse('${json['id'] ?? ''}') ?? 0,
      merchantId: merchantId,
      merchantName: merchantName,
      requestType: '${json['request_type'] ?? 'store_pays_app'}',
      paymentScope: '${json['payment_scope'] ?? 'all'}',
      status: '${json['status'] ?? ''}',
      amount: n(json['amount']),
      requestedAmount: n(json['requested_amount']),
      paidAmount: n(json['paid_amount']),
      isLocked: b(json['is_locked']),
      paymentMethod: json['payment_method']?.toString(),
      paymentMethodOther: json['payment_method_other']?.toString(),
      paymentDate: json['payment_date']?.toString(),
      referenceCode: json['reference_code']?.toString(),
      receiverName: json['receiver_name']?.toString(),
      selectionMode: json['selection_mode']?.toString(),
      linkedInvoiceCount:
          int.tryParse('${json['linked_invoice_count'] ?? ''}') ?? 0,
      selectionMeta: json['selection_meta_json'] is Map
          ? Map<String, dynamic>.from(json['selection_meta_json'] as Map)
          : const {},
      note: json['note']?.toString(),
      reviewNote: json['review_note']?.toString(),
      internalAdminNote: json['internal_admin_note']?.toString(),
      submittedAt: json['submitted_at']?.toString() ?? json['created_at']?.toString(),
    );
  }
}
