import '../../../orders/models/order_item_model.dart';
import '../../../orders/models/order_model.dart';

class ReceiptCustomer {
  final String name;
  final String phone;
  final String city;
  final String block;
  final String building;
  final String apartment;
  final String? note;

  const ReceiptCustomer({
    required this.name,
    required this.phone,
    required this.city,
    required this.block,
    required this.building,
    required this.apartment,
    this.note,
  });
}

class ReceiptStore {
  final String appName;
  final String title;
  final String storeName;
  final String? storePhone;
  final String? storeAddress;
  final String? branchName;
  final String? cashierName;

  const ReceiptStore({
    required this.appName,
    required this.title,
    required this.storeName,
    this.storePhone,
    this.storeAddress,
    this.branchName,
    this.cashierName,
  });
}

class ReceiptItem {
  final String name;
  final int quantity;
  final double unitPrice;
  final double grossLineTotal;
  final double lineDiscount;
  final double finalLineTotal;
  final String? note;

  const ReceiptItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.grossLineTotal,
    required this.lineDiscount,
    required this.finalLineTotal,
    this.note,
  });

  factory ReceiptItem.fromOrderItem(OrderItemModel item) {
    return ReceiptItem(
      name: item.productName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      grossLineTotal: item.baseUnitPrice * item.quantity,
      lineDiscount: item.lineDiscountTotal,
      finalLineTotal: item.lineTotal,
      note: item.variantSelectionsLabel.isEmpty
          ? null
          : item.variantSelectionsLabel,
    );
  }
}

class ReceiptTotals {
  final double grossSubtotal;
  final double productDiscounts;
  final double couponDiscounts;
  final double discounts;
  final double afterDiscount;
  final double deliveryFee;
  final double serviceFee;
  final double taxes;
  final double total;
  final String currency;

  const ReceiptTotals({
    required this.grossSubtotal,
    required this.productDiscounts,
    required this.couponDiscounts,
    required this.discounts,
    required this.afterDiscount,
    required this.deliveryFee,
    required this.serviceFee,
    required this.taxes,
    required this.total,
    required this.currency,
  });
}

class ReceiptPrintData {
  final String orderReference;
  final int orderId;
  final DateTime? orderCreatedAt;
  final DateTime printedAt;
  final DateTime? confirmedAt;
  final DateTime? preparingAt;
  final DateTime? outForDeliveryAt;
  final DateTime? deliveredAt;
  final String orderStatus;
  final String paymentMethod;
  final String deliveryType;
  final String orderSource;
  final int totalItemsCount;
  final int totalQuantity;
  final String? couponCode;
  final double savedAmount;
  final String? etaText;
  final String? internalMerchantNote;
  final String? customerGeneralNote;
  final ReceiptStore store;
  final ReceiptCustomer customer;
  final List<ReceiptItem> items;
  final ReceiptTotals totals;
  final String? driverName;
  final String? driverPhone;

  const ReceiptPrintData({
    required this.orderReference,
    required this.orderId,
    required this.orderCreatedAt,
    required this.printedAt,
    required this.confirmedAt,
    required this.preparingAt,
    required this.outForDeliveryAt,
    required this.deliveredAt,
    required this.orderStatus,
    required this.paymentMethod,
    required this.deliveryType,
    required this.orderSource,
    required this.totalItemsCount,
    required this.totalQuantity,
    required this.couponCode,
    required this.savedAmount,
    required this.etaText,
    required this.internalMerchantNote,
    required this.customerGeneralNote,
    required this.store,
    required this.customer,
    required this.items,
    required this.totals,
    required this.driverName,
    required this.driverPhone,
  });

  factory ReceiptPrintData.fromOrder({
    required OrderModel order,
    required String assignmentMode,
    required String appName,
    String? cashierName,
    String? branchName,
    String currency = 'IQD',
  }) {
    final deliveryType = assignmentMode == 'merchant_delivery'
        ? 'Merchant courier'
        : 'App courier';
    final items = order.items.map(ReceiptItem.fromOrderItem).toList();
    final totalQuantity = items.fold<int>(0, (sum, e) => sum + e.quantity);
    final totalItems = items.length;
    final productDiscounts = order.productDiscountTotal;
    final couponDiscounts = order.couponDiscountTotal;
    final discounts = productDiscounts + couponDiscounts;
    final afterDiscount = (order.grossSubtotal - discounts)
        .clamp(0, double.infinity)
        .toDouble();

    return ReceiptPrintData(
      orderReference: 'MSK-${order.id.toString().padLeft(6, '0')}',
      orderId: order.id,
      orderCreatedAt: order.createdAt,
      printedAt: DateTime.now(),
      confirmedAt: order.approvedAt,
      preparingAt: order.preparingStartedAt,
      outForDeliveryAt: order.pickedUpAt,
      deliveredAt: order.deliveredAt,
      orderStatus: order.status,
      paymentMethod: 'Cash',
      deliveryType: deliveryType,
      orderSource: 'App',
      totalItemsCount: totalItems,
      totalQuantity: totalQuantity,
      couponCode: order.couponCode,
      savedAmount: discounts,
      etaText: order.estimatedDeliveryMinutes == null
          ? null
          : '${order.estimatedDeliveryMinutes} min',
      internalMerchantNote: null,
      customerGeneralNote: order.note,
      store: ReceiptStore(
        appName: appName,
        title: 'Store Receipt',
        storeName: order.merchantName,
        storePhone: null,
        storeAddress: null,
        branchName: branchName,
        cashierName: cashierName,
      ),
      customer: ReceiptCustomer(
        name: order.customerFullName,
        phone: order.customerPhone,
        city: order.customerCity,
        block: order.customerBlock,
        building: order.customerBuildingNumber,
        apartment: order.customerApartment,
        note: order.note,
      ),
      items: items,
      totals: ReceiptTotals(
        grossSubtotal: order.grossSubtotal,
        productDiscounts: productDiscounts,
        couponDiscounts: couponDiscounts,
        discounts: discounts,
        afterDiscount: afterDiscount,
        deliveryFee: order.deliveryFee,
        serviceFee: order.serviceFee,
        taxes: 0,
        total: order.totalAmount,
        currency: currency,
      ),
      driverName: order.deliveryFullName,
      driverPhone: order.deliveryPhone,
    );
  }
}
