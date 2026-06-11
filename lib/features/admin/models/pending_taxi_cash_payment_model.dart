import '../../../core/utils/parsers.dart';

class PendingTaxiCashPaymentModel {
  final int captainUserId;
  final String fullName;
  final String phone;
  final String? block;
  final String? buildingNumber;
  final String? apartment;
  final String? profileImageUrl;
  final String? carImageUrl;
  final String? carMake;
  final String? carModel;
  final int? carYear;
  final String? plateNumber;
  final DateTime? cashPaymentRequestedAt;
  final int monthlyFeeIqd;
  final int discountPercent;
  final int discountedMonthlyFeeIqd;
  final int dueAmountIqd;

  const PendingTaxiCashPaymentModel({
    required this.captainUserId,
    required this.fullName,
    required this.phone,
    required this.block,
    required this.buildingNumber,
    required this.apartment,
    required this.profileImageUrl,
    required this.carImageUrl,
    required this.carMake,
    required this.carModel,
    required this.carYear,
    required this.plateNumber,
    required this.cashPaymentRequestedAt,
    required this.monthlyFeeIqd,
    required this.discountPercent,
    required this.discountedMonthlyFeeIqd,
    required this.dueAmountIqd,
  });

  factory PendingTaxiCashPaymentModel.fromJson(Map<String, dynamic> json) {
    final rawSubscription = json['subscription'];
    final subscription = rawSubscription is Map
        ? Map<String, dynamic>.from(rawSubscription)
        : const <String, dynamic>{};

    return PendingTaxiCashPaymentModel(
      captainUserId: parseInt(json['captainUserId'] ?? json['captain_user_id']),
      fullName: parseString(json['fullName'] ?? json['full_name']),
      phone: parseString(json['phone']),
      block: parseNullableString(json['block']),
      buildingNumber: parseNullableString(
        json['buildingNumber'] ?? json['building_number'],
      ),
      apartment: parseNullableString(json['apartment']),
      profileImageUrl: parseNullableString(
        json['profileImageUrl'] ?? json['profile_image_url'],
      ),
      carImageUrl: parseNullableString(
        json['carImageUrl'] ?? json['car_image_url'],
      ),
      carMake: parseNullableString(json['carMake'] ?? json['car_make']),
      carModel: parseNullableString(json['carModel'] ?? json['car_model']),
      carYear: (json['carYear'] ?? json['car_year']) == null
          ? null
          : parseInt(json['carYear'] ?? json['car_year']),
      plateNumber: parseNullableString(
        json['plateNumber'] ?? json['plate_number'],
      ),
      cashPaymentRequestedAt: parseNullableDateTime(
        json['cashPaymentRequestedAt'] ?? json['cash_payment_requested_at'],
      ),
      monthlyFeeIqd: parseInt(
        subscription['monthlyFeeIqd'] ?? subscription['monthly_fee_iqd'],
      ),
      discountPercent: parseInt(
        subscription['discountPercent'] ?? subscription['discount_percent'],
      ),
      discountedMonthlyFeeIqd: parseInt(
        subscription['discountedMonthlyFeeIqd'] ??
            subscription['discounted_monthly_fee_iqd'],
      ),
      dueAmountIqd: parseInt(
        subscription['dueAmountIqd'] ?? subscription['due_amount_iqd'],
      ),
    );
  }
}
