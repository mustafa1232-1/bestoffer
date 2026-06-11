import '../printer_adapter.dart';
import '../receipt_builder.dart';

class PreviewPrinterAdapter implements ReceiptPrinterAdapter {
  @override
  String get id => 'preview';

  @override
  Future<ReceiptPrintResult> print({
    required ReceiptTextDocument document,
    required ReceiptAdapterContext context,
    required bool isTest,
  }) async {
    final log = ReceiptPrinterLog(
      at: DateTime.now(),
      stage: 'preview',
      message: 'Preview generated (${document.lines.length} lines).',
      ok: true,
    );
    return ReceiptPrintResult.ok(
      adapterId: id,
      message: 'Preview ready.',
      logs: [log],
    );
  }
}
