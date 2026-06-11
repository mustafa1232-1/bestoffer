class MerchantFinancialSectionTotals {
  final double debit;
  final double credit;
  final double outstanding;

  const MerchantFinancialSectionTotals({
    required this.debit,
    required this.credit,
    required this.outstanding,
  });

  factory MerchantFinancialSectionTotals.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return MerchantFinancialSectionTotals(
      debit: n(json['debit']),
      credit: n(json['credit']),
      outstanding: n(json['outstanding']),
    );
  }
}

class MerchantFinancialSummaryModel {
  final int merchantId;
  final String merchantName;
  final MerchantFinancialSectionTotals storePaysApp;
  final MerchantFinancialSectionTotals appPaysStore;
  final MerchantFinancialSectionTotals totals;

  const MerchantFinancialSummaryModel({
    required this.merchantId,
    required this.merchantName,
    required this.storePaysApp,
    required this.appPaysStore,
    required this.totals,
  });

  factory MerchantFinancialSummaryModel.fromJson(Map<String, dynamic> json) {
    final merchant = Map<String, dynamic>.from(
      (json['merchant'] as Map?) ?? const {},
    );
    final storePays = Map<String, dynamic>.from(
      (Map<String, dynamic>.from(
        (json['storePaysApp'] as Map?) ?? const {},
      )['breakdown'] as Map?) ??
          const {},
    );
    final appPays = Map<String, dynamic>.from(
      (Map<String, dynamic>.from(
        (json['appPaysStore'] as Map?) ?? const {},
      )['breakdown'] as Map?) ??
          const {},
    );
    final totals = Map<String, dynamic>.from(
      (storePays['totals'] as Map?) ?? const {},
    );

    return MerchantFinancialSummaryModel(
      merchantId: int.tryParse('${merchant['id'] ?? ''}') ?? 0,
      merchantName: '${merchant['name'] ?? ''}'.trim(),
      storePaysApp: MerchantFinancialSectionTotals.fromJson(
        Map<String, dynamic>.from(storePays['totals'] as Map? ?? const {}),
      ),
      appPaysStore: MerchantFinancialSectionTotals.fromJson(
        Map<String, dynamic>.from(appPays['totals'] as Map? ?? const {}),
      ),
      totals: MerchantFinancialSectionTotals.fromJson(totals),
    );
  }
}
