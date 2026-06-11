import 'admin_financial_kpi_model.dart';

Map<String, dynamic> _asMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map(
      (key, value) => MapEntry<String, dynamic>(key.toString(), value),
    );
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _asMapList(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => e.map((k, v) => MapEntry<String, dynamic>('$k', v)))
      .toList(growable: false);
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? 0;
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

class AdminFinancialPagination {
  final int limit;
  final int offset;
  final int total;

  const AdminFinancialPagination({
    required this.limit,
    required this.offset,
    required this.total,
  });

  factory AdminFinancialPagination.fromJson(Map<String, dynamic> json) {
    return AdminFinancialPagination(
      limit: _toInt(json['limit']),
      offset: _toInt(json['offset']),
      total: _toInt(json['total']),
    );
  }
}

class AdminFinancialMerchantSummaryRow {
  final int merchantId;
  final String merchantName;
  final int ordersCount;
  final int operationsCount;
  final double totalSales;
  final double totalCollected;
  final double netReceivables;
  final double outstandingToCollect;
  final String? firstEventAt;
  final String? lastEventAt;

  const AdminFinancialMerchantSummaryRow({
    required this.merchantId,
    required this.merchantName,
    this.ordersCount = 0,
    this.operationsCount = 0,
    this.totalSales = 0,
    this.totalCollected = 0,
    this.netReceivables = 0,
    this.outstandingToCollect = 0,
    this.firstEventAt,
    this.lastEventAt,
  });

  factory AdminFinancialMerchantSummaryRow.fromJson(Map<String, dynamic> json) {
    return AdminFinancialMerchantSummaryRow(
      merchantId: _toInt(json['merchant_id'] ?? json['merchantId']),
      merchantName: '${json['merchant_name'] ?? json['merchantName'] ?? '-'}',
      ordersCount: _toInt(json['orders_count'] ?? json['ordersCount']),
      operationsCount: _toInt(
        json['operations_count'] ??
            json['collection_operations_count'] ??
            json['operationsCount'],
      ),
      totalSales: _toDouble(json['total_sales'] ?? json['totalSales']),
      totalCollected:
          _toDouble(json['total_collected'] ?? json['totalCollected']),
      netReceivables:
          _toDouble(json['net_receivables'] ?? json['netReceivables']),
      outstandingToCollect: _toDouble(
        json['outstanding_to_collect'] ?? json['outstandingToCollect'],
      ),
      firstEventAt:
          json['first_order_at']?.toString() ??
          json['first_collected_at']?.toString(),
      lastEventAt:
          json['last_order_at']?.toString() ??
          json['last_collected_at']?.toString(),
    );
  }
}

class AdminFinancialSalesOrderLine {
  final int orderId;
  final String? createdAt;
  final String status;
  final String customerName;
  final String customerPhone;
  final double totalAmount;
  final double subtotal;
  final double deliveryFee;
  final String? note;

  const AdminFinancialSalesOrderLine({
    required this.orderId,
    this.createdAt,
    required this.status,
    required this.customerName,
    required this.customerPhone,
    required this.totalAmount,
    required this.subtotal,
    required this.deliveryFee,
    this.note,
  });

  factory AdminFinancialSalesOrderLine.fromJson(Map<String, dynamic> json) {
    return AdminFinancialSalesOrderLine(
      orderId: _toInt(json['order_id'] ?? json['orderId']),
      createdAt: json['created_at']?.toString() ?? json['createdAt']?.toString(),
      status: '${json['status'] ?? ''}',
      customerName: '${json['customer_name'] ?? json['customerName'] ?? '-'}',
      customerPhone:
          '${json['customer_phone'] ?? json['customerPhone'] ?? '-'}',
      totalAmount: _toDouble(json['total_amount'] ?? json['totalAmount']),
      subtotal: _toDouble(json['subtotal']),
      deliveryFee: _toDouble(json['delivery_fee'] ?? json['deliveryFee']),
      note: json['note']?.toString(),
    );
  }
}

class AdminFinancialCollectionLine {
  final int paymentRequestId;
  final String paymentScope;
  final String status;
  final double amount;
  final double requestedAmount;
  final double paidAmount;
  final String? paymentMethod;
  final String? paymentDate;
  final String? referenceCode;
  final String? receiverName;
  final String? eventAt;

  const AdminFinancialCollectionLine({
    required this.paymentRequestId,
    required this.paymentScope,
    required this.status,
    required this.amount,
    required this.requestedAmount,
    required this.paidAmount,
    this.paymentMethod,
    this.paymentDate,
    this.referenceCode,
    this.receiverName,
    this.eventAt,
  });

  factory AdminFinancialCollectionLine.fromJson(Map<String, dynamic> json) {
    return AdminFinancialCollectionLine(
      paymentRequestId: _toInt(
        json['payment_request_id'] ?? json['paymentRequestId'],
      ),
      paymentScope: '${json['payment_scope'] ?? json['paymentScope'] ?? ''}',
      status: '${json['status'] ?? ''}',
      amount: _toDouble(json['amount']),
      requestedAmount:
          _toDouble(json['requested_amount'] ?? json['requestedAmount']),
      paidAmount: _toDouble(json['paid_amount'] ?? json['paidAmount']),
      paymentMethod: json['payment_method']?.toString(),
      paymentDate: json['payment_date']?.toString(),
      referenceCode: json['reference_code']?.toString(),
      receiverName: json['receiver_name']?.toString(),
      eventAt: json['event_at']?.toString(),
    );
  }
}

class AdminFinancialStatementLine {
  final String? eventAt;
  final String sourceType;
  final int sourceId;
  final String description;
  final double debit;
  final double credit;
  final double balanceAfter;

  const AdminFinancialStatementLine({
    this.eventAt,
    required this.sourceType,
    required this.sourceId,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balanceAfter,
  });

  factory AdminFinancialStatementLine.fromJson(Map<String, dynamic> json) {
    return AdminFinancialStatementLine(
      eventAt: json['event_at']?.toString(),
      sourceType: '${json['source_type'] ?? json['sourceType'] ?? ''}',
      sourceId: _toInt(json['source_id'] ?? json['sourceId']),
      description: '${json['description'] ?? '-'}',
      debit: _toDouble(json['debit']),
      credit: _toDouble(json['credit']),
      balanceAfter: _toDouble(json['balance_after'] ?? json['balanceAfter']),
    );
  }
}

class AdminFinancialMerchantInfo {
  final int id;
  final String name;

  const AdminFinancialMerchantInfo({
    required this.id,
    required this.name,
  });

  factory AdminFinancialMerchantInfo.fromJson(Map<String, dynamic> json) {
    return AdminFinancialMerchantInfo(
      id: _toInt(json['id']),
      name: '${json['name'] ?? '-'}',
    );
  }
}

class AdminFinancialReportSummary {
  final double totalSales;
  final double totalCollected;
  final double netReceivables;
  final double outstandingToCollect;
  final int totalOrders;
  final int totalOperations;
  final int merchantsCount;
  final double openingBalance;

  const AdminFinancialReportSummary({
    this.totalSales = 0,
    this.totalCollected = 0,
    this.netReceivables = 0,
    this.outstandingToCollect = 0,
    this.totalOrders = 0,
    this.totalOperations = 0,
    this.merchantsCount = 0,
    this.openingBalance = 0,
  });

  factory AdminFinancialReportSummary.fromJson(Map<String, dynamic> json) {
    return AdminFinancialReportSummary(
      totalSales: _toDouble(json['totalSales'] ?? json['total_sales']),
      totalCollected:
          _toDouble(json['totalCollected'] ?? json['total_collected']),
      netReceivables:
          _toDouble(json['netReceivables'] ?? json['net_receivables']),
      outstandingToCollect: _toDouble(
        json['outstandingToCollect'] ?? json['outstanding_to_collect'],
      ),
      totalOrders: _toInt(json['totalOrders'] ?? json['total_orders']),
      totalOperations:
          _toInt(json['totalOperations'] ?? json['total_operations']),
      merchantsCount:
          _toInt(json['merchantsCount'] ?? json['merchants_count']),
      openingBalance:
          _toDouble(json['openingBalance'] ?? json['opening_balance']),
    );
  }
}

class AdminFinancialMerchantsReportModel {
  final String currency;
  final AdminFinancialKpiWindow window;
  final AdminFinancialReportSummary summary;
  final List<AdminFinancialMerchantSummaryRow> merchants;
  final AdminFinancialPagination pagination;

  const AdminFinancialMerchantsReportModel({
    required this.currency,
    required this.window,
    required this.summary,
    required this.merchants,
    required this.pagination,
  });

  factory AdminFinancialMerchantsReportModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final windowMap = _asMap(json['window']);
    final summaryMap = _asMap(json['summary']);
    final paginationMap = _asMap(json['pagination']);
    final merchantRows = _asMapList(json['merchants']);
    return AdminFinancialMerchantsReportModel(
      currency: '${json['currency'] ?? 'IQD'}',
      window: AdminFinancialKpiWindow.fromJson(windowMap),
      summary: AdminFinancialReportSummary.fromJson(summaryMap),
      merchants: merchantRows
          .map(AdminFinancialMerchantSummaryRow.fromJson)
          .toList(growable: false),
      pagination: AdminFinancialPagination.fromJson(paginationMap),
    );
  }
}

class AdminFinancialMerchantDetailModel {
  final String currency;
  final AdminFinancialKpiWindow window;
  final AdminFinancialMerchantInfo merchant;
  final AdminFinancialReportSummary summary;
  final List<AdminFinancialSalesOrderLine> salesItems;
  final List<AdminFinancialCollectionLine> collectionItems;
  final List<AdminFinancialStatementLine> statementItems;
  final AdminFinancialPagination pagination;

  const AdminFinancialMerchantDetailModel({
    required this.currency,
    required this.window,
    required this.merchant,
    required this.summary,
    this.salesItems = const [],
    this.collectionItems = const [],
    this.statementItems = const [],
    required this.pagination,
  });

  factory AdminFinancialMerchantDetailModel.fromSalesJson(
    Map<String, dynamic> json,
  ) {
    final paginationMap = _asMap(json['pagination']);
    final summaryMap = _asMap(json['summary']);
    return AdminFinancialMerchantDetailModel(
      currency: '${json['currency'] ?? 'IQD'}',
      window: AdminFinancialKpiWindow.fromJson(_asMap(json['window'])),
      merchant: AdminFinancialMerchantInfo.fromJson(_asMap(json['merchant'])),
      summary: AdminFinancialReportSummary.fromJson(summaryMap),
      salesItems: _asMapList(json['items'])
          .map(AdminFinancialSalesOrderLine.fromJson)
          .toList(growable: false),
      pagination: AdminFinancialPagination.fromJson(paginationMap),
    );
  }

  factory AdminFinancialMerchantDetailModel.fromCollectionsJson(
    Map<String, dynamic> json,
  ) {
    final paginationMap = _asMap(json['pagination']);
    final summaryMap = _asMap(json['summary']);
    return AdminFinancialMerchantDetailModel(
      currency: '${json['currency'] ?? 'IQD'}',
      window: AdminFinancialKpiWindow.fromJson(_asMap(json['window'])),
      merchant: AdminFinancialMerchantInfo.fromJson(_asMap(json['merchant'])),
      summary: AdminFinancialReportSummary.fromJson(summaryMap),
      collectionItems: _asMapList(json['items'])
          .map(AdminFinancialCollectionLine.fromJson)
          .toList(growable: false),
      pagination: AdminFinancialPagination.fromJson(paginationMap),
    );
  }

  factory AdminFinancialMerchantDetailModel.fromStatementJson(
    Map<String, dynamic> json,
  ) {
    final paginationMap = _asMap(json['pagination']);
    final summaryMap = _asMap(json['summary']);
    return AdminFinancialMerchantDetailModel(
      currency: '${json['currency'] ?? 'IQD'}',
      window: AdminFinancialKpiWindow.fromJson(_asMap(json['window'])),
      merchant: AdminFinancialMerchantInfo.fromJson(_asMap(json['merchant'])),
      summary: AdminFinancialReportSummary.fromJson(summaryMap),
      statementItems: _asMapList(json['statement'])
          .map(AdminFinancialStatementLine.fromJson)
          .toList(growable: false),
      pagination: AdminFinancialPagination.fromJson(paginationMap),
    );
  }
}
