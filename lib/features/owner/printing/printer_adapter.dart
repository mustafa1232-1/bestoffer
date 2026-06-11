import 'package:flutter/foundation.dart';

import '../../../core/utils/store_printer_settings.dart';
import 'receipt_builder.dart';

enum ReceiptPrinterErrorCode {
  none,
  printerNotAvailable,
  printerBusy,
  noPermission,
  unsupportedDevice,
  dataTooLarge,
  encodingFailure,
  sdkChannelFailure,
  unknown,
}

class ReceiptPrinterLog {
  final DateTime at;
  final String stage;
  final String message;
  final bool ok;

  const ReceiptPrinterLog({
    required this.at,
    required this.stage,
    required this.message,
    required this.ok,
  });

  @override
  String toString() {
    final flag = ok ? '[OK]' : '[ERR]';
    return '$flag ${at.toIso8601String()} [$stage] $message';
  }
}

class ReceiptAdapterContext {
  final StorePrinterConfig config;

  const ReceiptAdapterContext({required this.config});
}

class ReceiptPrintResult {
  final bool success;
  final String adapterId;
  final ReceiptPrinterErrorCode errorCode;
  final String message;
  final List<ReceiptPrinterLog> logs;

  const ReceiptPrintResult({
    required this.success,
    required this.adapterId,
    required this.errorCode,
    required this.message,
    required this.logs,
  });

  factory ReceiptPrintResult.ok({
    required String adapterId,
    required String message,
    List<ReceiptPrinterLog> logs = const [],
  }) {
    return ReceiptPrintResult(
      success: true,
      adapterId: adapterId,
      errorCode: ReceiptPrinterErrorCode.none,
      message: message,
      logs: logs,
    );
  }

  factory ReceiptPrintResult.fail({
    required String adapterId,
    required ReceiptPrinterErrorCode errorCode,
    required String message,
    List<ReceiptPrinterLog> logs = const [],
  }) {
    return ReceiptPrintResult(
      success: false,
      adapterId: adapterId,
      errorCode: errorCode,
      message: message,
      logs: logs,
    );
  }
}

abstract class ReceiptPrinterAdapter {
  String get id;

  Future<ReceiptPrintResult> print({
    required ReceiptTextDocument document,
    required ReceiptAdapterContext context,
    required bool isTest,
  });
}

@immutable
class ReceiptPrintJobResult {
  final bool success;
  final String adapterId;
  final ReceiptPrinterErrorCode errorCode;
  final String message;
  final String renderedText;
  final List<ReceiptPrinterLog> logs;
  final DateTime createdAt;

  const ReceiptPrintJobResult({
    required this.success,
    required this.adapterId,
    required this.errorCode,
    required this.message,
    required this.renderedText,
    required this.logs,
    required this.createdAt,
  });

  factory ReceiptPrintJobResult.fromAdapterResult({
    required ReceiptPrintResult result,
    required String renderedText,
  }) {
    return ReceiptPrintJobResult(
      success: result.success,
      adapterId: result.adapterId,
      errorCode: result.errorCode,
      message: result.message,
      renderedText: renderedText,
      logs: result.logs,
      createdAt: DateTime.now(),
    );
  }
}
