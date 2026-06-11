import '../../auth/models/user_model.dart';

int _toInt(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

double _toDouble(dynamic value, [double fallback = 0]) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

bool _toBool(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  final normalized = '$value'.trim().toLowerCase();
  if (normalized == 'true' || normalized == '1') return true;
  if (normalized == 'false' || normalized == '0') return false;
  return fallback;
}

String? _toNullableString(dynamic value) {
  if (value == null) return null;
  final out = '$value'.trim();
  return out.isEmpty ? null : out;
}

Map<String, dynamic> _toMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry<String, dynamic>(key.toString(), item),
    );
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _toMapList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value.map(_toMap).toList(growable: false);
}

class CompanyMembership {
  final int id;
  final int companyId;
  final int userId;
  final String role;
  final String companyName;
  final String? companyCode;
  final String? companyStatus;
  final bool isActive;
  final Map<String, dynamic> permissions;

  const CompanyMembership({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.role,
    required this.companyName,
    required this.companyCode,
    required this.companyStatus,
    required this.isActive,
    required this.permissions,
  });

  factory CompanyMembership.fromJson(Map<String, dynamic> json) {
    return CompanyMembership(
      id: _toInt(json['id']),
      companyId: _toInt(json['companyId'] ?? json['company_id']),
      userId: _toInt(json['userId'] ?? json['user_id']),
      role: '${json['role'] ?? ''}'.trim(),
      companyName:
          '${json['companyName'] ?? json['company_name'] ?? ''}'.trim(),
      companyCode: _toNullableString(
        json['companyCode'] ?? json['company_code'],
      ),
      companyStatus: _toNullableString(
        json['companyStatus'] ?? json['company_status'],
      ),
      isActive: _toBool(json['isActive'] ?? json['is_active'], true),
      permissions: _toMap(json['permissions'] ?? json['permissions_json']),
    );
  }
}

class CompanySummary {
  final int id;
  final String name;
  final String? legalName;
  final String? brandName;
  final String code;
  final String? contactPhone;
  final String? contactEmail;
  final String? logoUrl;
  final String? summary;
  final String? businessType;
  final String? headquartersAddress;
  final String? primaryContactName;
  final String? supportPhone;
  final String? websiteUrl;
  final String? registrationNumber;
  final String? taxNumber;
  final String status;
  final String? notes;
  final int? branchesCount;
  final int? usersCount;
  final int? activeUsersCount;
  final String? createdAt;
  final String? updatedAt;

  const CompanySummary({
    required this.id,
    required this.name,
    required this.legalName,
    required this.brandName,
    required this.code,
    required this.contactPhone,
    required this.contactEmail,
    required this.logoUrl,
    required this.summary,
    required this.businessType,
    required this.headquartersAddress,
    required this.primaryContactName,
    required this.supportPhone,
    required this.websiteUrl,
    required this.registrationNumber,
    required this.taxNumber,
    required this.status,
    required this.notes,
    required this.branchesCount,
    required this.usersCount,
    required this.activeUsersCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CompanySummary.fromJson(Map<String, dynamic> json) {
    return CompanySummary(
      id: _toInt(json['id']),
      name: '${json['name'] ?? ''}'.trim(),
      legalName: _toNullableString(json['legalName'] ?? json['legal_name']),
      brandName: _toNullableString(json['brandName'] ?? json['brand_name']),
      code: '${json['code'] ?? ''}'.trim(),
      contactPhone: _toNullableString(
        json['contactPhone'] ?? json['contact_phone'],
      ),
      contactEmail: _toNullableString(
        json['contactEmail'] ?? json['contact_email'],
      ),
      logoUrl: _toNullableString(json['logoUrl'] ?? json['logo_url']),
      summary: _toNullableString(json['summary']),
      businessType: _toNullableString(
        json['businessType'] ?? json['business_type'],
      ),
      headquartersAddress: _toNullableString(
        json['headquartersAddress'] ?? json['headquarters_address'],
      ),
      primaryContactName: _toNullableString(
        json['primaryContactName'] ?? json['primary_contact_name'],
      ),
      supportPhone: _toNullableString(
        json['supportPhone'] ?? json['support_phone'],
      ),
      websiteUrl: _toNullableString(
        json['websiteUrl'] ?? json['website_url'],
      ),
      registrationNumber: _toNullableString(
        json['registrationNumber'] ?? json['registration_number'],
      ),
      taxNumber: _toNullableString(
        json['taxNumber'] ?? json['tax_number'],
      ),
      status: '${json['status'] ?? 'active'}'.trim(),
      notes: _toNullableString(json['notes']),
      branchesCount: json['branchesCount'] == null &&
              json['branches_count'] == null
          ? null
          : _toInt(json['branchesCount'] ?? json['branches_count']),
      usersCount: json['usersCount'] == null && json['users_count'] == null
          ? null
          : _toInt(json['usersCount'] ?? json['users_count']),
      activeUsersCount: json['activeUsersCount'] == null &&
              json['active_users_count'] == null
          ? null
          : _toInt(
              json['activeUsersCount'] ?? json['active_users_count'],
            ),
      createdAt: _toNullableString(json['createdAt'] ?? json['created_at']),
      updatedAt: _toNullableString(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

class CompanyDashboard {
  final int branchesCount;
  final int totalOrders;
  final int completedOrders;
  final int cancelledOrders;
  final int activeOrders;
  final double totalSales;
  final double totalServiceFees;
  final double totalAppDeliveryFees;
  final double totalAppDue;
  final double totalCollected;
  final double totalOutstanding;
  final Map<String, dynamic>? bestBranch;
  final Map<String, dynamic>? weakestBranch;

  const CompanyDashboard({
    required this.branchesCount,
    required this.totalOrders,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.activeOrders,
    required this.totalSales,
    required this.totalServiceFees,
    required this.totalAppDeliveryFees,
    required this.totalAppDue,
    required this.totalCollected,
    required this.totalOutstanding,
    required this.bestBranch,
    required this.weakestBranch,
  });

  factory CompanyDashboard.fromJson(Map<String, dynamic> json) {
    return CompanyDashboard(
      branchesCount: _toInt(json['branchesCount'] ?? json['branches_count']),
      totalOrders: _toInt(json['totalOrders'] ?? json['total_orders']),
      completedOrders:
          _toInt(json['completedOrders'] ?? json['completed_orders']),
      cancelledOrders:
          _toInt(json['cancelledOrders'] ?? json['cancelled_orders']),
      activeOrders: _toInt(json['activeOrders'] ?? json['active_orders']),
      totalSales: _toDouble(json['totalSales'] ?? json['total_sales']),
      totalServiceFees: _toDouble(
        json['totalServiceFees'] ?? json['total_service_fees'],
      ),
      totalAppDeliveryFees: _toDouble(
        json['totalAppDeliveryFees'] ?? json['total_app_delivery_fees'],
      ),
      totalAppDue: _toDouble(json['totalAppDue'] ?? json['total_app_due']),
      totalCollected:
          _toDouble(json['totalCollected'] ?? json['total_collected']),
      totalOutstanding:
          _toDouble(json['totalOutstanding'] ?? json['total_outstanding']),
      bestBranch: json['bestBranch'] == null ? null : _toMap(json['bestBranch']),
      weakestBranch: json['weakestBranch'] == null
          ? null
          : _toMap(json['weakestBranch']),
    );
  }
}

class CompanyPolicy {
  final double? commissionRate;
  final String? serviceFeeMode;
  final double? serviceFeeValue;
  final String? deliveryFeeMode;
  final double? deliveryFeeValue;
  final bool? appDeliveryEnabled;
  final bool? merchantDeliveryEnabled;
  final String? settlementCycle;
  final bool inventoryEnabled;
  final String inventoryUpdateMode;
  final int lowStockThreshold;
  final bool autoDisableOutOfStock;
  final bool showAllWithoutAutoDisable;

  const CompanyPolicy({
    required this.commissionRate,
    required this.serviceFeeMode,
    required this.serviceFeeValue,
    required this.deliveryFeeMode,
    required this.deliveryFeeValue,
    required this.appDeliveryEnabled,
    required this.merchantDeliveryEnabled,
    required this.settlementCycle,
    required this.inventoryEnabled,
    required this.inventoryUpdateMode,
    required this.lowStockThreshold,
    required this.autoDisableOutOfStock,
    required this.showAllWithoutAutoDisable,
  });

  factory CompanyPolicy.fromJson(Map<String, dynamic> json) {
    return CompanyPolicy(
      commissionRate: json['commissionRate'] == null &&
              json['commission_rate'] == null
          ? null
          : _toDouble(json['commissionRate'] ?? json['commission_rate']),
      serviceFeeMode: _toNullableString(
        json['serviceFeeMode'] ?? json['service_fee_mode'],
      ),
      serviceFeeValue: json['serviceFeeValue'] == null &&
              json['service_fee_value'] == null
          ? null
          : _toDouble(json['serviceFeeValue'] ?? json['service_fee_value']),
      deliveryFeeMode: _toNullableString(
        json['deliveryFeeMode'] ?? json['delivery_fee_mode'],
      ),
      deliveryFeeValue: json['deliveryFeeValue'] == null &&
              json['delivery_fee_value'] == null
          ? null
          : _toDouble(json['deliveryFeeValue'] ?? json['delivery_fee_value']),
      appDeliveryEnabled: json['appDeliveryEnabled'] == null &&
              json['app_delivery_enabled'] == null
          ? null
          : _toBool(
              json['appDeliveryEnabled'] ?? json['app_delivery_enabled'],
            ),
      merchantDeliveryEnabled: json['merchantDeliveryEnabled'] == null &&
              json['merchant_delivery_enabled'] == null
          ? null
          : _toBool(
              json['merchantDeliveryEnabled'] ??
                  json['merchant_delivery_enabled'],
            ),
      settlementCycle: _toNullableString(
        json['settlementCycle'] ?? json['settlement_cycle'],
      ),
      inventoryEnabled:
          _toBool(json['inventoryEnabled'] ?? json['inventory_enabled']),
      inventoryUpdateMode:
          '${json['inventoryUpdateMode'] ?? json['inventory_update_mode'] ?? 'manual_override'}'
              .trim(),
      lowStockThreshold: _toInt(
        json['lowStockThreshold'] ?? json['low_stock_threshold'],
        5,
      ),
      autoDisableOutOfStock: _toBool(
        json['autoDisableOutOfStock'] ?? json['auto_disable_out_of_stock'],
        true,
      ),
      showAllWithoutAutoDisable: _toBool(
        json['showAllWithoutAutoDisable'] ??
            json['show_all_without_auto_disable'],
      ),
    );
  }

  Map<String, dynamic> toPatchJson() {
    return {
      'commissionRate': commissionRate,
      'serviceFeeMode': serviceFeeMode,
      'serviceFeeValue': serviceFeeValue,
      'deliveryFeeMode': deliveryFeeMode,
      'deliveryFeeValue': deliveryFeeValue,
      'appDeliveryEnabled': appDeliveryEnabled,
      'merchantDeliveryEnabled': merchantDeliveryEnabled,
      'settlementCycle': settlementCycle,
      'inventoryEnabled': inventoryEnabled,
      'inventoryUpdateMode': inventoryUpdateMode,
      'lowStockThreshold': lowStockThreshold,
      'autoDisableOutOfStock': autoDisableOutOfStock,
      'showAllWithoutAutoDisable': showAllWithoutAutoDisable,
    }..removeWhere((key, value) => value == null);
  }
}

class CompanyHomeData {
  final CompanySummary company;
  final CompanyDashboard dashboard;
  final CompanyPolicy? defaultPolicy;

  const CompanyHomeData({
    required this.company,
    required this.dashboard,
    required this.defaultPolicy,
  });

  factory CompanyHomeData.fromJson(Map<String, dynamic> json) {
    return CompanyHomeData(
      company: CompanySummary.fromJson(_toMap(json['company'])),
      dashboard: CompanyDashboard.fromJson(_toMap(json['dashboard'])),
      defaultPolicy: json['defaultPolicy'] == null
          ? null
          : CompanyPolicy.fromJson(_toMap(json['defaultPolicy'])),
    );
  }
}

class CompanyBranch {
  final int id;
  final String name;
  final String type;
  final String? description;
  final String? phone;
  final String? imageUrl;
  final bool isOpen;
  final bool isApproved;
  final bool isDisabled;
  final String? ownerFullName;
  final String? ownerPhone;
  final int totalOrders;
  final int completedOrders;
  final int cancelledOrders;
  final int activeOrders;
  final double grossSales;
  final double appDue;
  final double totalCollected;
  final double outstandingAmount;
  final int trackedItems;
  final int outOfStockItems;
  final int lowStockItems;
  final bool inventoryEnabled;
  final String? dailyUpdateMode;
  final String? lastDailyCheckAt;
  final String? lastInventoryUpdateAt;
  final bool showAllWithoutAutoDisable;
  final bool staleDailyCheck;

  const CompanyBranch({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.phone,
    required this.imageUrl,
    required this.isOpen,
    required this.isApproved,
    required this.isDisabled,
    required this.ownerFullName,
    required this.ownerPhone,
    required this.totalOrders,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.activeOrders,
    required this.grossSales,
    required this.appDue,
    required this.totalCollected,
    required this.outstandingAmount,
    required this.trackedItems,
    required this.outOfStockItems,
    required this.lowStockItems,
    required this.inventoryEnabled,
    required this.dailyUpdateMode,
    required this.lastDailyCheckAt,
    required this.lastInventoryUpdateAt,
    required this.showAllWithoutAutoDisable,
    required this.staleDailyCheck,
  });

  factory CompanyBranch.fromJson(Map<String, dynamic> json) {
    return CompanyBranch(
      id: _toInt(json['id']),
      name: '${json['name'] ?? ''}'.trim(),
      type: '${json['type'] ?? ''}'.trim(),
      description:
          _toNullableString(json['description'] ?? json['requestedDescription']),
      phone: _toNullableString(json['phone']),
      imageUrl: _toNullableString(json['imageUrl'] ?? json['image_url']),
      isOpen: _toBool(json['isOpen'] ?? json['is_open']),
      isApproved: _toBool(json['isApproved'] ?? json['is_approved']),
      isDisabled: _toBool(json['isDisabled'] ?? json['is_disabled']),
      ownerFullName:
          _toNullableString(json['ownerFullName'] ?? json['owner_full_name']),
      ownerPhone:
          _toNullableString(json['ownerPhone'] ?? json['owner_phone']),
      totalOrders: _toInt(json['totalOrders'] ?? json['total_orders']),
      completedOrders:
          _toInt(json['completedOrders'] ?? json['completed_orders']),
      cancelledOrders:
          _toInt(json['cancelledOrders'] ?? json['cancelled_orders']),
      activeOrders: _toInt(json['activeOrders'] ?? json['active_orders']),
      grossSales: _toDouble(json['grossSales'] ?? json['gross_sales']),
      appDue: _toDouble(json['appDue'] ?? json['app_due']),
      totalCollected:
          _toDouble(json['totalCollected'] ?? json['total_collected']),
      outstandingAmount:
          _toDouble(json['outstandingAmount'] ?? json['outstanding_amount']),
      trackedItems: _toInt(json['trackedItems'] ?? json['tracked_items']),
      outOfStockItems:
          _toInt(json['outOfStockItems'] ?? json['out_of_stock_items']),
      lowStockItems: _toInt(json['lowStockItems'] ?? json['low_stock_items']),
      inventoryEnabled:
          _toBool(json['inventoryEnabled'] ?? json['inventory_enabled']),
      dailyUpdateMode: _toNullableString(
        json['dailyUpdateMode'] ?? json['daily_update_mode'],
      ),
      lastDailyCheckAt: _toNullableString(
        json['lastDailyCheckAt'] ?? json['last_daily_check_at'],
      ),
      lastInventoryUpdateAt: _toNullableString(
        json['lastInventoryUpdateAt'] ?? json['last_inventory_update_at'],
      ),
      showAllWithoutAutoDisable: _toBool(
        json['showAllWithoutAutoDisable'] ??
            json['show_all_without_auto_disable'],
      ),
      staleDailyCheck:
          _toBool(json['staleDailyCheck'] ?? json['stale_daily_check']),
    );
  }
}

class CompanyInventoryOverview {
  final Map<String, dynamic> totals;
  final List<CompanyBranch> branches;

  const CompanyInventoryOverview({
    required this.totals,
    required this.branches,
  });

  factory CompanyInventoryOverview.fromJson(Map<String, dynamic> json) {
    final rawBranches = (json['branches'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CompanyBranch.fromJson)
        .toList();
    return CompanyInventoryOverview(
      totals: _toMap(json['totals']),
      branches: rawBranches,
    );
  }
}

class CompanyInventorySettings {
  final int merchantId;
  final int? companyId;
  final bool inventoryEnabled;
  final String dailyUpdateMode;
  final int lowStockThreshold;
  final bool autoDisableOutOfStock;
  final bool showAllWithoutAutoDisable;
  final String? lastDailyCheckAt;
  final String? lastStockUpdateAt;

  const CompanyInventorySettings({
    required this.merchantId,
    required this.companyId,
    required this.inventoryEnabled,
    required this.dailyUpdateMode,
    required this.lowStockThreshold,
    required this.autoDisableOutOfStock,
    required this.showAllWithoutAutoDisable,
    required this.lastDailyCheckAt,
    required this.lastStockUpdateAt,
  });

  factory CompanyInventorySettings.fromJson(Map<String, dynamic> json) {
    return CompanyInventorySettings(
      merchantId: _toInt(json['merchantId'] ?? json['merchant_id']),
      companyId: json['companyId'] == null && json['company_id'] == null
          ? null
          : _toInt(json['companyId'] ?? json['company_id']),
      inventoryEnabled:
          _toBool(json['inventoryEnabled'] ?? json['inventory_enabled']),
      dailyUpdateMode:
          '${json['dailyUpdateMode'] ?? json['daily_update_mode'] ?? 'manual_override'}'
              .trim(),
      lowStockThreshold: _toInt(
        json['lowStockThreshold'] ?? json['low_stock_threshold'],
        5,
      ),
      autoDisableOutOfStock: _toBool(
        json['autoDisableOutOfStock'] ?? json['auto_disable_out_of_stock'],
        true,
      ),
      showAllWithoutAutoDisable: _toBool(
        json['showAllWithoutAutoDisable'] ??
            json['show_all_without_auto_disable'],
      ),
      lastDailyCheckAt: _toNullableString(
        json['lastDailyCheckAt'] ?? json['last_daily_check_at'],
      ),
      lastStockUpdateAt: _toNullableString(
        json['lastStockUpdateAt'] ?? json['last_stock_update_at'],
      ),
    );
  }
}

class CompanyInventoryItem {
  final int id;
  final int productId;
  final String productName;
  final String? productImageUrl;
  final double? price;
  final double? discountedPrice;
  final int quantity;
  final int? reorderThreshold;
  final String stockStatus;
  final bool manualDisabled;
  final bool autoDisabled;
  final bool productIsAvailable;
  final String? updatedAt;

  const CompanyInventoryItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productImageUrl,
    required this.price,
    required this.discountedPrice,
    required this.quantity,
    required this.reorderThreshold,
    required this.stockStatus,
    required this.manualDisabled,
    required this.autoDisabled,
    required this.productIsAvailable,
    required this.updatedAt,
  });

  factory CompanyInventoryItem.fromJson(Map<String, dynamic> json) {
    return CompanyInventoryItem(
      id: _toInt(json['id']),
      productId: _toInt(json['productId'] ?? json['product_id']),
      productName: '${json['productName'] ?? json['product_name'] ?? ''}'.trim(),
      productImageUrl: _toNullableString(
        json['productImageUrl'] ?? json['product_image_url'],
      ),
      price: json['price'] == null ? null : _toDouble(json['price']),
      discountedPrice: json['discountedPrice'] == null &&
              json['discounted_price'] == null
          ? null
          : _toDouble(json['discountedPrice'] ?? json['discounted_price']),
      quantity: _toInt(json['quantity']),
      reorderThreshold: json['reorderThreshold'] == null
          ? json['reorder_threshold'] == null
                ? null
                : _toInt(json['reorder_threshold'])
          : _toInt(json['reorderThreshold']),
      stockStatus:
          '${json['stockStatus'] ?? json['stock_status'] ?? 'in_stock'}'.trim(),
      manualDisabled:
          _toBool(json['manualDisabled'] ?? json['manual_disabled']),
      autoDisabled: _toBool(json['autoDisabled'] ?? json['auto_disabled']),
      productIsAvailable:
          _toBool(json['productIsAvailable'] ?? json['product_is_available']),
      updatedAt: _toNullableString(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

class CompanyBranchDetail {
  final CompanyBranch branch;
  final CompanyInventorySettings? inventorySettings;
  final List<CompanyInventoryItem> inventoryItems;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> categories;

  const CompanyBranchDetail({
    required this.branch,
    required this.inventorySettings,
    required this.inventoryItems,
    required this.products,
    required this.categories,
  });

  factory CompanyBranchDetail.fromJson(Map<String, dynamic> json) {
    return CompanyBranchDetail(
      branch: CompanyBranch.fromJson(_toMap(json['branch'])),
      inventorySettings: json['inventorySettings'] == null
          ? null
          : CompanyInventorySettings.fromJson(
              _toMap(json['inventorySettings']),
            ),
      inventoryItems: (json['inventoryItems'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CompanyInventoryItem.fromJson)
          .toList(),
      products: _toMapList(json['products']),
      categories: _toMapList(json['categories']),
    );
  }
}

class CompanyCoupon {
  final int id;
  final String code;
  final String discountType;
  final double discountValue;
  final bool appliesToAllBranches;
  final bool isActive;
  final List<Map<String, dynamic>> targets;

  const CompanyCoupon({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.appliesToAllBranches,
    required this.isActive,
    required this.targets,
  });

  factory CompanyCoupon.fromJson(Map<String, dynamic> json) {
    return CompanyCoupon(
      id: _toInt(json['id']),
      code: '${json['code'] ?? ''}'.trim(),
      discountType:
          '${json['discountType'] ?? json['discount_type'] ?? ''}'.trim(),
      discountValue:
          _toDouble(json['discountValue'] ?? json['discount_value']),
      appliesToAllBranches: _toBool(
        json['appliesToAllBranches'] ??
            json['company_applies_to_all_branches'],
      ),
      isActive: _toBool(json['isActive'] ?? json['is_active'], true),
      targets: _toMapList(json['targets']),
    );
  }
}

class CompanyCampaign {
  final int id;
  final String title;
  final String offerType;
  final String status;
  final List<Map<String, dynamic>> targets;

  const CompanyCampaign({
    required this.id,
    required this.title,
    required this.offerType,
    required this.status,
    required this.targets,
  });

  factory CompanyCampaign.fromJson(Map<String, dynamic> json) {
    return CompanyCampaign(
      id: _toInt(json['id']),
      title: '${json['title'] ?? ''}'.trim(),
      offerType: '${json['offerType'] ?? json['offer_type'] ?? ''}'.trim(),
      status: '${json['status'] ?? ''}'.trim(),
      targets: _toMapList(json['targets']),
    );
  }
}

class CompanyBranchRequest {
  final int id;
  final int companyId;
  final String requestedName;
  final String requestedType;
  final String? requestedDescription;
  final String? requestedPhone;
  final String? branchLocationLabel;
  final String? ownerFullName;
  final String? ownerPhone;
  final String status;
  final String? reviewNote;
  final int? approvedMerchantId;
  final String? approvedMerchantName;
  final String? createdAt;
  final String? reviewedAt;

  const CompanyBranchRequest({
    required this.id,
    required this.companyId,
    required this.requestedName,
    required this.requestedType,
    required this.requestedDescription,
    required this.requestedPhone,
    required this.branchLocationLabel,
    required this.ownerFullName,
    required this.ownerPhone,
    required this.status,
    required this.reviewNote,
    required this.approvedMerchantId,
    required this.approvedMerchantName,
    required this.createdAt,
    required this.reviewedAt,
  });

  factory CompanyBranchRequest.fromJson(Map<String, dynamic> json) {
    return CompanyBranchRequest(
      id: _toInt(json['id']),
      companyId: _toInt(json['companyId'] ?? json['company_id']),
      requestedName:
          '${json['requestedName'] ?? json['requested_name'] ?? ''}'.trim(),
      requestedType:
          '${json['requestedType'] ?? json['requested_type'] ?? ''}'.trim(),
      requestedDescription: _toNullableString(
        json['requestedDescription'] ?? json['requested_description'],
      ),
      requestedPhone:
          _toNullableString(json['requestedPhone'] ?? json['requested_phone']),
      branchLocationLabel: _toNullableString(
        json['branchLocationLabel'] ?? json['branch_location_label'],
      ),
      ownerFullName:
          _toNullableString(json['ownerFullName'] ?? json['owner_full_name']),
      ownerPhone:
          _toNullableString(json['ownerPhone'] ?? json['owner_phone']),
      status: '${json['status'] ?? ''}'.trim(),
      reviewNote: _toNullableString(json['reviewNote'] ?? json['review_note']),
      approvedMerchantId:
          json['approvedMerchantId'] ?? json['approved_merchant_id'] == null
              ? null
              : _toInt(
                  json['approvedMerchantId'] ?? json['approved_merchant_id'],
                ),
      approvedMerchantName: _toNullableString(
        json['approvedMerchantName'] ?? json['approved_merchant_name'],
      ),
      createdAt: _toNullableString(json['createdAt'] ?? json['created_at']),
      reviewedAt: _toNullableString(json['reviewedAt'] ?? json['reviewed_at']),
    );
  }
}

class CompanyPortalUser {
  final int id;
  final String fullName;
  final String? username;
  final String phone;
  final String role;
  final String? imageUrl;
  final String? workTitle;
  final String? workCompany;

  const CompanyPortalUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.phone,
    required this.role,
    required this.imageUrl,
    required this.workTitle,
    required this.workCompany,
  });

  factory CompanyPortalUser.fromJson(Map<String, dynamic> json) {
    return CompanyPortalUser(
      id: _toInt(json['id']),
      fullName: '${json['fullName'] ?? json['full_name'] ?? ''}'.trim(),
      username: _toNullableString(json['username']),
      phone: '${json['phone'] ?? ''}'.trim(),
      role: '${json['role'] ?? ''}'.trim(),
      imageUrl: _toNullableString(json['imageUrl'] ?? json['image_url']),
      workTitle: _toNullableString(json['workTitle'] ?? json['work_title']),
      workCompany:
          _toNullableString(json['workCompany'] ?? json['work_company']),
    );
  }
}

class CompanyPortalBootstrap {
  final CompanyPortalUser user;
  final List<CompanyMembership> memberships;

  const CompanyPortalBootstrap({
    required this.user,
    required this.memberships,
  });

  factory CompanyPortalBootstrap.fromJson(Map<String, dynamic> json) {
    final memberships = (json['memberships'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CompanyMembership.fromJson)
        .toList();
    return CompanyPortalBootstrap(
      user: CompanyPortalUser.fromJson(
        _toMap(json['user']),
      ),
      memberships: memberships,
    );
  }
}

class CompanyPortalLoginResult {
  final String token;
  final CompanyPortalUser user;
  final List<CompanyMembership> memberships;

  const CompanyPortalLoginResult({
    required this.token,
    required this.user,
    required this.memberships,
  });

  factory CompanyPortalLoginResult.fromJson(Map<String, dynamic> json) {
    final memberships = (json['memberships'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CompanyMembership.fromJson)
        .toList();
    return CompanyPortalLoginResult(
      token: '${json['token'] ?? ''}',
      user: CompanyPortalUser.fromJson(_toMap(json['user'])),
      memberships: memberships,
    );
  }
}

class CompanyUserRecord {
  final int id;
  final String role;
  final bool isActive;
  final UserModel user;

  const CompanyUserRecord({
    required this.id,
    required this.role,
    required this.isActive,
    required this.user,
  });

  factory CompanyUserRecord.fromJson(Map<String, dynamic> json) {
    final userJson = _toMap(json['user']);
    return CompanyUserRecord(
      id: _toInt(json['id']),
      role: '${json['role'] ?? ''}'.trim(),
      isActive: _toBool(json['isActive'] ?? json['is_active'], true),
      user: UserModel.fromJson(userJson),
    );
  }
}
