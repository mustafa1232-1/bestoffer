import '../../../core/utils/parsers.dart';

class PaidUpgradePlanModel {
  final int id;
  final String code;
  final String title;
  final String? description;
  final double monthlyFeeIqd;
  final String currency;
  final String? badgeLabel;
  final bool isActive;
  final int sortOrder;

  const PaidUpgradePlanModel({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.monthlyFeeIqd,
    required this.currency,
    required this.badgeLabel,
    required this.isActive,
    required this.sortOrder,
  });

  factory PaidUpgradePlanModel.fromJson(Map<String, dynamic> j) {
    return PaidUpgradePlanModel(
      id: parseInt(j['id']),
      code: parseString(j['code']),
      title: parseString(j['title']),
      description: parseNullableString(j['description']),
      monthlyFeeIqd: parseDouble(j['monthly_fee_iqd'] ?? j['monthlyFeeIqd']),
      currency: parseString(j['currency'], fallback: 'IQD'),
      badgeLabel: parseNullableString(j['badge_label'] ?? j['badgeLabel']),
      isActive: parseBool(j['is_active'] ?? j['isActive'], fallback: true),
      sortOrder: parseInt(j['sort_order'] ?? j['sortOrder']),
    );
  }
}

class PaidUpgradeRequestModel {
  final int id;
  final int userId;
  final int planId;
  final String? planCode;
  final String? planTitle;
  final String? userFullName;
  final String? userPhone;
  final String status;
  final String? activityName;
  final String? activityDescription;
  final String? contactPhone;
  final String? notes;
  final Map<String, dynamic> requestMeta;
  final double monthlyFeeIqd;
  final String currency;
  final String? reviewNote;
  final int? reviewedByUserId;
  final DateTime? reviewedAt;
  final int? activatedByUserId;
  final DateTime? activatedAt;
  final DateTime? cancelledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PaidUpgradeRequestModel({
    required this.id,
    required this.userId,
    required this.planId,
    required this.planCode,
    required this.planTitle,
    required this.userFullName,
    required this.userPhone,
    required this.status,
    required this.activityName,
    required this.activityDescription,
    required this.contactPhone,
    required this.notes,
    required this.requestMeta,
    required this.monthlyFeeIqd,
    required this.currency,
    required this.reviewNote,
    required this.reviewedByUserId,
    required this.reviewedAt,
    required this.activatedByUserId,
    required this.activatedAt,
    required this.cancelledAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaidUpgradeRequestModel.fromJson(Map<String, dynamic> j) {
    return PaidUpgradeRequestModel(
      id: parseInt(j['id']),
      userId: parseInt(j['user_id'] ?? j['userId']),
      planId: parseInt(j['plan_id'] ?? j['planId']),
      planCode: parseNullableString(j['plan_code'] ?? j['planCode']),
      planTitle: parseNullableString(j['plan_title'] ?? j['planTitle']),
      userFullName: parseNullableString(j['user_full_name'] ?? j['userFullName']),
      userPhone: parseNullableString(j['user_phone'] ?? j['userPhone']),
      status: parseString(j['status']),
      activityName: parseNullableString(j['activity_name'] ?? j['activityName']),
      activityDescription: parseNullableString(
        j['activity_description'] ?? j['activityDescription'],
      ),
      contactPhone: parseNullableString(j['contact_phone'] ?? j['contactPhone']),
      notes: parseNullableString(j['notes']),
      requestMeta: j['request_meta_json'] is Map
          ? Map<String, dynamic>.from(j['request_meta_json'] as Map)
          : j['requestMeta'] is Map
              ? Map<String, dynamic>.from(j['requestMeta'] as Map)
              : const <String, dynamic>{},
      monthlyFeeIqd: parseDouble(j['monthly_fee_iqd'] ?? j['monthlyFeeIqd']),
      currency: parseString(j['currency'], fallback: 'IQD'),
      reviewNote: parseNullableString(j['review_note'] ?? j['reviewNote']),
      reviewedByUserId: j['reviewed_by_user_id'] == null
          ? null
          : parseInt(j['reviewed_by_user_id']),
      reviewedAt: _parseDate(j['reviewed_at'] ?? j['reviewedAt']),
      activatedByUserId: j['activated_by_user_id'] == null
          ? null
          : parseInt(j['activated_by_user_id']),
      activatedAt: _parseDate(j['activated_at'] ?? j['activatedAt']),
      cancelledAt: _parseDate(j['cancelled_at'] ?? j['cancelledAt']),
      createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
      updatedAt: _parseDate(j['updated_at'] ?? j['updatedAt']),
    );
  }
}

class PaidUpgradeSubscriptionModel {
  final int id;
  final int userId;
  final int planId;
  final String? planCode;
  final String? planTitle;
  final int? requestId;
  final String status;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final int? activatedByUserId;
  final DateTime? expiredAt;
  final DateTime? lastExpiryReminderAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PaidUpgradeSubscriptionModel({
    required this.id,
    required this.userId,
    required this.planId,
    required this.planCode,
    required this.planTitle,
    required this.requestId,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    required this.activatedByUserId,
    required this.expiredAt,
    required this.lastExpiryReminderAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaidUpgradeSubscriptionModel.fromJson(Map<String, dynamic> j) {
    return PaidUpgradeSubscriptionModel(
      id: parseInt(j['id']),
      userId: parseInt(j['user_id'] ?? j['userId']),
      planId: parseInt(j['plan_id'] ?? j['planId']),
      planCode: parseNullableString(j['plan_code'] ?? j['planCode']),
      planTitle: parseNullableString(j['plan_title'] ?? j['planTitle']),
      requestId: j['request_id'] == null ? null : parseInt(j['request_id']),
      status: parseString(j['status']),
      startedAt: _parseDate(j['started_at'] ?? j['startedAt']),
      expiresAt: _parseDate(j['expires_at'] ?? j['expiresAt']),
      activatedByUserId: j['activated_by_user_id'] == null
          ? null
          : parseInt(j['activated_by_user_id']),
      expiredAt: _parseDate(j['expired_at'] ?? j['expiredAt']),
      lastExpiryReminderAt: _parseDate(
        j['last_expiry_reminder_at'] ?? j['lastExpiryReminderAt'],
      ),
      createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
      updatedAt: _parseDate(j['updated_at'] ?? j['updatedAt']),
    );
  }
}

class PaidUpgradesSummaryModel {
  final List<PaidUpgradePlanModel> plans;
  final List<PaidUpgradeRequestModel> requests;
  final List<PaidUpgradeSubscriptionModel> subscriptions;
  final List<PaidUpgradeSubscriptionModel> activeSubscriptions;
  final List<String> activePlanCodes;
  final bool carSellerMonthly;
  final bool propertySellerMonthly;
  final bool premiumMonthly;
  final bool premiumBadgeActive;
  final String? premiumBadgeTitle;
  final String? premiumBadgePlanCode;
  final DateTime? premiumBadgeExpiresAt;

  const PaidUpgradesSummaryModel({
    required this.plans,
    required this.requests,
    required this.subscriptions,
    required this.activeSubscriptions,
    required this.activePlanCodes,
    required this.carSellerMonthly,
    required this.propertySellerMonthly,
    required this.premiumMonthly,
    required this.premiumBadgeActive,
    required this.premiumBadgeTitle,
    required this.premiumBadgePlanCode,
    required this.premiumBadgeExpiresAt,
  });

  factory PaidUpgradesSummaryModel.fromJson(Map<String, dynamic> j) {
    final plans = List<dynamic>.from(j['plans'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PaidUpgradePlanModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    final requests = List<dynamic>.from(j['requests'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PaidUpgradeRequestModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    final subscriptions = List<dynamic>.from(j['subscriptions'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PaidUpgradeSubscriptionModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    final activeSubscriptions = List<dynamic>.from(
      j['activeSubscriptions'] as List? ?? const [],
    )
        .whereType<Map>()
        .map((e) => PaidUpgradeSubscriptionModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    final activePlanCodes = List<dynamic>.from(j['activePlanCodes'] as List? ?? const [])
        .map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);
    final premiumBadge = j['premiumBadge'] is Map
        ? Map<String, dynamic>.from(j['premiumBadge'] as Map)
        : const <String, dynamic>{};
    final entitlements = j['entitlements'] is Map
        ? Map<String, dynamic>.from(j['entitlements'] as Map)
        : const <String, dynamic>{};

    return PaidUpgradesSummaryModel(
      plans: plans,
      requests: requests,
      subscriptions: subscriptions,
      activeSubscriptions: activeSubscriptions,
      activePlanCodes: activePlanCodes,
      carSellerMonthly: parseBool(entitlements['carSellerMonthly']),
      propertySellerMonthly: parseBool(entitlements['propertySellerMonthly']),
      premiumMonthly: parseBool(entitlements['premiumMonthly']),
      premiumBadgeActive: parseBool(premiumBadge['active']),
      premiumBadgeTitle: parseNullableString(premiumBadge['title']),
      premiumBadgePlanCode: parseNullableString(premiumBadge['planCode']),
      premiumBadgeExpiresAt: _parseDate(premiumBadge['expiresAt']),
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
