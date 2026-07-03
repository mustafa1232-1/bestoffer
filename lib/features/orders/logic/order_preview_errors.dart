import 'package:dio/dio.dart';

/// تفاصيل PRODUCT_OUT_OF_STOCK المنظمة القادمة من backend عند رفض
/// مراجعة الطلب أو إنشائه، لعرض رسالة مفهومة بدل "تعذر مراجعة الطلب الآن".
class OutOfStockDetails {
  final int? productId;
  final String? productName;
  final int? variantId;
  final String? colorName;
  final String? size;
  final int requestedQuantity;
  final int availableQuantity;

  const OutOfStockDetails({
    this.productId,
    this.productName,
    this.variantId,
    this.colorName,
    this.size,
    this.requestedQuantity = 0,
    this.availableQuantity = 0,
  });

  static OutOfStockDetails? fromError(Object error) {
    if (error is! DioException) return null;
    final data = error.response?.data;
    if (data is! Map) return null;
    final code = '${data['message'] ?? ''}'.trim().toUpperCase();
    if (code != 'PRODUCT_OUT_OF_STOCK') return null;
    final details = data['details'];
    if (details is! Map) return const OutOfStockDetails();
    return OutOfStockDetails(
      productId: _toInt(details['productId']),
      productName: _toText(details['productName']),
      variantId: _toInt(details['variantId']),
      colorName: _toText(details['colorName']),
      size: _toText(details['size']),
      requestedQuantity: _toInt(details['requestedQuantity']) ?? 0,
      availableQuantity: _toInt(details['availableQuantity']) ?? 0,
    );
  }

  /// رسالة عربية جاهزة للعرض بدون تفاصيل تقنية.
  String get userMessage {
    final variantParts = <String>[
      if (colorName != null) 'باللون $colorName',
      if (size != null) 'بالمقاس $size',
    ];
    final variantText =
        variantParts.isEmpty ? '' : ' ${variantParts.join(' و')}';
    final productText = productName == null ? 'هذا المنتج' : 'المنتج "$productName"';
    if (availableQuantity <= 0) {
      return '$productText$variantText غير متوفر حالياً. احذفه من السلة أو اختر خياراً آخر.';
    }
    return 'الكمية المطلوبة من $productText$variantText غير متوفرة. المتاح: $availableQuantity';
  }

  /// هل ينطبق هذا الخطأ على عنصر سلة معيّن؟
  bool matchesCartItem({required int productId, int? variantId}) {
    if (this.productId == null) return false;
    if (this.productId != productId) return false;
    if (this.variantId == null) return true;
    return this.variantId == variantId;
  }
}

int? _toInt(Object? value) {
  if (value == null) return null;
  final parsed = int.tryParse('$value');
  return parsed;
}

String? _toText(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}
