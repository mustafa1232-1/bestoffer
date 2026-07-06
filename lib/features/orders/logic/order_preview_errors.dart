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
  final String? reason;
  final String? backendUserMessageAr;
  final String? backendUserMessageEn;

  const OutOfStockDetails({
    this.productId,
    this.productName,
    this.variantId,
    this.colorName,
    this.size,
    this.requestedQuantity = 0,
    this.availableQuantity = 0,
    this.reason,
    this.backendUserMessageAr,
    this.backendUserMessageEn,
  });

  static OutOfStockDetails? fromError(Object error) {
    if (error is! DioException) return null;
    final data = error.response?.data;
    if (data is! Map) return null;
    final code = '${data['message'] ?? ''}'.trim().toUpperCase();
    if (code != 'PRODUCT_OUT_OF_STOCK' && code != 'PRODUCT_UNAVAILABLE') {
      return null;
    }
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
      reason: _toText(details['reason']),
      backendUserMessageAr: _toText(details['userMessageAr']),
      backendUserMessageEn: _toText(details['userMessageEn']),
    );
  }

  /// رسالة عربية جاهزة للعرض بدون تفاصيل تقنية.
  String get userMessage {
    if (backendUserMessageAr != null &&
        backendUserMessageAr!.trim().isNotEmpty) {
      return backendUserMessageAr!;
    }
    final variantParts = <String>[
      if (colorName != null) 'باللون $colorName',
      if (size != null) 'بالمقاس $size',
    ];
    final variantText = variantParts.isEmpty
        ? ''
        : ' ${variantParts.join(' و')}';
    final productText = productName == null
        ? 'هذا المنتج'
        : 'المنتج "$productName"';
    if ((reason ?? '').toUpperCase() == 'VARIANT_UNAVAILABLE' ||
        (reason ?? '').toUpperCase() == 'MANUAL_DISABLED' ||
        availableQuantity <= 0) {
      return '$productText$variantText غير متوفر حالياً. احذفه من السلة أو اختر خياراً آخر.';
    }
    return 'الكمية المطلوبة من $productText$variantText غير متوفرة. المتاح: $availableQuantity';
  }

  String get userMessageEnglish {
    if (backendUserMessageEn != null &&
        backendUserMessageEn!.trim().isNotEmpty) {
      return backendUserMessageEn!;
    }
    final variantParts = <String>[
      if (colorName != null) 'with color $colorName',
      if (size != null) 'size $size',
    ];
    final variantText = variantParts.isEmpty
        ? ''
        : ' ${variantParts.join(' and ')}';
    final productText = productName == null
        ? 'This product'
        : 'Product "$productName"';
    if ((reason ?? '').toUpperCase() == 'VARIANT_UNAVAILABLE' ||
        (reason ?? '').toUpperCase() == 'MANUAL_DISABLED' ||
        availableQuantity <= 0) {
      return '$productText$variantText is currently unavailable. Remove it from the cart or choose another option.';
    }
    return 'The requested quantity for $productText$variantText is unavailable. Available: $availableQuantity';
  }

  String messageForLanguageCode(String languageCode) {
    final normalized = languageCode.trim().toLowerCase();
    if (normalized.startsWith('en')) return userMessageEnglish;
    return userMessage;
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
