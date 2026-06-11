import 'dart:math' as math;

import 'models/receipt_print_data.dart';

class ReceiptBuildOptions {
  final bool useArabicLabels;
  final bool forceEnglishLabels;
  final bool asciiSafe;
  final int lineWidth;

  const ReceiptBuildOptions({
    required this.useArabicLabels,
    this.forceEnglishLabels = false,
    this.asciiSafe = false,
    this.lineWidth = 32,
  });
}

class ReceiptTextDocument {
  final List<String> lines;
  final int lineWidth;

  const ReceiptTextDocument({required this.lines, required this.lineWidth});

  String get text => lines.join('\n');
}

class ReceiptBuilder {
  const ReceiptBuilder();

  ReceiptTextDocument build({
    required ReceiptPrintData data,
    required ReceiptBuildOptions options,
  }) {
    final t = _LabelResolver(
      useArabic: options.useArabicLabels && !options.forceEnglishLabels,
    );

    final out = <String>[];
    final sep = '-' * options.lineWidth;

    void pushLine(String value) {
      final normalized = _normalizeSpaces(value);
      if (normalized.isEmpty) {
        out.add('');
        return;
      }
      for (final line in _wrap(normalized, options.lineWidth)) {
        out.add(_sanitizeForTarget(line, asciiSafe: options.asciiSafe));
      }
    }

    void pushCentered(String value) {
      for (final line in _wrap(_normalizeSpaces(value), options.lineWidth)) {
        out.add(_center(line, options.lineWidth));
      }
    }

    void pushPair(String label, String value, {bool strong = false}) {
      final cleanValue = _normalizeSpaces(value);
      if (cleanValue.isEmpty) return;
      final key = strong ? '*$label' : label;
      final inline = '$key: $cleanValue';
      for (final line in _wrap(inline, options.lineWidth)) {
        out.add(_sanitizeForTarget(line, asciiSafe: options.asciiSafe));
      }
    }

    void pushMoney(String label, num value, {bool strong = false}) {
      final text = '${_money(value)} ${data.totals.currency}';
      final key = strong ? '*$label' : label;
      final rendered = _kvLine(
        key,
        text,
        width: options.lineWidth,
        asciiSafe: options.asciiSafe,
      );
      out.addAll(rendered);
    }

    pushCentered(data.store.appName.isEmpty ? 'MASLAKI' : data.store.appName);
    pushCentered(t.storeReceipt);
    pushLine(sep);

    pushPair(t.orderNumber, '#${data.orderId}');
    pushPair(t.referenceNumber, data.orderReference);
    if (data.orderCreatedAt != null) {
      pushPair(t.orderTime, _dateTime(data.orderCreatedAt!));
    }
    pushPair(t.printedAt, _dateTime(data.printedAt));
    pushPair(t.orderStatus, data.orderStatus);
    pushPair(t.paymentMethod, data.paymentMethod);
    pushPair(t.deliveryType, data.deliveryType);
    pushPair(t.orderSource, data.orderSource);
    if ((data.etaText ?? '').trim().isNotEmpty) {
      pushPair(t.eta, data.etaText!);
    }

    pushLine(sep);
    pushPair(t.customerName, data.customer.name);
    pushPair(t.customerPhone, data.customer.phone);

    final address = _normalizeSpaces(
      '${data.customer.city} / ${t.block} ${data.customer.block} / ${t.building} ${data.customer.building} / ${t.apartment} ${data.customer.apartment}',
    );
    pushPair(t.address, address);

    if ((data.customer.note ?? '').trim().isNotEmpty) {
      pushPair(t.customerNote, data.customer.note!);
    }
    if ((data.customerGeneralNote ?? '').trim().isNotEmpty) {
      pushPair(t.customerNote, data.customerGeneralNote!);
    }

    pushLine(sep);
    pushCentered(t.itemsHeader);

    if (data.items.isEmpty) {
      pushLine(t.noItems);
    } else {
      for (var i = 0; i < data.items.length; i++) {
        final item = data.items[i];
        pushPair('${t.item} ${i + 1}', item.name, strong: true);
        pushPair(t.quantity, '${item.quantity}');
        pushPair(t.unitPrice, _money(item.unitPrice));
        pushPair(t.itemGross, _money(item.grossLineTotal));
        if (item.lineDiscount > 0) {
          pushPair(t.itemDiscount, _money(item.lineDiscount));
        }
        pushPair(t.itemFinal, _money(item.finalLineTotal));
        if ((item.note ?? '').trim().isNotEmpty) {
          pushPair(t.itemNote, item.note!);
        }
        out.add(
          _sanitizeForTarget(
            '-' * options.lineWidth,
            asciiSafe: options.asciiSafe,
          ),
        );
      }
    }

    pushMoney(t.subtotal, data.totals.grossSubtotal);
    if (data.totals.productDiscounts > 0) {
      pushMoney(t.productDiscounts, data.totals.productDiscounts);
    }
    if (data.totals.couponDiscounts > 0) {
      pushMoney(t.couponDiscounts, data.totals.couponDiscounts);
    }
    pushMoney(t.discounts, data.totals.discounts);
    pushMoney(t.afterDiscount, data.totals.afterDiscount);
    pushMoney(t.deliveryFee, data.totals.deliveryFee);
    pushMoney(t.serviceFee, data.totals.serviceFee);
    pushMoney(t.taxes, data.totals.taxes);
    pushMoney(t.total, data.totals.total, strong: true);

    pushPair(t.totalProducts, '${data.totalItemsCount}');
    pushPair(t.totalQuantity, '${data.totalQuantity}');
    if ((data.couponCode ?? '').trim().isNotEmpty) {
      pushPair(t.couponCode, data.couponCode!);
    }
    if (data.savedAmount > 0) {
      pushPair(
        t.customerSavings,
        '${_money(data.savedAmount)} ${data.totals.currency}',
      );
    }

    pushLine(sep);
    pushPair(t.storeName, data.store.storeName);
    if ((data.store.branchName ?? '').trim().isNotEmpty) {
      pushPair(t.branchName, data.store.branchName!);
    }
    if ((data.store.storePhone ?? '').trim().isNotEmpty) {
      pushPair(t.storePhone, data.store.storePhone!);
    }
    if ((data.store.storeAddress ?? '').trim().isNotEmpty) {
      pushPair(t.storeAddress, data.store.storeAddress!);
    }
    if ((data.store.cashierName ?? '').trim().isNotEmpty) {
      pushPair(t.cashierName, data.store.cashierName!);
    }

    if ((data.driverName ?? '').trim().isNotEmpty) {
      pushPair(t.driverName, data.driverName!);
    }
    if ((data.driverPhone ?? '').trim().isNotEmpty) {
      pushPair(t.driverPhone, data.driverPhone!);
    }

    if (data.confirmedAt != null) {
      pushPair(t.confirmedAt, _dateTime(data.confirmedAt!));
    }
    if (data.preparingAt != null) {
      pushPair(t.preparedAt, _dateTime(data.preparingAt!));
    }
    if (data.outForDeliveryAt != null) {
      pushPair(t.outForDeliveryAt, _dateTime(data.outForDeliveryAt!));
    }
    if (data.deliveredAt != null) {
      pushPair(t.deliveredAt, _dateTime(data.deliveredAt!));
    }

    if ((data.internalMerchantNote ?? '').trim().isNotEmpty) {
      pushPair(t.internalNote, data.internalMerchantNote!);
    }

    pushLine(sep);
    pushCentered(t.thanksLine);
    pushCentered('MASLAKI');

    return ReceiptTextDocument(lines: out, lineWidth: options.lineWidth);
  }

  String _dateTime(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _money(num value) => value.toDouble().toStringAsFixed(0);

  String _normalizeSpaces(String value) {
    return value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _wrap(String text, int width) {
    if (text.isEmpty) return const [''];
    if (text.length <= width) return [text];

    final words = text.split(' ');
    final lines = <String>[];
    var current = '';

    for (final rawWord in words) {
      var word = rawWord;
      if (word.length > width) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }
        while (word.length > width) {
          lines.add(word.substring(0, width));
          word = word.substring(width);
        }
        if (word.isNotEmpty) {
          current = word;
        }
        continue;
      }

      if (current.isEmpty) {
        current = word;
      } else if ((current.length + 1 + word.length) <= width) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }

    if (current.isNotEmpty) {
      lines.add(current);
    }

    return lines.isEmpty ? [text] : lines;
  }

  String _center(String text, int width) {
    final clean = text.length > width ? text.substring(0, width) : text;
    final pad = ((width - clean.length) / 2).floor();
    return '${' ' * math.max(0, pad)}$clean';
  }

  List<String> _kvLine(
    String key,
    String value, {
    required int width,
    required bool asciiSafe,
  }) {
    final separator = ': ';
    final minimalSpacing = 1;
    final space = width - key.length - value.length - separator.length;

    if (space >= minimalSpacing) {
      final rendered = '$key$separator${' ' * space}$value';
      return [_sanitizeForTarget(rendered, asciiSafe: asciiSafe)];
    }

    return [
      _sanitizeForTarget(key, asciiSafe: asciiSafe),
      _sanitizeForTarget(value, asciiSafe: asciiSafe),
    ];
  }

  String _sanitizeForTarget(String input, {required bool asciiSafe}) {
    final clean = input.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'),
      ' ',
    );
    if (!asciiSafe) return clean;
    final b = StringBuffer();
    for (final rune in clean.runes) {
      if (rune >= 32 && rune <= 126) {
        b.writeCharCode(rune);
      } else if (rune >= 0xA0 && rune <= 0xFF) {
        b.writeCharCode(rune);
      } else {
        b.write('?');
      }
    }
    return b.toString();
  }
}

class _LabelResolver {
  final bool useArabic;

  const _LabelResolver({required this.useArabic});

  String _l(String ar, String en) => useArabic ? ar : en;

  String get storeReceipt => _l('وصل المتجر', 'Store Receipt');
  String get orderNumber => _l('رقم الطلب', 'Order No');
  String get referenceNumber => _l('الرقم المرجعي', 'Reference');
  String get orderTime => _l('وقت الطلب', 'Order Time');
  String get printedAt => _l('وقت الطباعة', 'Printed At');
  String get orderStatus => _l('الحالة', 'Status');
  String get paymentMethod => _l('طريقة الدفع', 'Payment');
  String get deliveryType => _l('نوع التوصيل', 'Delivery Type');
  String get orderSource => _l('مصدر الطلب', 'Order Source');
  String get eta => _l('الوقت المتوقع للوصول', 'ETA');

  String get customerName => _l('اسم الزبون', 'Customer');
  String get customerPhone => _l('هاتف الزبون', 'Phone');
  String get address => _l('العنوان', 'Address');
  String get block => _l('البلوك', 'Block');
  String get building => _l('العمارة', 'Building');
  String get apartment => _l('الشقة', 'Apt');
  String get customerNote => _l('ملاحظة الزبون', 'Customer Note');

  String get itemsHeader => _l('تفاصيل الأصناف', 'Items');
  String get noItems => _l('لا توجد أصناف', 'No items');
  String get item => _l('الصنف', 'Item');
  String get quantity => _l('الكمية', 'Qty');
  String get unitPrice => _l('سعر الوحدة', 'Unit Price');
  String get itemGross => _l('إجمالي قبل الخصم', 'Gross');
  String get itemDiscount => _l('خصم الصنف', 'Item Discount');
  String get itemFinal => _l('إجمالي الصنف', 'Item Total');
  String get itemNote => _l('ملاحظة الصنف', 'Item Note');

  String get subtotal => _l('الإجمالي الفرعي', 'Subtotal');
  String get productDiscounts => _l('خصومات العروض', 'Product Offers');
  String get couponDiscounts => _l('خصم الكوبون', 'Coupon Discount');
  String get discounts => _l('إجمالي الخصومات', 'Discounts');
  String get afterDiscount => _l('بعد الخصم', 'After Discount');
  String get deliveryFee => _l('أجور التوصيل', 'Delivery Fee');
  String get serviceFee => _l('أجور الخدمة', 'Service Fee');
  String get taxes => _l('الضرائب', 'Taxes');
  String get total => _l('الإجمالي النهائي', 'TOTAL');
  String get totalProducts => _l('عدد الأصناف', 'Items Count');
  String get totalQuantity => _l('إجمالي الكمية', 'Total Qty');
  String get couponCode => _l('رمز الكوبون', 'Coupon');
  String get customerSavings => _l('توفير الزبون', 'Savings');

  String get storeName => _l('اسم المتجر', 'Store');
  String get branchName => _l('الفرع', 'Branch');
  String get storePhone => _l('هاتف المتجر', 'Store Phone');
  String get storeAddress => _l('عنوان المتجر', 'Store Address');
  String get cashierName => _l('تمت الطباعة بواسطة', 'Printed By');

  String get driverName => _l('اسم المندوب', 'Driver');
  String get driverPhone => _l('هاتف المندوب', 'Driver Phone');

  String get confirmedAt => _l('وقت التأكيد', 'Confirmed At');
  String get preparedAt => _l('وقت بدء التحضير', 'Preparing At');
  String get outForDeliveryAt => _l('وقت الخروج للتوصيل', 'Out For Delivery');
  String get deliveredAt => _l('وقت التسليم', 'Delivered At');

  String get internalNote => _l('ملاحظة داخلية', 'Internal Note');
  String get thanksLine =>
      _l('شكراً لاستخدامكم مسلكي', 'Thanks for choosing Maslaki');
}

