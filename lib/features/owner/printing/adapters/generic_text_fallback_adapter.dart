import 'dart:typed_data';

import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/utils/store_printer_settings.dart';
import '../printer_adapter.dart';
import '../receipt_builder.dart';

class GenericTextFallbackAdapter implements ReceiptPrinterAdapter {
  GenericTextFallbackAdapter({
    required this.networkHost,
    required this.networkPort,
    required this.systemPrinter,
  });

  final String networkHost;
  final int networkPort;
  final StorePrinterSelection? systemPrinter;

  @override
  String get id => 'generic_fallback';

  @override
  Future<ReceiptPrintResult> print({
    required ReceiptTextDocument document,
    required ReceiptAdapterContext context,
    required bool isTest,
  }) async {
    final logs = <ReceiptPrinterLog>[];
    void log(String stage, String message, {bool ok = true}) {
      logs.add(
        ReceiptPrinterLog(
          at: DateTime.now(),
          stage: stage,
          message: message,
          ok: ok,
        ),
      );
    }

    final host = networkHost.trim();
    if (host.isNotEmpty) {
      log('network', 'Trying network ESC/POS fallback on $host:$networkPort');
      final network = await _printToNetwork(document, host, networkPort, logs);
      if (network.success) return network;
      log(
        'network',
        'Network fallback failed, trying system print service',
        ok: false,
      );
    } else {
      log(
        'network',
        'No network printer host configured; skipping network fallback',
      );
    }

    final system = await _printToSystem(document, logs);
    if (system.success) return system;

    return ReceiptPrintResult.fail(
      adapterId: id,
      errorCode: system.errorCode,
      message: system.message,
      logs: logs,
    );
  }

  Future<ReceiptPrintResult> _printToNetwork(
    ReceiptTextDocument document,
    String host,
    int port,
    List<ReceiptPrinterLog> logs,
  ) async {
    final safePort = (port < 1 || port > 65535) ? 9100 : port;
    try {
      final profile = await CapabilityProfile.load();
      final printer = NetworkPrinter(PaperSize.mm58, profile);
      final result = await printer.connect(host, port: safePort);

      if (result != PosPrintResult.success) {
        printer.disconnect();
        return ReceiptPrintResult.fail(
          adapterId: id,
          errorCode: ReceiptPrinterErrorCode.printerNotAvailable,
          message: 'Cannot connect to network printer ($result).',
          logs: logs,
        );
      }

      for (final line in document.lines) {
        printer.text(line);
      }
      printer.feed(3);
      printer.cut();
      printer.disconnect();

      return ReceiptPrintResult.ok(
        adapterId: id,
        message: 'Printed through network ESC/POS fallback.',
        logs: logs,
      );
    } catch (e) {
      logs.add(
        ReceiptPrinterLog(
          at: DateTime.now(),
          stage: 'network-exception',
          message: '$e',
          ok: false,
        ),
      );
      return ReceiptPrintResult.fail(
        adapterId: id,
        errorCode: ReceiptPrinterErrorCode.sdkChannelFailure,
        message: 'Network ESC/POS print failed.',
        logs: logs,
      );
    }
  }

  Future<ReceiptPrintResult> _printToSystem(
    ReceiptTextDocument document,
    List<ReceiptPrinterLog> logs,
  ) async {
    try {
      final info = await Printing.info();
      if (!info.directPrint) {
        return ReceiptPrintResult.fail(
          adapterId: id,
          errorCode: ReceiptPrinterErrorCode.unsupportedDevice,
          message: 'System print service is unavailable on this device.',
          logs: logs,
        );
      }

      final printer = await _resolvePrinter(systemPrinter);
      if (printer == null) {
        return ReceiptPrintResult.fail(
          adapterId: id,
          errorCode: ReceiptPrinterErrorCode.printerNotAvailable,
          message: 'No system printer selected/found.',
          logs: logs,
        );
      }

      final ok = await Printing.directPrintPdf(
        printer: printer,
        format: const PdfPageFormat(
          58 * PdfPageFormat.mm,
          420 * PdfPageFormat.mm,
          marginLeft: 2 * PdfPageFormat.mm,
          marginRight: 2 * PdfPageFormat.mm,
          marginTop: 2 * PdfPageFormat.mm,
          marginBottom: 2 * PdfPageFormat.mm,
        ),
        name: 'maslaki-receipt-58mm.pdf',
        onLayout: (_) => _buildPlainTextPdf(document),
      );

      if (!ok) {
        return ReceiptPrintResult.fail(
          adapterId: id,
          errorCode: ReceiptPrinterErrorCode.sdkChannelFailure,
          message: 'System print service rejected the print request.',
          logs: logs,
        );
      }

      return ReceiptPrintResult.ok(
        adapterId: id,
        message: 'Printed through system print fallback.',
        logs: logs,
      );
    } catch (e) {
      logs.add(
        ReceiptPrinterLog(
          at: DateTime.now(),
          stage: 'system-exception',
          message: '$e',
          ok: false,
        ),
      );
      return ReceiptPrintResult.fail(
        adapterId: id,
        errorCode: ReceiptPrinterErrorCode.unknown,
        message: 'System print fallback failed.',
        logs: logs,
      );
    }
  }

  Future<Printer?> _resolvePrinter(StorePrinterSelection? selected) async {
    final printers = await Printing.listPrinters();
    if (selected != null) {
      for (final p in printers) {
        if (p.url == selected.url) return p;
      }
      return Printer(url: selected.url, name: selected.name);
    }
    if (printers.isEmpty) return null;
    return printers.firstWhere(
      (p) => p.isDefault,
      orElse: () => printers.first,
    );
  }

  Future<Uint8List> _buildPlainTextPdf(ReceiptTextDocument document) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          58 * PdfPageFormat.mm,
          420 * PdfPageFormat.mm,
          marginLeft: 2 * PdfPageFormat.mm,
          marginRight: 2 * PdfPageFormat.mm,
          marginTop: 2 * PdfPageFormat.mm,
          marginBottom: 2 * PdfPageFormat.mm,
        ),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: document.lines
                .map(
                  (e) => pw.Text(e, style: const pw.TextStyle(fontSize: 8.2)),
                )
                .toList(),
          );
        },
      ),
    );
    return doc.save();
  }
}
