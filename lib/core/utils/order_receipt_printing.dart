// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';

import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../branding/maslaki_brand_assets.dart';
import '../../features/orders/models/order_model.dart';
import '../../features/owner/printing/receipt_printer_service.dart';
import '../platform/ipos_printer_bridge.dart';
import 'order_status.dart';
import 'store_printer_settings.dart';

const PdfPageFormat _receipt58mm = PdfPageFormat(
  58 * PdfPageFormat.mm,
  420 * PdfPageFormat.mm,
  marginLeft: 2 * PdfPageFormat.mm,
  marginRight: 2 * PdfPageFormat.mm,
  marginTop: 2 * PdfPageFormat.mm,
  marginBottom: 2 * PdfPageFormat.mm,
);

Future<List<Printer>> listAvailableStorePrinters() async {
  try {
    return await Printing.listPrinters();
  } catch (_) {
    return const [];
  }
}

Future<bool> printOwnerOrderReceipt58mm({
  required OrderModel order,
  required String assignmentMode,
  String appTitle = 'Maslaki',
  String? statusOverride,
}) async {
  final result = await ReceiptPrinterService.instance.printOrder(
    order: order,
    assignmentMode: assignmentMode,
    useArabicLabels: true,
    appTitle: appTitle,
  );
  return result.success;
}

Future<bool> printTestReceipt58mm() async {
  final result = await ReceiptPrinterService.instance.printTest(
    useArabicLabels: true,
    appTitle: 'MASLAKI',
  );
  return result.success;
}

Future<bool> _printSystemTestPdf({
  required StorePrinterSelection? selectedSystemPrinter,
  required String appTitle,
}) async {
  final info = await Printing.info();
  if (!info.directPrint) return false;

  final target = await _resolveSystemPrinter(selectedSystemPrinter);
  if (target == null) return false;

  Future<Uint8List> layout(PdfPageFormat _) async {
    final theme = await _buildTheme();
    final logoImage = await _loadLogo();
    final doc = pw.Document(theme: theme);
    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    doc.addPage(
      pw.Page(
        pageFormat: _receipt58mm,
        margin: const pw.EdgeInsets.all(2),
        textDirection: pw.TextDirection.ltr,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildMaslakiPrintLogo(logoImage: logoImage, appTitle: appTitle),
            pw.SizedBox(height: 6),
            _centerText('Printer Test - 58mm', bold: true),
            _centerText(now),
            pw.SizedBox(height: 8),
            _centerText('OK'),
          ],
        ),
      ),
    );
    return doc.save();
  }

  try {
    return await Printing.directPrintPdf(
      printer: target,
      onLayout: layout,
      format: _receipt58mm,
      name: 'printer-test-58mm.pdf',
    );
  } catch (_) {
    return false;
  }
}

Future<bool> _printSystemPdfReceipt({
  required OrderModel order,
  required String assignmentMode,
  required String appTitle,
  String? statusOverride,
  required StorePrinterSelection? selectedSystemPrinter,
}) async {
  final info = await Printing.info();
  if (!info.directPrint) return false;

  final target = await _resolveSystemPrinter(selectedSystemPrinter);
  if (target == null) return false;

  Future<Uint8List> layout(PdfPageFormat _) => _buildReceiptPdfBytes(
    order: order,
    assignmentMode: assignmentMode,
    appTitle: appTitle,
    statusOverride: statusOverride,
  );

  try {
    return await Printing.directPrintPdf(
      printer: target,
      onLayout: layout,
      format: _receipt58mm,
      name: 'order-${order.id}-58mm.pdf',
    );
  } catch (_) {
    return false;
  }
}

Future<Printer?> _resolveSystemPrinter(
  StorePrinterSelection? selectedSystemPrinter,
) async {
  final available = await listAvailableStorePrinters();
  if (available.isEmpty && selectedSystemPrinter == null) return null;

  if (selectedSystemPrinter != null) {
    for (final printer in available) {
      if (printer.url == selectedSystemPrinter.url) {
        return printer;
      }
    }
    return Printer(
      url: selectedSystemPrinter.url,
      name: selectedSystemPrinter.name,
    );
  }

  if (available.isEmpty) return null;
  return available.firstWhere(
    (p) => p.isDefault,
    orElse: () => available.first,
  );
}

Future<bool> _printEscPosOrderReceipt({
  required OrderModel order,
  required String assignmentMode,
  required String appTitle,
  String? statusOverride,
  required String host,
  required int port,
}) async {
  final trimmedHost = host.trim();
  if (trimmedHost.isEmpty) return false;
  final safePort = (port < 1 || port > 65535) ? 9100 : port;

  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final profile = await CapabilityProfile.load();
      final printer = NetworkPrinter(PaperSize.mm58, profile);
      final result = await printer.connect(trimmedHost, port: safePort);
      if (result != PosPrintResult.success) {
        printer.disconnect();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        continue;
      }

      try {
        printer.setGlobalCodeTable('CP864');
      } catch (_) {}

      final nowText = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      final currentStatus = statusOverride ?? order.status;

      printer.text(
        appTitle,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      printer.text(
        'ORDER RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      printer.text(
        _safeEscText(order.merchantName),
        styles: const PosStyles(align: PosAlign.center),
      );
      printer.hr();
      printer.text('Order #${order.id}');
      printer.text('Date: $nowText');
      printer.text('Status: ${_orderStatusLabelEn(currentStatus)}');
      printer.text(
        'Delivery: ${assignmentMode == 'merchant_delivery' ? 'Merchant' : 'App'}',
      );
      printer.hr();
      printer.text('Customer: ${_safeEscText(order.customerFullName)}');
      printer.text('Phone: ${order.customerPhone}');
      printer.text('City: ${_safeEscText(order.customerCity)}');
      printer.text('Block: ${_safeEscText(order.customerBlock)}');
      printer.text('Building: ${_safeEscText(order.customerBuildingNumber)}');
      printer.text('Apartment: ${_safeEscText(order.customerApartment)}');
      if ((order.note ?? '').trim().isNotEmpty) {
        printer.text('Note: ${_safeEscText(order.note!)}');
      }
      printer.hr();
      printer.row([
        PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
        PosColumn(
          text: 'Qty',
          width: 2,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
        PosColumn(
          text: 'Total',
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      printer.hr(ch: '-');
      if (order.items.isEmpty) {
        printer.text('No items');
      } else {
        for (final item in order.items) {
          printer.text(_safeEscText(item.productName));
          printer.row([
            PosColumn(text: '', width: 6),
            PosColumn(
              text: '${item.quantity}',
              width: 2,
              styles: const PosStyles(align: PosAlign.center),
            ),
            PosColumn(
              text: _money(item.lineTotal),
              width: 4,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }
      }

      printer.hr();
      printer.row([
        PosColumn(text: 'Subtotal', width: 8),
        PosColumn(
          text: _money(order.subtotal),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      printer.row([
        PosColumn(text: 'Service', width: 8),
        PosColumn(
          text: _money(order.serviceFee),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      printer.row([
        PosColumn(text: 'Delivery', width: 8),
        PosColumn(
          text: _money(order.deliveryFee),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      printer.row([
        PosColumn(text: 'TOTAL', width: 8, styles: const PosStyles(bold: true)),
        PosColumn(
          text: _money(order.totalAmount),
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      printer.hr();
      printer.text(
        'Thank you',
        styles: const PosStyles(align: PosAlign.center),
      );
      printer.feed(2);
      printer.cut();
      printer.disconnect();
      return true;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  return false;
}

Future<bool> _printIposBluetoothOrderReceipt({
  required OrderModel order,
  required String assignmentMode,
  required String appTitle,
  String? statusOverride,
}) async {
  try {
    final bytes = await _buildIposOrderReceiptBytes(
      order: order,
      assignmentMode: assignmentMode,
      appTitle: appTitle,
      statusOverride: statusOverride,
    );
    return IposPrinterBridge.printEscPosBytes(Uint8List.fromList(bytes));
  } catch (_) {
    return false;
  }
}

Future<bool> _printIposBluetoothTestReceipt() async {
  try {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final bytes = <int>[];
    bytes.addAll(generator.reset());
    bytes.addAll(
      generator.text(
        'MASLAKI',
        styles: const PosStyles(
          bold: true,
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    );
    bytes.addAll(
      generator.text(
        'IPOS PRINTER TEST',
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(
      generator.text(now, styles: const PosStyles(align: PosAlign.center)),
    );
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text('Print channel OK'));
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());
    return IposPrinterBridge.printEscPosBytes(Uint8List.fromList(bytes));
  } catch (_) {
    return false;
  }
}

Future<bool> _printEscPosTestReceipt({
  required String host,
  required int port,
}) async {
  final trimmedHost = host.trim();
  if (trimmedHost.isEmpty) return false;
  final safePort = (port < 1 || port > 65535) ? 9100 : port;

  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final profile = await CapabilityProfile.load();
      final printer = NetworkPrinter(PaperSize.mm58, profile);
      final result = await printer.connect(trimmedHost, port: safePort);
      if (result != PosPrintResult.success) {
        printer.disconnect();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        continue;
      }

      try {
        printer.setGlobalCodeTable('CP864');
      } catch (_) {}

      printer.text(
        'MASLAKI',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size2,
        ),
      );
      printer.text(
        '58mm TEST',
        styles: const PosStyles(align: PosAlign.center),
      );
      printer.text(
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
        styles: const PosStyles(align: PosAlign.center),
      );
      printer.hr();
      printer.text('NETWORK ESC/POS PRINT OK');
      printer.feed(2);
      printer.cut();
      printer.disconnect();
      return true;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  return false;
}

Future<Uint8List> _buildReceiptPdfBytes({
  required OrderModel order,
  required String assignmentMode,
  required String appTitle,
  String? statusOverride,
}) async {
  final theme = await _buildTheme();
  final logoImage = await _loadLogo();
  final doc = pw.Document(theme: theme);
  final nowText = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
  final currentStatus = statusOverride ?? order.status;

  doc.addPage(
    pw.MultiPage(
      pageFormat: _receipt58mm,
      margin: const pw.EdgeInsets.all(0),
      textDirection: pw.TextDirection.rtl,
      build: (_) {
        final rows = <pw.Widget>[
          pw.SizedBox(height: 2),
          _buildMaslakiPrintLogo(logoImage: logoImage, appTitle: appTitle),
          pw.SizedBox(height: 2),
          _centerText(order.merchantName, bold: true, size: 10),
          _centerText('فاتورة طلب', bold: true, size: 8.5),
          _centerText('رقم الطلب #${order.id}', bold: true),
          _line(),
          _pair('التاريخ', nowText),
          _pair('الحالة', orderStatusLabel(currentStatus)),
          _pair(
            'نوع التوصيل',
            assignmentMode == 'merchant_delivery'
                ? 'دلفري المطعم'
                : 'دلفري التطبيق',
          ),
          _line(),
          _pair('اسم الزبون', order.customerFullName),
          _pair('هاتف الزبون', order.customerPhone),
          _pair('العنوان', _composeAddress(order)),
          if ((order.note ?? '').trim().isNotEmpty)
            _pair('ملاحظة', order.note!),
          _line(),
          _centerText('عناصر الطلب', bold: true),
          pw.SizedBox(height: 2),
        ];

        if (order.items.isEmpty) {
          rows.add(_pair('-', 'لا توجد عناصر'));
        } else {
          for (final item in order.items) {
            rows.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _pair(
                    item.productName,
                    '${item.quantity} x ${_money(item.unitPrice)}',
                  ),
                  _pair('مجموع السطر', _money(item.lineTotal)),
                  pw.SizedBox(height: 1.5),
                ],
              ),
            );
          }
        }

        rows.addAll([
          _line(),
          _pair('المجموع الفرعي', _money(order.subtotal), bold: true),
          _pair('رسوم الخدمة', _money(order.serviceFee)),
          _pair('رسوم التوصيل', _money(order.deliveryFee)),
          _pair('الإجمالي', _money(order.totalAmount), bold: true),
          _line(),
          _centerText('شكراً لتعاملكم مع مسلكي'),
        ]);

        return rows;
      },
    ),
  );

  return doc.save();
}

String _composeAddress(OrderModel order) {
  final block = order.customerBlock.trim();
  final building = order.customerBuildingNumber.trim();
  final apartment = order.customerApartment.trim();
  return '${order.customerCity} | بلوك $block - بناية $building - شقة $apartment';
}

String _orderStatusLabelEn(String status) {
  switch (status) {
    case 'pending':
      return 'Pending';
    case 'approved':
      return 'Approved';
    case 'preparing':
      return 'Preparing';
    case 'ready_for_delivery':
      return 'Ready for delivery';
    case 'on_the_way':
      return 'On the way';
    case 'arrived':
      return 'Arrived';
    case 'delivered':
      return 'Delivered';
    case 'cancelled':
      return 'Cancelled';
    default:
      return status;
  }
}

String _safeEscText(String value) {
  final cleaned = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  if (cleaned.isEmpty) return '-';
  return const Latin1Codec(
    allowInvalid: true,
  ).decode(const Latin1Codec(allowInvalid: true).encode(cleaned));
}

Future<List<int>> _buildIposOrderReceiptBytes({
  required OrderModel order,
  required String assignmentMode,
  required String appTitle,
  String? statusOverride,
}) async {
  final profile = await CapabilityProfile.load();
  final generator = Generator(
    PaperSize.mm58,
    profile,
    codec: const Latin1Codec(allowInvalid: true),
  );
  final nowText = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
  final currentStatus = statusOverride ?? order.status;

  final bytes = <int>[];
  bytes.addAll(generator.reset());
  bytes.addAll(
    generator.text(
      appTitle.toUpperCase(),
      styles: const PosStyles(
        bold: true,
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    ),
  );
  bytes.addAll(
    generator.text(
      'ORDER RECEIPT',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ),
  );
  bytes.addAll(
    generator.text(
      _safeEscText(order.merchantName),
      styles: const PosStyles(align: PosAlign.center),
    ),
  );
  bytes.addAll(generator.hr());
  bytes.addAll(generator.text('Order #${order.id}'));
  bytes.addAll(generator.text('Date: $nowText'));
  bytes.addAll(generator.text('Status: ${_orderStatusLabelEn(currentStatus)}'));
  bytes.addAll(
    generator.text(
      'Delivery: ${assignmentMode == 'merchant_delivery' ? 'Merchant' : 'App'}',
    ),
  );
  bytes.addAll(generator.hr());
  bytes.addAll(
    generator.text('Customer: ${_safeEscText(order.customerFullName)}'),
  );
  bytes.addAll(generator.text('Phone: ${order.customerPhone}'));
  bytes.addAll(generator.text('City: ${_safeEscText(order.customerCity)}'));
  bytes.addAll(generator.text('Block: ${_safeEscText(order.customerBlock)}'));
  bytes.addAll(
    generator.text('Building: ${_safeEscText(order.customerBuildingNumber)}'),
  );
  bytes.addAll(generator.text('Apt: ${_safeEscText(order.customerApartment)}'));
  if ((order.note ?? '').trim().isNotEmpty) {
    bytes.addAll(generator.text('Note: ${_safeEscText(order.note!)}'));
  }
  bytes.addAll(generator.hr());
  bytes.addAll(
    generator.row([
      PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(
        text: 'Qty',
        width: 2,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
      PosColumn(
        text: 'Total',
        width: 4,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]),
  );
  bytes.addAll(generator.hr(ch: '-'));
  if (order.items.isEmpty) {
    bytes.addAll(generator.text('No items'));
  } else {
    for (final item in order.items) {
      bytes.addAll(generator.text(_safeEscText(item.productName)));
      bytes.addAll(
        generator.row([
          PosColumn(text: '', width: 6),
          PosColumn(
            text: '${item.quantity}',
            width: 2,
            styles: const PosStyles(align: PosAlign.center),
          ),
          PosColumn(
            text: _money(item.lineTotal),
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
  }

  bytes.addAll(generator.hr());
  bytes.addAll(generator.text('Subtotal: ${_money(order.subtotal)}'));
  bytes.addAll(generator.text('Service : ${_money(order.serviceFee)}'));
  bytes.addAll(generator.text('Delivery: ${_money(order.deliveryFee)}'));
  bytes.addAll(
    generator.text(
      'TOTAL   : ${_money(order.totalAmount)}',
      styles: const PosStyles(bold: true),
    ),
  );
  bytes.addAll(generator.hr());
  bytes.addAll(
    generator.text(
      'Thank you',
      styles: const PosStyles(align: PosAlign.center),
    ),
  );
  bytes.addAll(generator.feed(3));
  bytes.addAll(generator.cut());

  return bytes;
}

Future<pw.ThemeData> _buildTheme() async {
  try {
    final regularData = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final boldData = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Bold.ttf',
    );
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);
    return pw.ThemeData.withFont(base: regular, bold: bold);
  } catch (_) {
    try {
      final regular = await PdfGoogleFonts.notoNaskhArabicRegular();
      final bold = await PdfGoogleFonts.notoNaskhArabicBold();
      return pw.ThemeData.withFont(base: regular, bold: bold);
    } catch (_) {
      return pw.ThemeData.base();
    }
  }
}

Future<pw.MemoryImage?> _loadLogo() async {
  final candidates = <String>[
    MaslakiBrandAssets.printLogo,
    'assets/brand/maslaki_logo.png',
    'assets/brand/splash_logo.png',
    'assets/brand/app_icon.png',
    'assets/branding/app_icon_foreground.png',
    'assets/branding/app_icon.png',
  ];
  for (final path in candidates) {
    try {
      final data = await rootBundle.load(path);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      continue;
    }
  }
  return null;
}

String _money(double value) => value.toStringAsFixed(0);

pw.Widget _buildMaslakiPrintLogo({
  required pw.MemoryImage? logoImage,
  required String appTitle,
}) {
  return pw.Column(
    children: [
      if (logoImage != null)
        pw.Center(
          child: pw.Image(
            logoImage,
            width: 14 * PdfPageFormat.mm,
            height: 14 * PdfPageFormat.mm,
            fit: pw.BoxFit.contain,
          ),
        ),
      if (logoImage == null)
        pw.Center(
          child: pw.Container(
            width: 13 * PdfPageFormat.mm,
            height: 13 * PdfPageFormat.mm,
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border.all(color: PdfColors.blue800, width: 1.2),
              borderRadius: pw.BorderRadius.circular(999),
            ),
            child: pw.Center(
              child: pw.Text(
                'M',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
            ),
          ),
        ),
      pw.SizedBox(height: 1.5),
      _centerText(appTitle, bold: true, size: 10.5),
      _centerText('Maslaki order printing', size: 7.5),
    ],
  );
}

pw.Widget _line() => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 3),
  child: pw.Divider(thickness: 0.6, color: PdfColors.grey600),
);

pw.Widget _centerText(String text, {bool bold = false, double size = 8.3}) =>
    pw.Center(
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: PdfColors.black,
        ),
      ),
    );

pw.Widget _pair(String key, String value, {bool bold = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 6,
        child: pw.Text(
          key,
          style: pw.TextStyle(
            fontSize: 7.8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: PdfColors.black,
          ),
        ),
      ),
      pw.SizedBox(width: 2),
      pw.Expanded(
        flex: 7,
        child: pw.Text(
          value,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: 7.8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: PdfColors.black,
          ),
        ),
      ),
    ],
  ),
);

