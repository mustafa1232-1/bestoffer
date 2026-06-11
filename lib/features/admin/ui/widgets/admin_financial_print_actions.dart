import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/i18n/app_localizations_context.dart';

class AdminFinancialPrintActions extends StatelessWidget {
  final VoidCallback onPrint;

  const AdminFinancialPrintActions({super.key, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        FilledButton.icon(
          onPressed: onPrint,
          icon: const Icon(Icons.print_rounded),
          label: Text(context.l10n.adminFinancialPrintReport),
        ),
      ],
    );
  }
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
      if (rows.isEmpty) rowBuilder(['-', '-', '-', '-', '-']),
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

