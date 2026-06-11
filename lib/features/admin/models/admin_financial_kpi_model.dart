class AdminFinancialKpiWindow {
  final String period;
  final String? start;
  final String? end;

  const AdminFinancialKpiWindow({required this.period, this.start, this.end});

  factory AdminFinancialKpiWindow.fromJson(Map<String, dynamic> json) {
    return AdminFinancialKpiWindow(
      period: '${json['period'] ?? 'day'}',
      start: json['start']?.toString(),
      end: json['end']?.toString(),
    );
  }
}

class AdminFinancialKpiTotals {
  final double totalSales;
  final double totalCommission;
  final double totalServiceFees;
  final double totalAppDeliveryFees;
  final double totalStoreDeliveryFees;
  final double totalAppDue;
  final double totalStoreNetSales;
  final double totalCollected;
  final double netReceivables;
  final double outstandingToCollect;
  final int totalSalesOrders;
  final int totalCollectionOperations;
  final String currency;

  const AdminFinancialKpiTotals({
    required this.totalSales,
    required this.totalCommission,
    required this.totalServiceFees,
    required this.totalAppDeliveryFees,
    required this.totalStoreDeliveryFees,
    required this.totalAppDue,
    required this.totalStoreNetSales,
    required this.totalCollected,
    required this.netReceivables,
    required this.outstandingToCollect,
    required this.totalSalesOrders,
    required this.totalCollectionOperations,
    required this.currency,
  });

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  factory AdminFinancialKpiTotals.fromJson(
    Map<String, dynamic> json, {
    String defaultCurrency = 'IQD',
  }) {
    return AdminFinancialKpiTotals(
      totalSales: _toDouble(json['totalSales'] ?? json['total_sales']),
      totalCommission: _toDouble(
        json['totalCommission'] ?? json['total_commission'],
      ),
      totalServiceFees: _toDouble(
        json['totalServiceFees'] ?? json['total_service_fees'],
      ),
      totalAppDeliveryFees: _toDouble(
        json['totalAppDeliveryFees'] ?? json['total_app_delivery_fees'],
      ),
      totalStoreDeliveryFees: _toDouble(
        json['totalStoreDeliveryFees'] ?? json['total_store_delivery_fees'],
      ),
      totalAppDue: _toDouble(json['totalAppDue'] ?? json['total_app_due']),
      totalStoreNetSales: _toDouble(
        json['totalStoreNetSales'] ?? json['total_store_net_sales'],
      ),
      totalCollected: _toDouble(
        json['totalCollected'] ?? json['total_collected'],
      ),
      netReceivables: _toDouble(
        json['netReceivables'] ?? json['net_receivables'],
      ),
      outstandingToCollect: _toDouble(
        json['outstandingToCollect'] ?? json['outstanding_to_collect'],
      ),
      totalSalesOrders: _toInt(
        json['totalSalesOrders'] ?? json['total_sales_orders'],
      ),
      totalCollectionOperations: _toInt(
        json['totalCollectionOperations'] ??
            json['total_collection_operations'],
      ),
      currency: '${json['currency'] ?? defaultCurrency}',
    );
  }
}

class AdminFinancialKpiModel {
  final AdminFinancialKpiWindow window;
  final AdminFinancialKpiTotals totals;

  const AdminFinancialKpiModel({required this.window, required this.totals});

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }

  factory AdminFinancialKpiModel.fromJson(Map<String, dynamic> json) {
    final windowMap = _asMap(json['window']);
    final totalsMap = _asMap(json['totals']);
    final currency = '${json['currency'] ?? 'IQD'}';
    return AdminFinancialKpiModel(
      window: AdminFinancialKpiWindow.fromJson(windowMap),
      totals: AdminFinancialKpiTotals.fromJson(
        totalsMap,
        defaultCurrency: currency,
      ),
    );
  }
}
