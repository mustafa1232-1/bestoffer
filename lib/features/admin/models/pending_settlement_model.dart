import '../../../core/utils/parsers.dart';

class PendingSettlementModel {
  final int id;
  final int merchantId;
  final String merchantName;
  final String ownerName;
  final String ownerPhone;
  final double amount;
  final DateTime? requestedAt;
  final String? note;

  const PendingSettlementModel({
    required this.id,
    required this.merchantId,
    required this.merchantName,
    required this.ownerName,
    required this.ownerPhone,
    required this.amount,
    required this.requestedAt,
    required this.note,
  });

  factory PendingSettlementModel.fromJson(Map<String, dynamic> j) {
    return PendingSettlementModel(
      id: parseInt(j['id']),
      merchantId: parseInt(j['merchant_id'] ?? j['merchantId']),
      merchantName: parseString(j['merchant_name']),
      ownerName: parseString(j['owner_full_name']),
      ownerPhone: parseString(j['owner_phone']),
      amount: parseDouble(j['amount']),
      requestedAt: _date(j['requested_at']),
      note: parseNullableString(j['requested_note']),
    );
  }
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  final s = value.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
