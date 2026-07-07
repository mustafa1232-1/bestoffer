import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'order_status.dart';

Future<void> printSimpleReport({
  required String title,
  required List<String> lines,
}) async {
  final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      textDirection: pw.TextDirection.rtl,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('تاريخ التقرير: $now'),
            pw.SizedBox(height: 14),
            ...lines.map(
              (line) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(line),
              ),
            ),
          ],
        );
      },
    ),
  );

  final bytes = await doc.save();
  final filename = 'simple-report-$now.pdf';
  try {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  } catch (_) {
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      format: PdfPageFormat.a4,
      name: filename,
    );
  }
}

@visibleForTesting
List<OrdersReportOrder> buildOrdersReportRows(
  List<Map<String, dynamic>> orders,
) {
  return orders.map(_parseOrder).toList(growable: false);
}

@visibleForTesting
Future<Uint8List> buildOrdersReceiptReportPdfBytes({
  required String title,
  required List<Map<String, dynamic>> orders,
  List<String> summaryLines = const [],
  pw.ThemeData? theme,
}) async {
  final parsedOrders = buildOrdersReportRows(orders);
  final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
  final doc = theme == null ? pw.Document() : pw.Document(theme: theme);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      textDirection: pw.TextDirection.rtl,
      build: (context) {
        final widgets = <pw.Widget>[
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('ØªØ§Ø±ÙŠØ® Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„ØªÙ‚Ø±ÙŠØ±: $now'),
          pw.Text('Ø¹Ø¯Ø¯ Ø§Ù„Ø·Ù„Ø¨Ø§Øª: ${parsedOrders.length}'),
        ];

        if (summaryLines.isNotEmpty) {
          widgets.add(
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 8),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: summaryLines
                    .where((line) => line.trim().isNotEmpty)
                    .map(
                      (line) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3),
                        child: pw.Text(line),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        }

        if (parsedOrders.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 10));
          widgets.add(
            pw.Text(
              'Ø¬Ø¯ÙˆÙ„ Ù…Ù„Ø®Øµ Ø§Ù„Ø·Ù„Ø¨Ø§Øª',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
          );
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(_buildOrdersSummaryTable(parsedOrders));
        }

        for (final order in parsedOrders) {
          widgets.addAll(_buildOrderDetailTables(order));
        }

        return widgets;
      },
    ),
  );

  return doc.save();
}

@visibleForTesting
Future<Uint8List> buildOrdersReportExcelBytes({
  required String title,
  required List<Map<String, dynamic>> orders,
  List<String> summaryLines = const [],
}) async {
  final now = DateTime.now();
  final createdAt = DateFormat('yyyy-MM-dd HH:mm').format(now);
  final parsedOrders = buildOrdersReportRows(orders);

  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null) {
    excel.delete(defaultSheet);
  }

  final summarySheet = excel['Summary'];
  final ordersSheet = excel['Orders'];
  final itemsSheet = excel['Items'];
  final timelineSheet = excel['Timeline'];

  summarySheet.appendRow([
    TextCellValue('Ø§Ù„Ø¹Ù†ÙˆØ§Ù†'),
    TextCellValue(title),
  ]);
  summarySheet.appendRow([
    TextCellValue('ØªØ§Ø±ÙŠØ® Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„ØªÙ‚Ø±ÙŠØ±'),
    TextCellValue(createdAt),
  ]);
  summarySheet.appendRow([
    TextCellValue('Ø¹Ø¯Ø¯ Ø§Ù„Ø·Ù„Ø¨Ø§Øª'),
    IntCellValue(parsedOrders.length),
  ]);
  if (summaryLines.isNotEmpty) {
    summarySheet.appendRow([]);
    summarySheet.appendRow([TextCellValue('Ù…Ù„Ø®Øµ Ø§Ù„Ù…Ø¤Ø´Ø±Ø§Øª')]);
    for (final line in summaryLines) {
      final cleanLine = line.trim();
      if (cleanLine.isEmpty) continue;
      final sepIndex = cleanLine.indexOf(':');
      if (sepIndex > 0) {
        summarySheet.appendRow([
          TextCellValue(cleanLine.substring(0, sepIndex).trim()),
          TextCellValue(cleanLine.substring(sepIndex + 1).trim()),
        ]);
      } else {
        summarySheet.appendRow([TextCellValue(cleanLine)]);
      }
    }
  }

  ordersSheet.appendRow([
    TextCellValue('Ø±Ù‚Ù… Ø§Ù„Ø·Ù„Ø¨'),
    TextCellValue('Ø§Ù„Ø­Ø§Ù„Ø©'),
    TextCellValue('Ø§Ù„Ù…ØªØ¬Ø±'),
    TextCellValue('Ø§Ù„Ø²Ø¨ÙˆÙ†'),
    TextCellValue('Ù‡Ø§ØªÙ Ø§Ù„Ø²Ø¨ÙˆÙ†'),
    TextCellValue('Ø§Ù„Ø¹Ù†ÙˆØ§Ù†'),
    TextCellValue('Ø§Ù„Ù…Ø¬Ù…ÙˆØ¹ Ø§Ù„ÙØ±Ø¹ÙŠ'),
    TextCellValue('Ø±Ø³ÙˆÙ… Ø§Ù„Ø®Ø¯Ù…Ø©'),
    TextCellValue('Ø£Ø¬ÙˆØ± Ø§Ù„ØªÙˆØµÙŠÙ„'),
    TextCellValue('Ø§Ù„Ø¥Ø¬Ù…Ø§Ù„ÙŠ'),
    TextCellValue('ÙˆÙ‚Øª Ø§Ù„Ø·Ù„Ø¨'),
  ]);

  for (final order in parsedOrders) {
    ordersSheet.appendRow([
      IntCellValue(order.id),
      TextCellValue(_statusLabel(order.status)),
      TextCellValue(order.merchantName),
      TextCellValue(order.customerName),
      TextCellValue(order.customerPhone),
      TextCellValue(order.customerAddress),
      DoubleCellValue(order.subtotal),
      DoubleCellValue(order.serviceFee),
      DoubleCellValue(order.deliveryFee),
      DoubleCellValue(order.totalAmount),
      TextCellValue(order.createdAt),
    ]);
  }

  itemsSheet.appendRow([
    TextCellValue('Ø±Ù‚Ù… Ø§Ù„Ø·Ù„Ø¨'),
    TextCellValue('Ø§Ø³Ù… Ø§Ù„Ù…Ù†ØªØ¬'),
    TextCellValue('Ø§Ù„ÙƒÙ…ÙŠØ©'),
    TextCellValue('Ø³Ø¹Ø± Ø§Ù„ÙˆØ­Ø¯Ø©'),
    TextCellValue('Ø§Ù„Ø¥Ø¬Ù…Ø§Ù„ÙŠ'),
  ]);
  for (final order in parsedOrders) {
    if (order.items.isEmpty) {
      itemsSheet.appendRow([
        IntCellValue(order.id),
        TextCellValue('Ù„Ø§ ØªÙˆØ¬Ø¯ Ø¹Ù†Ø§ØµØ±'),
        const IntCellValue(0),
        const DoubleCellValue(0),
        const DoubleCellValue(0),
      ]);
      continue;
    }
    for (final item in order.items) {
      itemsSheet.appendRow([
        IntCellValue(order.id),
        TextCellValue(item.productName),
        IntCellValue(item.quantity),
        DoubleCellValue(item.unitPrice),
        DoubleCellValue(item.lineTotal),
      ]);
    }
  }

  timelineSheet.appendRow([
    TextCellValue('Ø±Ù‚Ù… Ø§Ù„Ø·Ù„Ø¨'),
    TextCellValue('ÙˆÙ‚Øª Ø§Ù„Ø·Ù„Ø¨'),
    TextCellValue('ÙˆÙ‚Øª Ø§Ù„Ù…ÙˆØ§ÙÙ‚Ø©'),
    TextCellValue('Ø¨Ø¯Ø¡ Ø§Ù„ØªØ­Ø¶ÙŠØ±'),
    TextCellValue('Ø¬Ø§Ù‡Ø²ÙŠØ© Ø§Ù„Ø·Ù„Ø¨'),
    TextCellValue('Ø§Ø³ØªÙ„Ø§Ù… Ø§Ù„Ø¯Ù„ÙØ±ÙŠ'),
    TextCellValue('ÙˆØµÙˆÙ„ Ø§Ù„Ø·Ù„Ø¨'),
    TextCellValue('ØªØ£ÙƒÙŠØ¯ Ø§Ù„Ø²Ø¨ÙˆÙ†'),
  ]);
  for (final order in parsedOrders) {
    timelineSheet.appendRow([
      IntCellValue(order.id),
      TextCellValue(order.createdAt),
      TextCellValue(order.approvedAt),
      TextCellValue(order.preparingStartedAt),
      TextCellValue(order.preparedAt),
      TextCellValue(order.pickedUpAt),
      TextCellValue(order.deliveredAt),
      TextCellValue(order.customerConfirmedAt),
    ]);
  }

  final fileBytes = excel.encode();
  if (fileBytes == null || fileBytes.isEmpty) {
    throw StateError('ØªØ¹Ø°Ø± Ø¥Ù†Ø´Ø§Ø¡ Ù…Ù„Ù Excel');
  }

  return Uint8List.fromList(fileBytes);
}

Future<void> printOrdersReceiptReport({
  required String title,
  required List<Map<String, dynamic>> orders,
  List<String> summaryLines = const [],
}) async {
  final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
  final parsedOrders = orders.map(_parseOrder).toList();

  pw.ThemeData? theme;
  try {
    final regularFont = await PdfGoogleFonts.notoNaskhArabicRegular();
    final boldFont = await PdfGoogleFonts.notoNaskhArabicBold();
    theme = pw.ThemeData.withFont(base: regularFont, bold: boldFont);
  } catch (_) {
    theme = null;
  }

  final doc = theme == null ? pw.Document() : pw.Document(theme: theme);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      textDirection: pw.TextDirection.rtl,
      build: (context) {
        final widgets = <pw.Widget>[
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('تاريخ إنشاء التقرير: $now'),
          pw.Text('عدد الطلبات: ${parsedOrders.length}'),
        ];

        if (summaryLines.isNotEmpty) {
          widgets.add(
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 8),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: summaryLines
                    .where((line) => line.trim().isNotEmpty)
                    .map(
                      (line) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3),
                        child: pw.Text(line),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        }

        if (parsedOrders.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 10));
          widgets.add(
            pw.Text(
              'جدول ملخص الطلبات',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
          );
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(_buildOrdersSummaryTable(parsedOrders));
        }

        for (final order in parsedOrders) {
          widgets.addAll(_buildOrderDetailTables(order));
        }

        return widgets;
      },
    ),
  );

  final bytes = await doc.save();
  final filename = 'orders-report-$now.pdf';
  try {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  } catch (_) {
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      format: PdfPageFormat.a4,
      name: filename,
    );
  }
}

Future<void> exportOrdersExcelReport({
  required String title,
  required List<Map<String, dynamic>> orders,
  List<String> summaryLines = const [],
}) async {
  final now = DateTime.now();
  final createdAt = DateFormat('yyyy-MM-dd HH:mm').format(now);
  final parsedOrders = orders.map(_parseOrder).toList();

  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null) {
    excel.delete(defaultSheet);
  }

  final summarySheet = excel['Summary'];
  final ordersSheet = excel['Orders'];
  final itemsSheet = excel['Items'];
  final timelineSheet = excel['Timeline'];

  summarySheet.appendRow([TextCellValue('العنوان'), TextCellValue(title)]);
  summarySheet.appendRow([
    TextCellValue('تاريخ إنشاء التقرير'),
    TextCellValue(createdAt),
  ]);
  summarySheet.appendRow([
    TextCellValue('عدد الطلبات'),
    IntCellValue(parsedOrders.length),
  ]);
  if (summaryLines.isNotEmpty) {
    summarySheet.appendRow([]);
    summarySheet.appendRow([TextCellValue('ملخص المؤشرات')]);
    for (final line in summaryLines) {
      final cleanLine = line.trim();
      if (cleanLine.isEmpty) continue;
      final sepIndex = cleanLine.indexOf(':');
      if (sepIndex > 0) {
        summarySheet.appendRow([
          TextCellValue(cleanLine.substring(0, sepIndex).trim()),
          TextCellValue(cleanLine.substring(sepIndex + 1).trim()),
        ]);
      } else {
        summarySheet.appendRow([TextCellValue(cleanLine)]);
      }
    }
  }

  ordersSheet.appendRow([
    TextCellValue('رقم الطلب'),
    TextCellValue('الحالة'),
    TextCellValue('المتجر'),
    TextCellValue('الزبون'),
    TextCellValue('هاتف الزبون'),
    TextCellValue('العنوان'),
    TextCellValue('المجموع الفرعي'),
    TextCellValue('رسوم الخدمة'),
    TextCellValue('أجور التوصيل'),
    TextCellValue('الإجمالي'),
    TextCellValue('وقت الطلب'),
  ]);

  for (final order in parsedOrders) {
    ordersSheet.appendRow([
      IntCellValue(order.id),
      TextCellValue(_statusLabel(order.status)),
      TextCellValue(order.merchantName),
      TextCellValue(order.customerName),
      TextCellValue(order.customerPhone),
      TextCellValue(order.customerAddress),
      DoubleCellValue(order.subtotal),
      DoubleCellValue(order.serviceFee),
      DoubleCellValue(order.deliveryFee),
      DoubleCellValue(order.totalAmount),
      TextCellValue(order.createdAt),
    ]);
  }

  itemsSheet.appendRow([
    TextCellValue('رقم الطلب'),
    TextCellValue('اسم المنتج'),
    TextCellValue('الكمية'),
    TextCellValue('سعر الوحدة'),
    TextCellValue('الإجمالي'),
  ]);
  for (final order in parsedOrders) {
    if (order.items.isEmpty) {
      itemsSheet.appendRow([
        IntCellValue(order.id),
        TextCellValue('لا توجد عناصر'),
        const IntCellValue(0),
        const DoubleCellValue(0),
        const DoubleCellValue(0),
      ]);
      continue;
    }
    for (final item in order.items) {
      itemsSheet.appendRow([
        IntCellValue(order.id),
        TextCellValue(item.productName),
        IntCellValue(item.quantity),
        DoubleCellValue(item.unitPrice),
        DoubleCellValue(item.lineTotal),
      ]);
    }
  }

  timelineSheet.appendRow([
    TextCellValue('رقم الطلب'),
    TextCellValue('وقت الطلب'),
    TextCellValue('وقت الموافقة'),
    TextCellValue('بدء التحضير'),
    TextCellValue('جاهزية الطلب'),
    TextCellValue('استلام الدلفري'),
    TextCellValue('وصول الطلب'),
    TextCellValue('تأكيد الزبون'),
  ]);
  for (final order in parsedOrders) {
    timelineSheet.appendRow([
      IntCellValue(order.id),
      TextCellValue(order.createdAt),
      TextCellValue(order.approvedAt),
      TextCellValue(order.preparingStartedAt),
      TextCellValue(order.preparedAt),
      TextCellValue(order.pickedUpAt),
      TextCellValue(order.deliveredAt),
      TextCellValue(order.customerConfirmedAt),
    ]);
  }

  final fileBytes = excel.encode();
  if (fileBytes == null || fileBytes.isEmpty) {
    throw StateError('تعذر إنشاء ملف Excel');
  }

  final filename =
      'orders-report-${DateFormat('yyyyMMdd_HHmm').format(now)}.xlsx';
  final xFile = XFile.fromData(
    Uint8List.fromList(fileBytes),
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );

  await SharePlus.instance.share(
    ShareParams(
      title: title,
      subject: title,
      text: 'تقرير طلبات مفصل - $createdAt',
      files: [xFile],
      fileNameOverrides: [filename],
    ),
  );
}

pw.Widget _buildOrdersSummaryTable(List<OrdersReportOrder> orders) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    columnWidths: const {
      0: pw.FixedColumnWidth(46),
      1: pw.FixedColumnWidth(74),
      2: pw.FlexColumnWidth(2.4),
      3: pw.FlexColumnWidth(2.2),
      4: pw.FixedColumnWidth(68),
      5: pw.FixedColumnWidth(64),
      6: pw.FixedColumnWidth(84),
    },
    children: [
      _pdfRow([
        'الطلب',
        'الحالة',
        'المتجر',
        'الزبون',
        'الإجمالي',
        'التوصيل',
        'وقت الطلب',
      ], header: true),
      ...orders.map(
        (order) => _pdfRow([
          '#${order.id}',
          _statusLabel(order.status),
          order.merchantName,
          order.customerName,
          _money(order.totalAmount),
          _money(order.deliveryFee),
          order.createdAt,
        ]),
      ),
    ],
  );
}

List<pw.Widget> _buildOrderDetailTables(OrdersReportOrder order) {
  final widgets = <pw.Widget>[
    pw.SizedBox(height: 10),
    pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Text(
        'تفاصيل الطلب #${order.id} - ${_statusLabel(order.status)}',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
      ),
    ),
    pw.SizedBox(height: 6),
    _buildKeyValueTable([
      ['المتجر', order.merchantName],
      ['الزبون', '${order.customerName} - ${order.customerPhone}'],
      ['العنوان', order.customerAddress],
      ['الدلفري', order.deliveryLabel],
      ['ملاحظة الطلب', order.note.isEmpty ? '-' : order.note],
      ['المجموع الفرعي', _money(order.subtotal)],
      ['رسوم الخدمة', _money(order.serviceFee)],
      ['أجور التوصيل', _money(order.deliveryFee)],
      ['الإجمالي', _money(order.totalAmount)],
    ]),
    pw.SizedBox(height: 6),
    _buildTimelineTable(order),
    pw.SizedBox(height: 6),
    _buildItemsTable(order.items),
  ];

  return widgets;
}

pw.Widget _buildKeyValueTable(List<List<String>> rows) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
    columnWidths: const {0: pw.FixedColumnWidth(130), 1: pw.FlexColumnWidth()},
    children: [
      _pdfRow(['الحقل', 'القيمة'], header: true),
      ...rows.map((row) => _pdfRow(row)),
    ],
  );
}

pw.Widget _buildTimelineTable(OrdersReportOrder order) {
  final rows = <List<String>>[
    ['وقت الطلب', order.createdAt],
    ['وقت الموافقة', order.approvedAt],
    ['بدء التحضير', order.preparingStartedAt],
    ['جاهزية الطلب', order.preparedAt],
    ['استلام الدلفري', order.pickedUpAt],
    ['وصول الطلب', order.deliveredAt],
    ['تأكيد الزبون', order.customerConfirmedAt],
  ];

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
    columnWidths: const {0: pw.FixedColumnWidth(130), 1: pw.FlexColumnWidth()},
    children: [
      _pdfRow(['الحدث', 'الوقت'], header: true),
      ...rows.map((row) => _pdfRow(row)),
    ],
  );
}

pw.Widget _buildItemsTable(List<OrdersReportItem> items) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
    columnWidths: const {
      0: pw.FlexColumnWidth(3),
      1: pw.FixedColumnWidth(52),
      2: pw.FixedColumnWidth(74),
      3: pw.FixedColumnWidth(84),
    },
    children: [
      _pdfRow(['المنتج', 'الكمية', 'سعر الوحدة', 'الإجمالي'], header: true),
      if (items.isEmpty) _pdfRow(['لا توجد عناصر', '-', '-', '-']),
      ...items.map(
        (item) => _pdfRow([
          item.productName,
          '${item.quantity}',
          _money(item.unitPrice),
          _money(item.lineTotal),
        ]),
      ),
    ],
  );
}

pw.TableRow _pdfRow(List<String> cells, {bool header = false}) {
  return pw.TableRow(
    children: cells
        .map(
          (cell) => pw.Container(
            color: header ? PdfColors.grey300 : null,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: pw.Text(
              cell,
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        )
        .toList(),
  );
}

OrdersReportOrder _parseOrder(Map<String, dynamic> raw) {
  final id = _i(raw['id']);
  final status = _s(raw['status']);
  final merchantName = _s(raw['merchant_name'] ?? raw['merchantName']);
  final customerName = _s(
    raw['customer_full_name'] ?? raw['customerFullName'] ?? 'غير معروف',
  );
  final customerPhone = _s(raw['customer_phone'] ?? raw['customerPhone']);
  final customerCity = _s(
    raw['customer_city'] ?? raw['customerCity'] ?? 'مدينة بسماية',
  );
  final customerBlock = _s(raw['customer_block'] ?? raw['customerBlock']);
  final customerBuilding = _s(
    raw['customer_building_number'] ?? raw['customerBuildingNumber'],
  );
  final customerApartment = _s(
    raw['customer_apartment'] ?? raw['customerApartment'],
  );
  final customerAddress =
      '$customerCity - بلوك ${customerBlock.isEmpty ? '-' : customerBlock}'
      ' - عمارة ${customerBuilding.isEmpty ? '-' : customerBuilding}'
      ' - شقة ${customerApartment.isEmpty ? '-' : customerApartment}';

  final deliveryName = _s(raw['delivery_full_name'] ?? raw['deliveryFullName']);
  final deliveryPhone = _s(raw['delivery_phone'] ?? raw['deliveryPhone']);
  final deliveryLabel = deliveryName.isEmpty && deliveryPhone.isEmpty
      ? '-'
      : '$deliveryName ${deliveryPhone.isEmpty ? '' : '- $deliveryPhone'}';

  final subtotal = _n(raw['subtotal']);
  final deliveryFee = _n(raw['delivery_fee'] ?? raw['deliveryFee']);
  final totalAmount = _n(raw['total_amount'] ?? raw['totalAmount']);
  final serviceFee = _resolveServiceFee(
    raw,
    subtotal,
    deliveryFee,
    totalAmount,
  );

  final items = _parseItems(raw['items']);

  return OrdersReportOrder(
    id: id,
    status: status,
    merchantName: merchantName,
    customerName: customerName,
    customerPhone: customerPhone,
    customerAddress: customerAddress,
    deliveryLabel: deliveryLabel,
    note: _s(raw['note']),
    subtotal: subtotal,
    serviceFee: serviceFee,
    deliveryFee: deliveryFee,
    totalAmount: totalAmount,
    createdAt: _fmt(raw['created_at']),
    approvedAt: _fmt(raw['approved_at']),
    preparingStartedAt: _fmt(raw['preparing_started_at']),
    preparedAt: _fmt(raw['prepared_at']),
    pickedUpAt: _fmt(raw['picked_up_at']),
    deliveredAt: _fmt(raw['delivered_at']),
    customerConfirmedAt: _fmt(raw['customer_confirmed_at']),
    items: items,
  );
}

List<OrdersReportItem> _parseItems(dynamic raw) {
  if (raw is! List) return const [];

  final items = <OrdersReportItem>[];
  for (final itemRaw in raw) {
    if (itemRaw is! Map) continue;
    final item = Map<String, dynamic>.from(itemRaw);
    final quantity = _n(item['quantity']).toInt();
    final unitPrice = _n(
      item['unit_price'] ?? item['unitPrice'] ?? item['price'],
    );
    final lineTotal = _n(item['line_total'] ?? item['lineTotal']);
    final safeLineTotal = lineTotal > 0 ? lineTotal : unitPrice * quantity;

    items.add(
      OrdersReportItem(
        productName: _s(item['product_name'] ?? item['productName']),
        quantity: quantity <= 0 ? 1 : quantity,
        unitPrice: unitPrice,
        lineTotal: safeLineTotal,
      ),
    );
  }
  return items;
}

double _resolveServiceFee(
  Map<String, dynamic> raw,
  double subtotal,
  double deliveryFee,
  double totalAmount,
) {
  final directServiceFee = _readPresentNumeric(raw, const [
    'service_fee',
    'serviceFee',
  ]);
  if (directServiceFee != null) {
    return directServiceFee;
  }

  final snapshot = _readSnapshot(raw);
  if (snapshot != null) {
    final snapshotServiceFee = _readPresentNumeric(snapshot, const [
      'serviceFeeAmount',
      'service_fee_amount',
    ]);
    if (snapshotServiceFee != null) {
      return snapshotServiceFee;
    }
  }

  final legacyServiceFee = _readPresentNumeric(raw, const [
    'service_fee_amount',
  ]);
  if (legacyServiceFee != null) {
    return legacyServiceFee;
  }

  return (totalAmount - subtotal - deliveryFee)
      .clamp(0, double.infinity)
      .toDouble();
}

Map<String, dynamic>? _readSnapshot(Map<String, dynamic> raw) {
  final snapshotRaw =
      raw['financial_config_snapshot_json'] ??
      raw['financialConfigSnapshotJson'];
  if (snapshotRaw is Map) {
    return Map<String, dynamic>.from(snapshotRaw);
  }
  if (snapshotRaw is String && snapshotRaw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(snapshotRaw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
  }
  return null;
}

double? _readPresentNumeric(Map<String, dynamic> raw, List<String> keys) {
  for (final key in keys) {
    if (!raw.containsKey(key)) continue;
    final value = raw[key];
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;
    return _n(value);
  }
  return null;
}

String _fmt(dynamic value) {
  if (value == null) return '-';
  final raw = value.toString().trim();
  if (raw.isEmpty) return '-';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  return DateFormat('yyyy-MM-dd HH:mm').format(date.toLocal());
}

int _i(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _n(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

String _s(dynamic value) {
  if (value == null) return '';
  return value.toString().trim();
}

String _money(double value) {
  final formatter = NumberFormat('#,###');
  return '${formatter.format(value.round())} IQD';
}

String _statusLabel(String status) {
  return orderStatusLabel(status);
}

class OrdersReportOrder {
  final int id;
  final String status;
  final String merchantName;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String deliveryLabel;
  final String note;
  final double subtotal;
  final double serviceFee;
  final double deliveryFee;
  final double totalAmount;
  final String createdAt;
  final String approvedAt;
  final String preparingStartedAt;
  final String preparedAt;
  final String pickedUpAt;
  final String deliveredAt;
  final String customerConfirmedAt;
  final List<OrdersReportItem> items;

  const OrdersReportOrder({
    required this.id,
    required this.status,
    required this.merchantName,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.deliveryLabel,
    required this.note,
    required this.subtotal,
    required this.serviceFee,
    required this.deliveryFee,
    required this.totalAmount,
    required this.createdAt,
    required this.approvedAt,
    required this.preparingStartedAt,
    required this.preparedAt,
    required this.pickedUpAt,
    required this.deliveredAt,
    required this.customerConfirmedAt,
    required this.items,
  });
}

class OrdersReportItem {
  final String productName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const OrdersReportItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });
}
