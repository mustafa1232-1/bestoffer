import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../../core/platform/ipos_printer_bridge.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

import '../printer_adapter.dart';
import '../receipt_builder.dart';

class InternalPosPrinterAdapter implements ReceiptPrinterAdapter {
  @override
  String get id => 'internal_pos';

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

    try {
      log('status', 'Checking built-in POS printer status');
      final status = await IposPrinterBridge.getStatus();
      log(
        'status',
        'Bluetooth=${status.bluetoothEnabled}, bonded=${status.bondedIposFound}, serviceInstalled=${status.iposServiceInstalled}',
      );

      if (!status.bluetoothEnabled) {
        return ReceiptPrintResult.fail(
          adapterId: id,
          errorCode: ReceiptPrinterErrorCode.printerNotAvailable,
          message: 'Bluetooth is disabled on POS device.',
          logs: logs,
        );
      }

      if (!status.bondedIposFound) {
        return ReceiptPrintResult.fail(
          adapterId: id,
          errorCode: ReceiptPrinterErrorCode.printerNotAvailable,
          message: 'Bonded POS printer not found.',
          logs: logs,
        );
      }

      log('build', 'Building ESC/POS payload');
      final bytes = await _buildEscPosBytesSmart(document, log);
      log('build', 'ESC/POS bytes prepared: ${bytes.length} bytes');

      if (bytes.length > 128 * 1024) {
        return ReceiptPrintResult.fail(
          adapterId: id,
          errorCode: ReceiptPrinterErrorCode.dataTooLarge,
          message: 'Receipt payload is too large for thermal printer.',
          logs: logs,
        );
      }

      log('send', 'Sending payload to native printer bridge');
      final response = await IposPrinterBridge.printEscPosBytesDetailed(
        Uint8List.fromList(bytes),
      );

      if (!response.success) {
        final mapped = _mapNativeError(response.errorCode);
        log(
          'send',
          'Native print failed: ${response.errorCode} - ${response.errorMessage}',
          ok: false,
        );
        return ReceiptPrintResult.fail(
          adapterId: id,
          errorCode: mapped,
          message:
              response.errorMessage ?? 'Built-in printer rejected print job.',
          logs: logs,
        );
      }

      log('done', 'Receipt printed successfully on internal POS printer');
      return ReceiptPrintResult.ok(
        adapterId: id,
        message: 'Printed successfully on internal POS printer.',
        logs: logs,
      );
    } catch (e) {
      log('exception', 'Internal POS print exception: $e', ok: false);
      return ReceiptPrintResult.fail(
        adapterId: id,
        errorCode: ReceiptPrinterErrorCode.unknown,
        message: 'Unexpected internal printer error.',
        logs: logs,
      );
    }
  }

  Future<List<int>> _buildEscPosBytesSmart(
    ReceiptTextDocument document,
    void Function(String stage, String message, {bool ok}) log,
  ) async {
    if (_containsArabic(document.text)) {
      try {
        log('build', 'Arabic content detected: using bitmap print mode');
        return await _buildEscPosBitmapBytes(document);
      } catch (e) {
        log(
          'build',
          'Bitmap mode failed, falling back to plain text: $e',
          ok: false,
        );
      }
    }
    return _buildEscPosTextBytes(document);
  }

  List<int> _buildEscPosTextBytes(ReceiptTextDocument document) {
    final codec = const Latin1Codec(allowInvalid: true);
    final bytes = <int>[];

    bytes.addAll(const [0x1B, 0x40]); // init
    bytes.addAll(const [0x1B, 0x61, 0x00]); // left align

    for (final rawLine in document.lines) {
      final line = rawLine.length > document.lineWidth
          ? rawLine.substring(0, document.lineWidth)
          : rawLine;
      final normalized = line
          .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ' ')
          .trimRight();
      bytes.addAll(codec.encode(normalized));
      bytes.add(0x0A);
    }

    bytes.addAll(const [0x1B, 0x64, 0x03]); // feed 3 lines
    bytes.addAll(const [0x1D, 0x56, 0x41, 0x03]); // partial cut
    return bytes;
  }

  Future<List<int>> _buildEscPosBitmapBytes(
    ReceiptTextDocument document,
  ) async {
    final rendered = await _renderReceiptToImage(document);
    if (rendered == null) {
      throw StateError('Failed to render receipt bitmap');
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(
      PaperSize.mm58,
      profile,
      codec: const Latin1Codec(allowInvalid: true),
    );
    final bytes = <int>[];
    bytes.addAll(generator.reset());
    bytes.addAll(generator.imageRaster(rendered, align: PosAlign.left));
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());
    return bytes;
  }

  Future<img.Image?> _renderReceiptToImage(ReceiptTextDocument document) async {
    const width = 384;
    const horizontalPadding = 8.0;
    const lineHeight = 28.0;
    const topPadding = 10.0;
    const bottomPadding = 16.0;

    final height =
        (topPadding + (document.lines.length * lineHeight) + bottomPadding)
            .ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    var y = topPadding;
    final paragraphWidth = width - (horizontalPadding * 2);

    for (final line in document.lines) {
      final rtl = _containsArabic(line);
      final pb =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textDirection: rtl
                    ? ui.TextDirection.rtl
                    : ui.TextDirection.ltr,
                fontSize: 22,
                maxLines: 2,
              ),
            )
            ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000), fontSize: 22))
            ..addText(line);
      final paragraph = pb.build()
        ..layout(ui.ParagraphConstraints(width: paragraphWidth.toDouble()));

      canvas.drawParagraph(paragraph, ui.Offset(horizontalPadding, y));
      y += lineHeight;
    }

    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(width, height);
    final data = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;

    return img.decodePng(data.buffer.asUint8List());
  }

  bool _containsArabic(String value) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(value);

  ReceiptPrinterErrorCode _mapNativeError(String? code) {
    final normalized = (code ?? '').toUpperCase();
    switch (normalized) {
      case 'NO_BT_PERMISSION':
        return ReceiptPrinterErrorCode.noPermission;
      case 'BT_DISABLED':
      case 'NO_BLUETOOTH':
      case 'IPOS_NOT_FOUND':
        return ReceiptPrinterErrorCode.printerNotAvailable;
      case 'INVALID_BYTES':
        return ReceiptPrinterErrorCode.encodingFailure;
      case 'IPOS_PRINT_FAILED':
        return ReceiptPrinterErrorCode.sdkChannelFailure;
      default:
        return ReceiptPrinterErrorCode.unknown;
    }
  }
}
