import '../../../core/utils/parsers.dart';
import 'delivery_assignment_model.dart';
import 'order_item_presentation_model.dart';
import 'order_item_model.dart';

class OrderModel {
  final int id;
  final int merchantId;
  final int customerUserId;
  final int? orderGroupId;
  final String? subOrderId;
  final String orderScope;
  final int storeSequence;
  final String merchantName;
  final String? merchantActivityType;
  final String status;
  final String customerFullName;
  final String customerPhone;
  final String customerCity;
  final String customerBlock;
  final String customerBuildingNumber;
  final String customerApartment;
  final String? customerImageUrl;
  final String? imageUrl;
  final String? note;
  final double grossSubtotal;
  final double productDiscountTotal;
  final double subtotal;
  final double _serviceFee;
  final double deliveryFee;
  final int? couponId;
  final String? couponCode;
  final double couponDiscountTotal;
  final double totalAmount;
  final Map<String, dynamic>? pricingBreakdown;
  final String? sourceType;
  final String? orderFlowType;
  final int? pharmacyConversationId;
  final String? pharmacyFlowStatus;
  final int? estimatedPrepMinutes;
  final int? estimatedDeliveryMinutes;
  final int? deliveryUserId;
  final bool isMerchantDelivery;
  final String? courierSource;
  final String? deliveryDriverType;
  final String? deliveryFullName;
  final String? deliveryPhone;
  final bool archivedByDelivery;
  final int? deliveryRating;
  final String? deliveryAssignmentStatus;
  final OrderDeliveryAssignmentModel? deliveryAssignment;
  final String? deliveryReview;
  final int? merchantRating;
  final String? merchantReview;
  final DateTime? merchantRatedAt;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? preparingStartedAt;
  final DateTime? preparedAt;
  final DateTime? pickedUpAt;
  final DateTime? arrivedAt;
  final DateTime? deliveredAt;
  final DateTime? customerConfirmedAt;
  final List<OrderItemModel> items;

  const OrderModel({
    required this.id,
    required this.merchantId,
    required this.customerUserId,
    required this.orderGroupId,
    required this.subOrderId,
    required this.orderScope,
    required this.storeSequence,
    required this.merchantName,
    required this.merchantActivityType,
    required this.status,
    required this.customerFullName,
    required this.customerPhone,
    required this.customerCity,
    required this.customerBlock,
    required this.customerBuildingNumber,
    required this.customerApartment,
    required this.customerImageUrl,
    required this.imageUrl,
    required this.note,
    required this.grossSubtotal,
    required this.productDiscountTotal,
    required this.subtotal,
    required double serviceFee,
    required this.deliveryFee,
    required this.couponId,
    required this.couponCode,
    required this.couponDiscountTotal,
    required this.totalAmount,
    required this.pricingBreakdown,
    required this.sourceType,
    required this.orderFlowType,
    required this.pharmacyConversationId,
    required this.pharmacyFlowStatus,
    required this.estimatedPrepMinutes,
    required this.estimatedDeliveryMinutes,
    required this.deliveryUserId,
    required this.isMerchantDelivery,
    required this.courierSource,
    required this.deliveryDriverType,
    required this.deliveryFullName,
    required this.deliveryPhone,
    required this.archivedByDelivery,
    required this.deliveryRating,
    required this.deliveryAssignmentStatus,
    required this.deliveryAssignment,
    required this.deliveryReview,
    required this.merchantRating,
    required this.merchantReview,
    required this.merchantRatedAt,
    required this.createdAt,
    required this.approvedAt,
    required this.preparingStartedAt,
    required this.preparedAt,
    required this.pickedUpAt,
    required this.arrivedAt,
    required this.deliveredAt,
    required this.customerConfirmedAt,
    required this.items,
  }) : _serviceFee = serviceFee;

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    final rawItems = (j['items'] as List?) ?? const [];
    final pricingRaw = j['pricing_breakdown_json'] ?? j['pricingBreakdown'];
    final assignmentRaw = j['deliveryAssignment'] ??
        j['delivery_assignment'] ??
        j['deliveryAssignmentJson'];
    final normalizedAssignmentStatus = parseNullableString(
          j['delivery_assignment_status'] ?? j['deliveryAssignmentStatus'],
        )
        ?.trim()
        .toUpperCase();
    final legacyDeliveryUserId = j['delivery_user_id'] == null
        ? (j['delivery_id'] == null ? null : parseInt(j['delivery_id']))
        : parseInt(j['delivery_user_id']);
    final legacyOrderStatus = parseString(j['status']).trim().toLowerCase();
    final fallbackAssignment = assignmentRaw is Map
        ? null
        : _buildLegacyDeliveryAssignment(
            status: normalizedAssignmentStatus,
            deliveryUserId: legacyDeliveryUserId,
            orderStatus: legacyOrderStatus,
            raw: j,
          );
    return OrderModel(
      id: parseInt(j['id']),
      merchantId: parseInt(j['merchant_id'] ?? j['merchantId']),
      customerUserId: parseInt(j['customer_user_id'] ?? j['customerUserId']),
      orderGroupId: j['order_group_id'] == null
          ? null
          : parseInt(j['order_group_id']),
      subOrderId: parseNullableString(j['sub_order_id'] ?? j['subOrderId']),
      orderScope: parseString(
        j['order_scope'] ?? j['orderScope'],
        fallback: 'single',
      ),
      storeSequence: parseInt(
        j['store_sequence'] ?? j['storeSequence'],
        fallback: 1,
      ),
      merchantName: parseString(j['merchant_name'] ?? j['merchantName']),
      merchantActivityType: parseNullableString(
        j['merchant_activity_type'] ?? j['merchantActivityType'],
      ),
      status: parseString(j['status']),
      customerFullName: parseString(
        j['customer_full_name'] ?? j['customerFullName'],
      ),
      customerPhone: parseString(j['customer_phone'] ?? j['customerPhone']),
      customerCity: parseString(
        j['customer_city'] ?? j['customerCity'],
        fallback: 'مدينة بسماية',
      ),
      customerBlock: parseString(j['customer_block'] ?? j['customerBlock']),
      customerBuildingNumber: parseString(
        j['customer_building_number'] ?? j['customerBuildingNumber'],
      ),
      customerApartment: parseString(
        j['customer_apartment'] ?? j['customerApartment'],
      ),
      customerImageUrl: parseNullableString(
        j['customer_image_url'] ?? j['customerImageUrl'],
      ),
      imageUrl: parseNullableString(j['image_url'] ?? j['imageUrl']),
      note: parseNullableString(j['note']),
      grossSubtotal: parseDouble(
        j['gross_subtotal'] ?? j['grossSubtotal'] ?? j['subtotal'],
      ),
      productDiscountTotal: parseDouble(
        j['product_discount_total'] ?? j['productDiscountTotal'],
      ),
      subtotal: parseDouble(j['subtotal']),
      serviceFee: parseDouble(j['service_fee'] ?? j['serviceFee']),
      deliveryFee: parseDouble(j['delivery_fee'] ?? j['deliveryFee']),
      couponId: j['coupon_id'] == null
          ? (j['couponId'] == null ? null : parseInt(j['couponId']))
          : parseInt(j['coupon_id']),
      couponCode: parseNullableString(j['coupon_code'] ?? j['couponCode']),
      couponDiscountTotal: parseDouble(
        j['coupon_discount_total'] ?? j['couponDiscountTotal'],
      ),
      totalAmount: parseDouble(j['total_amount'] ?? j['totalAmount']),
      pricingBreakdown: pricingRaw is Map
          ? Map<String, dynamic>.from(pricingRaw)
          : null,
      sourceType: parseNullableString(j['source_type'] ?? j['sourceType']),
      orderFlowType: parseNullableString(
        j['order_flow_type'] ?? j['orderFlowType'],
      ),
      pharmacyConversationId:
          j['pharmacy_conversation_id'] == null &&
              j['pharmacyConversationId'] == null
          ? null
          : parseInt(
              j['pharmacy_conversation_id'] ?? j['pharmacyConversationId'],
            ),
      pharmacyFlowStatus: parseNullableString(
        j['pharmacy_flow_status'] ?? j['pharmacyFlowStatus'],
      ),
      estimatedPrepMinutes: j['estimated_prep_minutes'] == null
          ? null
          : parseInt(j['estimated_prep_minutes']),
      estimatedDeliveryMinutes: j['estimated_delivery_minutes'] == null
          ? null
          : parseInt(j['estimated_delivery_minutes']),
      deliveryUserId: legacyDeliveryUserId,
      isMerchantDelivery:
          (j['is_merchant_delivery'] ?? j['isMerchantDelivery']) == true,
      courierSource: parseNullableString(
        j['courier_source'] ?? j['courierSource'],
      ),
      deliveryDriverType: parseNullableString(
        j['delivery_driver_type'] ?? j['deliveryDriverType'],
      ),
      deliveryFullName: parseNullableString(j['delivery_full_name']),
      deliveryPhone: parseNullableString(j['delivery_phone']),
      archivedByDelivery: j['archived_by_delivery'] ?? false,
      deliveryRating: j['delivery_rating'] == null
          ? null
          : parseInt(j['delivery_rating']),
      deliveryAssignmentStatus: normalizedAssignmentStatus,
      deliveryAssignment: assignmentRaw is Map
          ? OrderDeliveryAssignmentModel.fromJson(
              Map<String, dynamic>.from(assignmentRaw),
            )
          : fallbackAssignment,
      deliveryReview: parseNullableString(j['delivery_review']),
      merchantRating: j['merchant_rating'] == null
          ? null
          : parseInt(j['merchant_rating']),
      merchantReview: parseNullableString(j['merchant_review']),
      merchantRatedAt: _parseDate(j['merchant_rated_at']),
      createdAt: _parseDate(j['created_at']),
      approvedAt: _parseDate(j['approved_at']),
      preparingStartedAt: _parseDate(j['preparing_started_at']),
      preparedAt: _parseDate(j['prepared_at']),
      pickedUpAt: _parseDate(j['picked_up_at']),
      arrivedAt: _parseDate(j['arrived_at']),
      deliveredAt: _parseDate(j['delivered_at']),
      customerConfirmedAt: _parseDate(j['customer_confirmed_at']),
      items: rawItems
          .map(
            (e) => OrderItemModel.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }

  double get serviceFee => _serviceFee;

  double get subtotalAfterCoupon {
    final value = subtotal - couponDiscountTotal;
    if (value <= 0) return 0;
    return value;
  }

  double get totalDiscounts => productDiscountTotal + couponDiscountTotal;

  List<OrderItemPresentationModel> get presentationItems => items
      .map(
        (item) => OrderItemPresentationModel.fromOrderItemModel(
          item,
          orderContext: <String, dynamic>{
            'merchant_id': merchantId,
            'merchant_name': merchantName,
            'merchant_activity_type': merchantActivityType,
            'merchant_type': null,
          },
        ),
      )
      .toList(growable: false);

  bool get isAppDriverDelivery =>
      courierSource == 'app' ||
      (courierSource == null && deliveryDriverType == 'app_driver');

  bool get isStoreDriverDelivery =>
      courierSource == 'merchant' ||
      deliveryDriverType == 'store_driver' ||
      isMerchantDelivery;

  bool get hasExplicitDeliveryAssignment =>
      deliveryAssignment != null ||
      (deliveryAssignmentStatus ?? '').trim().isNotEmpty;

  bool get hasAssignedDelivery =>
      deliveryAssignment?.isAssigned == true ||
      deliveryAssignmentStatus == 'ASSIGNED';

  bool get hasPendingNoDriverAssignment =>
      deliveryAssignment?.isPendingNoDriver == true ||
      deliveryAssignmentStatus == 'PENDING_NO_DRIVER';

bool get isPharmacyFlow =>
      sourceType == 'pharmacy_chat_cart' ||
      orderFlowType == 'pharmacy' ||
      pharmacyConversationId != null;
}

OrderDeliveryAssignmentModel? _buildLegacyDeliveryAssignment({
  required String? status,
  required int? deliveryUserId,
  required String orderStatus,
  required Map<String, dynamic> raw,
}) {
  final normalizedStatus = (status ?? '').trim().toUpperCase();
  final shouldShowAssigned = deliveryUserId != null ||
      normalizedStatus == 'ASSIGNED' ||
      const {
        'approved',
        'preparing',
        'ready_for_delivery',
        'ready_for_pickup',
        'on_the_way',
        'arrived',
      }.contains(orderStatus);
  final shouldShowPending =
      normalizedStatus == 'PENDING_NO_DRIVER' ||
      (!shouldShowAssigned &&
          const {
            'approved',
            'preparing',
            'ready_for_delivery',
            'ready_for_pickup',
          }.contains(orderStatus));
  if (!shouldShowAssigned && !shouldShowPending) return null;

  final driver = deliveryUserId == null && !shouldShowAssigned
      ? null
      : DeliveryAssignmentDriverModel(
          id: deliveryUserId ?? 0,
          name: parseNullableString(
            raw['delivery_full_name'] ?? raw['deliveryFullName'],
          ),
          photoUrl: parseNullableString(
            raw['delivery_image_url'] ?? raw['deliveryImageUrl'],
          ),
          phone: parseNullableString(raw['delivery_phone'] ?? raw['deliveryPhone']),
          rating: raw['delivery_rating'] == null
              ? null
              : parseDouble(raw['delivery_rating'] ?? raw['deliveryRating']),
          availabilityStatus: parseNullableString(
            raw['delivery_availability_status'] ??
                raw['deliveryAvailabilityStatus'],
          ),
          coverageBlock: parseNullableString(
            raw['delivery_coverage_block'] ?? raw['deliveryCoverageBlock'],
          ),
          courierSource: parseNullableString(
            raw['courier_source'] ?? raw['courierSource'],
          ),
          isMerchantDelivery:
              (raw['is_merchant_delivery'] ?? raw['isMerchantDelivery']) == true,
          vehicleType: parseNullableString(
            raw['delivery_vehicle_type'] ?? raw['deliveryVehicleType'],
          ),
          vehicleModel: parseNullableString(
            raw['delivery_vehicle_model'] ?? raw['deliveryVehicleModel'],
          ),
          vehicleColor: parseNullableString(
            raw['delivery_vehicle_color'] ?? raw['deliveryVehicleColor'],
          ),
          vehiclePlateNumber: parseNullableString(
            raw['delivery_vehicle_plate_number'] ??
                raw['deliveryVehiclePlateNumber'],
          ),
        );

  return OrderDeliveryAssignmentModel(
    assignmentStatus: normalizedStatus.isNotEmpty
        ? normalizedStatus
        : (shouldShowAssigned ? 'ASSIGNED' : 'PENDING_NO_DRIVER'),
    assignmentId: raw['delivery_assignment_id'] == null
        ? null
        : parseInt(raw['delivery_assignment_id']),
    assignedAt: _parseDate(
      raw['delivery_assignment_assigned_at'] ??
          raw['deliveryAssignmentAssignedAt'] ??
          raw['courier_assigned_at'] ??
          raw['courierAssignedAt'],
    ),
    endedAt: _parseDate(
      raw['delivery_assignment_ended_at'] ??
          raw['deliveryAssignmentEndedAt'],
    ),
    endedReason: parseNullableString(
      raw['delivery_assignment_ended_reason'] ??
          raw['deliveryAssignmentEndedReason'],
    ),
    orderId: raw['id'] == null ? null : parseInt(raw['id']),
    driver: driver,
  );
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
