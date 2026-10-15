import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/files/file_downloader.dart';
import '../../../../core/i18n/app_localizations_context.dart';

class AdminFinancialPrintActions extends StatelessWidget {
  final AsyncCallback onPrintPdf;
  final AsyncCallback? onExportExcel;

  const AdminFinancialPrintActions({
    super.key,
    required this.onPrintPdf,
    this.onExportExcel,
  });

  Future<void> _handlePressed(BuildContext context) async {
    if (onExportExcel == null) {
      await onPrintPdf();
      return;
    }
    final action = await showModalBottomSheet<_AdminReportAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'اختر صيغة التقرير',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('طباعة أو حفظ PDF'),
                  subtitle: const Text('يفتح نافذة الطباعة أو حفظ ملف PDF.'),
                  onTap: () =>
                      Navigator.of(context).pop(_AdminReportAction.pdf),
                ),
                ListTile(
                  leading: const Icon(Icons.table_chart_outlined),
                  title: const Text('استخراج Excel'),
                  subtitle: const Text('ينزل ملف xlsx مرتب وقابل للمراجعة.'),
                  onTap: () =>
                      Navigator.of(context).pop(_AdminReportAction.excel),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action == null) return;
    if (action == _AdminReportAction.pdf) {
      await onPrintPdf();
    } else {
      await onExportExcel?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        FilledButton.icon(
          onPressed: () => _handlePressed(context),
          icon: const Icon(Icons.print_rounded),
          label: Text(context.l10n.adminFinancialPrintReport),
        ),
      ],
    );
  }
}

enum _AdminReportAction { pdf, excel }

class AdminFinancialExcelSheet {
  final String name;
  final List<String> headers;
  final List<List<Object?>> rows;

  const AdminFinancialExcelSheet({
    required this.name,
    required this.headers,
    required this.rows,
  });
}

Future<pw.ThemeData?> _loadFinancialPdfTheme() async {
  try {
    final regular = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final bold = await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
    final regularFont = pw.Font.ttf(regular.buffer.asByteData());
    final boldFont = pw.Font.ttf(bold.buffer.asByteData());
    return pw.ThemeData.withFont(base: regularFont, bold: boldFont);
  } catch (_) {
    return null;
  }
}

Future<void> printAdminFinancialTableReport({
  required String title,
  required String periodLabel,
  required List<String> summaryLines,
  required List<String> headers,
  required List<List<String>> rows,
  String? merchantName,
}) async {
  final theme = await _loadFinancialPdfTheme();
  final doc = theme == null ? pw.Document() : pw.Document(theme: theme);
  final printedAt = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(20),
      build: (context) => [
        pw.Text(
          title,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18),
        ),
        pw.SizedBox(height: 4),
        if ((merchantName ?? '').trim().isNotEmpty)
          pw.Text('المتجر: $merchantName'),
        pw.Text('الفترة: $periodLabel'),
        pw.Text('تاريخ الطباعة: $printedAt'),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
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
        pw.SizedBox(height: 10),
        _buildTable(headers, rows),
        pw.SizedBox(height: 10),
        pw.Text(
          'شكراً لاستخدامكم مسلكي',
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    ),
  );

  final bytes = await doc.save();
  final fileName =
      'maslaki-financial-${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
  await _shareOrLayout(bytes, fileName);
}

Future<void> exportAdminFinancialExcelReport({
  required String title,
  required String periodLabel,
  required List<String> summaryLines,
  required List<AdminFinancialExcelSheet> sheets,
  String? merchantName,
  String? filenamePrefix,
}) async {
  final now = DateTime.now();
  final createdAt = DateFormat('yyyy-MM-dd HH:mm').format(now);
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null) {
    excel.delete(defaultSheet);
  }

  final summarySheet = excel['ملخص التقرير'];
  summarySheet.appendRow([TextCellValue('العنوان'), TextCellValue(title)]);
  summarySheet.appendRow([TextCellValue('الفترة'), TextCellValue(periodLabel)]);
  if ((merchantName ?? '').trim().isNotEmpty) {
    summarySheet.appendRow([
      TextCellValue('المتجر'),
      TextCellValue(merchantName!.trim()),
    ]);
  }
  summarySheet.appendRow([
    TextCellValue('تاريخ الاستخراج'),
    TextCellValue(createdAt),
  ]);
  if (summaryLines.isNotEmpty) {
    summarySheet.appendRow(<CellValue>[]);
    summarySheet.appendRow([TextCellValue('ملخص الأرقام')]);
    for (final line in summaryLines) {
      final cleanLine = line.trim();
      if (cleanLine.isEmpty) continue;
      final separator = cleanLine.indexOf(':');
      if (separator > 0) {
        summarySheet.appendRow([
          TextCellValue(cleanLine.substring(0, separator).trim()),
          TextCellValue(cleanLine.substring(separator + 1).trim()),
        ]);
      } else {
        summarySheet.appendRow([TextCellValue(cleanLine)]);
      }
    }
  }

  for (final sheetSpec in sheets) {
    final sheet = excel[_safeSheetName(sheetSpec.name)];
    sheet.appendRow(
      sheetSpec.headers.map((header) => TextCellValue(header)).toList(),
    );
    if (sheetSpec.rows.isEmpty) {
      sheet.appendRow([TextCellValue('لا توجد بيانات')]);
      continue;
    }
    for (final row in sheetSpec.rows) {
      sheet.appendRow(row.map(_excelCell).toList());
    }
  }

  final encoded = excel.encode();
  if (encoded == null || encoded.isEmpty) {
    throw StateError('تعذر إنشاء ملف Excel');
  }

  final safePrefix = (filenamePrefix ?? 'maslaki-financial')
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  final filename =
      '${safePrefix.isEmpty ? 'maslaki-financial' : safePrefix}-${DateFormat('yyyyMMdd_HHmm').format(now)}.xlsx';
  await downloadBytesFile(
    bytes: Uint8List.fromList(encoded),
    filename: filename,
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
}

CellValue _excelCell(Object? value) {
  if (value == null) return TextCellValue('');
  if (value is int) return IntCellValue(value);
  if (value is double) return DoubleCellValue(value);
  if (value is num) return DoubleCellValue(value.toDouble());
  return TextCellValue('$value');
}

String _safeSheetName(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return 'Sheet';
  return cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;
}

pw.Widget _buildTable(List<String> headers, List<List<String>> rows) {
  pw.TableRow rowBuilder(List<String> cells, {bool header = false}) {
    return pw.TableRow(
      children: cells
          .map(
            (cell) => pw.Container(
              color: header ? PdfColors.grey300 : null,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
              child: pw.Text(
                cell,
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: header
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
    children: [
      rowBuilder(headers, header: true),
      if (rows.isEmpty) rowBuilder(List<String>.filled(headers.length, '-')),
      ...rows.map((row) => rowBuilder(row)),
    ],
  );
}

Future<void> _shareOrLayout(Uint8List bytes, String filename) async {
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
